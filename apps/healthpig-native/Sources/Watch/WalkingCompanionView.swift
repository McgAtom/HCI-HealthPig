import SwiftUI
import WatchKit

// Wrist-first: entering from the deliberate "养猪" action starts one capture.
struct WalkingCompanionView: View {
    @ObservedObject var store: PigStore
    @StateObject private var motion = LiveMotion()
    @Environment(\.scenePhase) private var scenePhase
    @State private var didEnter = false
    @State private var reading: WatchReading?
    @State private var demoVerdict: MotionVerdict?
    @AccessibilityFocusState private var outcomeFocused: Bool

    var body: some View {
        WatchFrame {
            VStack(spacing: 8) {
                if motion.capturing || !didEnter {
                    Image(systemName: "waveform.path").font(.title2).foregroundStyle(PigTheme.mint)
                    Text("采样中").font(.headline)
                    ProgressView(value: motion.progress).tint(PigTheme.mint)
                        .accessibilityLabel("动作采集").accessibilityValue("\(Int(motion.progress * 100))%")
                    Button("结束") { motion.cancel() }
                        .buttonStyle(PigPrimaryButton()).accessibilityIdentifier("companion.stop")
                } else if let verdict = demoVerdict ?? reading?.verdict {
                    if demoVerdict != nil {
                        Label("示例", systemImage: "play.rectangle").font(.footnote)
                    }
                    PigResponseScene(card: store.companion, verdict: verdict, compact: true)
                        .accessibilityFocused($outcomeFocused)
                    retry
                } else {
                    Image(systemName: "exclamationmark.circle").font(.title2).foregroundStyle(PigTheme.cream)
                    Text(motion.error.isEmpty ? "已结束" : "未采到动作")
                        .font(.headline).accessibilityValue(motion.error)
                        .accessibilityIdentifier("companion.no-result").accessibilityFocused($outcomeFocused)
                    retry
                    if !motion.error.isEmpty {
                        Button("看示例") { showDemo() }.buttonStyle(.bordered)
                            .accessibilityIdentifier("companion.demo")
                    }
                }
            }
        }.navigationTitle("测动作")
            .task {
                guard !didEnter else { return }
                didEnter = true
                start()
            }
            .onChange(of: motion.measuredAt) { _, date in
                guard let date, let score = motion.score, let hz = motion.actualHz else { return }
                let result = WatchReading(id: UUID(), date: date, verdict: motion.verdict, score: score,
                    threshold: motion.threshold, sampleCount: motion.sampleCount, actualHz: hz)
                reading = result; store.record(result); WKInterfaceDevice.current().play(.click)
                outcomeFocused = true
            }
            .onChange(of: motion.error) { _, error in if !error.isEmpty { outcomeFocused = true } }
            // Lowering the wrist makes a frontmost watchOS app inactive. The measurement can still finish.
            .onChange(of: scenePhase) { _, phase in
                if phase == .background && motion.capturing { motion.cancel() }
            }
            .onDisappear { if motion.capturing { motion.cancel() } }
    }

    private var retry: some View {
        Button("再来") { start() }.buttonStyle(PigPrimaryButton()).accessibilityIdentifier("companion.start")
    }
    private func start() {
        outcomeFocused = false
        demoVerdict = nil; reading = nil; motion.error = ""
        motion.start()
    }
    private func showDemo() {
        let bundle = Bundle.main
        guard let modelURL = bundle.url(forResource: "motion-model", withExtension: "json"),
              let demoURL = bundle.url(forResource: "demo-examples", withExtension: "json"),
              let modelBytes = try? Data(contentsOf: modelURL),
              let demoBytes = try? Data(contentsOf: demoURL),
              let model = try? JSONDecoder().decode(MotionModel.self, from: modelBytes),
              let demos = try? JSONDecoder().decode(DemoExamples.self, from: demoBytes).validated(),
              let example = demos.examples.first else { return }
        demoVerdict = MotionVerdict.decide(score: model.score(example.features), threshold: model.threshold)
        outcomeFocused = true
    }
}
