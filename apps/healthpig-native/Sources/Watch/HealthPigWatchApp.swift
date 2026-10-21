import SwiftUI
import WatchKit

@main struct HealthPigWatchApp: App {
    @WKApplicationDelegateAdaptor(PigApplicationDelegate.self) private var delegate
    @StateObject private var store: PigStore
    @StateObject private var bridge: CompanionBridge
    init() {
        let store = PigStore()
        _store = StateObject(wrappedValue: store)
        _bridge = StateObject(wrappedValue: CompanionBridge(store: store))
    }
    var body: some Scene {
        WindowGroup {
            WatchRootView(store: store, bridge: bridge).modifier(PigAccessibilityTestSize()).preferredColorScheme(.dark).tint(PigTheme.rose)
        }
    }
}

@MainActor final class PigApplicationDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() { HealthReader.shared.beginAutomaticUpdatesIfEnabled() }
}

struct WatchRootView: View {
    @ObservedObject var store: PigStore
    @ObservedObject var bridge: CompanionBridge
    @StateObject private var health = HealthReader.shared
    @StateObject private var motion = LiveMotion()
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = ProcessInfo.processInfo.arguments.contains("--show-collection") ? 2 : ProcessInfo.processInfo.arguments.contains("--show-trends") ? 1 : 0
    var body: some View {
        NavigationStack {
            TabView(selection: $tab) {
                WatchTodayView(store: store, health: health, motion: motion).tag(0)
                TrendHomeView(health: health).tag(1)
                PigCollectionView(store: store).tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .safeAreaPadding(.bottom, 8)
            .navigationTitle(tab == 0 ? "走走猪猪" : tab == 1 ? "近期趋势" : "猪猪收藏")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { WatchMoreView(store: store, bridge: bridge, health: health) } label: {
                        Image(systemName: "ellipsis").foregroundStyle(PigTheme.background)
                    }.accessibilityLabel("更多与设置").accessibilityIdentifier("more.entry")
                }
            }
        }
        .onChange(of: scenePhase) { _, value in
            if value == .background, motion.capturing { motion.cancel() }
            if value == .active {
                store.refreshDay()
                Task { await health.refreshAutomaticallyIfEnabled() }
            }
        }
    }
}

struct WatchTodayView: View {
    @ObservedObject var store: PigStore
    @ObservedObject var health: HealthReader
    @ObservedObject var motion: LiveMotion
    var body: some View {
        PigScreen {
            HStack(spacing: 8) {
                if let card = store.companion {
                    PigArtwork(card: card, size: 64).frame(width: 68)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(card.name).font(.subheadline.weight(.semibold)).foregroundStyle(PigTheme.cream).lineLimit(2)
                        if store.ledger.selection == nil { Text("初始").font(.caption2).foregroundStyle(.secondary) }
                    }
                }
            }.frame(maxWidth: .infinity)
            NavigationLink { WalkingCompanionView(store: store) } label: {
                Label("养猪", systemImage: "figure.walk")
            }.buttonStyle(PigPrimaryButton()).accessibilityIdentifier("watch.companion")
            Text("满三环，抽猪猪").font(.caption2).foregroundStyle(.secondary)
            NavigationLink { ActivityRingsView(health: health) } label: {
                Label(health.rings?.canUnlock() == true ? "满能量" : "能量", systemImage: "flame")
            }.font(.caption).accessibilityIdentifier("watch.rings")
            NavigationLink { DailyRevealView(store: store) } label: {
                Label(store.todayClaim() == nil ? "抽猪" : "已抽", systemImage: store.todayClaim() == nil ? "gift" : "checkmark.circle")
            }.font(.caption).buttonStyle(.bordered).accessibilityIdentifier("daily.entry")
            PigPanel {
                HealthMetric(label: "今日已记录", value: health.steps.map { "\(Int($0))" } ?? "暂无步数", unit: health.steps == nil ? "" : "步", symbol: "shoeprints.fill")
                if let date = health.refreshedAt { Text("读取于 \(date.formatted(date: .omitted, time: .shortened))").font(.caption2).foregroundStyle(.secondary) }
                else { NavigationLink("读取健康记录") { HealthRecordView(health: health) }.font(.caption) }
            }
            NavigationLink { TodayReviewView(health: health) } label: { Label("记录", systemImage: "heart.text.clipboard") }
                .font(.caption).accessibilityIdentifier("watch.review")
            NavigationLink { WatchCaptureView(store: store, motion: motion) } label: {
                Label("模型", systemImage: "waveform.path")
            }.font(.caption).accessibilityIdentifier("watch.capture")

            StoreErrorView(store: store)
        }
    }
}

