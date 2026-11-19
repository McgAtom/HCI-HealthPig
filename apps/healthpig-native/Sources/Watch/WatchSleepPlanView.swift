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
                }
            }
        }.navigationTitle("今晚作息")
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

    private func controls(_ plan: SleepSchedule.Proposal) -> some View {
        let scheduled = sleep.alarm?.date.flatMap { $0 > .now ? $0 : nil }
        return VStack(spacing: 5) {
            if alarm.pending {
                ProgressView().accessibilityLabel("正在设置")
            } else if scheduled != plan.wake {
                Button {
                    alarm.apply(SleepAlarmRequest(date: plan.wake))
                } label: {
                    Label(scheduled == nil ? "设闹钟" : "改闹钟", systemImage: "alarm.fill")
                }.buttonStyle(PigPrimaryButton()).accessibilityIdentifier("sleep.set-alarm")
            }
            if let scheduled {
                Button { alarm.stop() } label: {
                    Label("已设 \(scheduled.formatted(date: .omitted, time: .shortened))",
                          systemImage: sleep.alarm?.reminder == true ? "bell.fill" : "alarm.fill")
                        .foregroundStyle(PigTheme.mint)
                }.buttonStyle(.bordered).accessibilityHint("取消闹钟").accessibilityIdentifier("sleep.alarm-confirmed")
                .disabled(alarm.pending)
            }
        }
    }
}
