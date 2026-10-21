import Foundation

struct RingValue: Equatable {
    let value: Double
    let goal: Double
    var valid: Bool { value.isFinite && value >= 0 && goal.isFinite && goal > 0 }
    var fraction: Double? { valid ? min(value / goal, 1) : nil }
    var closed: Bool { valid && value >= goal }
}

// This is game eligibility based on the user's system goals, never a health score.
// A reading is intentionally not restored from cache or synchronized as fresh HealthKit data.
struct DailyRings: Equatable {
    let day: String
    let readAt: Date
    let move: RingValue
    let exercise: RingValue
    let stand: RingValue
    var moveUsesMinutes = false
    var paused = false
    var valid: Bool { DailyPig.ordinal(day) != nil && move.valid && exercise.valid && stand.valid }
    var closedCount: Int { [move, exercise, stand].filter(\.closed).count }
    func canUnlock(now: Date = .now) -> Bool {
        valid && !paused && day == DailyPig.dayKey(now)
            && now.timeIntervalSince(readAt) >= 0 && now.timeIntervalSince(readAt) <= 300
            && closedCount == 3
    }
}

struct CompanionSegments {
    private(set) var readings: [WatchReading] = []
    var walking: Int { readings.filter { $0.verdict == .walking }.count }
    var still: Int { readings.filter { $0.verdict == .still }.count }
    var uncertain: Int { readings.filter { $0.verdict == .uncertain }.count }
    @discardableResult mutating func append(_ reading: WatchReading) -> Bool {
        guard reading.valid, !readings.contains(where: { $0.id == reading.id }),
              readings.last.map({ reading.date > $0.date }) ?? true else { return false }
        readings.append(reading); return true
    }
}
