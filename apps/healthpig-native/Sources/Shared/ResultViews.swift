import SwiftUI

struct TodayReviewView: View {
    @ObservedObject var health: HealthReader
    var body: some View {
        PigScreen {
            HealthReadStateView(health: health)
            PigPanel {
                HealthMetric(label: "今日已记录", value: health.steps.map { "\(Int($0))" } ?? "暂无步数", unit: health.steps == nil ? "" : "步", symbol: "figure.walk")
                Text("今天尚未结束，步数仍会变化。").font(.caption).foregroundStyle(.secondary)
                NavigationLink("看近 7 日活动") { HealthTrendView(health: health, sleep: false) }
            }
            PigPanel {
                Label("睡眠记录", systemImage: "moon.zzz").font(.headline)
                if let day = health.days.max(by: { $0.date < $1.date }) {
                    Text("\(day.date.formatted(.dateTime.month().day())) · \(day.hours, specifier: "%.1f") 小时")
                    Text("已结束自然日的总量，包含午睡。").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("暂时没有可读记录").font(.subheadline)
                    Text("需先佩戴过夜并完成同步；这里只读取已有记录。").font(.caption).foregroundStyle(.secondary)
                }
                NavigationLink("看睡眠记录与说明") { HealthTrendView(health: health, sleep: true) }.accessibilityIdentifier("review.sleep")
            }
            NavigationLink("读取已有健康记录") { HealthRecordView(health: health) }.accessibilityIdentifier("review.authorize")
            if health.steps == nil && health.days.isEmpty {
                Text("暂无记录不等于零。可先检查授权与同步。").font(.caption).foregroundStyle(.secondary)
            }
            if let date = health.refreshedAt { Text("读取于 \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
        }.navigationTitle("今日回顾").task { await health.refreshAutomaticallyIfEnabled() }
    }
}

struct ReadingResultView: View {
    @ObservedObject var store: PigStore
    let reading: WatchReading
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PigPanel {
                Label("10 秒动作快照", systemImage: reading.verdict.symbol).font(.caption).foregroundStyle(PigTheme.mint)
                Text(reading.verdict.title).font(.title2.bold()).foregroundStyle(PigTheme.cream)
                Text(explanation).font(.callout)
                Text(reading.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                Text("只描述这次动作，不评价整体健康。").font(.caption).foregroundStyle(.secondary)
            }
            NavigationLink { ResultFeedbackView(store: store, reading: reading) } label: {
                Label("这个结果符合吗？", systemImage: "bubble")
            }.buttonStyle(.bordered)
            NavigationLink("查看模型依据") {
                PigScreen {
                    PigPanel {
                        Text("模型分数 \(reading.score, specifier: "%.3f")").font(.headline)
                        Text("分类分界 \(reading.threshold, specifier: "%.3f")")
                        Text("距离分界小于 0.1 时显示拿不准；这不是置信区间，也不是校准后的可信概率。").font(.caption).foregroundStyle(.secondary)
                        Text("\(reading.sampleCount) 个真实样本 · \(reading.actualHz, specifier: "%.1f") Hz").font(.caption)
                        Text("原始加速度未持久保存。模型与第 4 版一致。").font(.caption).foregroundStyle(.secondary)
                    }
                    NavigationLink("完整适用范围") { ModelExplanationView() }
                }.navigationTitle("结果依据")
            }.font(.caption)
        }
    }
    private var explanation: String {
        switch reading.verdict {
        case .walking: return "模型把这段记录分到了步行一类。"
        case .still: return "模型把这段记录分到了坐／站一类。坐与站不会进一步区分。"
        default: return "结果接近分类分界。检查佩戴与动作，再采集一次。"
        }
    }
}

struct TrendHomeView: View {
    @ObservedObject var health: HealthReader
    var body: some View {
        PigScreen {
            Text("看看最近的节奏").font(.headline)
            HealthReadStateView(health: health)
            NavigationLink { HealthTrendView(health: health, sleep: false) } label: {
                PigPanel {
                    Label("日常活动", systemImage: "figure.walk").foregroundStyle(PigTheme.mint)
                    Text("\(health.activityDays.count) / 7 日有记录").font(.headline)
                    Text("步数变化与记录日均值").font(.caption).foregroundStyle(.secondary)
                }
            }.buttonStyle(.plain)
            NavigationLink { HealthTrendView(health: health, sleep: true) } label: {
                PigPanel {
                    Label("睡眠节奏", systemImage: "moon.zzz").foregroundStyle(PigTheme.rose)
                    Text("\(health.days.count) / 7 日有记录").font(.headline)
                    Text(health.days.isEmpty ? "暂缺记录 · 查看来源与下一步" : "自然日睡眠总量，含午睡").font(.caption).foregroundStyle(.secondary)
                }
            }.buttonStyle(.plain).accessibilityIdentifier("trend.sleep")
            if health.days.isEmpty && health.activityDays.isEmpty {
                StatusNote(title: "还没有可读趋势", message: "可以先读取健康记录。没有数据的日期会保持未知。", symbol: "chart.bar")
            }
            NavigationLink("数据与授权") { HealthRecordView(health: health) }
        }.navigationTitle("近期趋势")
    }
}
