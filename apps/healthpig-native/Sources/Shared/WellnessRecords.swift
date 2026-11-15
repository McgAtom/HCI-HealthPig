import Foundation
import HealthKit

enum VitalMetric: String, CaseIterable, Identifiable {
    case resting, variability, breathing, oxygen

    var id: Self { self }
    var title: String {
        switch self {
        case .resting: return "静息心率"
        case .variability: return "心率变异性"
        case .breathing: return "呼吸频率"
        case .oxygen: return "血氧"
        }
    }
    var symbol: String {
        switch self {
        case .resting: return "heart.fill"
        case .variability: return "waveform.path.ecg"
        case .breathing: return "lungs.fill"
        case .oxygen: return "drop.fill"
        }
    }
    var unitLabel: String {
        switch self {
        case .resting, .breathing: return "次／分"
        case .variability: return "ms"
        case .oxygen: return "%"
        }
    }
    var type: HKQuantityType {
        switch self {
        case .resting: return HKQuantityType(.restingHeartRate)
        case .variability: return HKQuantityType(.heartRateVariabilitySDNN)
        case .breathing: return HKQuantityType(.respiratoryRate)
        case .oxygen: return HKQuantityType(.oxygenSaturation)
        }
    }
    func read(_ quantity: HKQuantity) -> Double {
        switch self {
        case .resting, .breathing:
            return quantity.doubleValue(for: .count().unitDivided(by: .minute()))
        case .variability:
            return quantity.doubleValue(for: .secondUnit(with: .milli))
        case .oxygen:
            return 100 * quantity.doubleValue(for: .percent())
        }
    }
    func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...(self == .breathing || self == .oxygen ? 1 : 0))))
    }
}

struct VitalRecord: Identifiable {
    let id: UUID
    let date: Date
    let value: Double
    let source: String

    static func latestPerDay(_ records: [Self], calendar: Calendar = .current) -> [Self] {
        var seen = Set<Date>()
        return records.sorted { $0.date > $1.date }
            .filter { seen.insert(calendar.startOfDay(for: $0.date)).inserted }
    }
}

struct SleepStageSlice: Identifiable {
    enum Stage: String, CaseIterable {
        case awake, rem, core, deep
        init?(_ rawValue: Int) {
            switch HKCategoryValueSleepAnalysis(rawValue: rawValue) {
            case .awake: self = .awake
            case .asleepREM: self = .rem
            case .asleepCore: self = .core
            case .asleepDeep: self = .deep
            default: return nil
            }
        }
        var title: String {
            switch self {
            case .awake: return "清醒"
            case .rem: return "快速动眼"
            case .core: return "核心"
            case .deep: return "深睡"
            }
        }
    }

    let id: UUID
    let stage: Stage
    let start, end: Date
    let source: String

    static func overnight(_ samples: [HKCategorySample], now: Date, calendar: Calendar = .current) -> [Self] {
        guard let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: now),
              let from = calendar.date(byAdding: .day, value: -1, to: noon) else { return [] }
        let through = min(now, noon)
        let categories = samples.compactMap { sample -> (String, Self)? in
            let start = max(from, sample.startDate), end = min(through, sample.endDate)
            guard start < end, let stage = Stage(sample.value) else { return nil }
            let source = sample.sourceRevision.source
            return (source.bundleIdentifier,
                    Self(id: sample.uuid, stage: stage, start: start, end: end, source: source.name))
        }
        let groups = Dictionary(grouping: categories, by: { $0.0 })
        func coverage(_ entries: [(String, Self)]) -> Double {
            SleepIntervals.seconds(entries.compactMap { _, item in
                item.stage == .awake ? nil : (item.start, item.end)
            }, start: from, end: through)
        }
        // Keep one source. Multiple apps can report the same night's overlapping estimates.
        guard let best = groups.sorted(by: {
            let a = coverage($0.value), b = coverage($1.value)
            return a == b ? $0.key < $1.key : a > b
        }).first, coverage(best.value) > 0 else { return [] }
        return best.value.map(\.1).sorted { a, b in
            a.start == b.start ? a.id.uuidString < b.id.uuidString : a.start < b.start
        }
    }
}
