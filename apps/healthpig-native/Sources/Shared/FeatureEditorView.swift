import SwiftUI

struct FeatureEditorView: View {
    let initial: [Double]
    let names: [String]
    let units: [String]
    let onApply: ([Double]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var error = ""
    @FocusState private var focused: Bool
    var body: some View {
        PigScreen {
            Text("24项模型特征").font(.headline).accessibilityAddTraits(.isHeader)
            Text("按下方顺序输入，用逗号或换行分隔。仅修改演示，不写入健康记录。").font(.caption).foregroundStyle(.secondary)
#if os(iOS)
            TextEditor(text: $text).frame(minHeight: 170).padding(8).background(PigTheme.panel, in: RoundedRectangle(cornerRadius: 12))
                .keyboardType(.numbersAndPunctuation).focused($focused)
                .accessibilityLabel("24项特征数值，逗号分隔").accessibilityIdentifier("input.values")
            Button("收起键盘") { focused = false }
#else
            TextField("24项数值，逗号分隔", text: $text).focused($focused).accessibilityIdentifier("input.values")
#endif
            if !error.isEmpty { StatusNote(title: "请检查输入", message: error, symbol: "exclamationmark.triangle").accessibilityIdentifier("input.error") }
            Button("使用这些数值") { apply() }.buttonStyle(PigPrimaryButton()).accessibilityIdentifier("input.apply")
            Button("清空输入") { text = "" }.accessibilityIdentifier("input.clear")
            Button("恢复原示例") { restore() }.buttonStyle(.bordered).accessibilityIdentifier("input.restore")
            NavigationLink("顺序与单位") {
                PigScreen {
                    ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                        Text("\(index + 1). \(name) · \(units[index])").font(.caption)
                    }
                    Text("加速度单位g；时间相关项为秒或Hz，其余单位以各项标注为准。请勿直接粘贴步数、心率或疾病状态。自填数值不保证来自有效动作窗口。").font(.caption)
                }.navigationTitle("输入格式")
            }
        }.navigationTitle("修改输入").onAppear { if text.isEmpty { restore() } }
            .onChange(of: text) { _, _ in error = "" }
    }
    private func restore() { text = initial.map { String($0) }.joined(separator: ", "); error = "" }
    private func apply() {
        do { let values = try FeatureInput.parse(text); onApply(values); focused = false; dismiss() }
        catch { self.error = error.localizedDescription }
    }
}
