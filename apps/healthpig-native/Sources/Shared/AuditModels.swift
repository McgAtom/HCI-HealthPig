import Foundation

struct AuditRate: Decodable {
    let accuracy: Double?
    let balancedAccuracy: Double?
    let f1: Double?
    let fnr: Double?
    let fpr: Double?
    let selectionRate: Double?
}
struct AuditGroup: Decodable, Identifiable {
    let id: String
    let name: String
    let people: Int
    let positive: Int
    let negative: Int
    let baseline: AuditRate
    let candidate: AuditRate
    let caution: String
}
struct AuditAttribute: Decodable, Identifiable {
    let id: String
    let name: String
    let baselineEO: Double?
    let candidateEO: Double?
    let groups: [AuditGroup]
}
struct AuditDocument: Decodable {
    let title: String
    let dataset: String
    let recordUnit: String
    let positiveName: String
    let negativeName: String
    let falseNegativeExplanation: String
    let falsePositiveExplanation: String
    let people: Int
    let windows: Int
    let selectedBound: Double
    let recommended: Bool
    let baseline: AuditRate
    let candidate: AuditRate
    let attributes: [AuditAttribute]
    let conclusion: String
    let eoInterval: [Double]?
}
