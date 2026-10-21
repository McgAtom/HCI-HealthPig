import SwiftUI

struct FeatureEditorView: View {
    let initial: [Double]
    let names: [String]
    let units: [String]
    let onApply: ([Double]) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var text = ""
    @State private var values: [String] = []
    @State private var index = 0
    @State private var bulk = false
    @State private var initialized = false
    @State private var error = ""
    @FocusState private var focused: Bool
    @AccessibilityFocusState private var errorFocused: Bool
    var body: some View {
        PigScreen {
            Text("演示输入").font(.headline).accessibilityAddTraits(.isHeader)
            Text("仅演示，不存健康记录。").font(.caption).foregroundStyle(.secondary)
#if os(iOS)
            Group {
                if typeSize.isAccessibilitySize { VStack(spacing: 10) { modes } }
                else { HStack(spacing: 10) { modes } }
            }.accessibilityIdentifier("input.mode")
            if !bulk, values.count == 24 {
                PigPanel {
                    Menu {
                        Picker("选择特征", selection: $index) {
                            ForEach(0..<names.count, id: \.self) { item in
                                Text("\(item + 1). \(FeatureLabels.title(names[item]))").tag(item)
                            }
                        }
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index + 1). \(FeatureLabels.title(names[index]))")
                                .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.up.chevron.down").accessibilityHidden(true)
                        }.font(.body).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }.accessibilityLabel("选择特征，当前\(FeatureLabels.title(names[index]))").accessibilityIdentifier("input.feature")
                    Text("第 \(index + 1) / 24 项 · \(units[index])")
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("数值", text: singleValue, axis: .vertical)
                        .lineLimit(1...6).onSubmit { apply() }.submitLabel(.done)
                        .onKeyPress(.return, phases: .down) { _ in apply(); return .handled }
                        .onKeyPress(.escape, phases: .down) { _ in dismiss(); return .handled }
                        .font(.body.monospacedDigit()).textFieldStyle(.roundedBorder)
                        .keyboardType(.numbersAndPunctuation).focused($focused)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                        .accessibilityLabel("\(FeatureLabels.title(names[index]))，单位\(units[index])")
                        .accessibilityHint("只改这一项，其他23项保留。")
                        .accessibilityIdentifier("input.single-value")
                    ViewThatFits(in: .horizontal) {
                        HStack { previous; next }
                        VStack { previous; next }
                    }
                }
            } else {
                Text("24项数值，按顺序用逗号或换行分隔。").font(.caption)
                TextEditor(text: $text).font(.body.monospaced())
                    .frame(minHeight: 170).padding(8)
                    .background(PigTheme.panel, in: RoundedRectangle(cornerRadius: 12))
                    .keyboardType(.numbersAndPunctuation).focused($focused)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                    .accessibilityLabel("24项特征数值，逗号分隔").accessibilityIdentifier("input.values")
            }
#else
            Text("24项数值，用逗号分隔；建议在手机逐项修改。").font(.caption)
            TextField("24项数值，逗号分隔", text: $text).focused($focused).accessibilityIdentifier("input.values")
#endif
            if !error.isEmpty {
                StatusNote(title: "请检查输入", message: error, symbol: "exclamationmark.triangle")
                    .accessibilityIdentifier("input.error").accessibilityFocused($errorFocused)
            }
            Button("使用这些数值") { apply() }.buttonStyle(PigPrimaryButton()).accessibilityIdentifier("input.apply")
#if os(iOS)
                .keyboardShortcut(.return, modifiers: [.command])
#endif
            Button { clear() } label: { Text("清空输入").frame(maxWidth: .infinity, minHeight: 44) }
                .buttonStyle(PigSecondaryButton()).accessibilityIdentifier("input.clear")
            Button { restore() } label: { Text("恢复原示例").frame(maxWidth: .infinity, minHeight: 44) }
                .buttonStyle(PigSecondaryButton()).accessibilityIdentifier("input.restore")
#if os(iOS)
            Button("取消修改") { dismiss() }.keyboardShortcut(.cancelAction).accessibilityIdentifier("input.cancel")
                .buttonStyle(PigSecondaryButton())
#endif
            NavigationLink {
                PigScreen {
                    ForEach(Array(names.enumerated()), id: \.offset) { item, name in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(item + 1). \(FeatureLabels.title(name)) · \(units[item])").font(.subheadline)
                            Text(name).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }.accessibilityElement(children: .combine)
                    }
                    Text("只适用于模型特征，不能直接填步数、心率或疾病状态。格式正确也不保证来自有效动作。").font(.caption)
                }.navigationTitle("顺序与单位")
            } label: { Text("顺序与单位").frame(minHeight: 44) }
        }.navigationTitle("修改输入")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline).toolbar(.hidden, for: .tabBar)
