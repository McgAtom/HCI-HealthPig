import Foundation

struct ModelInsights: Decodable {
    enum Task: String, CaseIterable, Identifiable {
        case motion, sleep
        var id: Self { self }
        var title: String { self == .motion ? "动作" : "睡眠" }
        var resource: String { self == .motion ? "model-insights" : "sleep-forecast-insights" }
        var source: String { self == .motion ? "腕部加速度" : "近 7 天睡眠 · 次晨日期" }
        var icon: String { self == .motion ? "figure.walk" : "moon.stars" }
        var metric: String { self == .motion ? "表现下降" : "误差增加" }
        var unit: String { self == .motion ? "百分点" : "分钟" }
        var sampleName: String { self == .motion ? "窗口" : "晚" }
        var scope: String { self == .motion ? "只看动作，不判病因" : "预测实睡时长" }
        var baselineName: String { self == .motion ? "验证集基线" : "原始平均误差" }
        var comparison: String { self == .motion ? "这两段" : "这两晚" }

        func impact(_ value: Double) -> String {
            self == .motion ? String(format: "%+.2f", value) : String(format: "%+.3f", value)
        }

        func output(_ value: Double) -> String {
            switch self {
            case .motion: value == 1 ? "步行" : "坐／站"
            case .sleep: value.formatted(.number.precision(.fractionLength(0...1))) + " 分钟"
            }
        }

        func caseTitle(_ id: String) -> String {
            switch self {
            case .motion: id == "correct" ? "判对" : "判错"
            case .sleep: id == "near" ? "偏差较小" : "偏差较大"
            }
        }
    }

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
        var suffix: String { ["无单位", "0 / 1"].contains(unit) ? "" : " " + unit }
    }

    struct Example: Decodable, Identifiable {
        let id: String
        let actual, prediction: Double
        let inputs: [Double]

        var positive: Bool { id == "correct" || id == "near" }

        func value(for feature: Feature) -> String {
            let raw = inputs[feature.index]
            return feature.formatted(raw * (feature.unit == "%" ? 100 : 1)) + feature.suffix
        }
    }

    let schema, windows, people, repeats: Int
    let dataset, split: String
    let baseline: Double
    let overview: [String]
    let features: [Feature]
    let cases: [Example]

    var highlights: [Feature] { features.filter { overview.contains($0.id) } }

    func domain(for task: Task) -> ClosedRange<Double> {
        let minimum = features.map(\.low).min() ?? 0
        let maximum = features.map(\.high).max() ?? 0
        if task == .motion {
            return min(-2, floor(minimum / 5) * 5)...max(5, ceil(maximum / 5) * 5)
        }
        return min(-0.4, floor(minimum * 2) / 2)...max(1, ceil(maximum * 2) / 2)
    }

    func ticks(for task: Task) -> [Double] {
        if task == .motion { return [0, 20, 40] }
        let axis = domain(for: task)
        let step = max(1, floor(axis.upperBound / 2))
        return [0, step, step * 2, step * 3].filter { axis.contains($0) }
    }

    static func load(_ task: Task) -> Self? {
        guard let url = Bundle.main.url(forResource: task.resource, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return decode(data, task: task)
    }

    static func decode(_ data: Data, task: Task) -> Self? {
        let count = task == .motion ? 24 : 10
        let caseIDs = task == .motion ? Set(["correct", "wrong"]) : Set(["near", "far"])
        guard let value = try? JSONDecoder().decode(Self.self, from: data),
              value.schema == (task == .motion ? 1 : 2),
              value.split == (task == .motion ? "validation" : "external"),
              value.windows > 0, value.people > 0, value.repeats > 0,
              value.features.count == count, Set(value.features.map(\.index)) == Set(0..<count),
              Set(value.features.map(\.id)).count == count, value.highlights.count == 5,
              value.features.allSatisfy({ feature in
                  feature.low <= feature.mean && feature.mean <= feature.high &&
                  !feature.bins.isEmpty && feature.bins.reduce(0, { $0 + $1.count }) == value.windows
              }),
              value.cases.isEmpty || (value.cases.count == 2 && Set(value.cases.map(\.id)) == caseIDs),
              value.cases.allSatisfy({ $0.inputs.count == count }) else { return nil }
        return value
    }
}
