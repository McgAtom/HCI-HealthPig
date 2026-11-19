import Foundation

struct SleepSchedule {
    struct Interval {
        let start, end: Date
        let source: String
    }

    struct Night {
        let start, end: Date
        let asleepMinutes: Int
    }

    struct Proposal {
        let bedtime, wake: Date
        let reservedMinutes, nightsUsed: Int
        let fallsShort: Bool
    }

    static let targetRange = 420...540

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
        mainNights(input, now: now, calendar: calendar).map(\.asleepMinutes)
    }

    static func mainNights(_ input: [Interval], now: Date, calendar: Calendar) -> [Night] {
        guard let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: now) else { return [] }
        let sources = Dictionary(grouping: input, by: \.source)
        let candidates = sources.map { source, intervals in
            let nights = (0..<7).compactMap { offset -> Night? in
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

    private static func mainSleep(_ intervals: [Interval], start: Date, end: Date) -> Night? {
        let clipped = intervals.map { (start: max($0.start, start), end: min($0.end, end)) }
            .filter { $0.end > $0.start }.sorted { $0.start < $1.start }
        guard var span = clipped.first else { return nil }
        var first = span.start, night = 0.0
        var best: Night?
        func consider(end: Date) {
            let minutes = Int(night / 60)
            if minutes >= 180 && minutes > (best?.asleepMinutes ?? 0) {
                best = Night(start: first, end: end, asleepMinutes: minutes)
            }
        }
        for next in clipped.dropFirst() {
            if next.start <= span.end {
                span.end = max(span.end, next.end)
            } else {
                night += span.end.timeIntervalSince(span.start)
                if next.start.timeIntervalSince(span.end) > 3600 {
                    consider(end: span.end)
                    night = 0; first = next.start
                }
                span = next
            }
        }
        night += span.end.timeIntervalSince(span.start)
        consider(end: span.end)
        return best
    }

    static func wakeWindow(now: Date, calendar: Calendar) -> ClosedRange<Date>? {
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
              let start = clockDate(240, on: tomorrow, calendar: calendar),
              let end = clockDate(720, on: tomorrow, calendar: calendar) else { return nil }
        return start...end
    }

    static func recommend(nights: [Night], target: Int, latestWake: Date, now: Date,
                          calendar: Calendar = .current) -> Proposal? {
        guard let window = wakeWindow(now: now, calendar: calendar), window.contains(latestWake),
              let evening = clockDate(1080, on: now, calendar: calendar) else { return nil }
        let remaining = max(now, evening)
        let firstBed = nextQuarter(remaining, calendar: calendar)
        guard firstBed < latestWake else { return nil }

        let target = min(targetRange.upperBound, max(targetRange.lowerBound, target))
        let typicalNights = nights.filter { night in
            let start = clockMinutes(night.start, calendar: calendar)
            return (start >= 1080 || start < 360) && clockMinutes(night.end, calendar: calendar) <= 720
        }
        let showsRoutine = typicalNights.count >= 3
        let durations = SleepSchedule(target: target, nights: typicalNights.map(\.asleepMinutes))
        let typicalWake = showsRoutine ? median(typicalNights.map { clockMinutes($0.end, calendar: calendar) }) : 450
        let wakeCenter = clockDate(typicalWake, on: latestWake, calendar: calendar) ?? latestWake
        let bedCenter: Date
        if showsRoutine {
            // Noon separates the prior evening from the morning, so midnight is continuous.
            let usual = median(typicalNights.map { night in
                let minutes = clockMinutes(night.start, calendar: calendar)
                return minutes >= 720 ? minutes - 1440 : minutes
            })
            let day = usual < 0 ? now : latestWake
            bedCenter = clockDate((usual + 1440) % 1440, on: day, calendar: calendar) ?? evening
        } else {
            bedCenter = min(wakeCenter, latestWake).addingTimeInterval(-Double(target * 60))
        }

        let availableMinutes = Int(latestWake.timeIntervalSince(firstBed) / 60)
        if availableMinutes < target {
            return Proposal(bedtime: firstBed, wake: latestWake, reservedMinutes: availableMinutes,
                            nightsUsed: durations.typicalDuration == nil ? 0 : typicalNights.count, fallsShort: true)
        }

        var wakeDates = strideDates(from: window.lowerBound, through: latestWake)
        if wakeDates.last != latestWake { wakeDates.append(latestWake) }
        var best: (score: Double, plan: Proposal)?
        for wake in wakeDates {
            let lastBed = wake.addingTimeInterval(-Double(target * 60))
            for bedtime in strideDates(from: firstBed, through: lastBed) {
                let minutes = Int(wake.timeIntervalSince(bedtime) / 60)
                let timing = (abs(bedtime.timeIntervalSince(bedCenter)) + abs(wake.timeIntervalSince(wakeCenter))) / 60
                let score = timing + 3 * Double(abs(minutes - durations.duration))
                if best.map({ score < $0.score }) ?? true {
                    best = (score, Proposal(bedtime: bedtime, wake: wake, reservedMinutes: minutes,
                                            nightsUsed: showsRoutine ? typicalNights.count : 0, fallsShort: false))
                }
            }
        }
        return best?.plan
    }

    static func clockMinutes(_ date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    static func clockDate(_ minutes: Int, on day: Date, calendar: Calendar) -> Date? {
        guard let result = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day),
              calendar.isDate(result, inSameDayAs: day) else { return nil }
        return result
    }

    private static func median(_ values: [Int]) -> Int {
        let values = values.sorted()
        return (values[(values.count - 1) / 2] + values[values.count / 2]) / 2
    }

    private static func nextQuarter(_ date: Date, calendar: Calendar) -> Date {
        let start = calendar.dateInterval(of: .minute, for: date)?.start ?? date
        let remaining = (15 - calendar.component(.minute, from: date) % 15) % 15
        let result = start.addingTimeInterval(Double(remaining * 60))
        return result < date ? result.addingTimeInterval(900) : result
    }

    private static func strideDates(from start: Date, through end: Date) -> [Date] {
        guard start <= end else { return [] }
        return stride(from: 0.0, through: end.timeIntervalSince(start), by: 900).map { start.addingTimeInterval($0) }
    }
}
