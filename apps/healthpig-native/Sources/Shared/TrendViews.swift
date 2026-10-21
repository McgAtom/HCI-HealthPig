import SwiftUI
import Charts

struct TrendPoint: Identifiable {
    var id: Date { date }
    let date: Date
    let value: Double?
}

enum TrendSeries {
    static func completedWeek(values: [(Date, Double)], now: Date = .now,
                              calendar: Calendar = .current) -> [TrendPoint] {
        let today = calendar.startOfDay(for: now)
        let byDay = Dictionary(values.map { (calendar.startOfDay(for: $0.0), $0.1) },
                               uniquingKeysWith: { _, latest in latest })
        return (-7..<0).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            return TrendPoint(date: date, value: byDay[date])
        }
    }
    static func mean(_ points: [TrendPoint]) -> Double? {
        let known = points.compactMap(\.value)
        return known.isEmpty ? nil : known.reduce(0, +) / Double(known.count)
    }
}

struct HealthTrendView: View {
    @ObservedObject var health: HealthReader
    let sleep: Bool
    private var points: [TrendPoint] {
        TrendSeries.completedWeek(values: sleep ? health.days.map { ($0.date, $0.hours) } : health.activityDays.map { ($0.date, $0.steps) })
    }
    private var title: String { sleep ? "睡眠趋势" : "活动趋势" }
    private var unit: String { sleep ? "小时" : "步" }
    private var count: Int { points.compactMap(\.value).count }
    private var color: Color { sleep ? PigTheme.rose : PigTheme.mint }
    private func formatted(_ value: Double) -> String { sleep ? String(format: "%.1f 小时", value) : "\(Int(value)) 步" }
    var body: some View {
        PigScreen {
            Text("最近 7 个已结束日期").font(.caption).foregroundStyle(.secondary)
            if health.loading { ProgressView("正在读取健康记录") }
            if !health.error.isEmpty {
                StatusNote(title: "读取未完成", message: health.error, symbol: "exclamationmark.triangle")
                Button("重试") { Task { await health.refresh() } }.disabled(health.loading)
            }
            if let average = TrendSeries.mean(points) {
                PigPanel {
                    Label("记录日均值", systemImage: sleep ? "moon.zzz" : "figure.walk").font(.caption).foregroundStyle(color)
                    Text(formatted(average)).font(.system(.title2, design: .rounded, weight: .semibold))
                    Text("\(count) / 7 日有记录").font(.caption).foregroundStyle(.secondary)
                    Chart(points) { point in
                        if let value = point.value {
                            BarMark(x: .value("日期", point.date, unit: .day), y: .value(unit, value))
                                .foregroundStyle(color).cornerRadius(4)
                        }
                    }
                    .chartXScale(domain: points.first!.date...points.last!.date.addingTimeInterval(86400))
                    .chartXAxis { AxisMarks(values: .stride(by: .day, count: 2)) { AxisValueLabel(format: .dateTime.day()) } }
                    .chartYAxis { AxisMarks(position: .leading) }
                    .frame(height: chartHeight)
                    .accessibilityLabel("\(title)，\(count)个日期有记录，记录日均\(formatted(average))。缺失日期不补零，完整数值见下方日期列表。")
                }
            } else if !health.loading {
                PigPanel {
                    StatusNote(title: sleep ? "暂时没有睡眠记录" : "还没有可读趋势", message: sleep ? "先检查授权与同步；尚未佩戴过夜时，可能没有睡眠记录。" : "没有记录的日期保持未知。先检查健康授权、已有记录和同步。", symbol: sleep ? "moon.zzz" : "chart.bar")
                    if sleep {
                        Text("可以先查看活动，不必等待睡眠数据。").font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("sleep.empty-next-step")
                    }
                    NavigationLink("读取健康数据") { HealthRecordView(health: health) }
                }
            }
            PigPanel {
                Text("逐日记录").font(.headline)
                ForEach(points.reversed()) { point in
                    HStack(alignment: .firstTextBaseline) {
                        Text(point.date.formatted(.dateTime.month().day()))
                        Spacer()
                        if let value = point.value { Text(formatted(value)).monospacedDigit() }
                        else { Label("未知", systemImage: "minus.circle").foregroundStyle(.secondary) }
                    }.font(.caption).accessibilityElement(children: .combine)
                }
            }
            NavigationLink("统计范围与来源") { PigScreen { PigPanel {
                Text("范围与来源").font(.headline)
                Text(sleep ? "按自然日统计总睡眠，包含午睡，重叠时段合并。这里不是夜间连续睡眠时长。" : "来源为 HealthKit 已记录步数累计。今日尚未结束，不进入这 7 日均值。")
                Text("缺失不等于零，均值只包括有记录的日期。趋势描述已有记录，不判断健康好坏。").foregroundStyle(.secondary)
                if let date = health.refreshedAt { Text("读取于 \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                NavigationLink("查看详细来源与授权") { HealthRecordView(health: health) }.font(.caption)
            }.font(.callout) }.navigationTitle("统计说明") }
        }.navigationTitle(title).task { await health.refreshAutomaticallyIfEnabled() }
    }
    private var chartHeight: CGFloat {
#if os(watchOS)
        120
#else
        190
#endif
    }
}
