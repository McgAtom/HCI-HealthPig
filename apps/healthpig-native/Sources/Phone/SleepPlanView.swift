import SwiftUI

struct SleepPlanView: View {
    @ObservedObject var health: HealthReader
    @EnvironmentObject private var bridge: CompanionBridge

    var body: some View {
        PhoneSleepPlan(health: health, sleep: bridge.sleep, hasWatch: bridge.hasWatch)
    }
}

private struct PhoneSleepPlan: View {
    @ObservedObject var health: HealthReader
    @ObservedObject var sleep: SleepCompanion
    let hasWatch: Bool
    @Environment(\.calendar) private var calendar

    var body: some View {
        PigScreen {
            TimelineView(.everyMinute) { context in
                let local = sleep.preferences.recommend(nights: health.recentSleepNights, now: context.date, calendar: calendar)
                if let plan = sleep.plan(nights: health.recentSleepNights, now: context.date, calendar: calendar) {
                    VStack(alignment: .leading, spacing: 14) {
                        PigPanel { SleepPlanTimes(plan: plan, now: context.date) }
                        alarm(for: plan)
                        PigPanel { SleepPlanSettings(sleep: sleep) }
                    }.onChange(of: local, initial: true) { _, plan in
                        if let plan { sleep.project(plan) }
                    }
                } else { Label("暂无作息", systemImage: "moon.zzz").font(.headline) }
            }
        }.navigationTitle("今晚作息").navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
    }

    @ViewBuilder private func alarm(for plan: SleepSchedule.Proposal) -> some View {
        if hasWatch {
            if sleep.pending != nil {
                Label("已提交", systemImage: "applewatch").font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityIdentifier("sleep.alarm-pending")
            } else {
                let scheduled = sleep.alarm?.date.flatMap { $0 > .now ? $0 : nil }
                if let scheduled {
                    Label("\(sleep.alarm?.reminder == true ? "腕上提醒" : "手表闹钟") \(scheduled.formatted(date: .omitted, time: .shortened))",
                          systemImage: sleep.alarm?.reminder == true ? "bell.fill" : "alarm.fill")
                        .foregroundStyle(PigTheme.mint).font(.headline).accessibilityIdentifier("sleep.alarm-confirmed")
                    Button("取消闹钟", role: .destructive) { sleep.request(nil) }.buttonStyle(.bordered)
                }
                if scheduled != plan.wake {
                    Button { sleep.request(plan.wake) } label: {
                        Label("设到手表", systemImage: "applewatch")
                    }.buttonStyle(PigPrimaryButton()).accessibilityIdentifier("sleep.set-watch-alarm")
                }
                if sleep.alarm?.failed == true {
                    Label(sleep.alarm?.permissionRequired == true ? "腕上提醒未授权" : "手表设置失败",
                          systemImage: "exclamationmark.circle").font(.headline).accessibilityIdentifier("sleep.alarm-failed")
                }
            }
        } else {
            Label("连接 Apple Watch", systemImage: "applewatch").font(.headline)
                .accessibilityIdentifier("sleep.watch-required")
        }
    }
}
