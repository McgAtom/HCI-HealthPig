import SwiftUI

struct SleepPlanTimes: View {
    let plan: SleepSchedule.Proposal
    let now: Date
    @Environment(\.calendar) private var calendar
    @Environment(\.dynamicTypeSize) private var size

    var body: some View {
        let layout = size.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 4))
        layout {
            time(calendar.isDate(plan.bedtime, inSameDayAs: now) ? "今晚" : "凌晨",
                 at: plan.bedtime, icon: "moon.stars.fill", id: "sleep.proposal")
            time("明早", at: plan.wake, icon: "sun.max.fill", id: "sleep.wake-proposal")
        }
        if plan.fallsShort {
            Label("预留 \(SleepPlanSettings.duration(plan.reservedMinutes))", systemImage: "clock.badge.exclamationmark")
                .font(.subheadline).foregroundStyle(PigTheme.cream)
        }
    }

    private func time(_ label: String, at date: Date, icon: String, id: String) -> some View {
        VStack(spacing: 3) {
            Label(label, systemImage: icon).font(.subheadline)
            Text(date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(Locale(identifier: "zh_CN"))))
                .font(.title2.bold().monospacedDigit())
                .foregroundStyle(PigTheme.cream)
                .accessibilityLabel(label == "明早" ? "建议起床" : "建议上床")
                .accessibilityValue(date.formatted(date: .omitted, time: .shortened))
                .accessibilityIdentifier(id)
        }.frame(maxWidth: .infinity).padding(.vertical, 5)
    }
}

struct SleepPlanSettings: View {
    @ObservedObject var sleep: SleepCompanion
    @Environment(\.calendar) private var calendar

    var body: some View {
        if let window = SleepSchedule.wakeWindow(now: .now, calendar: calendar) {
            let selection = Binding {
                sleep.preferences.wakeLimit(now: .now, calendar: calendar) ?? window.upperBound
            } set: { sleep.set(latest: SleepSchedule.clockMinutes($0, calendar: calendar)) }
            DatePicker("最晚起床", selection: selection, in: window, displayedComponents: .hourAndMinute)
                .accessibilityIdentifier("sleep.latest")
            Picker("睡眠目标", selection: Binding(get: { sleep.preferences.target }, set: { sleep.set(target: $0) })) {
                ForEach(Array(stride(from: 420, through: 540, by: 15)), id: \.self) { minutes in
                    Text(Self.duration(minutes)).tag(minutes)
                }
            }.accessibilityIdentifier("sleep.target")
        }
    }

    static func duration(_ minutes: Int) -> String {
        "\(minutes / 60) 小时" + (minutes % 60 == 0 ? "" : " \(minutes % 60) 分")
    }
}
