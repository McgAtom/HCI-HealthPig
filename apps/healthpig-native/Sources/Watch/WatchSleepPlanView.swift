import SwiftUI

struct WatchSleepPlanView: View {
    @ObservedObject var health: HealthReader
    @ObservedObject var sleep: SleepCompanion
    @StateObject private var alarm = WristAlarm.shared
    @Environment(\.calendar) private var calendar
    @State private var settings = false

    var body: some View {
        WatchFrame {
            TimelineView(.everyMinute) { context in
                VStack(spacing: 5) {
                    if let plan = sleep.plan(nights: health.recentSleepNights, now: context.date, calendar: calendar) {
                        SleepPlanTimes(plan: plan, now: context.date)
                        controls(plan)
                    } else { Label("暂无作息", systemImage: "moon.zzz") }
                    if sleep.alarm?.failed == true {
                        Label("设置失败", systemImage: "exclamationmark.circle").font(.subheadline)
                            .accessibilityIdentifier("sleep.alarm-failed")
                    }
                }.padding(.top, 20)
            }
        }.navigationTitle("睡眠计划")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { settings = true } label: { Image(systemName: "slider.horizontal.3").foregroundStyle(PigTheme.background) }
                        .accessibilityLabel("调整作息").accessibilityIdentifier("sleep.settings")
                }
            }
            .sheet(isPresented: $settings) {
                ScrollView {
                    VStack(spacing: 8) {
                        SleepPlanSettings(sleep: sleep)
                        if !health.hasRequestedWatchSleep {
                            Button {
                                Task { await health.refreshWatchSleep(requestAccess: true) }
                            } label: { Label("连接睡眠记录", systemImage: "heart.text.square") }
                            .disabled(health.watchSleepLoading)
                        }
                        if !alarm.notificationAllowed {
                            Button("允许腕上提醒") { Task { await alarm.authorizeReminders() } }
                                .buttonStyle(.bordered)
                        }
                        Button("完成") { settings = false }.buttonStyle(PigPrimaryButton())
                    }.padding(.horizontal, 12)
                }.background(PigTheme.background)
            }
            .task { await health.refreshWatchSleep(); await alarm.refreshNotificationAccess() }
    }

    @ViewBuilder private func controls(_ plan: SleepSchedule.Proposal) -> some View {
        let scheduled = sleep.alarm?.date.flatMap { $0 > .now ? $0 : nil }
        if alarm.pending {
            ProgressView().accessibilityLabel("正在设置")
        } else if let scheduled {
            if scheduled == plan.wake {
                cancelAlarm(scheduled, compact: false)
            } else {
                HStack(spacing: 6) {
                    setAlarm(plan.wake, replacing: true)
                    cancelAlarm(scheduled, compact: true)
                }
            }
        } else {
            setAlarm(plan.wake, replacing: false)
        }
    }

    private func setAlarm(_ date: Date, replacing: Bool) -> some View {
        let clock = SleepPlanSettings.clock(date)
        return Button { alarm.apply(SleepAlarmRequest(date: date)) } label: {
            if replacing { Text("改 " + clock).monospacedDigit().lineLimit(1).minimumScaleFactor(0.84) }
            else { Label("设 " + clock + " 闹钟", systemImage: "alarm.fill") }
        }.buttonStyle(PigPrimaryButton())
            .accessibilityLabel((replacing ? "改为 " : "设 ") + clock + " 闹钟")
            .accessibilityIdentifier("sleep.set-alarm")
    }

    private func cancelAlarm(_ date: Date, compact: Bool) -> some View {
        let clock = SleepPlanSettings.clock(date)
        return Button { alarm.stop() } label: {
            if compact {
                VStack(spacing: 1) {
                    Label("已设", systemImage: "xmark.circle").font(.caption2)
                    Text(clock).font(.caption.weight(.semibold).monospacedDigit())
                }.frame(width: 60, height: 44)
                    .background(PigTheme.panel, in: Capsule())
            } else {
                Label("已设 " + clock, systemImage: sleep.alarm?.reminder == true ? "bell.fill" : "alarm.fill")
                    .frame(minHeight: 44)
            }
        }.buttonStyle(.plain).foregroundStyle(PigTheme.mint)
            .accessibilityLabel("已设 " + clock).accessibilityHint("取消闹钟")
            .accessibilityIdentifier("sleep.alarm-confirmed")
    }
}
