import CoreMotion
import SwiftUI

@MainActor final class PigWalk: ObservableObject {
    enum Phase: Equatable { case idle, active, finishing, finished, unavailable }

    @Published private(set) var phase = Phase.idle
    @Published private(set) var steps: Int?
    @Published private(set) var moving = false
    @Published private(set) var finalReading = false
    private let pedometer = CMPedometer()
    private var startDate: Date?
    private var lastReading: Date?
    private var lastIncrease: Date?
    private var session = UUID()
    private let usesUITestSteps: Bool = {
#if DEBUG && targetEnvironment(simulator)
        ProcessInfo.processInfo.arguments.contains("--walk-ui-test")
#else
        false
#endif
    }()

    var motionRestricted: Bool {
        let authorization = CMPedometer.authorizationStatus()
        return authorization == .denied || authorization == .restricted
    }

    func start() {
        guard phase != .active, phase != .finishing else { return }
        if unavailableDevice && !usesUITestSteps { phase = .unavailable; return }
        let now = Date()
        session = UUID(); startDate = now; lastReading = nil; lastIncrease = nil
        steps = nil; moving = false; finalReading = false; phase = .active
        let id = session
        if usesUITestSteps {
            apply(value: 12, end: now)
            return
        }
        pedometer.startUpdates(from: now) { [weak self] data, error in
            let value = data?.numberOfSteps.intValue, end = data?.endDate
            let failed = error != nil
            Task { @MainActor [weak self] in
                guard let self, self.session == id, self.phase == .active else { return }
                if failed, self.steps == nil {
                    self.pedometer.stopUpdates(); self.moving = false; self.phase = .unavailable
                }
                else { self.apply(value: value, end: end) }
            }
        }
    }

    func catchUp() {
        guard !usesUITestSteps, phase == .active, let startDate else { return }
        read(from: startDate, through: .now, finishing: false)
    }

    func finish() {
        guard phase == .active, let startDate else { return }
        if usesUITestSteps { finalReading = true; moving = false; phase = .finished; return }
        pedometer.stopUpdates(); moving = false; phase = .finishing
        read(from: startDate, through: .now, finishing: true)
    }

    func updatePose(at now: Date) {
        let active = lastIncrease.map { now.timeIntervalSince($0) < 8 } ?? false
        if moving != active { moving = active }
    }

    var isUITestSession: Bool { usesUITestSteps }

    private var unavailableDevice: Bool {
#if targetEnvironment(simulator)
        return true
#else
        return !CMPedometer.isStepCountingAvailable() || motionRestricted
#endif
    }

    private func read(from start: Date, through end: Date, finishing: Bool) {
        let id = session
        pedometer.queryPedometerData(from: start, to: end) { [weak self] data, error in
            let value = error == nil ? data?.numberOfSteps.intValue : nil
            let timestamp = data?.endDate
            Task { @MainActor [weak self] in
                guard let self, self.session == id, self.phase == (finishing ? .finishing : .active) else { return }
                self.apply(value: value, end: timestamp)
                if finishing {
                    self.finalReading = value != nil && timestamp != nil
                    self.moving = false; self.phase = .finished
                }
            }
        }
    }

    private func apply(value: Int?, end: Date?) {
        guard let value, let end, lastReading.map({ end >= $0 }) ?? true else { return }
        if value > (steps ?? 0) { lastIncrease = end }
        lastReading = end
        steps = value
        if phase == .active { updatePose(at: .now) }
    }
}

struct PigWalkView: View {
    @ObservedObject var walk: PigWalk
    @ObservedObject var store: PigStore
    @ObservedObject var health: HealthReader

    var body: some View {
        WatchFrame {
            VStack(spacing: 7) {
                switch walk.phase {
                case .idle, .unavailable:
                    Label(walk.motionRestricted ? "需开启运动权限" : "计步暂不可用", systemImage: "figure.walk.circle")
                        .font(.headline).accessibilityIdentifier("walk.unavailable")
                    Button("重试") { walk.start() }.buttonStyle(.bordered)
                    modelLink.buttonStyle(PigPrimaryButton())
                case .active, .finishing:
                    PigResponseScene(card: store.companion,
                                     verdict: walk.moving ? .walking : walk.steps == nil ? .waiting : .still, compact: true)
                    Text(walk.steps.map { "\(walk.isUITestSession ? "测试 " : "")\($0) 步" } ?? "等待计步")
                        .font(.headline).monospacedDigit().accessibilityIdentifier("walk.steps")
                    Button(walk.phase == .finishing ? "正在结束…" : "结束陪走") { walk.finish() }
                        .buttonStyle(PigPrimaryButton()).disabled(walk.phase == .finishing).accessibilityIdentifier("walk.stop")
                case .finished:
                    Label(walk.steps.map { "\(walk.isUITestSession ? "测试" : walk.finalReading ? "本次" : "最近记录") \($0) 步" } ?? "暂无本次步数",
                          systemImage: "checkmark.circle")
                        .font(.headline).accessibilityIdentifier("walk.finished")
                    if let energy = health.rings?.energy() {
                        Label("今日能量 \(energy)", systemImage: "flame.fill").font(.subheadline)
                    }
                    Button("再陪一次") { walk.start() }.buttonStyle(PigPrimaryButton())
                    modelLink.buttonStyle(.bordered)
                }
            }.padding(.top, 10)
        }.navigationTitle("陪走")
            .task { if walk.phase != .active && walk.phase != .finishing { walk.start() } }
            .task(id: walk.phase) { if walk.phase == .finished, !walk.isUITestSession, health.readsRings { await health.refreshRings() } }
            .task(id: walk.phase) {
                while !Task.isCancelled && walk.phase == .active {
                    walk.updatePose(at: .now)
                    try? await Task.sleep(for: .seconds(2))
                }
            }
    }

    private var modelLink: some View {
        NavigationLink("测动作") { WalkingCompanionView(store: store) }.accessibilityIdentifier("walk.model")
    }
}
