import SwiftUI
import WatchKit

@main struct HealthPigApp: App {
    @WKApplicationDelegateAdaptor(PigApplicationDelegate.self) private var delegate
    var body: some Scene { WindowGroup { HealthPigView() } }
}

struct HealthPigView: View {
    @StateObject private var health = HealthReader.shared
    @StateObject private var motion = LiveMotion()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("healthPigGiftDay") private var giftDay = ""
    private var today: String { Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash)) }
    private var pigState: PigVisualState { motion.verdict }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    Text("走走猪猪").font(.headline)
                    Text("版本2 · 自动健康记录").font(.caption2).foregroundStyle(.secondary)
                    PigFace(state: pigState, scarf: giftDay == today)
                    Text(motion.message).font(.callout).multilineTextAlignment(.center)
                    Text("步行／坐站 · 10秒检查").font(.caption2).foregroundStyle(.secondary)
                    Text(motion.runtimeMessage).font(.caption2).foregroundStyle(.secondary)
                    if motion.capturing {
                        ProgressView(value: motion.progress)
                        Text("已读取\(motion.sampleCount)个真实样本").font(.caption2)
                        Button("停止") { motion.cancel() }
                    } else {
                        Button("采集手表动作") { motion.start() }.tint(.pink)
                    }
                    if !motion.error.isEmpty { Text(motion.error).font(.caption2).foregroundStyle(.orange) }
                    if let time = motion.measuredAt {
                        Text("实际采集：\(time.formatted(date: .omitted, time: .standard))").font(.caption2)
                        if let rate = motion.actualHz {
                            Text("\(motion.sampleCount)个样本 · \(rate, specifier: "%.1f")Hz").font(.caption2)
                        }
                    }
                    if let score = motion.score {
                        Text("模型分数 \(score, specifier: "%.3f")").font(.caption2)
                        Text("分界 \(motion.threshold, specifier: "%.3f") · \(motion.verdict == .still ? "坐／站" : motion.verdict == .walking ? "步行" : "待确认")").font(.caption2)
                        Text("不是健康分或可信概率").font(.caption2).foregroundStyle(.secondary)
                    }
                    NavigationLink("真实健康记录") { HealthRecordView(health: health) }
                    if let steps = health.steps {
                        Text("今日已记录 \(Int(steps))步").font(.caption2)
                    }
                    if let date = health.refreshedAt {
                        Text("健康读取 \(date.formatted(date: .omitted, time: .shortened))").font(.caption2).foregroundStyle(.secondary)
                    }
                    NavigationLink("本次动作摘要") {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("仅在本机保存最近一次动作摘要，方便核对；不保存原始加速度。").font(.caption2)
                                if let s = motion.lastSummary {
                                    Text(s.date.formatted(date: .abbreviated, time: .standard))
                                    Text("分数 \(s.score, specifier: "%.3f")／分界 \(s.threshold, specifier: "%.3f")")
                                    Text(s.verdict.message)
                                    Text("\(s.sampleCount)点 · \(s.actualHz, specifier: "%.1f")Hz")
                                    Text("幅度标准差 \(s.features[1], specifier: "%.5f")g")
                                    Button("清除动作摘要") { motion.clearSummary() }
                                } else { Text("暂无动作摘要") }
                            }.font(.caption2)
                        }
                    }
                    Button(giftDay == today ? "🧣 今天已领取" : "领取今日围巾") { giftDay = today }
                    NavigationLink("怎么测与适用范围") {
                        ScrollView {
                            Text("戴好手表，打开应用开始测量后可以放下手腕。选择正常步行或安静坐／站，保持约10秒。按表冠或切换应用会结束本次测量。骑车、驾驶、刷牙等动作超出当前模型范围。\n\n模型来自151名成年人佩戴的Axivity设备；Apple Watch的设备差异仍需实测。此课程实验只识别动作，不表示疾病、整体健康或运动量是否足够。\n\n接近模型分界会显示拿不准。健康记录由手表系统采集，经授权自动读取HealthKit，后台更新由系统安排，并非每秒同步。最近心率是记录值，不是现在测量。原始加速度只在内存处理；最新动作摘要和健康记录缓存在本机，可分别清除，不上传。")
                                .font(.caption).padding()
                        }
                    }
                }.padding(.horizontal, 6)
            }
        }
        .onChange(of: scenePhase) { _, value in
            if value == .background { motion.cancel() }
            if value == .active { Task { await health.refreshAutomaticallyIfEnabled() } }
        }
    }
}

