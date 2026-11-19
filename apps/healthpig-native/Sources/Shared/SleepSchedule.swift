import Foundation

struct SleepSchedule {
    struct Interval {
        let start, end: Date
        let source: String
    }

    struct Night: Equatable {
        let start, end: Date
        let asleepMinutes: Int
    }

    struct Basis: Codable, Equatable {
        let targetMinutes, observedNights: Int
        let latestWake: Date
        let usualBedtime, usualWake, typicalAsleepMinutes: Int?
        var goalWake: Date? = nil
        var forecast: SleepForecast.Range? = nil
    }

    struct Proposal: Codable, Equatable {
        let bedtime, wake: Date
        let reservedMinutes, nightsUsed: Int
        let fallsShort: Bool
        var basis: Basis? = nil
    }

    static let targetRange = 420...540
    static let defaultRoutineWake = 7 * 60 + 30
    private static let transitionStep: TimeInterval = 30 * 60

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
        let midnight = calendar.startOfDay(for: now)
        // Until the first supported wake time, keep planning the night that is still in progress.
        let offset = clockMinutes(now, calendar: calendar) < 240 ? 0 : 1
        guard let morning = calendar.date(byAdding: .day, value: offset, to: midnight),
              let start = clockDate(240, on: morning, calendar: calendar),
              let end = clockDate(720, on: morning, calendar: calendar) else { return nil }
        return start...end
    }

    static func recommend(nights: [Night], target: Int, latestWake: Date, now: Date,
                          routineWake: Int = defaultRoutineWake, calendar: Calendar = .current) -> Proposal? {
        guard let window = wakeWindow(now: now, calendar: calendar), window.contains(latestWake),
              let eveningDay = calendar.date(byAdding: .day, value: -1, to: latestWake),
              let evening = clockDate(1080, on: eveningDay, calendar: calendar),
              let goalWake = clockDate(routineWake, on: latestWake, calendar: calendar),
              window.contains(goalWake) else { return nil }
        let availableFrom = max(now, evening)
        guard availableFrom.addingTimeInterval(60) <= latestWake else { return nil }

        let target = min(targetRange.upperBound, max(targetRange.lowerBound, target))
        let typicalNights = nights.filter { night in
            let start = clockMinutes(night.start, calendar: calendar)
            return night.end <= evening &&
                (start >= 1080 || start < 360) && clockMinutes(night.end, calendar: calendar) <= 720
        }
        let durations = SleepSchedule(target: target, nights: typicalNights.map(\.asleepMinutes))
        let nightsUsed = durations.typicalDuration == nil ? 0 : typicalNights.count
        var usualBedtime: Int?
        var usualWake: Int?
        if nightsUsed > 0 {
            // Noon separates the prior evening from the morning on the clock.
            usualBedtime = median(typicalNights.map { night in
                let minutes = clockMinutes(night.start, calendar: calendar)
                return minutes >= 720 ? minutes - 1440 : minutes
            })
            usualWake = median(typicalNights.map { clockMinutes($0.end, calendar: calendar) })
        }
        let forecast = SleepForecast.bundled?.predict(nights: nights, wake: latestWake, now: now, calendar: calendar)
        let basis = Basis(targetMinutes: target, observedNights: typicalNights.count, latestWake: latestWake,
                          usualBedtime: usualBedtime.map { ($0 + 1440) % 1440 },
                          usualWake: usualWake, typicalAsleepMinutes: durations.typicalDuration,
                          goalWake: goalWake, forecast: forecast)
        func proposal(bedtime: Date, wake: Date) -> Proposal {
            let reserved = Int(wake.timeIntervalSince(bedtime) / 60)
            return Proposal(bedtime: bedtime, wake: wake, reservedMinutes: reserved, nightsUsed: nightsUsed,
                            fallsShort: reserved < target, basis: basis)
        }

        let firstWakeWithEnoughTime = availableFrom.addingTimeInterval(Double(target * 60))
        if firstWakeWithEnoughTime > latestWake {
            return proposal(bedtime: availableFrom, wake: latestWake)
        }

        // History sets the first step toward the wake goal. The saved goal stays fixed.
        let wakeTowardGoal: Date
        if let usualWake, let previousWake = clockDate(usualWake, on: latestWake, calendar: calendar) {
            let gap = goalWake.timeIntervalSince(previousWake)
            wakeTowardGoal = previousWake.addingTimeInterval(min(transitionStep, max(-transitionStep, gap)))
        } else {
            wakeTowardGoal = goalWake
        }

        let wake = min(latestWake, max(firstWakeWithEnoughTime, window.lowerBound, wakeTowardGoal))
        let bedtime = max(availableFrom, wake.addingTimeInterval(-Double(durations.duration * 60)))
        return proposal(bedtime: bedtime, wake: wake)
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
}
