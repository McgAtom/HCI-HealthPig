import SwiftUI
import WatchKit

// Short, foreground-only sessions reuse the frozen ten-second pipeline unchanged.
struct WalkingCompanionView: View {
    @ObservedObject var store: PigStore
    @StateObject private var motion = LiveMotion()
    @Environment(\.scenePhase) private var scenePhase
    @State private var segments = CompanionSegments()
    @State private var running = false
    @State private var ended = false
    @State private var generation = UUID()
    @State private var segmentGoal = 3
    var body: some View {
        PigScreen {
            if running || ended {
                PigResponseScene(card: store.companion, verdict: segments.readings.last?.verdict ?? .waiting, compact: true)
            } else {
                HStack(spacing: 8) {
                    if let card = store.companion { PigArtwork(card: card, size: 64).frame(width: 68) }
                    Text("走走，陪猪猪").font(.headline)
                }
            }
            if running {
                Button("结束") { stop() }.buttonStyle(PigPrimaryButton()).accessibilityIdentifier("companion.stop")
                Text("第 \(segments.readings.count + 1) / \(segmentGoal) 段").font(.headline)
                ProgressView(value: motion.progress).tint(PigTheme.mint)
                Text(motion.capturing ? "正在采集约 10 秒动作" : "准备下一片段…").font(.caption)

            } else if ended {
                Text("本次陪伴结束").font(.headline)
                if segments.readings.isEmpty {
                    StatusNote(title: "没有有效动作结果", message: motion.error.isEmpty ? "采集已停止。没有把未采到的时间记成静止。" : motion.error, symbol: "exclamationmark.triangle")
                        .accessibilityIdentifier("companion.no-result")
                } else {
                    Text("\(segments.readings.count) 个有效片段：步行 \(segments.walking)，坐／站 \(segments.still)，拿不准 \(segments.uncertain)。").font(.caption).accessibilityIdentifier("companion.summary")

                    ForEach(Array(segments.readings.enumerated()), id: \.element.id) { index, reading in
                        NavigationLink("第 \(index + 1) 段 · \(reading.verdict.title)") { PigScreen { ReadingResultView(store: store, reading: reading) }.navigationTitle("片段与反馈") }
                    }
                }
                Button("再来") { start() }.buttonStyle(PigPrimaryButton()).accessibilityIdentifier("companion.start")
            } else {
                Button("出发") { start() }.buttonStyle(PigPrimaryButton()).accessibilityIdentifier("companion.start")
                Picker("陪伴长度", selection: $segmentGoal) {
                    Text("试一试 · 1段").tag(1)
                    Text("走一会 · 3段").tag(3)
                }.pickerStyle(.navigationLink).accessibilityIdentifier("companion.length")
                Text("每段约10秒，离开即停止。").font(.caption).foregroundStyle(.secondary)
            }
            NavigationLink("样本演示") { DemoAnalysisView(companionCard: store.companion) }.font(.caption).accessibilityIdentifier("companion.demo")

            NavigationLink("玩法与模型") { CompanionGuideView() }.font(.caption)
            StoreErrorView(store: store)
        }.navigationTitle("养猪")
            .onChange(of: motion.measuredAt) { _, date in
                guard running, let date, let score = motion.score, let hz = motion.actualHz else { return }
                let reading = WatchReading(id: UUID(), date: date, verdict: motion.verdict, score: score,
                    threshold: motion.threshold, sampleCount: motion.sampleCount, actualHz: hz)
                guard segments.append(reading) else { stop(); return }
                store.record(reading)
                WKInterfaceDevice.current().play(.click)
                if segments.readings.count == segmentGoal { stop(); return }
                let expected = generation
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1))
                    guard running, generation == expected, scenePhase == .active else { return }
                    motion.start()
                    if !motion.error.isEmpty { stop() }
                }
            }
            .onChange(of: motion.error) { _, error in if running && !error.isEmpty { stop() } }
            .onChange(of: scenePhase) { _, phase in if phase != .active && running { stop() } }
            .onDisappear { if running { stop() } }
    }
    private func start() {
        guard !running else { return }
        generation = UUID(); segments = CompanionSegments(); ended = false; running = true
        motion.error = ""; motion.start()
        if !motion.error.isEmpty { stop() }
    }
    private func stop() {
        generation = UUID(); running = false; ended = true; motion.cancel()
    }
}
