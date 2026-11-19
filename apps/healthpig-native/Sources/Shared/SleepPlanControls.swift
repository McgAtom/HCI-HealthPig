import SwiftUI

struct SleepPlanTimes: View {
    let plan: SleepSchedule.Proposal
    let now: Date
    @Environment(\.calendar) private var calendar
    @Environment(\.dynamicTypeSize) private var size
    @State private var showBasis = false

    var body: some View {
        VStack(spacing: 4) {
            let layout = size.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 4))
            let sameDayWake = calendar.isDate(plan.wake, inSameDayAs: now)
            let bedtimeDay = sameDayWake ? "今天凌晨" : calendar.isDate(plan.bedtime, inSameDayAs: now) ? "今晚" : "明天凌晨"
            layout {
                time("上床", at: plan.bedtime, day: bedtimeDay, icon: "moon.stars.fill", id: "sleep.proposal")
                time("起床", at: plan.wake, day: sameDayWake ? "今天" : "明天", icon: "sun.max.fill", id: "sleep.wake-proposal")
            }
            Button { showBasis = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: plan.fallsShort ? "clock.badge.exclamationmark" : "clock")
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("预留 " + SleepPlanSettings.duration(plan.reservedMinutes)).font(.subheadline.weight(.semibold))
                            .accessibilityIdentifier("sleep.reserved")
                        Text(summary).font(.caption).foregroundStyle(PigTheme.cream)
                            .accessibilityIdentifier("sleep.basis-summary")
                    }
                    Spacer(minLength: 1)
                    Image(systemName: "info.circle").accessibilityHidden(true)
                }.frame(minHeight: 44).padding(.horizontal, 8)
                    .background(PigTheme.panel, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("查看推荐依据")
            .accessibilityIdentifier("sleep.basis")
        }.sheet(isPresented: $showBasis) {
            NavigationStack { SleepPlanBasisView(plan: plan) }
        }
    }

    private var summary: String {
        if plan.fallsShort, let basis = plan.basis {
            let shortage = SleepPlanSettings.duration(basis.targetMinutes - plan.reservedMinutes)
            return PigText.compact("少 " + shortage.replacingOccurrences(of: " ", with: ""),
                                   full: "比目标少 " + shortage)
        }
        if let wake = plan.basis?.goalWake {
            let clock = SleepPlanSettings.clock(wake)
            return PigText.compact("目标 " + clock, full: "固定起床目标 " + clock)
        }
        return "按睡眠目标"
    }

    private func time(_ action: String, at date: Date, day: String, icon: String, id: String) -> some View {
        VStack(spacing: 1) {
#if os(watchOS)
            let shortDay = day.contains("凌晨") ? "凌晨" : day == "明天" ? "明早" : day == "今天" ? "今早" : day
            Label(shortDay + action, systemImage: icon).font(.caption.weight(.semibold))
#else
            Label(action, systemImage: icon).font(.subheadline.weight(.medium))
#endif
            Text(SleepPlanSettings.clock(date)).font(.title2.bold().monospacedDigit())
                .foregroundStyle(PigTheme.cream)
                .accessibilityLabel("建议" + action)
                .accessibilityValue(day + " " + SleepPlanSettings.clock(date))
                .accessibilityIdentifier(id)
#if os(iOS)
            Text(day).font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
#endif
        }.frame(maxWidth: .infinity)
    }
}

private struct SleepPlanBasisView: View {
    let plan: SleepSchedule.Proposal
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PigScreen {
            if let basis = plan.basis {
                if let goal = basis.goalWake {
                    let goalBed = goal.addingTimeInterval(-Double(basis.targetMinutes * 60))
                    metric("目标作息", SleepPlanSettings.clock(goalBed) + "–" + SleepPlanSettings.clock(goal), symbol: "calendar")
                    if goal > basis.latestWake {
                        Label("今晚须更早起床", systemImage: "sun.max").font(.subheadline)
                    }
                }
                if let bed = basis.usualBedtime, let wake = basis.usualWake, let asleep = basis.typicalAsleepMinutes {
                    metric("近 \(plan.nightsUsed) 晚常见作息", SleepPlanSettings.clock(minutes: bed) + "–" + SleepPlanSettings.clock(minutes: wake),
                           symbol: "chart.line.uptrend.xyaxis")
                    metric("通常实睡", SleepPlanSettings.duration(asleep), symbol: "bed.double")
                } else {
                    Text(basis.observedNights == 0 ? "暂无睡眠记录" : "可用记录 \(basis.observedNights) 晚").font(.subheadline)
                }
                metric("最晚起床", SleepPlanSettings.clock(basis.latestWake), symbol: "sun.max")
                metric("睡眠目标", SleepPlanSettings.duration(basis.targetMinutes), symbol: "target")
                let difference = plan.reservedMinutes - basis.targetMinutes
                if difference != 0 {
                    metric(difference > 0 ? "多留缓冲" : "距目标还差", SleepPlanSettings.duration(abs(difference)),
                           symbol: difference > 0 ? "clock.badge.plus" : "clock.badge.exclamationmark")
                }
            }
        }.navigationTitle("推荐依据")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
    }

    private func metric(_ title: String, _ value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: symbol).font(.subheadline)
            Text(value).font(.headline.monospacedDigit()).foregroundStyle(PigTheme.cream)
        }.accessibilityElement(children: .combine)
    }
}

struct SleepPlanSettings: View {
    @ObservedObject var sleep: SleepCompanion
    @Environment(\.calendar) private var calendar

    var body: some View {
        if let window = SleepSchedule.wakeWindow(now: .now, calendar: calendar) {
            let routine = Binding {
                SleepSchedule.clockDate(sleep.preferences.routineWake, on: window.lowerBound, calendar: calendar)
                    ?? window.lowerBound
            } set: { sleep.set(routineWake: SleepSchedule.clockMinutes($0, calendar: calendar)) }
            DatePicker("目标起床", selection: routine, in: window, displayedComponents: .hourAndMinute)
                .accessibilityIdentifier("sleep.routine")
            let selection = Binding {
                sleep.preferences.wakeLimit(now: .now, calendar: calendar) ?? window.upperBound
            } set: { sleep.set(latest: SleepSchedule.clockMinutes($0, calendar: calendar)) }
            DatePicker("最晚起床", selection: selection, in: window, displayedComponents: .hourAndMinute)
                .accessibilityIdentifier("sleep.latest")
#if os(iOS)
            LabeledContent("睡眠目标") { targetPicker.labelsHidden() }
#else
            targetPicker
#endif
        }
    }

    private var targetPicker: some View {
        Picker("睡眠目标", selection: Binding(get: { sleep.preferences.target }, set: { sleep.set(target: $0) })) {
            ForEach(Array(stride(from: 420, through: 540, by: 15)), id: \.self) { minutes in
                Text(Self.duration(minutes)).tag(minutes)
            }
        }.accessibilityIdentifier("sleep.target")
    }

    static func duration(_ minutes: Int) -> String {
        let hours = minutes / 60, remainder = minutes % 60
        if hours == 0 { return "\(remainder) 分钟" }
        return "\(hours) 小时" + (remainder == 0 ? "" : " \(remainder) 分")
    }

    static func clock(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(Locale(identifier: "zh_CN")))
    }

    static func clock(minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }
}
