import AlarmKit
import SwiftUI
import UIKit

private let sleepDefaults: UserDefaults = {
#if DEBUG
    if ProcessInfo.processInfo.arguments.contains("--wellness-ui-test"),
       let isolated = UserDefaults(suiteName: "healthpig.wellness-ui-test") { return isolated }
#endif
    return .standard
}()

struct SleepPlanView: View {
    @ObservedObject var health: HealthReader
    @AppStorage("wellnessWakeMinutes", store: sleepDefaults) private var savedLatest = -1
    @AppStorage("wellnessSleepTarget", store: sleepDefaults) private var savedTarget = 480
    @Environment(\.calendar) private var calendar

    var body: some View {
        PigScreen {
            TimelineView(.everyMinute) { context in
                if let tomorrow = SleepSchedule.wakeWindow(now: context.date, calendar: calendar),
                   let latest = SleepSchedule.clockDate(wakeLimit, on: tomorrow.lowerBound, calendar: calendar),
                   let plan = SleepSchedule.recommend(nights: health.recentSleepNights, target: target.wrappedValue,
                                                      latestWake: latest, now: context.date, calendar: calendar) {
                    VStack(alignment: .leading, spacing: 16) {
                        recommendation(plan, now: context.date)
                        if #available(iOS 26.0, *) { SleepAlarmControls(wake: plan.wake) }
                        else { Label("闹钟需要 iOS 26", systemImage: "alarm").font(.headline) }
                        PigPanel {
                            DatePicker(selection: latestSelection(fallback: latest, day: tomorrow.lowerBound),
                                       in: tomorrow, displayedComponents: .hourAndMinute) {
                                Label("最晚起床", systemImage: "sun.max")
                            }.accessibilityIdentifier("sleep.latest")
                            Divider()
                            LabeledContent {
                                Picker("睡眠目标", selection: target) {
                                    ForEach(Array(stride(from: 420, through: 540, by: 15)), id: \.self) { minutes in
                                        Text(Self.duration(minutes)).tag(minutes)
                                    }
                                }.pickerStyle(.menu).labelsHidden().accessibilityIdentifier("sleep.target")
                            } label: { Label("睡眠目标", systemImage: "target") }
                        }
                    }
                } else {
                    Label("今晚暂无作息方案", systemImage: "moon.zzz").font(.headline)
                }
            }
        }.navigationTitle("今晚作息").navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
    }

    private var wakeLimit: Int { (240...720).contains(savedLatest) ? savedLatest : 540 }

    private var target: Binding<Int> {
        Binding {
            SleepSchedule.targetRange.contains(savedTarget) && savedTarget.isMultiple(of: 15) ? savedTarget : 480
        } set: { savedTarget = $0 }
    }

    private func latestSelection(fallback: Date, day: Date) -> Binding<Date> {
        Binding {
            SleepSchedule.clockDate(wakeLimit, on: day, calendar: calendar) ?? fallback
        } set: { savedLatest = SleepSchedule.clockMinutes($0, calendar: calendar) }
    }

    private func recommendation(_ plan: SleepSchedule.Proposal, now: Date) -> some View {
        PigPanel {
            timeRow(calendar.isDate(plan.bedtime, inSameDayAs: now) ? "今晚建议上床" : "明天建议上床",
                    date: plan.bedtime, symbol: "moon.stars.fill", id: "sleep.proposal")
            Divider()
            timeRow("明早建议起床", date: plan.wake, symbol: "sun.max.fill", id: "sleep.wake-proposal")
            Label("预留 \(Self.duration(plan.reservedMinutes))", systemImage: "clock").font(.headline)
            if plan.fallsShort {
                Label("今晚时间不足", systemImage: "exclamationmark.circle").foregroundStyle(PigTheme.cream)
            } else {
                Label(plan.nightsUsed > 0 ? "参考近 \(plan.nightsUsed) 晚" : "按你的目标", systemImage: "chart.line.uptrend.xyaxis")
                    .foregroundStyle(.secondary).accessibilityIdentifier("sleep.basis")
            }
        }
    }

    private func timeRow(_ label: String, date: Date, symbol: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(label, systemImage: symbol).font(.headline)
            Text(date.formatted(date: .omitted, time: .shortened)).font(.largeTitle.bold()).monospacedDigit()
                .foregroundStyle(PigTheme.cream).accessibilityIdentifier(id)
        }
    }

    private static func duration(_ minutes: Int) -> String {
        "\(minutes / 60) 小时" + (minutes % 60 == 0 ? "" : " \(minutes % 60) 分")
    }
}

