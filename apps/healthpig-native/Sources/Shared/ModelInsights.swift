import Foundation

struct ModelInsights: Decodable {
    struct Bin: Decodable {
        let lower, upper: Double
        let count: Int
    }
    struct Feature: Decodable, Identifiable {
        let id, title, unit, meaning: String
        let index: Int
        let mean, low, high: Double
        let bins: [Bin]
        func formatted(_ value: Double) -> String {
            value.formatted(.number.precision(.fractionLength(0...(unit == "g" ? 3 : 2))))
        }
        var suffix: String { unit == "无单位" ? "" : " " + unit }
    }
    struct Example: Decodable, Identifiable {
        let id: String
        let actual, prediction: Int
        let score: Double
        let inputs: [Double]
        var correct: Bool { actual == prediction }
        func value(for feature: Feature) -> String {
            let raw = inputs[feature.index]
            return feature.formatted(raw * (feature.unit == "%" ? 100 : 1)) + feature.suffix
        }
        static func label(_ value: Int) -> String { value == 1 ? "步行" : "坐／站" }
    }
    let schema, windows, people, walking, still, repeats: Int
    let dataset, split: String
    let baseline, threshold: Double
    let overview: [String]
    let features: [Feature]
    let cases: [Example]

    var highlights: [Feature] { features.filter { overview.contains($0.id) } }
    var domain: ClosedRange<Double> {
        let minimum = features.map(\.low).min() ?? 0
        let maximum = features.map(\.high).max() ?? 0
        return min(-2, floor(minimum / 5) * 5)...max(5, ceil(maximum / 5) * 5)
    }
    var ticks: [Double] {
        [domain.lowerBound, 0, 20, 40].filter { domain.contains($0) }
    }
    static func load() -> Self? {
        guard let url = Bundle.main.url(forResource: "model-insights", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(Self.self, from: data),
              value.schema == 1, value.split == "validation",
              value.windows > 0, value.people > 0, value.repeats > 0,
              value.walking + value.still == value.windows, value.features.count == 24,
              Set(value.features.map(\.index)) == Set(0..<24),
              value.highlights.count == 5,
              value.features.allSatisfy({ feature in
                  feature.low <= feature.mean && feature.mean <= feature.high &&
                  !feature.bins.isEmpty && feature.bins.reduce(0, { $0 + $1.count }) == value.windows
              }),
              value.cases.allSatisfy({ $0.inputs.count == 24 }) else { return nil }
        return value
    }
}
