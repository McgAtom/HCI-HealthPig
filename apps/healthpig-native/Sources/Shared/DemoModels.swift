import Foundation

struct DemoExample: Decodable, Identifiable {
    let id: String
    let name: String
    let features: [Double]
}
struct DemoExamples: Decodable {
    let source: String
    let sourceURL: String
    let license: String
    let featureNames: [String]
    let featureUnits: [String]
    let examples: [DemoExample]
    func validated() throws -> DemoExamples {
        guard featureNames.count == 24, featureUnits.count == 24, !examples.isEmpty,
              Set(examples.map(\.id)).count == examples.count,
              examples.allSatisfy({ $0.features.count == 24 && $0.features.allSatisfy(\.isFinite) }) else {
            throw PigDataError.invalid("公开演示样本不完整，请重新安装应用。")
        }
        return self
    }
}
