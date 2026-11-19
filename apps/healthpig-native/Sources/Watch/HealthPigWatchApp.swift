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
            WatchRootView(store: store, bridge: bridge, sleep: bridge.sleep).modifier(PigAccessibilityTestSize()).preferredColorScheme(.dark).tint(PigTheme.rose)
        }.backgroundTask(.watchConnectivity) { await bridge.finishBackgroundDelivery() }
    }
}

@MainActor final class PigApplicationDelegate: NSObject, WKApplicationDelegate {
    func handle(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        WristAlarm.shared.restore(extendedRuntimeSession)
    }

    func applicationDidFinishLaunching() { HealthReader.shared.beginAutomaticUpdatesIfEnabled() }
}

struct WatchRootView: View {
    @ObservedObject var store: PigStore
    let bridge: CompanionBridge
    @ObservedObject var sleep: SleepCompanion
    @StateObject private var alarm = WristAlarm.shared
    @StateObject private var health = HealthReader.shared
    @StateObject private var walk = PigWalk()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            WatchTodayView(store: store, health: health, walk: walk, sleep: sleep)
                .toolbar(.hidden, for: .navigationBar)
        }.onChange(of: scenePhase) { _, value in
            if value == .active {
                store.refreshDay()
                walk.catchUp()
                bridge.applyWristRequest()
                Task { await health.refreshAutomaticallyIfEnabled(); await health.refreshWatchSleep() }
            }
        }.task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await health.refreshWatchSleep()
            while !Task.isCancelled {
                projectSleep()
                if health.readsRings { await health.refreshRings() }
                try? await Task.sleep(for: .seconds(60))
            }
        }
        .onChange(of: sleep.preferences, initial: true) { _, _ in projectSleep() }
        .onChange(of: health.recentSleepNights) { _, _ in projectSleep() }
        .sheet(isPresented: Binding(get: { alarm.ringing }, set: { if !$0 { alarm.stop() } })) {
            Button { alarm.stop() } label: {
                Label("停止闹钟", systemImage: "alarm.fill")
            }.buttonStyle(PigPrimaryButton()).padding(12)
        }
    }

    private func projectSleep() {
        if let plan = sleep.preferences.recommend(nights: health.recentSleepNights, now: .now, calendar: .current) {
            sleep.project(plan)
        }
    }

}

struct WatchFrame<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var textSize
    @ViewBuilder let content: Content
    var body: some View {
        Group {
            if textSize >= .xxxLarge {
                ViewThatFits(in: .vertical) {
                    content.fixedSize(horizontal: false, vertical: true)
                    ScrollView { content }
                }
            } else {
                content
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 12).padding(.bottom, 10)
        .background(PigTheme.background)
    }
}

struct WatchTodayView: View {
    @ObservedObject var store: PigStore
    @ObservedObject var health: HealthReader
    @ObservedObject var walk: PigWalk
    @ObservedObject var sleep: SleepCompanion
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var page = 0

    var body: some View {
        TabView(selection: $page) {
            WatchFrame {
                VStack(spacing: 6) {
                    if let card = store.companion {
                        PigArtwork(card: card, size: textSize.isAccessibilitySize ? 67 : 106)
                            .accessibilityIdentifier("watch.pig")
                    }
                    HStack(spacing: 8) {
                        NavigationLink { PigWalkView(walk: walk, store: store, health: health) } label: {
                            Label(walk.phase == .active || walk.phase == .finishing ? "陪走" : "养猪", systemImage: "figure.walk")
                        }.buttonStyle(PigPrimaryButton()).accessibilityIdentifier("watch.companion")
                        NavigationLink { WatchSleepPlanView(health: health, sleep: sleep) } label: {
                            WatchCompactButton(title: "作息", symbol: "moon.stars.fill")
                        }.buttonStyle(.plain).accessibilityIdentifier("watch.sleep")
                    }
                }.padding(.top, 3)
            }.tag(0)
            WatchMoodPage { compact in
                NavigationLink { WatchDailyView(store: store, health: health) } label: {
                    let energy = health.rings?.energy()
                    let title = store.todayClaim() != nil ? "已抽" : energy == 100 ? "可抽猪" : "抽猪"
                    if compact {
                        Image(systemName: store.todayClaim() == nil ? "gift.fill" : "checkmark")
                            .font(.callout.weight(.semibold)).foregroundStyle(PigTheme.cream)
                            .frame(width: 30, height: 30).background(.black.opacity(0.72), in: Circle())
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                            .accessibilityLabel(title)
                            .accessibilityValue(energy.map { "能量 \($0)" } ?? "")
                    } else {
                        WatchCompactButton(title: title, symbol: "gift.fill")
                            .accessibilityValue(energy.map { "能量 \($0)" } ?? "")
                    }
                }.buttonStyle(.plain).accessibilityIdentifier("daily.entry")
            }.tag(1)
        }.tabViewStyle(.verticalPage)
    }
}

struct WatchCompactButton: View {
    let title, symbol: String
    var value: String? = nil
    var body: some View {
        VStack(spacing: 2) {
            if let value {
                Text(value).font(.subheadline.weight(.semibold)).monospacedDigit().accessibilityHidden(true)
            } else {
                Image(systemName: symbol).font(.subheadline.weight(.semibold))
            }
            Text(title).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, minHeight: 44).padding(.horizontal, 3)
            .foregroundStyle(PigTheme.rose)
            .background(PigTheme.panel, in: RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore).accessibilityLabel(title).accessibilityValue(value ?? "")
    }
}

private struct WatchDailyView: View {
    @ObservedObject var store: PigStore
    @ObservedObject var health: HealthReader
    var body: some View {
        WatchFrame {
            VStack(spacing: 7) {
                if let claim = store.todayClaim(), let card = store.catalog?.card(claim.cardID) {
                    PigArtwork(card: card, size: 63)
                    Text(card.name).font(.headline)
                    let worn = store.ledger.selection?.cardID == card.id
                    Button(worn ? "陪伴中" : "佩戴") { store.wear(card) }
                        .buttonStyle(PigPrimaryButton()).disabled(worn).accessibilityIdentifier("daily.wear")
                } else {
                    let rings = health.rings.flatMap { $0.day == DailyPig.dayKey(.now) ? $0 : nil }
                    let ready = rings?.canUnlock() == true
                    Image(systemName: ready ? "gift.fill" : "lock.fill").font(.title2).foregroundStyle(PigTheme.rose)
                    let energy = rings?.energy()
                    Text(rings?.paused == true ? "圆环已暂停" : energy.map { "能量 \($0) / 100" } ?? "圆环待同步")
                        .font(.headline).accessibilityIdentifier("daily.status")
                    if let rings, energy != nil { Text("\(rings.closedCount) / 3 环闭合").font(.subheadline) }
                    else if rings?.paused != true { Text("三环全闭合后可抽").font(.subheadline) }
                    let optedIn = health.readsRings
                    Button(health.ringsLoading ? "读取中…" : ready ? "抽猪" : optedIn ? "刷新圆环" : "读取圆环") {
                        Task {
                            if optedIn { await health.refreshRings() } else { await health.requestRingsRead() }
                            if ready { _ = store.claimToday(rings: health.rings) }
                        }
                    }.buttonStyle(PigPrimaryButton()).disabled(health.ringsLoading || (ready && !store.ready))
                        .accessibilityIdentifier(ready ? "daily.reveal" : "daily.refresh")
                }
                StoreErrorView(store: store)
            }
        }.navigationTitle("抽猪")
            .task { if health.readsRings { await health.refreshRings() } }
    }
}
