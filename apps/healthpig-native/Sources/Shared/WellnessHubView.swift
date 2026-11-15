import Charts
import SwiftUI

private let lavender = Color(red: 0.75, green: 0.76, blue: 1)

struct WellnessHubView: View {
    @ObservedObject var health: HealthReader
    let companion: PigCard?

    var body: some View {
        PigScreen {
            NavigationLink { VitalDashboard(health: health) } label: {
                WellnessTile("身体指标", symbol: "waveform.path.ecg", tint: PigTheme.rose)
            }.buttonStyle(.plain).accessibilityIdentifier("wellness.vitals")
            NavigationLink { SleepWellnessView(health: health) } label: {
                WellnessTile("睡眠与作息", symbol: "moon.stars.fill", tint: lavender)
            }.buttonStyle(.plain).accessibilityIdentifier("wellness.sleep")
            NavigationLink { MoodCheckInView(companion: companion) } label: {
                WellnessTile("心情", symbol: "face.smiling.inverse", tint: PigTheme.cream)
            }.buttonStyle(.plain).accessibilityIdentifier("wellness.mood")
            NavigationLink { ActivityRingsView(health: health) } label: {
                WellnessTile("活动与站立", symbol: "figure.stand", tint: PigTheme.mint)
            }.buttonStyle(.plain)
            NavigationLink { TrendHomeView(health: health) } label: {
                WellnessTile("步数与睡眠", symbol: "chart.xyaxis.line", tint: lavender)
            }.buttonStyle(.plain)
        }.navigationTitle("健康")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
#endif
    }
}

struct WellnessTile: View {
    let title, symbol: String
    let tint: Color

    init(_ title: String, symbol: String, tint: Color) {
        self.title = title; self.symbol = symbol; self.tint = tint
    }
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.title3.weight(.semibold))
                .foregroundStyle(tint).frame(width: 32, height: 32)
                .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 10))
            Text(title).font(.headline)
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }.padding(10).frame(minHeight: 46)
            .background(PigTheme.panel, in: RoundedRectangle(cornerRadius: 17))
            .accessibilityLabel(title)
    }
}

private struct VitalDashboard: View {
    @ObservedObject var health: HealthReader

    var body: some View {
        PigScreen {
            ForEach(VitalMetric.allCases) { metric in
                let records = health.vitalRecords[metric, default: []]
                NavigationLink {
                    VitalTrendView(metric: metric, records: records, demo: false)
                } label: {
                    row(metric, value: records.first?.value)
                }.buttonStyle(.plain).accessibilityIdentifier("vitals." + metric.rawValue)
            }
            if health.vitalsLoading {
                ProgressView().accessibilityLabel("读取中")
            }
            if health.vitalsError {
                Label("部分记录未能读取", systemImage: "exclamationmark.circle").font(.subheadline)
            }
            if health.vitalsEnabled {
                Button { Task { await health.refreshVitals() } } label: { Label("刷新", systemImage: "arrow.clockwise") }
                    .buttonStyle(.bordered).disabled(health.vitalsLoading)
                Button("停止读取", role: .destructive) { health.stopVitals() }.buttonStyle(.bordered)
            } else {
                Button { Task { await health.authorizeVitals() } } label: { Label("读取健康数据", systemImage: "lock.open") }
                    .buttonStyle(PigPrimaryButton()).disabled(health.vitalsLoading)
            }
            NavigationLink {
                VitalTrendView(metric: .resting, records: demoResting, demo: true)
            } label: {
                Label("示例", systemImage: "play.rectangle").font(.subheadline)
            }.buttonStyle(.bordered).accessibilityIdentifier("vitals.demo")
        }.navigationTitle("身体指标")
#if os(iOS)
            .toolbar(.hidden, for: .tabBar)
#endif
            .task { await health.refreshVitals() }
            .refreshable { await health.refreshVitals() }
    }
    private var demoResting: [VitalRecord] {
        [63.0, 62, 65, 62, 64, 62, 61].enumerated().compactMap { offset, value in
            guard let date = Calendar.current.date(byAdding: .day, value: -offset, to: .now) else { return nil }
            return VitalRecord(id: UUID(), date: date, value: value, source: "示例数据")
        }
    }
    private func row(_ metric: VitalMetric, value: Double?) -> some View {
        HStack(spacing: 10) {
            Label(metric.title, systemImage: metric.symbol)
                .foregroundStyle(metric == .oxygen || metric == .breathing ? lavender : PigTheme.rose)
            Spacer(minLength: 4)
            if let value {
                Text(metric.format(value)).font(.headline.monospacedDigit()) + Text(" " + metric.unitLabel).font(.subheadline)
            } else {
                Image(systemName: "minus").accessibilityLabel("无可读记录")
            }
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }.frame(minHeight: 46).padding(.horizontal, 12)
            .background(PigTheme.panel, in: RoundedRectangle(cornerRadius: 15))
            .accessibilityElement(children: .combine)
    }
}

private struct VitalTrendView: View {
    let metric: VitalMetric
    let records: [VitalRecord]
    let demo: Bool

    var body: some View {
        PigScreen {
            if demo { Label("示例数据", systemImage: "play.rectangle").font(.headline).foregroundStyle(PigTheme.cream) }
            if let latest = records.first {
                PigPanel {
                    Label {
                        Text(metric.format(latest.value)).font(.largeTitle.weight(.semibold)).monospacedDigit() +
                        Text(" " + metric.unitLabel).font(.subheadline)
                    } icon: {
                        Image(systemName: metric.symbol).font(.title2).foregroundStyle(PigTheme.rose)
                    }
                    Label("近7日", systemImage: "calendar").font(.subheadline)
                    Chart(records) { sample in
                        PointMark(x: .value("日期", sample.date, unit: .day),
                                  y: .value(metric.unitLabel, sample.value))
                            .symbolSize(48).foregroundStyle(lavender)
                            .accessibilityLabel(sample.date.formatted(date: .abbreviated, time: .omitted))
                            .accessibilityValue(metric.format(sample.value) + " " + metric.unitLabel)
                    }.chartYScale(domain: .automatic(includesZero: false))
                        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
                        .chartYAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
                        .frame(height: 135)
                }
                ForEach(records) { record in
                    PigPanel {
                        Text(metric.format(record.value) + " " + metric.unitLabel).font(.headline.monospacedDigit())
                        Label(record.date.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                            .font(.subheadline)
                        if !demo { Label(record.source, systemImage: "heart.text.clipboard").font(.subheadline) }
                    }
                }
            } else {
                ContentUnavailableView("暂无可读记录", systemImage: metric.symbol)
            }
        }.navigationTitle(metric.title)
#if os(iOS)
            .toolbar(.hidden, for: .tabBar)
#endif
    }
}
