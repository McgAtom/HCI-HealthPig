import Foundation
import HealthKit
import Combine

struct SleepDay: Identifiable, Codable {
    var id: Date { date }
    let date: Date
    let hours: Double
    let sources: [String]
}

struct ActivityDay: Identifiable, Codable {
    var id: Date { date }
    let date: Date
    let steps: Double
}

// HealthKit may contain overlapping stages and duplicate sources.
// Merge asleep intervals, exclude in-bed/awake, and clip at calendar-day edges.
enum SleepIntervals {
    static func seconds(_ intervals: [(Date, Date)], start: Date, end: Date) -> Double {
        let clipped = intervals.map { (max($0.0, start), min($0.1, end)) }
            .filter { $0.1 > $0.0 }.sorted { $0.0 < $1.0 }
        guard var current = clipped.first else { return 0 }
        var total = 0.0
        for next in clipped.dropFirst() {
            if next.0 <= current.1 { current.1 = max(current.1, next.1) }
            else { total += current.1.timeIntervalSince(current.0); current = next }
        }
        return total + current.1.timeIntervalSince(current.0)
    }
}

@MainActor final class HealthReader: ObservableObject {
    static let shared = HealthReader()
    @Published var days: [SleepDay] = []
    @Published var activityDays: [ActivityDay] = []
    @Published var heartRate: Double?
    @Published var heartDate: Date?
    @Published var steps: Double?
    @Published private(set) var rings: DailyRings?
    @Published private(set) var ringsLoading = false
    @Published private(set) var ringsMessage = "授权后读取今日活动摘要；未读取不等于零。"
    @Published var loading = false
    @Published var message = "点授权，读取本机健康数据库"
    @Published var error = ""
    @Published var refreshedAt: Date?
    @Published private(set) var automaticUpdates = UserDefaults.standard.bool(forKey: "healthAutomaticUpdatesV2")
    @Published var backgroundMessage = "授权后自动读取；后台更新由系统安排"
    private let store = HKHealthStore()
    private let sleepType = HKCategoryType(.sleepAnalysis)
    private let heartType = HKQuantityType(.heartRate)
    private let stepType = HKQuantityType(.stepCount)
    private var observers: [HKObserverQuery] = []
    private var refreshTask: Task<Void, Never>?
    private var backgroundConfigured = false
    private var cacheURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("health-records-v2.json")
    }

    init() {
        if automaticUpdates, let data = try? Data(contentsOf: cacheURL),
           let snapshot = try? JSONDecoder().decode(HealthSnapshot.self, from: data) {
            days = snapshot.days; heartRate = snapshot.heartRate; heartDate = snapshot.heartDate
            activityDays = snapshot.activityDays ?? []
            steps = snapshot.steps; refreshedAt = snapshot.refreshedAt
            message = "显示上次读取的记录，正在检查更新"
        }
    }

    func beginAutomaticUpdatesIfEnabled() {
        guard automaticUpdates, HKHealthStore.isHealthDataAvailable() else { return }
        startObservers()
        Task { await configureBackgroundDelivery(); await refresh() }
    }

    func refreshAutomaticallyIfEnabled() async {
        guard automaticUpdates else { return }
        await refresh()
    }

    private func startObservers() {
        guard observers.isEmpty else { return }
        for type in [sleepType as HKSampleType, heartType, stepType] {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, error in
                Task { @MainActor [weak self] in
                    defer { completion() }
                    guard let self, self.automaticUpdates else { return }
                    if let error { self.backgroundMessage = "更新通知出错：\(error.localizedDescription)"; return }
                    await self.refresh()
                }
            }
            observers.append(query); store.execute(query)
        }
    }

    private func configureBackgroundDelivery() async {
        guard !backgroundConfigured else { return }
        backgroundConfigured = true
        do {
            for type in [sleepType as HKSampleType, heartType, stepType] {
                try await store.enableBackgroundDelivery(for: type, frequency: .hourly)
            }
            backgroundMessage = "已请求自动更新；后台通常为小时级，由系统安排"
        } catch {
            backgroundConfigured = false
            backgroundMessage = "后台更新暂不可用；打开应用仍会自动刷新：\(error.localizedDescription)"
        }
    }

    func stopAutomaticUpdatesAndClearCache() async {
        automaticUpdates = false
        UserDefaults.standard.set(false, forKey: "healthAutomaticUpdatesV2")
        refreshTask?.cancel()
        if let task = refreshTask { await task.value }
        for query in observers { store.stop(query) }; observers = []
        for type in [sleepType as HKSampleType, heartType, stepType] {
            try? await store.disableBackgroundDelivery(for: type)
        }
        backgroundConfigured = false
        try? FileManager.default.removeItem(at: cacheURL)
        days = []; activityDays = []; heartRate = nil; heartDate = nil; steps = nil; refreshedAt = nil; rings = nil
        ringsMessage = "自动读取已关闭，可重新授权。"
        message = "自动读取已关闭，本机缓存已清除"
        backgroundMessage = "可再次授权开启；系统健康记录未被删除"
    }

    func authorizeAndRefresh() async {
        guard !loading else { return }
        guard HKHealthStore.isHealthDataAvailable() else {
            error = "当前设备没有可用的健康数据库"; return
        }
        loading = true; error = ""
        do {
            try await store.requestAuthorization(toShare: [], read: [sleepType, heartType, stepType, HKObjectType.activitySummaryType()])
            // Successful request does not prove read permission was granted.
            automaticUpdates = true
            UserDefaults.standard.set(true, forKey: "healthAutomaticUpdatesV2")
            loading = false
            startObservers()
            await configureBackgroundDelivery()
            await refresh()
        } catch { self.error = error.localizedDescription }
        loading = false
    }

    func refresh() async {
        guard HKHealthStore.isHealthDataAvailable() else { error = "当前设备没有可用健康数据库。请检查设备支持情况。"; return }
        if let task = refreshTask { await task.value; return }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            self.loading = true; self.error = ""
            do { try await self.fetch() } catch { self.error = error.localizedDescription }
            self.loading = false
        }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    private func fetch() async throws {
        // Clear previous data before each query; never present stale data as refreshed.
        days = []; activityDays = []; heartRate = nil; heartDate = nil; steps = nil; refreshedAt = nil
        await refreshRings()
        let now = Date(), calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        guard let from = calendar.date(byAdding: .day, value: -7, to: today) else { return }
        let sleepSamples = try await samples(type: sleepType, start: from, end: today)
        let asleep = Set([HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                          HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                          HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                          HKCategoryValueSleepAnalysis.asleepREM.rawValue])
        let valid = sleepSamples.compactMap { $0 as? HKCategorySample }
            .filter { asleep.contains($0.value) && $0.endDate > $0.startDate }
        for offset in -7..<0 {
            guard let start = calendar.date(byAdding: .day, value: offset, to: today),
                  let end = calendar.date(byAdding: .day, value: 1, to: start) else { continue }
            let overlap = valid.filter { $0.startDate < end && $0.endDate > start }
            // No returned sleep samples means unknown; do not turn it into 0h sleep.
            guard !overlap.isEmpty else { continue }
            days.append(SleepDay(date: start,
                                 hours: SleepIntervals.seconds(overlap.map { ($0.startDate, $0.endDate) }, start: start, end: end)/3600,
                                 sources: Array(Set(overlap.map { $0.sourceRevision.source.name })).sorted()))
        }
        let hearts = try await samples(type: heartType,
                                     start: calendar.date(byAdding: .day, value: -2, to: now)!, end: now, limit: 1)
        if let h = hearts.first as? HKQuantitySample {
            heartRate = h.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            heartDate = h.endDate
        }
        steps = try await stepTotal(start: today, end: now)
        for offset in -7..<0 {
            guard let start = calendar.date(byAdding: .day, value: offset, to: today),
                  let end = calendar.date(byAdding: .day, value: 1, to: start) else { continue }
            // An absent sum is unknown, not zero. Completed days exclude today's partial total.
            if let total = try await stepTotal(start: start, end: end) {
                activityDays.append(ActivityDay(date: start, steps: total))
            }
        }
        refreshedAt = now
        message = days.isEmpty && activityDays.isEmpty && heartRate == nil && steps == nil
            ? "暂无可读取记录；可能尚未同步、没有记录或未允许读取。"
            : "已读取健康数据库，时间见各项记录"
        if automaticUpdates, !Task.isCancelled {
            let snapshot = HealthSnapshot(days: days, heartRate: heartRate, heartDate: heartDate,
                                          steps: steps, refreshedAt: now, activityDays: activityDays)
            do {
                try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true)
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: cacheURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                var url = cacheURL
                var values = URLResourceValues(); values.isExcludedFromBackup = true
                try url.setResourceValues(values)
            } catch { backgroundMessage = "记录已读取，但本机缓存未保存" }
        }
    }

    private func samples(type: HKSampleType, start: Date, end: Date, limit: Int = HKObjectQueryNoLimit) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: limit,
                                      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, result, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: result ?? []) }
            }
            store.execute(query)
        }
    }

    private func stepTotal(start: Date, end: Date) async throws -> Double? {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let query = HKStatisticsQuery(quantityType: stepType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, statistics, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: statistics?.sumQuantity()?.doubleValue(for: .count())) }
            }
            store.execute(query)
        }
    }

    func refreshRings() async {
        guard !ringsLoading else { return }
        rings = nil
        guard HKHealthStore.isHealthDataAvailable() else {
            ringsMessage = "当前设备没有可用健康数据库。可以先查看规则说明。"; return
        }
        ringsLoading = true
        defer { ringsLoading = false }
        do {
            let now = Date(), calendar = DailyPig.calendar(.current)
            var components = calendar.dateComponents([.era, .year, .month, .day], from: now)
            components.calendar = calendar
            let summary: HKActivitySummary? = try await withCheckedThrowingContinuation { continuation in
                let predicate = HKQuery.predicateForActivitySummary(with: components)
                let query = HKActivitySummaryQuery(predicate: predicate) { _, summaries, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: summaries?.first) }
                }
                store.execute(query)
            }
            guard automaticUpdates else { return }
            guard let summary, let date = calendar.date(from: summary.dateComponents(for: calendar)) else {
                ringsMessage = "暂无可读活动摘要。请检查系统健身记录、同步与读取权限。"; return
            }
            let minutes = summary.activityMoveMode == .appleMoveTime
            var paused = false
            if #available(iOS 18, watchOS 11, *) { paused = summary.isPaused }
            let result = DailyRings(day: DailyPig.dayKey(date), readAt: .now,
                move: RingValue(value: minutes ? summary.appleMoveTime.doubleValue(for: .minute()) : summary.activeEnergyBurned.doubleValue(for: .kilocalorie()),
                                goal: minutes ? summary.appleMoveTimeGoal.doubleValue(for: .minute()) : summary.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie())),
                exercise: RingValue(value: summary.appleExerciseTime.doubleValue(for: .minute()), goal: summary.exerciseTimeGoal?.doubleValue(for: .minute()) ?? 0),
                stand: RingValue(value: summary.appleStandHours.doubleValue(for: .count()), goal: summary.standHoursGoal?.doubleValue(for: .count()) ?? 0),
                moveUsesMinutes: minutes, paused: paused)
            guard result.valid else { ringsMessage = "活动摘要的目标不完整，暂不能确认抽卡资格。"; return }
            rings = result
            ringsMessage = paused ? "系统圆环已暂停，当前不判断满能量。" : "来自今日系统活动摘要；目标跟随系统设置。"
        } catch { ringsMessage = "活动摘要未能读取：\(error.localizedDescription)" }
    }
}

private struct HealthSnapshot: Codable {
    let days: [SleepDay]
    let heartRate: Double?, heartDate: Date?, steps: Double?
    let refreshedAt: Date
    let activityDays: [ActivityDay]?
}
