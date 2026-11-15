import SwiftUI

@main struct HealthPigPhoneApp: App {
    @StateObject private var store: PigStore
    @StateObject private var bridge: CompanionBridge
    @StateObject private var health = HealthReader.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = 0
    init() {
        let store = PigStore()
        _store = StateObject(wrappedValue: store)
        _bridge = StateObject(wrappedValue: CompanionBridge(store: store))
    }
    var body: some Scene {
        WindowGroup {
            TabView(selection: $tab) {
                NavigationStack { PhoneTodayView(store: store, health: health, openInsights: { tab = 3 }) }
                    .tabItem { Label("今日", systemImage: "sun.max") }.tag(0)
                NavigationStack { TrendHomeView(health: health) }
                    .tabItem { Label("趋势", systemImage: "chart.xyaxis.line") }.tag(1)
                NavigationStack { PigCollectionView(store: store) }
                    .tabItem { Label("猪猪", systemImage: "square.grid.2x2") }.tag(2)
                NavigationStack { ModelInsightsView() }
                    .tabItem { Label("判断", systemImage: "chart.bar.xaxis") }.tag(3)
                NavigationStack { PhoneMoreView(store: store, bridge: bridge, health: health) }
                    .tabItem { Label("更多", systemImage: "ellipsis.circle") }.tag(4)
            }.modifier(PigAccessibilityTestSize()).tint(PigTheme.rose).preferredColorScheme(.dark)
                .task { health.beginAutomaticUpdatesIfEnabled() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { store.refreshDay(); Task { await health.refreshAutomaticallyIfEnabled() }; bridge.publish() }
                }
                .task(id: scenePhase) {
                    if scenePhase == .active, health.ringsReadOptIn { await health.refreshRings() }
                }
        }
    }
}

struct PhoneTodayView: View {
    @ObservedObject var store: PigStore
    @ObservedObject var health: HealthReader
    var openInsights: (() -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        PigScreen {
            VStack(alignment: .leading, spacing: 4) {
                Text(Date.now.formatted(.dateTime.month().day().weekday(.wide)))
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Text("今天，一起养猪").font(.largeTitle.bold()).foregroundStyle(PigTheme.cream)
            }
            if let card = store.companion {
                VStack(spacing: 10) {
                    PigArtwork(card: card, size: 148)
                    Text(card.name).font(.title3.bold())
                    NavigationLink { DailyRevealView(store: store) } label: {
                        Label(store.todayClaim() == nil ? "抽今日猪猪" : "查看今日猪猪", systemImage: "gift")
                    }.buttonStyle(PigPrimaryButton()).accessibilityIdentifier("phone.daily-entry")
                }.padding(14).frame(maxWidth: .infinity)
                    .background {
                        RoundedRectangle(cornerRadius: 25)
                            .fill(LinearGradient(colors: [PigTheme.color(for: card.series).opacity(0.24), PigTheme.panel],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
            }
            let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
            layout {
                NavigationLink { WellnessHubView(health: health, companion: store.companion) } label: {
                    WellnessTile("健康", symbol: "heart.text.clipboard", tint: PigTheme.rose)
                }.buttonStyle(.plain).accessibilityIdentifier("phone.wellness")
                if let openInsights {
                    Button(action: openInsights) {
                        WellnessTile("模型判断", symbol: "chart.bar.xaxis", tint: Color(red: 0.77, green: 0.77, blue: 1))
                    }.buttonStyle(.plain).accessibilityIdentifier("phone.model-insights")
                }
            }
            NavigationLink { ActivityRingsView(health: health) } label: {
                PigPanel {
                    Label("猪猪能量", systemImage: "flame").font(.headline)
                    Text(health.rings?.energy().map { "\($0) / 100" } ?? (health.rings?.paused == true ? "圆环已暂停" : "等待读取"))
                        .font(.title3.weight(.semibold)).monospacedDigit()
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
                Text("走走猪猪 · 原生第 8.2 版")
                Text("HealthPig\n人机交互课程学习项目").font(.caption)
            }
        }.navigationTitle("更多")
            .confirmationDialog("清除本机全部反馈？", isPresented: $clearFeedback, titleVisibility: .visible) {
                Button("清除反馈", role: .destructive) { store.clearFeedback() }
            } message: { Text("收藏和系统健康记录会保留。") }
    }
}
