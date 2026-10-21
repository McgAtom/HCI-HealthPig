import SwiftUI

struct DailyRevealView: View {
    @ObservedObject var store: PigStore
    @ObservedObject var health = HealthReader.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed: PigCard?
    var body: some View {
        PigScreen {
            Label(store.todayClaim() == nil ? "三环闭合，解锁今日抽卡" : "今日已领取 · 明天再来", systemImage: store.todayClaim() == nil ? "gift" : "checkmark.circle")
                .font(.caption).foregroundStyle(PigTheme.mint).accessibilityIdentifier("daily.status")
            if let card = revealed ?? store.todayClaim().flatMap({ store.catalog?.card($0.cardID) }) {
                Text("今天遇见了").font(.subheadline).foregroundStyle(.secondary)
                PigArtwork(card: card, size: artworkSize)
                Text(card.name).font(.title2.bold()).foregroundStyle(PigTheme.cream)
                Label(card.series, systemImage: "sparkles").font(.caption).foregroundStyle(PigTheme.color(for: card.series))
                Text(card.flavor).font(.body)
                Label("已存入收藏", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(PigTheme.mint)
                Button(store.ledger.selection?.cardID == card.id ? PigText.compact("陪伴中", full: "正在陪伴你") : PigText.compact("佩戴", full: "让它陪伴我")) { store.wear(card) }
                    .accessibilityLabel(store.ledger.selection?.cardID == card.id ? "正在陪伴你" : "让它陪伴我")
                    .buttonStyle(PigPrimaryButton()).disabled(store.ledger.selection?.cardID == card.id).accessibilityIdentifier("daily.wear")
                NavigationLink("抽卡规则") { DailyRulesView() }
            } else {
                if let rings = health.rings, rings.day == DailyPig.dayKey(.now) { RingSummaryPanel(rings: rings) }
                else { StatusNote(title: "等待今日圆环数据", message: health.ringsMessage, symbol: "circle.dashed").accessibilityIdentifier("rings.unavailable") }
                NavigationLink(PigText.compact("能量", full: "查看能量与读取圆环")) { ActivityRingsView(health: health) }.accessibilityIdentifier("daily.rings")
                Button(health.ringsLoading ? PigText.compact("确认中", full: "正在确认圆环…") : PigText.compact("抽猪", full: "确认满能量并抽卡")) {
                    Task {
                        await health.refreshRings()
                        let card = store.claimToday(rings: health.rings)
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { revealed = card }
                    }
                }.buttonStyle(PigPrimaryButton()).disabled(!store.ready || health.ringsLoading || health.rings?.canUnlock() != true).accessibilityIdentifier("daily.reveal")
                Text(health.rings?.canUnlock() == true ? "满能量，今天的惊喜等你揭晓。" : "三个环全闭合后可抽。暂无数据时，先读取圆环。").font(.caption).foregroundStyle(.secondary)
                Button(health.ringsLoading ? "读取中…" : "重新读取圆环") { Task { await health.refreshRings() } }
                    .buttonStyle(.bordered).disabled(health.ringsLoading).accessibilityIdentifier("daily.refresh")
                NavigationLink("抽卡规则") { DailyRulesView() }
            }
            StoreErrorView(store: store)
        }.navigationTitle(PigText.compact("抽猪", full: "每日猪猪")).task { if health.automaticUpdates { await health.refreshRings() } }
            .onChange(of: store.currentDay) { _, _ in revealed = nil }
    }
    private var artworkSize: CGFloat {
#if os(watchOS)
        158
#else
        300
#endif
    }
}

struct MysteryPigArtwork: View {
    var size: CGFloat
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24).fill(PigTheme.panel)
            Image(systemName: "questionmark").font(.system(size: size * 0.38, weight: .semibold, design: .rounded)).foregroundStyle(PigTheme.rose)
        }.frame(maxWidth: .infinity).frame(height: size).accessibilityLabel("待揭晓的猪猪，形象暂不公开")
    }
}

struct DailyRulesView: View {
    var body: some View {
        PigScreen {
            StatusNote(title: "每天一只", message: "当天三个系统活动圆环全部闭合后领取。按日期轮换，共24只；不设稀有度或付费。", symbol: "gift")
            StatusNote(title: "获得后再揭晓", message: "未获得的形象保持隐藏，不提供模拟抽卡。已获得的猪猪可在收藏中切换陪伴。", symbol: "questionmark")
            StatusNote(title: "模型不影响奖励", message: "养猪页的动作判断不增加或扣除能量。游戏能量不是健康评级。暂停圆环的日期不判断达标。", symbol: "info.circle")
            StatusNote(title: "两端共享领取记录", message: "本机先保存，配套设备连接后同步。同一天只领一次；旧版本收藏继续保留。", symbol: "arrow.triangle.2.circlepath")
        }.navigationTitle("抽卡规则")
    }
}

