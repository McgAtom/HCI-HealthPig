import SwiftUI

struct AuditCatalogView: View {
    var body: some View {
        PigScreen {
            PigPanel {
                Label("独立研究审核", systemImage: "person.2").font(.headline)
                Text("查看不同群体的样本量与错误率，并比较基线和约束候选。").font(.callout)
                Text("两个数据集分别评估；这些不是本人健康结论，也不是手表实机准确率。").font(.caption).foregroundStyle(.secondary)
            }
            NavigationLink { FairnessAuditView(resource: "fairness-audit") } label: {
                PigPanel {
                    Text("步行模型").font(.headline)
                    Text("CAPTURE-24 · 步行与坐／站").font(.caption).foregroundStyle(.secondary)
                }
            }.buttonStyle(.plain).accessibilityIdentifier("audit.walk")
            NavigationLink { FairnessAuditView(resource: "sleep-audit") } label: {
                PigPanel {
                    Text("睡眠研究").font(.headline)
                    Text("NHANES · 独立离线审核").font(.caption).foregroundStyle(.secondary)
                }
            }.buttonStyle(.plain)
        }.navigationTitle("公平性审核")
    }
}

struct FairnessAuditView: View {
    let resource: String
    @State private var attribute = "sex"
    @State private var document: AuditDocument?
    @State private var failure = ""
    var body: some View {
        PigScreen {
            if let d = document {
                PigPanel {
                    Text(d.title).font(.headline)
                    Text("\(d.dataset) · 测试 \(d.people) 人").font(.subheadline)
                    Text("\(d.windows) 个\(d.recordUnit)，多条记录可能来自同一个人。").font(.caption).foregroundStyle(.secondary)
                    Label(d.recommended ? "候选仍需设备验证" : "保留基线，未推荐替换", systemImage: d.recommended ? "info.circle" : "exclamationmark.circle")
                        .font(.subheadline).foregroundStyle(PigTheme.cream)
                    Text(d.conclusion).font(.caption).foregroundStyle(.secondary)
                }
                PigPanel {
                    Text("整体表现").font(.headline)
                    AuditComparisonRow(label: "准确率", before: d.baseline.accuracy, after: d.candidate.accuracy)
                    AuditComparisonRow(label: "漏判率", before: d.baseline.fnr, after: d.candidate.fnr)
                    AuditComparisonRow(label: "误判率", before: d.baseline.fpr, after: d.candidate.fpr)
                    Text("前：基线；后：约束候选。准确率上升不代表错误代价或群体差距都改善。").font(.caption).foregroundStyle(.secondary)
                }
                Picker("比较分组", selection: $attribute) {
                    ForEach(d.attributes) { Text($0.name).tag($0.id) }
                }
#if os(watchOS)
                .pickerStyle(.navigationLink)
#else
                .pickerStyle(.menu)
#endif
                if let a = d.attributes.first(where: { $0.id == attribute }) {
                    PigPanel {
                        Text(a.name).font(.headline)
                        AuditComparisonRow(label: "最大错误率差距", before: a.baselineEO, after: a.candidateEO)
                        Text("比较群体之间的漏判率和误判率，取其中最大的差距。更接近不代表完全公平。").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(a.groups) { group in
                        NavigationLink {
                            AuditGroupView(group: group, positiveName: d.positiveName, negativeName: d.negativeName, recordUnit: d.recordUnit)
                        } label: {
                            PigPanel {
                                HStack { Text(group.name).font(.headline); Spacer(); Image(systemName: "chevron.right").font(.caption) }
                                Text("\(group.people) 人 · \(group.positive + group.negative) 个\(d.recordUnit)").font(.caption).foregroundStyle(.secondary)
                                AuditComparisonRow(label: "漏判", before: group.baseline.fnr, after: group.candidate.fnr)
                                AuditComparisonRow(label: "误判", before: group.baseline.fpr, after: group.candidate.fpr)
                                if !group.caution.isEmpty { Label("样本较少，谨慎解释", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(PigTheme.cream) }
                            }
                        }.buttonStyle(.plain)
                    }
                }
                NavigationLink("漏判、误判与研究局限") { AuditExplanationView(document: d) }.buttonStyle(.bordered)
            } else if !failure.isEmpty {
                StatusNote(title: "审核数据未能读取", message: failure, symbol: "exclamationmark.triangle")
                Button("重新读取") { load() }
            } else { ProgressView("读取审核资源") }
        }.navigationTitle("研究结果").task { if document == nil { load() } }
    }
    private func load() {
        do {
            guard let url = Bundle.main.url(forResource: resource, withExtension: "json") else {
                throw PigDataError.invalid("应用内审核资源缺失，请重新安装完整应用。")
            }
            let d = try JSONDecoder().decode(AuditDocument.self, from: Data(contentsOf: url))
            document = d; failure = ""
            if !d.attributes.contains(where: { $0.id == attribute }), let first = d.attributes.first { attribute = first.id }
        } catch { failure = error.localizedDescription }
    }
}

struct AuditComparisonRow: View {
    let label: String
    let before: Double?
    let after: Double?
    private func percent(_ value: Double?) -> String { value.map { String(format: "%.1f%%", $0 * 100) } ?? "无法估计" }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Text("前 \(percent(before))")
                Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                Text("后 \(percent(after))")
            }.font(.subheadline.monospacedDigit()).fixedSize(horizontal: false, vertical: true)
        }.accessibilityElement(children: .ignore).accessibilityLabel("\(label)，基线\(percent(before))，约束候选\(percent(after))")
    }
}

