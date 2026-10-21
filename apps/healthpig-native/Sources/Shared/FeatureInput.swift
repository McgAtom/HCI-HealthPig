import Foundation

enum FeatureInput {
    static func parse(_ text: String) throws -> [Double] {
        let normalized = text.replacingOccurrences(of: "，", with: ",").replacingOccurrences(of: ";", with: ",").replacingOccurrences(of: "；", with: ",")
        if normalized.contains(","), normalized.split(separator: ",", omittingEmptySubsequences: false).contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            throw PigDataError.invalid("有空白项，请补全数值或恢复示例。逗号之间不能留空。")
        }
        let parts = text.split(whereSeparator: { $0 == "," || $0 == "，" || $0 == ";" || $0 == "；" || $0.isWhitespace })
        guard parts.count == 24 else { throw PigDataError.invalid("需要24个数值，当前有\(parts.count)个。可恢复示例后再修改。") }
        return try parts.enumerated().map { index, token in
            guard let value = Double(token), value.isFinite else {
                throw PigDataError.invalid("第\(index + 1)项不是有效数值。请使用数字与小数点，不填空值、NaN或无穷大。")
            }
            return value
        }
    }
}

// Display labels only. Names, order, units and values of the frozen model remain unchanged.
enum FeatureLabels {
    static func title(_ name: String) -> String { labels[name] ?? name }
    private static let labels = [
        "mag_mean": "加速度幅值均值", "mag_std": "幅值标准差",
        "mag_p10": "幅值第10百分位", "mag_p50": "幅值中位数",
        "mag_p90": "幅值第90百分位", "mag_range": "幅值极差",
        "mag_abs_dev": "幅值平均绝对偏差", "mag_rms": "幅值均方根",
        "diff_abs_mean": "相邻幅值变化均值", "diff_std": "相邻幅值变化标准差",
        "acf1": "间隔1点自相关", "acf10": "间隔10点自相关",
        "acf20": "间隔20点自相关", "acf40": "间隔40点自相关",
        "peak_hz": "主频", "power_low": "低频功率占比",
        "power_walk": "步行频带功率占比", "power_high": "高频功率占比",
        "spectral_entropy": "频谱熵", "mean_vector_norm": "平均加速度向量模长",
        "axis_std_total": "三轴标准差合成幅值", "axis_std_min": "三轴最小标准差",
        "axis_std_max": "三轴最大标准差", "mag_skew": "幅值偏度"
    ]
}
