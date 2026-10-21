import SwiftUI

struct HealthRecordView: View {
    @ObservedObject var health: HealthReader
    @State private var confirmClear = false
    var body: some View {
        PigScreen {
            PigPanel {
                Label("健康数据", systemImage: "heart.text.clipboard").font(.headline)
                Text("经你授权，从本机 HealthKit 读取步数、睡眠、最近心率和今日活动圆环。圆环仅用于猪猪能量与抽卡条件。").font(.callout).foregroundStyle(.secondary)
                Button(health.loading ? "正在读取…" : health.automaticUpdates ? "管理读取授权" : "授权并读取") {
                    Task { await health.authorizeAndRefresh() }
                }.buttonStyle(PigPrimaryButton()).disabled(health.loading)
                if health.loading { ProgressView("正在查询已有记录") }
                Text(health.message).font(.caption).accessibilityIdentifier("health.status")
                if !health.error.isEmpty {
                    StatusNote(title: "读取未完成", message: health.error, symbol: "exclamationmark.triangle")
                    Button("重试读取") { Task { await health.refresh() } }.disabled(health.loading)
                }
            }
            PigPanel {
                HealthMetric(label: "今日已记录步数", value: health.steps.map { "\(Int($0))" } ?? "暂无记录", unit: health.steps == nil ? "" : "步", symbol: "figure.walk")
                Divider()
                HealthMetric(label: "最近心率记录", value: health.heartRate.map { "\(Int($0))" } ?? "暂无记录", unit: health.heartRate == nil ? "" : "次／分", symbol: "heart")
                if let date = health.heartDate {
                    Text(date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    Text("这是已有记录，不是正在测量。").font(.caption).foregroundStyle(.secondary)
                }
            }
            PigPanel {
                Label("睡眠记录来源", systemImage: "moon.zzz").font(.headline)
                if health.days.isEmpty { Text("暂无可读睡眠。可能尚未记录、同步，或未允许读取。").font(.caption).foregroundStyle(.secondary) }
                ForEach(health.days.reversed()) { day in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(day.date.formatted(.dateTime.month().day())) · \(day.hours, specifier: "%.1f") 小时").font(.subheadline)
                        Text(day.sources.joined(separator: "、")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("按已结束的自然日统计，包含午睡；重叠时段合并，缺失保留未知。").font(.caption).foregroundStyle(.secondary)
            }
            if let date = health.refreshedAt {
                Text("上次读取 \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                Button("刷新已有记录") { Task { await health.refresh() } }.disabled(health.loading)
            }
            NavigationLink("刷新、权限与缓存说明") {
                PigScreen {
                    Text(health.backgroundMessage)
                    Text("健康系统不会说明是否拒绝读取。空结果也可能是未记录或未同步；在系统健康权限中检查。")
                    Text("应用仅查询已有记录，不主动测量心率或睡眠。")
                }.navigationTitle("数据说明")
            }

            if health.automaticUpdates {
                Button("关闭自动读取并清除本机缓存", role: .destructive) { confirmClear = true }.disabled(health.loading)
            }
        }.navigationTitle("数据与授权")
            .confirmationDialog("关闭自动读取？", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("关闭并清除缓存", role: .destructive) { Task { await health.stopAutomaticUpdatesAndClearCache() } }
            } message: { Text("只清除此应用的健康缓存，系统健康记录和猪猪收藏会保留。") }
    }
}

struct HealthMetric: View {
    let label: String
    let value: String
    let unit: String
    let symbol: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(label, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            Text(unit.isEmpty ? value : "\(value) \(unit)").font(.system(.title2, design: .rounded, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
        }.accessibilityElement(children: .combine)
    }
}

struct ModelExplanationView: View {
    var body: some View {
        PigScreen {
            PigPanel {
                Label("怎样采集", systemImage: "applewatch").font(.headline)
                Text("戴好手表，选择正常步行或安静坐／站。开始后保持约 10 秒，可以放下手腕；离开应用会停止采集。").font(.body)
            }
            PigPanel {
                Text("结果能说明什么").font(.headline)
                Text("模型只区分这段动作更像“步行”还是“坐／站”。接近分界时显示“拿不准”，可以重新采集。")
                Text("模型来自 CAPTURE-24 的 151 名成年人及 Axivity 设备记录。Apple Watch 的设备差异仍需实测；骑车、驾驶、刷牙等不在当前任务范围。").foregroundStyle(.secondary)
            }
            PigPanel {
                Text("适用范围与数据").font(.headline)
                Text("模型分数不是综合健康分，也不是校准后的可信概率。不能据此判断疾病、身体好坏或一天的活动是否足够。")
                Text("原始加速度只在手表内存处理。应用保存最近一次动作摘要；配套两端可同步摘要和收藏，反馈只保存在提交反馈的本机，不上传服务器。").foregroundStyle(.secondary)
                Text("睡眠与步数趋势仅描述已有记录。睡眠审核是 NHANES 离线研究，不向你输出个人睡眠预测。").foregroundStyle(.secondary)
            }
        }.navigationTitle("模型与说明")
    }
}

struct ResultFeedbackView: View {
    @ObservedObject var store: PigStore
    let reading: WatchReading
    var answer: String? { store.feedback.first { $0.readingID == reading.id }?.answer }
    var body: some View {
        PigScreen {
            Text("这个结果符合刚才的动作吗？").font(.headline)
            Text("模型判断：\(reading.verdict.title)").font(.callout).foregroundStyle(.secondary)
            ForEach(["符合", "不符合", "不确定"], id: \.self) { option in
                Button { _ = store.addFeedback(readingID: reading.id, answer: option) } label: {
                    HStack {
                        Text(option)
                        Spacer()
                        if answer == option { Image(systemName: "checkmark.circle.fill") }
                    }.padding(.vertical, 7)
                }.buttonStyle(.bordered).accessibilityLabel(answer == option ? "\(option)，已选择" : option)
            }
            if answer != nil {
                StatusNote(title: "反馈已保存", message: "你可以重新选择修改。反馈不会立即改变模型，也不作为人工标注的准确率。", symbol: "checkmark.circle")
            } else { Text("可直接返回跳过，不影响使用或领取猪猪。").font(.caption).foregroundStyle(.secondary) }
            StoreErrorView(store: store)
        }.navigationTitle("告诉猪猪")
    }
}

extension MotionVerdict {
    var title: String {
        switch self {
        case .walking: return "更像步行"
        case .still: return "更像坐／站"
        case .uncertain: return "这次拿不准"
        case .waiting: return "尚未采集"
        }
    }
    var symbol: String {
        switch self {
        case .walking: return "figure.walk"
        case .still: return "figure.seated.side"
        case .uncertain: return "questionmark.circle"
        case .waiting: return "applewatch"
        }
    }
}
