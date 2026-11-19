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
    @Published private(set) var vitalRecords: [VitalMetric: [VitalRecord]] = [:]
    @Published private(set) var vitalsLoading = false
    @Published private(set) var vitalsError = false
    @Published private(set) var vitalsEnabled = UserDefaults.standard.bool(forKey: "wellnessVitalsReadOptIn")
    private var vitalsGeneration = 0
    @Published private(set) var sleepStages: [SleepStageSlice] = []
    @Published private(set) var recentSleepNights: [SleepSchedule.Night] = []
    var recentNights: [Int] { recentSleepNights.map(\.asleepMinutes) }
    @Published var days: [SleepDay] = []
    @Published var activityDays: [ActivityDay] = []
    @Published var heartRate: Double?
    @Published var heartDate: Date?
    @Published var steps: Double?
    @Published private(set) var rings: DailyRings?
    @Published private(set) var ringsLoading = false
    @Published private(set) var ringsReadOptIn = UserDefaults.standard.bool(forKey: "watchRingsReadOptIn")
    var readsRings: Bool { automaticUpdates || ringsReadOptIn }
    private var ringsGeneration = 0
    private var ringsTask: Task<Void, Never>?
    @Published private(set) var ringsMessage = "授权后读取今日活动摘要；未读取不等于零。"
    @Published var loading = false
    @Published private(set) var authorizing = false
    @Published private(set) var authorizationError = ""
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

    func refreshVitals() async {
        guard vitalsEnabled, !vitalsLoading, HKHealthStore.isHealthDataAvailable() else { return }
        vitalsLoading = true; vitalsError = false
        let generation = vitalsGeneration
        let now = Date()
        guard let from = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: now)) else {
            vitalsLoading = false; return
        }
        var updated: [VitalMetric: [VitalRecord]] = [:]
        var queryFailed = false
        for metric in VitalMetric.allCases {
            guard generation == vitalsGeneration else { return }
            do {
                let values = try await samples(type: metric.type, start: from, end: now)
                let latest = values.compactMap { sample -> VitalRecord? in
                    guard let value = sample as? HKQuantitySample, (from...now).contains(value.endDate) else { return nil }
                    let converted = metric.read(value.quantity)
                    guard converted.isFinite, converted > 0, metric != .oxygen || converted <= 100 else { return nil }
                    return VitalRecord(id: value.uuid, date: value.endDate, value: converted,
                                       source: value.sourceRevision.source.name)
                }
                updated[metric] = VitalRecord.latestPerDay(latest)
            } catch { queryFailed = true }
        }
        guard generation == vitalsGeneration else { return }
        vitalRecords = updated; vitalsError = queryFailed; vitalsLoading = false
    }

    private func stopVitals() {
        vitalsGeneration += 1
        vitalRecords = [:]; vitalsEnabled = false; vitalsLoading = false; vitalsError = false
        UserDefaults.standard.removeObject(forKey: "wellnessVitalsReadOptIn")
    }

    func stopAutomaticUpdatesAndClearCache() async {
        stopVitals()
        ringsGeneration += 1
        ringsTask?.cancel(); ringsTask = nil; ringsLoading = false; rings = nil
        ringsReadOptIn = false
        UserDefaults.standard.removeObject(forKey: "watchRingsReadOptIn")
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
        sleepStages = []; recentSleepNights = []; days = []; activityDays = []; heartRate = nil; heartDate = nil; steps = nil; refreshedAt = nil; rings = nil
        ringsMessage = "自动读取已关闭，可重新授权。"
        message = "自动读取已关闭，本机缓存已清除"
        backgroundMessage = "可再次授权开启；系统健康记录未被删除"
    }

    @discardableResult func authorizeAndRefresh() async -> Bool {
        guard !authorizing else { return false }
        guard HKHealthStore.isHealthDataAvailable() else {
            authorizationError = "当前设备没有可用的健康数据库"; return false
        }
        authorizing = true; authorizationError = ""
        defer { authorizing = false }
        var readTypes: Set<HKObjectType> = [sleepType, heartType, stepType, HKObjectType.activitySummaryType()]
#if os(iOS)
        readTypes.formUnion(VitalMetric.allCases.map(\.type))
#endif
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            // Successful request does not prove read permission was granted.
            automaticUpdates = true
            UserDefaults.standard.set(true, forKey: "healthAutomaticUpdatesV2")
#if os(iOS)
            vitalsEnabled = true
            UserDefaults.standard.set(true, forKey: "wellnessVitalsReadOptIn")
#endif
            beginAutomaticUpdatesIfEnabled()
            Task { await refreshVitals() }
            return true
        } catch {
            authorizationError = "未完成健康数据设置，请重试。"
            return false
        }
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
        sleepStages = []; recentSleepNights = []; days = []; activityDays = []; heartRate = nil; heartDate = nil; steps = nil; refreshedAt = nil
        await refreshRings()
        let now = Date(), calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        guard let from = calendar.date(byAdding: .day, value: -7, to: today) else { return }
        let sleepSamples = try await samples(type: sleepType, start: from, end: now)
        sleepStages = SleepStageSlice.overnight(sleepSamples.compactMap { $0 as? HKCategorySample }, now: now)
        let asleep = Set([HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                          HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                          HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                          HKCategoryValueSleepAnalysis.asleepREM.rawValue])
        let valid = sleepSamples.compactMap { $0 as? HKCategorySample }
            .filter { asleep.contains($0.value) && $0.endDate > $0.startDate }
        recentSleepNights = SleepSchedule.mainNights(valid.map {
            .init(start: $0.startDate, end: $0.endDate, source: $0.sourceRevision.source.bundleIdentifier)
        }, now: now, calendar: calendar)
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

