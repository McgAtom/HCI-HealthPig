import Charts
import SwiftUI

private let insightAccent = Color(red: 0.78, green: 0.75, blue: 1)

struct ModelInsightsView: View {
    @State private var report = ModelInsights.load()
    @State private var selection: ModelInsights.Feature?
    @State private var allFeatures = false
    @State private var showMethod = false

    var body: some View {
        PigScreen {
            if let report {
#if os(iOS)
                header(report)
#endif
                Label("整批依赖 · 不是个人病因", systemImage: "info.circle")
                    .font(.footnote.weight(.medium)).foregroundStyle(PigTheme.cream)
                    .accessibilityIdentifier("insights.not-causal")
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("打乱哪项影响最大？").font(.headline)
                        Spacer(minLength: 0)
#if os(iOS)
                        Button { showMethod = true } label: {
                            Image(systemName: "info.circle").font(.title3)
                                .frame(minWidth: 44, minHeight: 44)
                        }.accessibilityLabel("实验方法与图例")
#endif
                    }
                    Text(PigText.compact("分数下降 · 百分点", full: "平衡准确率下降 · 百分点"))
                        .font(.caption).foregroundStyle(.secondary)
                    scale(report)
                    ForEach(allFeatures ? report.features : report.highlights) { feature in
                        featureRow(feature, report: report)
                    }
                    HStack(spacing: 7) {
                        Image(systemName: "line.horizontal")
                        Text("细线：\(report.repeats) 次最小–最大")
                    }.font(.caption2).foregroundStyle(.secondary)
                    Button {
                        allFeatures.toggle()
                    } label: {
                        Label(allFeatures ? "收起 · 只看 5 项" : "全部 24 项输入",
                              systemImage: allFeatures ? "chevron.up" : "list.bullet")
                            .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                    }.buttonStyle(.plain).foregroundStyle(insightAccent)
                    .accessibilityIdentifier("insights.all-features")
                }.padding(14).background(PigTheme.panel, in: RoundedRectangle(cornerRadius: 22))
#if os(watchOS)
                header(report)
                Button("实验方法") { showMethod = true }.font(.footnote)
#endif
            } else {
                StatusNote(title: "判断资料不可用", message: "重新读取实验结果", symbol: "exclamationmark.triangle")
                Button("重新读取") { report = ModelInsights.load() }.buttonStyle(PigPrimaryButton())
            }
        }
        .navigationTitle("模型判断")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .sheet(item: $selection) { feature in
            if let report { NavigationStack { InsightDetail(feature: feature, report: report) } }
        }
        .sheet(isPresented: $showMethod) {
            if let report {
                NavigationStack { InsightMethod(report: report) }
#if os(iOS)
                    .presentationDetents([.medium, .large])
#endif
            }
        }
    }

    private func header(_ report: ModelInsights) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("动作分类 · CAPTURE-24", systemImage: "waveform.path")
                .font(.caption.weight(.semibold)).foregroundStyle(insightAccent)
#if os(iOS)
            Text("24 项腕部加速度特征").font(.title2.bold())
#endif
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 20) {
                    metric("验证集基线", String(format: "%.2f%%", report.baseline))
                    metric("验证窗口", report.windows.formatted())
                }
                VStack(alignment: .leading, spacing: 8) {
                    metric("验证集基线", String(format: "%.2f%%", report.baseline))
                    metric("验证窗口", report.windows.formatted())
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 20)
                    .fill(LinearGradient(colors: [insightAccent.opacity(0.21), PigTheme.panel],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            }
    }

    private func metric(_ title: String, _ number: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(number).font(.title2.bold()).monospacedDigit()
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
    }

    private func scale(_ report: ModelInsights) -> some View {
        Chart {
            RuleMark(x: .value("基线", 0.0)).foregroundStyle(.clear)
        }
        .chartXScale(domain: report.domain)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: report.ticks.filter { $0 >= 0 }) { value in
                AxisValueLabel(anchor: .top) {
                    if let score = value.as(Double.self) {
                        Text(score.formatted(.number.precision(.fractionLength(0))))
                            .font(.caption2).foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
        }.frame(height: 18).accessibilityHidden(true)
    }

    private func featureRow(_ feature: ModelInsights.Feature, report: ModelInsights) -> some View {
        Button { selection = feature } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(feature.title).font(.subheadline.weight(.semibold))
                    Spacer(minLength: 2)
                    Text(String(format: "%+.2f", feature.mean)).monospacedDigit()
                        .font(.subheadline.weight(.semibold)).foregroundStyle(feature.mean < 0 ? PigTheme.mint : insightAccent)
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                }
                Chart {
                    BarMark(xStart: .value("起点", min(0, feature.mean)),
                            xEnd: .value("均值", max(0, feature.mean)),
                            y: .value("特征", feature.id), height: .fixed(10))
                        .foregroundStyle((feature.mean < 0 ? PigTheme.mint : insightAccent).opacity(0.62))
                    RuleMark(x: .value("零点", 0.0))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2])).foregroundStyle(.white.opacity(0.65))
                    RuleMark(xStart: .value("最小", feature.low), xEnd: .value("最大", feature.high),
                             y: .value("特征", feature.id))
                        .lineStyle(StrokeStyle(lineWidth: 1.5)).foregroundStyle(.white)
                    PointMark(x: .value("均值", feature.mean), y: .value("特征", feature.id))
                        .symbolSize(11).foregroundStyle(.white)
                }
                .chartXScale(domain: report.domain)
                .chartXAxis(.hidden).chartYAxis(.hidden)
                .frame(height: 14).accessibilityHidden(true)
            }.frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel(feature.title)
            .accessibilityValue(String(format: "平均下降 %+.2f 个百分点，最小 %+.2f，最大 %+.2f", feature.mean, feature.low, feature.high))
            .accessibilityHint("查看分布与预测样例")
            .accessibilityIdentifier("insights.feature." + feature.id)
    }
}

