import Foundation
import CoreMotion
import Combine
import WatchKit

@MainActor final class LiveMotion: ObservableObject {
    @Published var capturing = false
    @Published var progress = 0.0
    @Published var message = "戴好手表，测一次10秒动作"
    @Published var error = ""
    @Published var score: Double?
    @Published var measuredAt: Date?
    @Published var actualHz: Double?
    @Published var sampleCount = 0
    @Published private(set) var threshold = 0.5
    @Published private(set) var lastSummary: MotionSummary?
    var verdict: MotionVerdict { MotionVerdict.decide(score: score, threshold: threshold) }
    private let manager = CMMotionManager()
    private var timer: Timer?
    private var points: [MotionPoint] = []
    private var began: Date?
    private var model: MotionModel?

    init() {
        if let url = Bundle.main.url(forResource: "motion-model", withExtension: "json") {
            model = try? JSONDecoder().decode(MotionModel.self, from: Data(contentsOf: url))
            threshold = model?.threshold ?? 0.5
        }
        if let data = UserDefaults.standard.data(forKey: "lastMotionSummaryV2") {
            lastSummary = try? JSONDecoder().decode(MotionSummary.self, from: data)
        }
    }

    func start() {
        guard !capturing else { return }
        guard manager.isAccelerometerAvailable else { error = "当前设备没有可用加速度计"; return }
        guard model != nil else { error = "动作模型尚未安装，不显示模拟判断"; return }
        guard WKApplication.shared().applicationState == .active else {
            error = "请先打开应用，再开始测量"; return
        }
        score = nil; measuredAt = nil; error = ""; points = []; sampleCount = 0; actualHz = nil
        capturing = true; progress = 0
        began = Date(); message = "采样中"
        manager.accelerometerUpdateInterval = 1.0/20.0
        manager.startAccelerometerUpdates(to: .main) { [weak self] data, failure in
            guard let self else { return }
            if let failure { self.error = failure.localizedDescription; self.cancel(); return }
            guard let data, self.capturing else { return }
            let a = data.acceleration
            if a.x.isFinite && a.y.isFinite && a.z.isFinite {
                self.points.append(MotionPoint(time: data.timestamp, x: a.x, y: a.y, z: a.z))
                self.sampleCount = self.points.count
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let began = self.began, self.capturing else { return }
                self.progress = min(Date().timeIntervalSince(began)/10.5, 1)
                if self.progress >= 1 { self.finish() }
            }
        }
    }

    func cancel() {
        manager.stopAccelerometerUpdates(); timer?.invalidate(); timer = nil
        capturing = false; points = []; progress = 0
        if score == nil { message = "采集已停止，未产生判断" }
    }

    func clearSummary() {
        lastSummary = nil; UserDefaults.standard.removeObject(forKey: "lastMotionSummaryV2")
    }

    private func finish() {
        manager.stopAccelerometerUpdates(); timer?.invalidate(); timer = nil; capturing = false
        guard let first = points.first, let last = points.last,
              last.time-first.time >= 9.95, points.count >= 160 else {
            error = "样本不足，请重新打开应用开始测量"; message = "这次没有判断"; points = []; return
        }
        let intervals = zip(points.dropFirst(), points).map { $0.time-$1.time }
        guard intervals.allSatisfy({ $0 > 0 && $0 <= 0.25 }) else {
            error = "采样中断，请重新测量"; message = "这次没有判断"; points = []; return
        }
        actualHz = Double(points.count-1)/(last.time-first.time)
        // Resample by actual sensor timestamps onto the same 20Hz grid as training.
        var resampled: [MotionPoint] = []; var cursor = 0
        for i in 0..<200 {
            let time = first.time+Double(i)/20
            while cursor+1 < points.count && points[cursor+1].time < time { cursor += 1 }
            guard cursor+1 < points.count else { error = "采样时间不足"; points = []; return }
            let a = points[cursor], b = points[cursor+1], f = (time-a.time)/(b.time-a.time)
            resampled.append(MotionPoint(time: time, x: a.x+(b.x-a.x)*f, y: a.y+(b.y-a.y)*f, z: a.z+(b.z-a.z)*f))
        }
        guard let model else { return }
        let features = MotionFeatures.compute(resampled)
        let result = model.score(features)
        guard result.isFinite else { error = "无法计算，请重新测量"; points = []; return }
        score = result; measuredAt = Date()
        message = verdict.message
        let summary = MotionSummary(date: Date(), score: result, threshold: model.threshold,
             verdict: verdict, sampleCount: sampleCount, actualHz: actualHz ?? 0, features: features)
        lastSummary = summary
        if let data = try? JSONEncoder().encode(summary) {
            UserDefaults.standard.set(data, forKey: "lastMotionSummaryV2")
        }
        points = [] // Raw personal sensor samples stay in memory only.
    }
}

struct MotionSummary: Codable {
    let date: Date, score: Double, threshold: Double
    let verdict: MotionVerdict
    let sampleCount: Int, actualHz: Double
    let features: [Double]
}
