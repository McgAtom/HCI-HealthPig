import SwiftUI

@main struct HealthPigPhoneApp: App {
    @StateObject private var store: PigStore
    @StateObject private var bridge: CompanionBridge
    @StateObject private var health = HealthReader.shared
    @Environment(\.scenePhase) private var scenePhase
    init() {
        let store = PigStore()
        _store = StateObject(wrappedValue: store)
        _bridge = StateObject(wrappedValue: CompanionBridge(store: store))
    }
    var body: some Scene {
        WindowGroup {
            TabView {
                NavigationStack { PhoneTodayView(store: store, health: health) }
                    .tabItem { Label("今日", systemImage: "sun.max") }
                NavigationStack { TrendHomeView(health: health) }
                    .tabItem { Label("趋势", systemImage: "chart.xyaxis.line") }
                NavigationStack { PigCollectionView(store: store) }
                    .tabItem { Label("猪猪", systemImage: "square.grid.2x2") }
                NavigationStack { PhoneMoreView(store: store, bridge: bridge, health: health) }
                    .tabItem { Label("更多", systemImage: "ellipsis.circle") }
            }.modifier(PigAccessibilityTestSize()).tint(PigTheme.rose).preferredColorScheme(.dark)
                .task { health.beginAutomaticUpdatesIfEnabled() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { store.refreshDay(); Task { await health.refreshAutomaticallyIfEnabled() }; bridge.publish() }
                }
        }
    }
}

struct PhoneTodayView: View {
    @ObservedObject var store: PigStore
    @ObservedObject var health: HealthReader
    var body: some View {
        PigScreen {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Date.now.formatted(.dateTime.month().day().weekday(.wide))).font(.caption).foregroundStyle(.secondary)
                    Text("今天，一起养猪").font(.title.bold()).foregroundStyle(PigTheme.cream)
                }
                Spacer()
            }
            if let card = store.companion {
                PigPanel {
                    HStack(alignment: .center) {
                        PigArtwork(card: card, size: 100).frame(width: 104)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(card.name).font(.title2.bold())
                            Text("今天也一起走走吧").font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    NavigationLink { DailyRevealView(store: store) } label: {
                        Label(store.todayClaim() == nil ? "抽今日猪猪" : "查看今日猪猪", systemImage: "gift")
                    }.buttonStyle(PigPrimaryButton()).accessibilityIdentifier("phone.daily-entry")
                }
            }
            NavigationLink { ActivityRingsView(health: health) } label: {
                PigPanel {
                    Label("猪猪能量", systemImage: "flame").font(.headline)
                    Text(health.rings.map { $0.paused ? "圆环已暂停" : "\($0.closedCount) / 3 环闭合" } ?? "等待圆环数据").font(.title3.weight(.semibold))
                    Text("三环全闭合，每天抽一只").font(.caption).foregroundStyle(.secondary)
                }
            }.buttonStyle(.plain).accessibilityIdentifier("phone.rings")
            NavigationLink { TodayReviewView(health: health) } label: { Label("健康记录", systemImage: "heart.text.clipboard") }
                .buttonStyle(.bordered).accessibilityIdentifier("phone.review")
            PigPanel {
                HealthMetric(label: "今日步数", value: health.steps.map { "\(Int($0))" } ?? "未知", unit: health.steps == nil ? "" : "步", symbol: "figure.walk")
                Divider()
                HealthMetric(label: "最近心率", value: health.heartRate.map { "\(Int($0))" } ?? "未知", unit: health.heartRate == nil ? "" : "次／分", symbol: "heart")
                if let date = health.heartDate { Text("记录于 \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                if health.steps == nil && health.heartRate == nil {
                    NavigationLink("读取健康记录") { HealthRecordView(health: health) }
                }
            }
            StoreErrorView(store: store)
        }.navigationTitle("走走猪猪").navigationBarTitleDisplayMode(.inline)
    }
}

struct PhoneMoreView: View {
    @ObservedObject var store: PigStore
    @ObservedObject var bridge: CompanionBridge
    @ObservedObject var health: HealthReader
    @State private var clearFeedback = false
    var body: some View {
        List {
            Section("常用") {
                NavigationLink { HealthRecordView(health: health) } label: { Label("数据与授权", systemImage: "heart.text.clipboard") }
                NavigationLink { DemoAnalysisView() } label: { Label("模型体验", systemImage: "play.rectangle") }.accessibilityIdentifier("demo.entry")
                NavigationLink { AccessibilityHelpView() } label: { Label("操作帮助", systemImage: "accessibility") }.accessibilityIdentifier("accessibility.help")
                if let reading = store.ledger.reading { NavigationLink("最近动作结果") { ReadingResultView(store: store, reading: reading) } }
            }
            Section("玩法与依据") {
                NavigationLink("手表陪伴玩法") { CompanionGuideView() }
                NavigationLink { ModelExplanationView() } label: { Label("模型适用范围", systemImage: "info.circle") }
                NavigationLink { DemoAnalysisView(companionCard: store.companion) } label: { Label("猪猪回应示例", systemImage: "figure.walk") }.accessibilityIdentifier("companion.demo")
                NavigationLink { RingsRuleDemoView() } label: { Label("圆环规则示例", systemImage: "flame") }.accessibilityIdentifier("rings.demo")
            }
            Section("管理与审核人员") {
                NavigationLink { AuditCatalogView() } label: { Label("公平性审核", systemImage: "person.2") }.accessibilityIdentifier("audit.entry")
            }
            Section("手表与手机") {
                Label(bridge.status, systemImage: "arrow.triangle.2.circlepath").accessibilityIdentifier("sync.status")
                if let date = bridge.lastReceivedAt { Text("最近接收 \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption) }
                Button("再次同步收藏与摘要") { bridge.publish() }.accessibilityIdentifier("sync.retry")
            }
            Section("我的反馈") {
                Text("本机已保存 \(store.feedback.count) 条反馈")
                Text("在动作结果页可修改；不直接训练模型。").font(.caption)
                Button("清除本机反馈", role: .destructive) { clearFeedback = true }.disabled(store.feedback.isEmpty)
            }
            Section("关于") {
                Text("走走猪猪 · 原生第 7.1 版")
                Text("HealthPig\n人机交互课程学习项目").font(.caption)
            }
        }.navigationTitle("更多")
            .confirmationDialog("清除本机全部反馈？", isPresented: $clearFeedback, titleVisibility: .visible) {
                Button("清除反馈", role: .destructive) { store.clearFeedback() }
            } message: { Text("收藏和系统健康记录会保留。") }
    }
}
