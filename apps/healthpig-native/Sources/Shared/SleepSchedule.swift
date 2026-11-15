import Foundation

struct SleepSchedule {
    struct Interval {
        let start, end: Date
        let source: String
    }

    let duration: Int
    let typicalDuration: Int?
    let nightCount: Int

    init(target: Int, nights: [Int]) {
        nightCount = nights.count
        let sorted = nights.sorted()
        guard sorted.count >= 3 else { typicalDuration = nil; duration = target; return }
        let middle = sorted.count / 2
        let typical = (sorted[(sorted.count - 1) / 2] + sorted[middle]) / 2
        typicalDuration = typical
        // Small planning buffer based on the user's goal, rounded down to the form's 15-minute steps.
        let buffer = min(30, max(0, target - typical) / 15 * 15)
        duration = min(720, target + buffer)
    }

    static func bedtime(wake: Int, duration: Int) -> Int { (wake - duration + 1440) % 1440 }

    static func recentNights(_ input: [Interval], now: Date, calendar: Calendar) -> [Int] {
        guard let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: now) else { return [] }
        let sources = Dictionary(grouping: input, by: \.source)
        let candidates = sources.map { source, intervals in
            let nights = (0..<7).compactMap { offset -> Int? in
                guard let end = calendar.date(byAdding: .day, value: -offset, to: noon),
                      let start = calendar.date(byAdding: .day, value: -1, to: end) else { return nil }
                return mainSleep(intervals, start: start, end: min(now, end))
            }
            return (source: source, nights: nights)
        }
        return candidates.sorted {
            if $0.nights.count != $1.nights.count { return $0.nights.count > $1.nights.count }
            return $0.source < $1.source
        }.first?.nights ?? []
    }

    private static func mainSleep(_ intervals: [Interval], start: Date, end: Date) -> Int? {
        let clipped = intervals.map { (start: max($0.start, start), end: min($0.end, end)) }
            .filter { $0.end > $0.start }.sorted { $0.start < $1.start }
        guard var span = clipped.first else { return nil }
        var night = 0.0, longest = 0.0
        for next in clipped.dropFirst() {
            if next.start <= span.end {
                span.end = max(span.end, next.end)
            } else {
                night += span.end.timeIntervalSince(span.start)
                if next.start.timeIntervalSince(span.end) > 3600 { longest = max(longest, night); night = 0 }
                span = next
            }
        }
        let minutes = Int(max(longest, night + span.end.timeIntervalSince(span.start)) / 60)
        return minutes >= 180 ? minutes : nil
    }
}