#endif
            .onAppear { if !initialized { restore(); initialized = true } }
            .onChange(of: text) { _, _ in error = "" }
#if os(iOS)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    if !bulk { previous; next }
                    Spacer()
                    Button("完成输入") { focused = false }.accessibilityIdentifier("input.dismiss-keyboard")
                }
            }
#endif
    }
#if os(iOS)
    @ViewBuilder private var modes: some View {
        Button { changeMode(false) } label: {
            Label("逐项修改", systemImage: bulk ? "circle" : "checkmark.circle.fill")
        }.buttonStyle(PigSecondaryButton()).accessibilityValue(bulk ? "未选中" : "已选中")
        Button { changeMode(true) } label: {
            Label("批量粘贴", systemImage: bulk ? "checkmark.circle.fill" : "circle")
        }.buttonStyle(PigSecondaryButton()).accessibilityValue(bulk ? "已选中" : "未选中")
    }
    private var singleValue: Binding<String> {
        Binding(get: { values[index] }, set: { newValue in
            guard newValue != values[index] else { return }
            error = ""
            // Multiline layout lets long values wrap at large text sizes; a typed Return commits this one numeric field.
            let submit = newValue.contains("\n") || newValue.contains("\r")
            values[index] = newValue.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\r", with: "")
            if submit { Task { @MainActor in await Task.yield(); apply() } }
        })
    }
    private func changeMode(_ useBulk: Bool) {
        focused = false
        if useBulk { text = values.joined(separator: ", "); bulk = true }
        else {
            do { values = try FeatureInput.parse(text).map { String($0) }; error = ""; bulk = false }
            catch { self.error = error.localizedDescription; errorFocused = true }
        }
    }
    private var previous: some View {
        Group {
            if index > 0 {
                Button { focused = false; index -= 1 } label: { Label("上一项", systemImage: "chevron.left").frame(minHeight: 44) }
                    .accessibilityIdentifier("input.previous")
            } else { Text("第一项").font(.callout).foregroundStyle(.secondary).frame(minHeight: 44) }
        }
    }
    private var next: some View {
        Group {
            if index < 23 {
                Button { focused = false; index += 1 } label: { Label("下一项", systemImage: "chevron.right").frame(minHeight: 44) }
                    .accessibilityIdentifier("input.next")
            } else { Text("最后一项").font(.callout).foregroundStyle(.secondary).frame(minHeight: 44) }
        }
    }
#endif
    private func clear() {
        values = Array(repeating: "", count: 24); text = ""; bulk = true; focused = false; error = ""
    }
    private func restore() {
        values = initial.map { String($0) }; text = values.joined(separator: ", "); error = ""; focused = false
    }
    private func apply() {
        do {
#if os(iOS)
            let input = bulk ? text : values.joined(separator: ", ")
#else
            let input = text
#endif
            let parsed = try FeatureInput.parse(input); onApply(parsed); focused = false; dismiss()
        } catch {
            self.error = error.localizedDescription; focused = false
            Task { @MainActor in await Task.yield(); errorFocused = true }
        }
    }
}
