import Charts
import SwiftUI

private let insightAccent = Color(red: 0.78, green: 0.75, blue: 1)

struct ModelInsightsView: View {
    @State private var task: ModelInsights.Task

    init(initialTask: ModelInsights.Task = .motion) {
        _task = State(initialValue: initialTask)
    }

    var body: some View {
        InsightReportView(task: task, picker: $task).id(task)
            .navigationTitle("模型判断")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
    }
}

private struct InsightReportView: View {
    let task: ModelInsights.Task
    @Binding var picker: ModelInsights.Task
    @State private var report: ModelInsights?
    @State private var selection: ModelInsights.Feature?
    @State private var allFeatures = false
    @State private var showMethod = false
    @ScaledMetric(relativeTo: .caption2) private var axisHeight = 18.0

    init(task: ModelInsights.Task, picker: Binding<ModelInsights.Task>) {
        self.task = task
        _picker = picker
        _report = State(initialValue: ModelInsights.load(task))
    }

    var body: some View {
        PigScreen {
#if os(iOS)
            Picker("模型", selection: $picker) {
                ForEach(ModelInsights.Task.allCases) { choice in
                    Text(choice.title).tag(choice)
                }
            }.pickerStyle(.segmented).accessibilityIdentifier("insights.picker")
#endif
            if let report {
                Label(task.source, systemImage: task.icon)
                    .font(.headline).foregroundStyle(PigTheme.cream)
                    .accessibilityIdentifier("insights.source")
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("打乱输入", systemImage: "shuffle").font(.headline)
                        Spacer(minLength: 4)
                        Button { showMethod = true } label: {
                            Image(systemName: "info.circle").font(.title3)
                                .frame(minWidth: 44, minHeight: 44)
                        }.buttonStyle(.plain).foregroundStyle(insightAccent)
                            .accessibilityLabel("图例与实验方法")
                    }
                    Label("\(task.metric) · \(task.unit)", systemImage: task == .motion ? "arrow.down.right" : "arrow.up.right")
                        .font(.subheadline.weight(.medium)).foregroundStyle(insightAccent)
                    scale(report)
                    ForEach(allFeatures ? report.features : report.highlights) { feature in
                        featureRow(feature, report: report)
                    }
                    Button {
                        allFeatures.toggle()
                    } label: {
                        Label(allFeatures ? "收起 · 只看 \(report.highlights.count) 项" : "全部 \(report.features.count) 项输入",
                              systemImage: allFeatures ? "chevron.up" : "list.bullet")
                            .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                    }.buttonStyle(.plain).foregroundStyle(insightAccent)
                    .accessibilityIdentifier("insights.all-features")
                }.padding(14).background(PigTheme.panel, in: RoundedRectangle(cornerRadius: 22))
                Label(task.scope, systemImage: task.icon)
                    .font(.subheadline).foregroundStyle(PigTheme.cream)
                    .accessibilityIdentifier(task == .motion ? "insights.not-causal" : "insights.sleep-scope")
            } else {
                StatusNote(title: "判断资料不可用", message: "重新读取实验结果", symbol: "exclamationmark.triangle")
                Button("重新读取") { report = ModelInsights.load(task) }.buttonStyle(PigPrimaryButton())
            }
        }
        .sheet(item: $selection) { feature in
            if let report { NavigationStack { InsightDetail(feature: feature, report: report, task: task) } }
        }
        .sheet(isPresented: $showMethod) {
            if let report {
                NavigationStack { InsightMethod(report: report, task: task) }
#if os(iOS)
                    .presentationDetents([.medium, .large])
#endif
            }
        }
    }

    private func scale(_ report: ModelInsights) -> some View {
        Chart {
            RuleMark(x: .value("基线", 0.0)).foregroundStyle(.clear)
        }
        .chartXScale(domain: report.domain(for: task))
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: report.ticks(for: task)) { value in
                AxisValueLabel(anchor: .top) {
                    if let score = value.as(Double.self) {
                        Text(score.formatted(.number.precision(.fractionLength(0))))
                            .font(.caption2).foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
        }.frame(height: axisHeight).accessibilityHidden(true)
    }

    private func featureRow(_ feature: ModelInsights.Feature, report: ModelInsights) -> some View {
        Button { selection = feature } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(feature.title).font(.subheadline.weight(.semibold))
                    Spacer(minLength: 2)
                    Text(task.impact(feature.mean)).monospacedDigit()
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
                .chartXScale(domain: report.domain(for: task))
                .chartXAxis(.hidden).chartYAxis(.hidden)
                .frame(height: 14).accessibilityHidden(true)
            }.frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel(feature.title)
            .accessibilityValue("\(task.metric) \(task.impact(feature.mean)) \(task.unit)，最小 \(task.impact(feature.low))，最大 \(task.impact(feature.high))")
            .accessibilityHint("查看分布与预测样例")
            .accessibilityIdentifier("insights.feature." + feature.id)
    }
}

