import Foundation

/// Estimates the duration of the upcoming main sleep episode from seven calendar days of history.
struct SleepForecast: Decodable {
    struct Range: Codable, Equatable {
        let low, high: Int
    }

    private struct Tree: Decodable {
        let left, right, feature: [Int]
        let threshold, value: [Double]

        func predict(_ input: [Double]) -> Double? {
            var node = 0
            // A valid tree never visits as many nodes as its full node count more than once.
            for _ in left.indices {
                guard left.indices.contains(node), right.indices.contains(node), feature.indices.contains(node),
                      threshold.indices.contains(node), value.indices.contains(node) else { return nil }
                if left[node] == -1 { return value[node] }
                let column = feature[node]
                guard input.indices.contains(column) else { return nil }
                // sklearn trees compare float32-converted input against a double threshold.
                node = Double(Float(input[column])) <= threshold[node] ? left[node] : right[node]
            }
            return nil
        }
    }

    private let schemaVersion, radiusMinutes: Int
    private let model: String
    private let features: [String]
    private let intercept, learningRate: Double?
    private let weights: [Double]?
    private let trees: [Tree]?

    private static let featureOrder = [
        "median_minutes", "mean_minutes", "sd_minutes", "recent_two_mean",
        "last_minutes", "median_start", "median_end", "nights", "last_gap", "weekend",
    ]

    static let bundled: SleepForecast? = {
        guard let url = Bundle.main.url(forResource: "sleep-forecast", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SleepForecast.self, from: data)
    }()

    func predict(nights: [SleepSchedule.Night], wake: Date, now: Date, calendar: Calendar) -> Range? {
        guard let input = Self.inputs(nights: nights, wake: wake, now: now, calendar: calendar),
              let predicted = estimate(input), (180...720).contains(predicted),
              (1...240).contains(radiusMinutes) else { return nil }
        let low = Int(floor((predicted - Double(radiusMinutes)) / 15)) * 15
        let high = Int(ceil((predicted + Double(radiusMinutes)) / 15)) * 15
        return Range(low: max(180, low), high: min(720, high))
    }

    func estimate(_ input: [Double]) -> Double? {
        guard schemaVersion == 1, features == Self.featureOrder, input.count == features.count,
              input.allSatisfy(\.isFinite) else { return nil }
        switch model {
        case "median":
            return input[0]
        case "ridge":
            guard let intercept, let weights, weights.count == input.count else { return nil }
            return zip(weights, input).reduce(intercept) { $0 + $1.0 * $1.1 }
        case "boosted_trees":
            guard let intercept, let learningRate, let trees, !trees.isEmpty else { return nil }
            var estimate = intercept
            for tree in trees {
                guard let value = tree.predict(input) else { return nil }
                estimate += learningRate * value
            }
            return estimate
        default:
            return nil
        }
    }

    static func inputs(nights: [SleepSchedule.Night], wake: Date, now: Date, calendar: Calendar) -> [Double]? {
        let wakeDay = calendar.startOfDay(for: wake)
        // Once the target night is in progress, the full-night forecast no longer answers the plan's question.
        guard calendar.startOfDay(for: now) < wakeDay,
              let earliestNight = calendar.date(byAdding: .day, value: -7, to: wakeDay) else { return nil }
        var byDay: [Int: SleepSchedule.Night] = [:]
        for night in nights {
            let endDay = calendar.startOfDay(for: night.end)
            let startDay = calendar.startOfDay(for: night.start)
            let start = SleepSchedule.clockMinutes(night.start, calendar: calendar)
            let end = SleepSchedule.clockMinutes(night.end, calendar: calendar)
            let span = night.end.timeIntervalSince(night.start) / 60
            guard endDay >= earliestNight, endDay < wakeDay, night.end <= now,
                  (180...720).contains(night.asleepMinutes), (180...840).contains(span),
                  Double(night.asleepMinutes) <= span + 61, end < 720,
                  (startDay == endDay && start < 360)
                  || (start >= 1200 && calendar.date(byAdding: .day, value: 1, to: startDay) == endDay),
                  let offset = calendar.dateComponents([.day], from: endDay, to: wakeDay).day else { continue }
            if let existing = byDay[offset],
               existing.asleepMinutes > night.asleepMinutes
               || (existing.asleepMinutes == night.asleepMinutes && existing.start <= night.start) { continue }
            byDay[offset] = night
        }
        let offsets = byDay.keys.sorted()
        let history = offsets.compactMap { byDay[$0] }
        guard history.count >= 3, let first = offsets.first else { return nil }
        let durations = history.map { Double($0.asleepMinutes) }
        let avg = durations.reduce(0, +) / Double(durations.count)
        let deviation = sqrt(durations.reduce(0) { $0 + pow($1 - avg, 2) } / Double(durations.count))
        let start = median(history.map {
            let minute = SleepSchedule.clockMinutes($0.start, calendar: calendar)
            return Double(minute >= 720 ? minute - 1440 : minute)
        })
        let end = median(history.map { Double(SleepSchedule.clockMinutes($0.end, calendar: calendar)) })
        let weekday = calendar.component(.weekday, from: wakeDay)
        return [median(durations), avg, deviation, (durations[0] + durations[1]) / 2, durations[0],
                start, end, Double(durations.count), Double(first), weekday == 1 || weekday == 7 ? 1 : 0]
    }

    private static func median(_ input: [Double]) -> Double {
        let sorted = input.sorted()
        return (sorted[(sorted.count - 1) / 2] + sorted[sorted.count / 2]) / 2
    }
}