private struct InsightDetail: View {
    let feature: ModelInsights.Feature
    let report: ModelInsights
    @Environment(\.dismiss) private var dismiss
    @State private var showAll = false

    var body: some View {
        PigScreen {
            VStack(alignment: .leading, spacing: 6) {
#if os(watchOS)
                Text(feature.title).font(.headline.bold())
#else
                Text(feature.title).font(.title.bold())
#endif
                Text(feature.meaning).font(.subheadline)
                Label(feature.unit, systemImage: "ruler").font(.caption).foregroundStyle(insightAccent)
            }
#if os(iOS)
            Label(String(format: "打乱后平均%@ %.2f 个百分点",
                         feature.mean < 0 ? "上升" : "下降", abs(feature.mean)),
                         systemImage: "shuffle").font(.footnote.weight(.semibold))
                .foregroundStyle(insightAccent)
#endif
            PigPanel {
                Text("验证集分布").font(.headline)
                Text("\(report.windows.formatted()) 个窗口 · \(report.people) 人")
                    .font(.caption).foregroundStyle(.secondary)
                Chart(Array(feature.bins.enumerated()), id: \.offset) { _, bin in
                    RectangleMark(xStart: .value("下界", bin.lower), xEnd: .value("上界", bin.upper),
                                  yStart: .value("零", 0), yEnd: .value("窗口数", bin.count))
                        .foregroundStyle(insightAccent.gradient)
                        .accessibilityLabel("\(feature.formatted(bin.lower)) 至 \(feature.formatted(bin.upper))\(feature.suffix)")
                        .accessibilityValue("\(bin.count) 个窗口")
                }
                .chartXScale(domain: histogramDomain)
                .chartYScale(domain: 0...max(1, feature.bins.map(\.count).max() ?? 1))
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
                .chartXAxisLabel(feature.unit)
                .frame(height: 138)
                .accessibilityIdentifier("insights.distribution")
            }
            if !report.cases.isEmpty {
                PigPanel {
                    Text("同为步行，两种结果").font(.headline)
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 8) { exampleCards }
                        VStack(spacing: 8) { exampleCards }
                    }
                    Label("样例对照 · 不解释单条预测原因", systemImage: "info.circle")
                        .font(.caption2).foregroundStyle(.secondary)
                    Button { showAll.toggle() } label: {
                        Label(showAll ? "收起 24 项输入" : "这两段的 24 项输入",
                              systemImage: showAll ? "chevron.up" : "chevron.down")
                            .font(.subheadline).frame(minHeight: 44)
                    }.buttonStyle(.plain).foregroundStyle(insightAccent)
                        .accessibilityIdentifier("insights.case-inputs")
                    if showAll {
                        ForEach(report.features.sorted { $0.index < $1.index }) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).font(.caption.weight(.semibold))
                                ForEach(report.cases) { example in
                                    Text("\(example.correct ? "判对" : "判错")  \(example.value(for: item))")
                                        .font(.caption2).monospacedDigit()
                                }
                            }.padding(.vertical, 4)
                        }
                    }
                }
            }
        }.navigationTitle("输入证据")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
    }

    private var histogramDomain: ClosedRange<Double> {
        let low = feature.bins.first?.lower ?? 0
        let high = feature.bins.last?.upper ?? 1
        return low...max(low + 0.000001, high)
    }

    @ViewBuilder private var exampleCards: some View {
        ForEach(report.cases) { example in
            VStack(alignment: .leading, spacing: 5) {
                Label(example.correct ? "判对" : "判错", systemImage: example.correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.subheadline.weight(.bold)).foregroundStyle(example.correct ? PigTheme.mint : PigTheme.rose)
                Text(example.value(for: feature)).font(.headline.monospacedDigit())
                Text("真实：\(ModelInsights.Example.label(example.actual))").font(.caption)
                Text("模型：\(ModelInsights.Example.label(example.prediction))").font(.caption)
            }.fixedSize(horizontal: true, vertical: false)
                .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                .background(PigTheme.background, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("insights.case." + example.id)
        }
    }
}

private struct InsightMethod: View {
    let report: ModelInsights
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        PigScreen {
            Label("打乱一列 → 重算 → 比基线", systemImage: "shuffle").font(.headline)
            Text("同一模型，同一验证集；每项打乱 \(report.repeats) 次。条形与圆点是平均下降，细线是重复结果的最小–最大，不是置信区间。").font(.subheadline)
            Text("零表示无变化，负值表示打乱后分数上升。输入有关联时，重要性可能被分摊或放大。").font(.subheadline)
            Text("平衡准确率是步行与坐／站召回率的平均。比较固定二分类阈值；应用另有「拿不准」提示。").font(.subheadline)
            Label("只判断动作，不能用来判断个人患病原因。", systemImage: "info.circle")
                .font(.footnote.weight(.semibold)).foregroundStyle(PigTheme.cream)
        }.navigationTitle("怎么看这张图")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
    }
}
