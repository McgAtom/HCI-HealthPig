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