private struct InsightDetail: View {
    let feature: ModelInsights.Feature
    let report: ModelInsights
    let task: ModelInsights.Task
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
            PigPanel {
                Label(task == .motion ? "验证集分布" : "外部验证分布", systemImage: "chart.bar.xaxis").font(.headline)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { samplingBadges }
                    VStack(alignment: .leading, spacing: 6) { samplingBadges }
                }.font(.subheadline).foregroundStyle(insightAccent)
                Chart(Array(feature.bins.enumerated()), id: \.offset) { _, bin in
                    RectangleMark(xStart: .value("下界", bin.lower), xEnd: .value("上界", bin.upper),
                                  yStart: .value("零", 0), yEnd: .value(task.sampleName, bin.count))
                        .foregroundStyle(insightAccent.gradient)
                        .accessibilityLabel("\(feature.formatted(bin.lower)) 至 \(feature.formatted(bin.upper))\(feature.suffix)")
                        .accessibilityValue("\(bin.count) \(task.sampleName)")
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
                    Label("预测对照", systemImage: "rectangle.split.2x1").font(.headline)
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 8) { exampleCards }
                        VStack(spacing: 8) { exampleCards }
                    }
                    Button { showAll.toggle() } label: {
                        Label(showAll ? "收起 \(report.features.count) 项输入" : "\(task.comparison)的 \(report.features.count) 项输入",
                              systemImage: showAll ? "chevron.up" : "chevron.down")
                            .font(.subheadline).frame(minHeight: 44)
                    }.buttonStyle(.plain).foregroundStyle(insightAccent)
                        .accessibilityIdentifier("insights.case-inputs")
                    if showAll {
                        ForEach(report.features.sorted { $0.index < $1.index }) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).font(.caption.weight(.semibold))
                                ForEach(report.cases) { example in
                                    Text("\(task.caseTitle(example.id))  \(example.value(for: item))")
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

    @ViewBuilder private var samplingBadges: some View {
        Label("\(report.windows.formatted()) \(task.sampleName)", systemImage: "square.stack").monospacedDigit()
        Label("\(report.people) 人", systemImage: "person.2").monospacedDigit()
    }

    private var histogramDomain: ClosedRange<Double> {
        let low = feature.bins.first?.lower ?? 0
        let high = feature.bins.last?.upper ?? 1
        return low...max(low + 0.000001, high)
    }

    @ViewBuilder private var exampleCards: some View {
        ForEach(report.cases) { example in
            VStack(alignment: .leading, spacing: 5) {
                Label(task.caseTitle(example.id), systemImage: example.positive ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.subheadline.weight(.bold)).foregroundStyle(example.positive ? PigTheme.mint : PigTheme.rose)
                Text(example.value(for: feature)).font(.headline.monospacedDigit())
                Text("\(task == .sleep ? "实睡" : "真实")：\(task.output(example.actual))").font(.caption)
                Text("模型：\(task.output(example.prediction))").font(.caption)
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
    let task: ModelInsights.Task
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        PigScreen {
            Label("打乱一列 → 重算 → 比基线", systemImage: "shuffle").font(.headline)
            let unit = task == .motion ? "%" : " 分钟"
            Label("\(task.baselineName) \(report.baseline.formatted(.number.precision(.fractionLength(2))))\(unit)", systemImage: "scope")
                .font(.headline)
            Text("\(report.dataset) · \(report.features.count) 项输入")
            Text("每项打乱 \(report.repeats) 次。条和圆点表示平均值，细线表示最小至最大。")
            if task == .motion {
                Text("比较固定阈值的平衡准确率。零为无变化，负值表示打乱后的分数较高。")
                Label("只看动作，不判病因", systemImage: task.icon)
            } else {
                Text("比较平均绝对误差。零为无变化，负值表示打乱后的误差较小。")
                Label("历史实睡与次晨日期", systemImage: task.icon)
            }
            Text("排行表示整批结果对输入的依赖。有关联的输入可能相互替代，样例显示实际值与模型输出。")
        }.navigationTitle("怎么看这张图")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
    }
}