struct AuditGroupView: View {
    let group: AuditGroup
    let positiveName: String
    let negativeName: String
    let recordUnit: String
    var body: some View {
        PigScreen {
            PigPanel {
                Text(group.name).font(.headline)
                Text("\(group.people) 名参与者").font(.title3.bold())
                Text("\(positiveName)：\(group.positive) 个\(recordUnit)\n\(negativeName)：\(group.negative) 个\(recordUnit)").font(.callout)
                Text("人数与记录数不同。重复个体的记录不能当作更多独立参与者。").font(.caption).foregroundStyle(.secondary)
            }
            PigPanel {
                AuditComparisonRow(label: "漏判率", before: group.baseline.fnr, after: group.candidate.fnr)
                AuditComparisonRow(label: "误判率", before: group.baseline.fpr, after: group.candidate.fpr)
                AuditComparisonRow(label: "平衡准确率", before: group.baseline.balancedAccuracy, after: group.candidate.balancedAccuracy)
                AuditComparisonRow(label: "正类 F1", before: group.baseline.f1, after: group.candidate.f1)
                AuditComparisonRow(label: "预测为正类的比例", before: group.baseline.selectionRate, after: group.candidate.selectionRate)
            }
            if !group.caution.isEmpty { StatusNote(title: "谨慎解释", message: group.caution, symbol: "exclamationmark.triangle") }
            Text("前为基线，后为约束候选。群体样本少时，错误率可能很不稳定；无法估计的项不会写成零。").font(.caption).foregroundStyle(.secondary)
        }.navigationTitle(group.name)
    }
}

struct AuditExplanationView: View {
    let document: AuditDocument
    var body: some View {
        PigScreen {
            PigPanel {
                Text("漏判与误判").font(.headline)
                Text(document.falseNegativeExplanation)
                Text(document.falsePositiveExplanation)
            }
            PigPanel {
                Text("怎样理解差距").font(.headline)
                Text("整体准确率高，不代表每个群体都一样好。这里同时比较群体之间的漏判率与误判率，报告其中最大差距。差距小不能证明模型完全公平。")
                if let interval = document.eoInterval, interval.count == 2 {
                    Text(String(format: "性别差距变化的95%%区间为 %.1f 至 %.1f 个百分点。", interval[0] * 100, interval[1] * 100))
                    if interval[0] <= 0 && interval[1] >= 0 { Text("区间包含零，不能确定差距稳定改善。") }
                }
            }
            PigPanel {
                Text("研究边界").font(.headline)
                Text(document.recommended ? "候选通过研究替换条件，仍需设备迁移验证。" : "候选未通过验证集替换条件，因此应用继续使用基线模型。")
                Text("这些是 \(document.dataset) 的离线实验。不是本人的健康评价，也不等于 Apple Watch 上的实际准确率。")
                Text("睡眠研究与步行识别使用不同数据集，不能拼成同一批参与者或综合健康分。")
            }
        }.navigationTitle("怎样理解")
    }
}