struct PigCollectionView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @ObservedObject var store: PigStore
    @State private var series = "全部"
    @State private var onlyOwned = false
    var filtered: [PigCard] {
        (store.catalog?.cards ?? []).filter { (series == "全部" || $0.series == series) && (!onlyOwned || store.ledger.ownedIDs.contains($0.id)) }
    }
    var body: some View {
        PigScreen {
            NavigationLink { DailyRevealView(store: store) } label: {
                Label(store.todayClaim() == nil ? PigText.compact("抽猪", full: "领取今日猪猪") : PigText.compact("今日已抽", full: "查看今日猪猪"), systemImage: "gift")
            }.buttonStyle(.bordered).accessibilityIdentifier("collection.daily")
#if os(watchOS)
            HStack {
                Text("已收藏 \(store.ledger.ownedIDs.count) / 24").font(.caption.weight(.medium)).foregroundStyle(PigTheme.mint)
                Spacer()
                NavigationLink {
                    CollectionFilterView(series: $series, onlyOwned: $onlyOwned, availableSeries: store.catalog?.series ?? [])
                } label: {
                    Image(systemName: "line.3.horizontal.decrease").frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel("筛选收藏").accessibilityIdentifier("collection.filter")
            }
#else
            HStack(alignment: .firstTextBaseline) {
                Text("我的小小世界").font(.headline)
                Spacer()
                Text("\(store.ledger.ownedIDs.count) / 24").font(.headline.monospacedDigit()).foregroundStyle(PigTheme.mint)
            }
            Picker("主题", selection: $series) {
                Text("全部主题").tag("全部")
                ForEach(store.catalog?.series ?? [], id: \.self) { Text($0).tag($0) }
            }
#if os(watchOS)
            .pickerStyle(.navigationLink)
#else
            .pickerStyle(.menu)
#endif
            Toggle("只看已收藏", isOn: $onlyOwned).font(.subheadline).accessibilityIdentifier("collection.only-owned")
#endif
            if filtered.isEmpty {
                StatusNote(title: "这里还空着", message: "可以关闭“只看已收藏”，或等三环闭合后领取今日猪猪。", symbol: "tray")
                Button("显示全部") { onlyOwned = false; series = "全部" }.accessibilityIdentifier("collection.reset")
            }
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(filtered) { card in
                    if store.ledger.ownedIDs.contains(card.id) {
                      NavigationLink { PigCardDetailView(store: store, card: card) } label: {
                        VStack(spacing: 5) {
                            PigArtwork(card: card, size: tileSize)
                            Text(card.name).font(.caption.weight(.medium)).foregroundStyle(.primary).lineLimit(2)
                            Label(store.ledger.ownedIDs.contains(card.id) ? "已收藏" : "未获得", systemImage: store.ledger.ownedIDs.contains(card.id) ? "checkmark.circle.fill" : "lock")
                                .font(.caption2).foregroundStyle(store.ledger.ownedIDs.contains(card.id) ? PigTheme.mint : .secondary)
                        }.padding(8).frame(maxWidth: .infinity).background(PigTheme.panel, in: RoundedRectangle(cornerRadius: 18))
                      }.buttonStyle(.plain).accessibilityIdentifier("card.\(card.id)")
                    } else {
                        VStack(spacing: 5) {
                            MysteryPigArtwork(size: tileSize)
                            Text("待相遇").font(.caption.weight(.medium))
                            Label("尚未获得", systemImage: "lock").font(.caption2).foregroundStyle(.secondary)
                        }.padding(8).frame(maxWidth: .infinity).background(PigTheme.panel, in: RoundedRectangle(cornerRadius: 18))
                            .accessibilityElement(children: .ignore).accessibilityLabel("尚未获得的猪猪，领取后揭晓")
                            .accessibilityIdentifier("locked.\(card.id)")
                    }
                }
            }
            StoreErrorView(store: store)
        }.navigationTitle("猪猪收藏")
    }
    private var columns: [GridItem] {
#if os(watchOS)
        typeSize >= .xxxLarge ? [GridItem(.flexible())] : [GridItem(.flexible()), GridItem(.flexible())]
#else
        [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 280 : 140), spacing: 12)]
#endif
    }
    private var tileSize: CGFloat {
#if os(watchOS)
        76
#else
        140
#endif
    }
}

struct PigCardDetailView: View {
    @ObservedObject var store: PigStore
    let card: PigCard
    var body: some View {
        PigScreen {
            PigArtwork(card: card, size: size)
            Text(card.name).font(.title2.bold())
            Text(card.series).font(.subheadline).foregroundStyle(PigTheme.color(for: card.series))
            Text(card.flavor).font(.body)
            if store.ledger.ownedIDs.contains(card.id) {
                Label("已收藏", systemImage: "checkmark.circle.fill").foregroundStyle(PigTheme.mint)
                Button(store.ledger.selection?.cardID == card.id ? PigText.compact("陪伴中", full: "正在陪伴你") : PigText.compact("佩戴", full: "让它陪伴我")) { store.wear(card) }
                    .accessibilityLabel(store.ledger.selection?.cardID == card.id ? "正在陪伴你" : "让它陪伴我")
                    .buttonStyle(PigPrimaryButton()).disabled(store.ledger.selection?.cardID == card.id).accessibilityIdentifier("daily.wear")
                if let claim = store.ledger.claims.first(where: { $0.cardID == card.id }) {
                    Text("初次相遇 · \(claim.day)").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                StatusNote(title: "尚未获得", message: "每天来领取一张猪猪，逐渐填满你的收藏。", symbol: "lock")
            }
            StoreErrorView(store: store)
        }.navigationTitle("猪猪档案")
    }
    private var size: CGFloat {
#if os(watchOS)
        160
#else
        320
#endif
    }
}

#if os(watchOS)
struct CollectionFilterView: View {
    @Binding var series: String
    @Binding var onlyOwned: Bool
    let availableSeries: [String]
    var body: some View {
        List {
            Picker("主题", selection: $series) {
                Text("全部主题").tag("全部")
                ForEach(availableSeries, id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.navigationLink)
            Toggle("只看已收藏", isOn: $onlyOwned).accessibilityIdentifier("collection.only-owned")
            Text("选择后返回图鉴，条件会立即生效。").font(.caption).foregroundStyle(.secondary)
        }.navigationTitle("筛选收藏")
    }
}
#endif