@available(iOS 26.0, *)
private struct WakeAlarmMetadata: AlarmMetadata {}

@available(iOS 26.0, *)
@MainActor private final class WakeAlarmStore: ObservableObject {
    static let shared = WakeAlarmStore()
    @Published private(set) var dates: [Date] = []
    @Published private(set) var busy = false
    @Published private(set) var denied = false
    @Published private(set) var message = ""
    private let manager = AlarmManager.shared

    func refresh() {
        denied = manager.authorizationState == .denied
        if manager.authorizationState != .authorized { dates = []; return }
        do { dates = try upcoming().map(\.date) }
        catch { message = "暂时无法确认闹钟"; dates = [] }
    }

    func set(_ date: Date) async {
        guard !busy, date > .now else { return }
        busy = true; message = ""
        defer { busy = false; refresh() }
        do {
            let initial = manager.authorizationState
            let permission = initial == .notDetermined ? try await manager.requestAuthorization() : initial
            guard permission == .authorized else { return }
            guard date > .now else { message = "时间已过，请重新选择"; return }
            let old = try upcoming()
            if old.count == 1 && old.first?.date == date { return }
            let id = UUID()
            let alert: AlarmPresentation.Alert
            if #available(iOS 26.1, *) { alert = .init(title: "走走猪猪 · 起床") }
            else {
                alert = .init(title: "走走猪猪 · 起床",
                              stopButton: AlarmButton(text: "停止", textColor: .white, systemImageName: "stop.circle"))
            }
            let attributes = AlarmAttributes<WakeAlarmMetadata>(presentation: AlarmPresentation(alert: alert),
                                                               tintColor: PigTheme.rose)
            _ = try await manager.schedule(id: id, configuration: .alarm(schedule: .fixed(date), attributes: attributes))
            do {
                for alarm in old { try manager.cancel(id: alarm.alarm.id) }
            } catch {
                try? manager.cancel(id: id)
                message = "闹钟更新未完成，请核对下方时间"
            }
        } catch { message = "闹钟设置失败，请重试" }
    }

    func cancel() {
        guard !busy else { return }
        message = ""
        defer { refresh() }
        do { for alarm in try upcoming() { try manager.cancel(id: alarm.alarm.id) } }
        catch { message = "闹钟未完全取消" }
    }

    private func upcoming() throws -> [(alarm: Alarm, date: Date)] {
        try manager.alarms.compactMap { alarm in
            guard case let .fixed(date)? = alarm.schedule, date > .now else { return nil }
            return (alarm, date)
        }.sorted { $0.date < $1.date }
    }
}

@available(iOS 26.0, *)
private struct SleepAlarmControls: View {
    let wake: Date
    @StateObject private var alarm = WakeAlarmStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    var body: some View {
        let alreadySet = alarm.dates.count == 1 && alarm.dates.first == wake
        VStack(alignment: .leading, spacing: 10) {
            if alarm.denied {
                Button {
                    if let settings = URL(string: UIApplication.openSettingsURLString) { openURL(settings) }
                } label: { Label("开启闹钟权限", systemImage: "gear") }.buttonStyle(PigPrimaryButton())
                    .accessibilityIdentifier("sleep.alarm-permission")
            } else if !alreadySet {
                Button { Task { await alarm.set(wake) } } label: {
                    Label(alarm.dates.isEmpty ? "设闹钟" : "改闹钟", systemImage: "alarm.fill")
                }.buttonStyle(PigPrimaryButton()).disabled(alarm.busy).accessibilityIdentifier("sleep.set-alarm")
            }
            ForEach(alarm.dates, id: \.self) { date in
                Label("已设 \(date.formatted(date: .abbreviated, time: .shortened))", systemImage: "alarm.fill")
                    .font(.headline).foregroundStyle(PigTheme.mint).accessibilityIdentifier("sleep.alarm-confirmed")
            }
            if !alarm.dates.isEmpty {
                Button("取消闹钟", role: .destructive) { alarm.cancel() }
                    .buttonStyle(.bordered).disabled(alarm.busy).accessibilityIdentifier("sleep.cancel-alarm")
            }
            if alarm.busy { ProgressView().accessibilityLabel("正在设置闹钟") }
            if !alarm.message.isEmpty { Label(alarm.message, systemImage: "exclamationmark.circle") }
        }.task(id: scenePhase) { if scenePhase == .active { alarm.refresh() } }
    }
}
