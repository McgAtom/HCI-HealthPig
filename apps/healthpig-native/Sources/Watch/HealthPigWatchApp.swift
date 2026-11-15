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
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            WatchTodayView(store: store, health: health)
                .navigationTitle("走走猪猪")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink { WatchStatusView(health: health, bridge: bridge) } label: {
                            Image(systemName: "ellipsis").foregroundStyle(PigTheme.background)
                        }.accessibilityLabel("今日状态").accessibilityIdentifier("watch.status")
                    }
                }
        }.onChange(of: scenePhase) { _, value in
            if value == .active {
                store.refreshDay()
                Task { await health.refreshAutomaticallyIfEnabled() }
            }
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

    var body: some View {
        WatchFrame {
            VStack(spacing: 6) {
                NavigationLink { WalkingCompanionView(store: store) } label: {
                    Label("养猪", systemImage: "figure.walk")
                }.buttonStyle(PigPrimaryButton()).accessibilityIdentifier("watch.companion")
                if let card = store.companion {
                    HStack(spacing: 8) {
                        PigArtwork(card: card, size: 47).frame(width: 49).accessibilityHidden(true)
                        Text(card.name).font(.subheadline.weight(.semibold)).foregroundStyle(PigTheme.cream)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack(spacing: 6) {
                    NavigationLink { WatchDailyView(store: store, health: health) } label: {
                        WatchCompactButton(title: store.todayClaim() == nil ? "抽猪" : "已抽", symbol: "gift.fill")
                    }.buttonStyle(.plain).accessibilityIdentifier("daily.entry")
                    NavigationLink { WatchQuickMoodView(companion: store.companion) } label: {
                        WatchCompactButton(title: "心情", symbol: "face.smiling.inverse")
                    }.buttonStyle(.plain).accessibilityIdentifier("watch.mood")
                }
            }.padding(.top, 20)
        }
    }
}

struct WatchCompactButton: View {
    let title, symbol: String
    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: symbol).font(.subheadline.weight(.semibold))
            Text(title).font(.footnote.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, minHeight: 44).padding(.horizontal, 3)
            .foregroundStyle(PigTheme.rose)
            .background(PigTheme.panel, in: RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore).accessibilityLabel(title)
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
                    Text(rings?.paused == true ? "圆环已暂停" : rings.map { "\($0.closedCount) / 3 环" } ?? "圆环待同步")
                        .font(.headline).accessibilityIdentifier("daily.status")
                    let optedIn = health.automaticUpdates || health.ringsReadOptIn
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
            .task { if health.automaticUpdates || health.ringsReadOptIn { await health.refreshRings() } }
    }
}

private struct WatchStatusView: View {
    @ObservedObject var health: HealthReader
    @ObservedObject var bridge: CompanionBridge

    var body: some View {
        WatchFrame {
            VStack(alignment: .leading, spacing: 6) {
                let rings = health.rings.flatMap { $0.day == DailyPig.dayKey(.now) ? $0 : nil }
                Label(rings.map { "运动 \(Int($0.exercise.value)) 分钟" } ?? "运动 —", systemImage: "figure.walk")
                Label(rings.map { "站立 \(Int($0.stand.value)) / \(Int($0.stand.goal)) 小时" } ?? "站立 —",
                      systemImage: "figure.stand")
                let synced = bridge.status == "对端已保存本次同步" || bridge.status == "已接收并保存在本机"
                Button { bridge.publish() } label: {
                    Label(synced ? "已同步" : "同步收藏", systemImage: synced ? "checkmark" : "arrow.triangle.2.circlepath")
                }.buttonStyle(.bordered).accessibilityValue(bridge.status)
                Label("详情在手机", systemImage: "iphone").font(.footnote).foregroundStyle(.secondary)
            }.font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
        }.navigationTitle("今日")
            .task { if health.automaticUpdates || health.ringsReadOptIn { await health.refreshRings() } }
    }
}