struct HealthRecordView: View {
    @ObservedObject var health: HealthReader
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("手表健康记录").font(.headline)
                Button(health.loading ? "正在读取…" : health.automaticUpdates ? "管理读取授权" : "授权并自动读取") { Task { await health.authorizeAndRefresh() } }
                    .disabled(health.loading)
                if health.refreshedAt != nil {
                    Button("刷新记录") { Task { await health.refresh() } }.disabled(health.loading)
                }
                Text(health.message).font(.caption2)
                Text(health.backgroundMessage).font(.caption2).foregroundStyle(.secondary)
                if let date = health.refreshedAt {
                    Text("上次读取：\(date.formatted(date: .abbreviated, time: .shortened))").font(.caption2)
                }
                if !health.error.isEmpty { Text(health.error).font(.caption2).foregroundStyle(.orange) }
                Text(health.steps.map { "今日步数 \(Int($0))" } ?? "今日步数：暂无可读记录").font(.callout)
                if let rate = health.heartRate, let date = health.heartDate {
                    Text("最近心率 \(Int(rate))次／分").font(.callout)
                    Text(date.formatted(date: .abbreviated, time: .shortened)).font(.caption2)
                    Text("记录值，不是现在测量").font(.caption2).foregroundStyle(.secondary)
                } else { Text("心率：暂无可读记录").font(.caption2) }
                Divider()
                Text("已结束日期的总睡眠").font(.caption)
                if health.days.isEmpty { Text("暂无可读睡眠，请检查记录、同步与读取权限").font(.caption2) }
                ForEach(health.days.reversed()) { day in
                    VStack(alignment: .leading) {
                        Text("\(day.date.formatted(.dateTime.month().day())) · \(day.hours, specifier: "%.1f")小时").font(.caption)
                        Text(day.sources.joined(separator: "、")).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text("按自然日拆分，含午睡；重叠睡眠合并，未记录的日期视为未知。仅显示数据库已有记录，尚未同步的数据可能缺失。").font(.caption2)
                if health.automaticUpdates {
                    Button("关闭自动读取并清除缓存") { Task { await health.stopAutomaticUpdatesAndClearCache() } }
                        .disabled(health.loading)
                }
            }.padding(.horizontal, 6)
        }
    }
}

typealias PigVisualState = MotionVerdict

@MainActor final class PigApplicationDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() { HealthReader.shared.beginAutomaticUpdatesIfEnabled() }
}

struct PigFace: View {
    let state: PigVisualState
    let scarf: Bool
    var body: some View {
        ZStack {
            Ellipse().fill(.pink.opacity(0.65)).frame(width: 28,height: 38).rotationEffect(.degrees(-25)).offset(x: -35,y: -28)
            Ellipse().fill(.pink.opacity(0.65)).frame(width: 28,height: 38).rotationEffect(.degrees(25)).offset(x: 35,y: -28)
            Ellipse().fill(state == .waiting ? Color.gray.opacity(0.5) : Color(red:0.96,green:0.73,blue:0.81)).frame(width: 115,height: 94)
            Ellipse().fill(.pink.opacity(0.4)).frame(width: 45,height: 30).offset(y: 14)
            ForEach([-1,1],id: \.self) { side in
                if state == .still {
                    Capsule().fill(.black.opacity(0.7)).frame(width: 14,height: 3).offset(x: Double(side)*24,y: -12)
                } else {
                    Circle().fill(.black.opacity(0.7)).frame(width: 7,height: 7).offset(x: Double(side)*24,y: -12)
                }
                Ellipse().fill(.pink.opacity(0.85)).frame(width: 6,height: 10).offset(x: Double(side)*9,y: 14)
            }
            if state == .walking { Text("♪").font(.title2).foregroundStyle(.pink).offset(x: 65,y: -15) }
            if state == .uncertain { Text("?").font(.title2).foregroundStyle(.orange).offset(x: 65,y: -15) }
            if scarf { Capsule().fill(.mint).frame(width: 74,height: 9).offset(y: 44) }
        }.frame(height: 115).accessibilityLabel(state == .walking ? "跟你一起走的猪猪" : state == .still ? "休息的猪猪" : state == .uncertain ? "拿不准的猪猪" : "尚未测量的猪猪")
    }
}