struct WatchCaptureView: View {
    @ObservedObject var store: PigStore
    @ObservedObject var motion: LiveMotion
    @State private var reading: WatchReading?
    var body: some View {
        PigScreen {
            if motion.capturing {
                VStack(spacing: 12) {
                    Image(systemName: "waveform.path").font(.largeTitle).foregroundStyle(PigTheme.mint)
                    Text(motion.progress == 0 ? "正在准备" : "正在采集").font(.headline)
                    Text("\(max(0, Int(ceil(10.5 * (1 - motion.progress)))))").font(.system(size: 48, weight: .semibold, design: .rounded)).monospacedDigit()
                        .accessibilityLabel("约剩余\(max(0, Int(ceil(10.5 * (1 - motion.progress)))))秒")
                    ProgressView(value: motion.progress).tint(PigTheme.mint)
                    Text("保持正常步行或坐／站\n可以放下手腕").font(.caption).multilineTextAlignment(.center)
                    Text("已读取 \(motion.sampleCount) 个真实样本").font(.caption2).foregroundStyle(.secondary)
                    Button("取消采集", role: .cancel) { motion.cancel() }
                }.frame(maxWidth: .infinity)
            } else if !motion.error.isEmpty {
                StatusNote(title: "这次未能完成", message: motion.error, symbol: "exclamationmark.triangle")
                Button("重新采集") { reading = nil; motion.start() }.buttonStyle(PigPrimaryButton())
                NavigationLink("查看采集方法") { ModelExplanationView() }
                NavigationLink("用公开样本体验流程") { DemoAnalysisView() }.accessibilityIdentifier("demo.entry")
            } else if let reading {
                ReadingResultView(store: store, reading: reading)
                Button("再测一次") { self.reading = nil; motion.start() }.buttonStyle(PigPrimaryButton())
            } else {
                if let card = store.companion { PigArtwork(card: card, size: 100) }
                Text("体验模型怎样识别动作").font(.headline)
                Text("戴好手表，保持正常步行或安静坐／站约 10 秒。").font(.callout)
                Text("只识别这段动作；离开即停止。").font(.caption).foregroundStyle(.secondary)
                Button("开始 10 秒采集") { motion.start() }.buttonStyle(PigPrimaryButton()).accessibilityIdentifier("capture.start")
                NavigationLink("方法与适用范围") { ModelExplanationView() }.font(.caption)
                NavigationLink("公开样本演示") { DemoAnalysisView() }.font(.caption).accessibilityIdentifier("demo.entry")
            }
            StoreErrorView(store: store)
        }.navigationTitle(motion.capturing ? "采集中" : "动作快照")
            .onChange(of: motion.measuredAt) { _, date in
                guard let date, let score = motion.score, let hz = motion.actualHz else { return }
                let result = WatchReading(id: UUID(), date: date, verdict: motion.verdict, score: score,
                                          threshold: motion.threshold, sampleCount: motion.sampleCount, actualHz: hz)
                reading = result; store.record(result)
                WKInterfaceDevice.current().play(.success)
            }
            .onDisappear { if motion.capturing { motion.cancel() } }
    }
}

struct WatchMoreView: View {
    @ObservedObject var store: PigStore
    @ObservedObject var bridge: CompanionBridge
    @ObservedObject var health: HealthReader
    var body: some View {
        List {
            NavigationLink { HealthRecordView(health: health) } label: { Label("数据与授权", systemImage: "heart.text.clipboard") }
            NavigationLink { AccessibilityHelpView() } label: { Label("操作帮助", systemImage: "accessibility") }.accessibilityIdentifier("accessibility.help")
            NavigationLink { ModelExplanationView() } label: { Label("模型与说明", systemImage: "info.circle") }
            NavigationLink { AuditCatalogView() } label: { Label("独立模型审核", systemImage: "person.2") }
            if let reading = store.ledger.reading {
                NavigationLink("最近动作结果") { ReadingResultView(store: store, reading: reading) }
            }
            Section("与 iPhone 配套") {
                Text(bridge.status).font(.caption).accessibilityIdentifier("sync.status")
                Button("再次同步") { bridge.publish() }.accessibilityIdentifier("sync.retry")
                Text("只同步收藏、佩戴和最近动作摘要。健康记录由两端各自读取。").font(.caption2).foregroundStyle(.secondary)
            }
            Section("本机反馈") {
                Text("已记录 \(store.feedback.count) 条，可在结果页修改。").font(.caption2)
            }
            Text("原生界面第 7 版 · 课程实验").font(.caption2).foregroundStyle(.secondary)
        }.navigationTitle("更多")
    }
}