#if os(watchOS)
    func requestRingsRead() async {
        if readsRings { await refreshRings(); return }
        guard !ringsLoading, HKHealthStore.isHealthDataAvailable() else { return }
        ringsLoading = true
        let generation = ringsGeneration
        do {
            try await store.requestAuthorization(toShare: [], read: [HKObjectType.activitySummaryType()])
            guard ringsGeneration == generation else { return }
            ringsReadOptIn = true
            UserDefaults.standard.set(true, forKey: "watchRingsReadOptIn")
            ringsLoading = false
            await refreshRings()
        } catch {
            guard ringsGeneration == generation else { return }
            ringsLoading = false
            ringsMessage = "活动摘要未能读取：\(error.localizedDescription)"
        }
    }
#endif

    func refreshRings() async {
        if let ringsTask { await ringsTask.value; return }
        guard readsRings, !ringsLoading else { return }
        guard HKHealthStore.isHealthDataAvailable() else {
            rings = nil; ringsMessage = "当前设备没有可用健康数据库。"; return
        }
        ringsLoading = true
        let generation = ringsGeneration
        let task = Task { await fetchRings(generation: generation) }
        ringsTask = task
        await task.value
    }

    private func fetchRings(generation: Int) async {
        defer {
            if ringsGeneration == generation { ringsLoading = false; ringsTask = nil }
        }
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
            guard ringsGeneration == generation, readsRings else { return }
            guard let summary, let date = calendar.date(from: summary.dateComponents(for: calendar)) else {
                rings = nil; ringsMessage = "暂无可读活动摘要。请检查系统健身记录、同步与读取权限。"; return
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
            guard result.valid else { rings = nil; ringsMessage = "活动摘要的目标不完整，暂不能确认抽卡资格。"; return }
            rings = result
            ringsMessage = paused ? "系统圆环已暂停，当前不判断满能量。" : "来自今日系统活动摘要；目标跟随系统设置。"
        } catch {
            guard ringsGeneration == generation else { return }
            rings = nil; ringsMessage = "活动摘要未能读取：\(error.localizedDescription)"
        }
    }
}

private struct HealthSnapshot: Codable {
    let days: [SleepDay]
    let heartRate: Double?, heartDate: Date?, steps: Double?
    let refreshedAt: Date
    let activityDays: [ActivityDay]?
}
