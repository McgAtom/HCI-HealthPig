import Foundation

struct MotionPoint { let time: Double, x: Double, y: Double, z: Double }

enum MotionVerdict: String, Codable {
    case waiting, walking, still, uncertain
    static func decide(score: Double?, threshold: Double) -> MotionVerdict {
        guard let score, score.isFinite else { return .waiting }
        if abs(score-threshold) < 0.1 { return .uncertain }
        return score >= threshold ? .walking : .still
    }
    var message: String {
        switch self {
        case .waiting: return "戴好手表，测一次10秒动作"
        case .walking: return "猪猪跟你一起步行"
        case .still: return "这次更像坐／站"
        case .uncertain: return "猪猪还拿不准，请再测一次"
        }
    }
}

struct MotionModel: Decodable {
    struct Tree: Decodable {
        let left: [Int], right: [Int], feature: [Int]
        let threshold: [Double], positive_probability: [Double]
    }
    let name: String, kind: String, threshold: Double
    let mean: [Double]?, scale: [Double]?, coefficients: [Double]?, intercept: Double?
    let trees: [Tree]?
    func score(_ x: [Double]) -> Double {
        guard x.count == 24, x.allSatisfy({ $0.isFinite }) else { return .nan }
        if kind == "logistic", let mean, let scale, let coefficients, let intercept {
            let z = x.indices.reduce(intercept) { $0+coefficients[$1]*(x[$1]-mean[$1])/scale[$1] }
            return 1/(1+exp(-z))
        }
        guard let trees, !trees.isEmpty else { return .nan }
        let values = x.map { Double(Float($0)) }
        return trees.reduce(0) { total, tree in
            var node = 0
            while tree.left[node] != -1 {
                node = values[tree.feature[node]] <= tree.threshold[node] ? tree.left[node] : tree.right[node]
            }
            return total+tree.positive_probability[node]
        }/Double(trees.count)
    }
}

enum MotionFeatures {
    static func compute(_ points: [MotionPoint]) -> [Double] {
        precondition(points.count == 200)
        let magnitude = points.map { sqrt($0.x*$0.x+$0.y*$0.y+$0.z*$0.z) }
        let avg = mean(magnitude), centered = magnitude.map { $0-avg }, std = deviation(magnitude)
        let sorted = magnitude.sorted(), diffs = zip(magnitude.dropFirst(),magnitude).map { $0-$1 }
        let energy = centered.reduce(0) { $0+$1*$1 }
        let correlations = [1,10,20,40].map { lag -> Double in
            guard energy > 1e-12 else { return 0 }
            return (0..<(200-lag)).reduce(0) { $0+centered[$1]*centered[$1+lag] }/energy
        }
        var powers: [Double] = []
        for k in 1...80 {
            var real = 0.0, imaginary = 0.0
            for i in 0..<200 {
                let angle = 2*Double.pi*Double(k*i)/200
                real += centered[i]*cos(angle); imaginary -= centered[i]*sin(angle)
            }
            powers.append(real*real+imaginary*imaginary)
        }
        let total = powers.reduce(0,+)
        let normalized = total > 1e-12 ? powers.map { $0/total } : powers.map { _ in 0.0 }
        var peak = 0
        for i in 1..<80 { if powers[i] > powers[peak] { peak = i } }
        let peakHz = total > 1e-12 ? Double(peak+1)/10 : 0
        func band(_ low: Int, _ high: Int) -> Double {
            (low...high).reduce(0) { $0+normalized[$1-1] }
        }
        let entropy = -normalized.reduce(0) { $0+$1*log(max($1,1e-30)) }
        let axes = [points.map(\.x),points.map(\.y),points.map(\.z)]
        let axisMeans = axes.map(mean), axisStd = axes.map(deviation)
        let meanNorm = sqrt(axisMeans.reduce(0) { $0+$1*$1 })
        let stdNorm = sqrt(axisStd.reduce(0) { $0+$1*$1 })
        let skew = std > 1e-6 ? mean(centered.map { $0*$0*$0 })/(std*std*std) : 0
        return [avg,std,quantile(sorted,0.1),quantile(sorted,0.5),quantile(sorted,0.9),sorted.last!-sorted.first!,
                mean(centered.map(abs)),sqrt(mean(magnitude.map { $0*$0 })),mean(diffs.map(abs)),deviation(diffs)]
            + correlations + [peakHz,band(2,7),band(8,29),band(30,80),entropy,meanNorm,stdNorm,
                              axisStd.min()!,axisStd.max()!,skew]
    }
    private static func mean(_ values: [Double]) -> Double { values.reduce(0,+)/Double(values.count) }
    private static func deviation(_ values: [Double]) -> Double {
        let avg = mean(values)
        return sqrt(values.reduce(0) { $0+($1-avg)*($1-avg) }/Double(values.count))
    }
    private static func quantile(_ values: [Double], _ q: Double) -> Double {
        let index = q*Double(values.count-1), low = Int(floor(index)), high = Int(ceil(index))
        return values[low]+(values[high]-values[low])*(index-Double(low))
    }
}
