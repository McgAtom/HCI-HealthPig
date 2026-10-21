import SwiftUI

struct RingSummaryPanel: View {
    let rings: DailyRings
    var simulated = false
    var body: some View {
        PigPanel {
            Label(rings.canUnlock() ? "满能量 100 · 可以抽卡" : rings.paused ? "圆环已暂停" : "能量积攒中 · \(rings.closedCount) / 3 环闭合", systemImage: rings.canUnlock() ? "gift.fill" : "flame")
                .font(.headline).accessibilityIdentifier("rings.summary")
            ZStack {
                ForEach(0..<3) { index in
                    let metric = [rings.move, rings.exercise, rings.stand][index]
                    let color: Color = [.pink, .green, .cyan][index]
                    Circle().stroke(color.opacity(0.18), lineWidth: 10).padding(CGFloat(index) * 15)
                    Circle().trim(from: 0, to: metric.fraction ?? 0).stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90)).padding(CGFloat(index) * 15)
                }
            }.frame(width: 110, height: 110).frame(maxWidth: .infinity).padding(6).accessibilityHidden(true)
            row("活动", rings.move, rings.moveUsesMinutes ? "分钟" : "千卡", .pink)
            row("锻炼", rings.exercise, "分钟", .green)
            row("站立／活动小时", rings.stand, "小时", .cyan)
            Text(simulated ? "模拟目标与数值，仅说明三环规则。不是整体健康评分。" : "目标来自系统设置；三个环全部闭合才满能量。不是整体健康评分。").font(.caption).foregroundStyle(.secondary)
            Text("\(simulated ? "演示时刻" : "读取于") \(rings.readAt.formatted(date: .omitted, time: .shortened))").font(.caption2).foregroundStyle(.secondary)
        }
    }
    private func row(_ title: String, _ value: RingValue, _ unit: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ViewThatFits(in: .horizontal) {
              HStack {
                Label(title, systemImage: value.closed ? "checkmark.circle.fill" : "circle").foregroundStyle(color)
                Spacer()
                Text("\(value.value, specifier: "%.0f") / \(value.goal, specifier: "%.0f") \(unit)").monospacedDigit()
              }
              VStack(alignment: .leading, spacing: 4) {
                  Label(title, systemImage: value.closed ? "checkmark.circle.fill" : "circle").foregroundStyle(color)
                  Text("\(value.value, specifier: "%.0f") / \(value.goal, specifier: "%.0f") \(unit)")
              }
            }.font(.caption)
            ProgressView(value: value.fraction ?? 0).tint(color).accessibilityLabel("\(title)，\(value.closed ? "已闭合" : "未闭合")")
        }.accessibilityElement(children: .combine)
    }
}

struct ActivityRingsView: View {
    @ObservedObject var health: HealthReader = .shared
    var body: some View {
        PigScreen {
            Text("活动，让猪猪充满能量").font(.headline)
            if let rings = health.rings, rings.day == DailyPig.dayKey(.now) { RingSummaryPanel(rings: rings) }
            else { StatusNote(title: "等待今日圆环数据", message: health.ringsMessage, symbol: "circle.dashed").accessibilityIdentifier("rings.unavailable") }
            if health.ringsLoading { ProgressView("正在读取活动摘要") }
            Button("刷新今日圆环") { Task { await health.refreshRings() } }.buttonStyle(.bordered).disabled(health.ringsLoading)
            NavigationLink("授权与数据来源") { HealthRecordView(health: health) }
            NavigationLink("怎样解锁抽卡？") { DailyRulesView() }
            NavigationLink("圆环规则示例") { RingsRuleDemoView() }.accessibilityIdentifier("rings.demo")
        }.navigationTitle("猪猪能量").task { if health.automaticUpdates { await health.refreshRings() } }
    }
}

// These synthetic ring values are isolated from HealthReader, PigStore and WatchConnectivity.
struct RingsRuleDemoView: View {
    @State private var completed = false
    var body: some View {
        PigScreen {
            Label("规则演示 · 模拟数据", systemImage: "play.rectangle").font(.headline)
            Text("不读取或写入健康记录，不解锁真实抽卡，不增加收藏。").font(.caption).foregroundStyle(.secondary)
            Toggle("演示三个圆环全闭合", isOn: $completed).accessibilityIdentifier("rings.demo-complete")
            RingSummaryPanel(rings: DailyRings(day: DailyPig.dayKey(.now), readAt: .now,
                move: RingValue(value: completed ? 400 : 260, goal: 400),
                exercise: RingValue(value: completed ? 30 : 18, goal: 30),
                stand: RingValue(value: completed ? 10 : 6, goal: 10)), simulated: true)
            Label(completed ? "演示：已达到抽卡条件" : "演示：还未达到抽卡条件", systemImage: completed ? "gift" : "lock").font(.caption).accessibilityIdentifier("rings.demo-result")
        }.navigationTitle("规则演示")
    }
}

struct PigResponseScene: View {
    let card: PigCard?
    let verdict: MotionVerdict
    var compact = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 6) {
            TimelineView(.animation(minimumInterval: 0.15, paused: verdict != .walking || reduceMotion)) { context in
                let phase = context.date.timeIntervalSinceReferenceDate * 5
                ZStack(alignment: .bottom) {
                    Capsule().fill(PigTheme.mint.opacity(0.2)).frame(height: 7).padding(.horizontal, 12)
                    if let card {
                        PigArtwork(card: card, size: size)
                            .offset(x: verdict == .walking && !reduceMotion ? sin(phase) * 7 : 0,
                                    y: verdict == .walking && !reduceMotion ? -abs(sin(phase)) * 5 : 0)
                    }
                }
            }.frame(height: size).accessibilityHidden(true)
            Label(compact ? (verdict == .walking ? "一起走" : verdict == .still ? "休息" : verdict == .uncertain ? "等等" : "待出发") : (verdict == .walking ? "猪猪一起走" : verdict == .still ? "猪猪停下来休息" : verdict == .uncertain ? "猪猪还拿不准，先等等" : "猪猪等你出发"), systemImage: verdict.symbol)
                .font(.subheadline.weight(.semibold)).foregroundStyle(PigTheme.cream).accessibilityIdentifier("companion.response")
                .accessibilityValue(reduceMotion ? "静态回应，减少动态效果已开启" : "文字回应")
        }
    }
    private var size: CGFloat {
#if os(watchOS)
        compact ? 46 : 98
#else
        180
#endif
    }
}
