import SwiftUI

// Demo inputs and feedback deliberately never enter PigLedger, HealthKit, or real result feedback.
struct DemoAnalysisView: View {
    var companionCard: PigCard? = nil
    @State private var document: DemoExamples?
    @State private var model: MotionModel?
    @State private var selected = "walking"
    @State private var score: Double?
    @State private var answer: String?
    @State private var failure = ""
    @State private var customFeatures: [Double]?
    @State private var analyzing = false
    private var example: DemoExample? { document?.examples.first { $0.id == selected } }
    var body: some View {
        PigScreen {
            PigPanel {
                Label("公开样本 · 演示模式", systemImage: "play.rectangle").font(.headline).foregroundStyle(PigTheme.cream)
                Text("CAPTURE-24公开数据，可修改后重算；不是本人测量。").font(.caption).foregroundStyle(.secondary)
            }
            if let document, let example, let model {
                Picker("选择演示输入", selection: $selected) {
                    ForEach(document.examples) { Text($0.name).tag($0.id) }
                }
#if os(watchOS)
                .pickerStyle(.navigationLink)
#else
                .pickerStyle(.segmented)
#endif
                .accessibilityIdentifier("demo.input")
                NavigationLink("修改24项输入") {
                    FeatureEditorView(initial: customFeatures ?? example.features, names: document.featureNames, units: document.featureUnits) { values in
                        customFeatures = values; score = nil; answer = nil; failure = ""
                    }
                }.accessibilityIdentifier("demo.edit")
                if customFeatures != nil {
                    Label("已修改 · 演示输入", systemImage: "pencil").font(.caption)
                    Button("恢复选中示例") { customFeatures = nil; score = nil; answer = nil; failure = "" }.accessibilityIdentifier("demo.reset")
                }
                NavigationLink("查看输入与单位") {
                    PigScreen {
                    Text("10 秒、20 Hz 公开记录提取的 24 项特征。修改上方示例后可以重新分析。").font(.caption)
                    ForEach(Array(document.featureNames.enumerated()), id: \.offset) { index, name in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(name).font(.caption).foregroundStyle(.secondary)
                            Text("\((customFeatures ?? example.features)[index], specifier: "%.4f") \(document.featureUnits[index])").font(.caption.monospacedDigit())
                        }
                    }
                    }.navigationTitle("演示输入")
                }.font(.caption)
                Button(analyzing ? "分析中…" : score == nil ? "分析演示样本" : "重新分析此样本") {
                    score = nil; failure = ""; answer = nil; analyzing = true
                    Task { @MainActor in
                        await Task.yield()
                        let output = model.score(customFeatures ?? example.features)
                        if output.isFinite { score = output }
                        else { failure = "输入超出模型可计算范围。请恢复示例后重试。" }
                        analyzing = false
                    }
                }.buttonStyle(PigPrimaryButton()).disabled(analyzing).accessibilityIdentifier("demo.analyze")
#if os(iOS)
                .keyboardShortcut(.return, modifiers: [.command])
#endif
                if analyzing { ProgressView("正在执行本地模型") }
                if let score {
                    let verdict = MotionVerdict.decide(score: score, threshold: model.threshold)
                    if let companionCard {
                        PigResponseScene(card: companionCard, verdict: verdict)
                        Text("公开样本驱动的猪猪回应；不改变本人能量、收藏或动作记录。").font(.caption).foregroundStyle(.secondary)
                    }
                    PigPanel {
                        Label("演示结果", systemImage: verdict.symbol).font(.caption).foregroundStyle(PigTheme.mint)
                        Text(verdict.title).font(.title2.bold()).accessibilityIdentifier("demo.result")
                        Text("只区分步行与坐／站，不评价身体健康。").font(.callout)
                        Text("分数 \(score, specifier: "%.3f") · 分界 \(model.threshold, specifier: "%.3f")").font(.caption)
                        Text("不是健康分或校准后的可信概率。").font(.caption).foregroundStyle(.secondary)
                    }
                    PigPanel {
                        Text("演示反馈").font(.headline)
                        Text("这个解释容易理解吗？").font(.caption)
                        ForEach(["容易理解", "需要更多说明"], id: \.self) { option in
                            Button { answer = option } label: {
                                HStack { Text(option); Spacer(); if answer == option { Image(systemName: "checkmark.circle.fill") } }
                            }.buttonStyle(.bordered)
                        }
                        if answer != nil {
                            Label("演示选择已更新", systemImage: "checkmark.circle").font(.caption).accessibilityIdentifier("demo.feedback-saved")
                            Text("仅演示交互，不计入用户测试统计，也不会修改模型。").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Text("来源：\(document.source) · Chan 等（2024）\n许可：\(document.license)\n选取两例仅为说明流程，不能据此推断准确率。").font(.caption).foregroundStyle(.secondary)
            } else if failure.isEmpty { ProgressView("读取演示资源") }
            if !failure.isEmpty {
                StatusNote(title: "演示暂不可用", message: failure, symbol: "exclamationmark.triangle")
                Button("恢复示例并重试") { customFeatures = nil; score = nil; answer = nil; load() }.accessibilityIdentifier("demo.recover")
            }
        }.navigationTitle("公开样本演示")
            .task { load() }
            .onChange(of: selected) { _, _ in score = nil; answer = nil; customFeatures = nil; failure = "" }
    }
    private func load() {
        do {
            guard let examplesURL = Bundle.main.url(forResource: "demo-examples", withExtension: "json"),
                  let modelURL = Bundle.main.url(forResource: "motion-model", withExtension: "json") else {
                throw PigDataError.invalid("演示资源缺失，请重新安装完整应用。")
            }
            document = try JSONDecoder().decode(DemoExamples.self, from: Data(contentsOf: examplesURL)).validated()
            model = try JSONDecoder().decode(MotionModel.self, from: Data(contentsOf: modelURL)); failure = ""
        } catch { failure = error.localizedDescription }
    }
}
