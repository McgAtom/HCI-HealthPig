import Charts
import SwiftUI

struct SleepWellnessView: View {
    @ObservedObject var health: HealthReader
    var body: some View {
        PigScreen {
#if os(iOS)
            NavigationLink { SleepPlanView(health: health) } label: {
                WellnessTile("今晚作息", symbol: "alarm.fill", tint: PigTheme.cream)
            }.buttonStyle(.plain).accessibilityIdentifier("wellness.sleep-plan")
#endif
            if health.sleepStages.isEmpty {
                PigPanel {
                    Label("暂无睡眠阶段", systemImage: "moon.zzz").font(.headline)
                    NavigationLink("读取睡眠") { HealthRecordView(health: health) }
                        .buttonStyle(.bordered)
                    NavigationLink {
                        PigScreen {
                            Label("示例数据", systemImage: "play.rectangle").font(.headline)
                            SleepStageChart(slices: Self.demo)
                        }.navigationTitle("睡眠阶段")
#if os(iOS)
                            .toolbar(.hidden, for: .tabBar)
#endif
                    } label: { Label("阶段示例", systemImage: "play.rectangle") }
                        .buttonStyle(.bordered).accessibilityIdentifier("wellness.sleep-demo")
                }
            } else {
                SleepStageChart(slices: health.sleepStages)
            }
            NavigationLink { HealthTrendView(health: health, sleep: true) } label: {
                WellnessTile("睡眠时长", symbol: "chart.xyaxis.line", tint: PigTheme.mint)
            }.buttonStyle(.plain)
        }.navigationTitle("睡眠与作息")
#if os(iOS)
            .toolbar(.hidden, for: .tabBar)
#endif
            .task { await health.refreshAutomaticallyIfEnabled() }
    }

    private static let demo: [SleepStageSlice] = {
        let initial = Date(timeIntervalSince1970: 1_794_762_000)
        let stages: [SleepStageSlice.Stage] = [.core, .deep, .core, .rem, .awake, .core, .rem, .core]
        let durations = [40, 65, 50, 42, 12, 84, 62, 28]
        var start = initial
        return zip(stages, durations).map { stage, minutes in
            let end = start.addingTimeInterval(Double(minutes * 60))
            defer { start = end }
            return SleepStageSlice(id: UUID(), stage: stage, start: start, end: end, source: "示例数据")
        }
    }()
}

private struct SleepStageChart: View {
    let slices: [SleepStageSlice]
    var body: some View {
        PigPanel {
            Label("睡眠阶段", systemImage: "moon.stars.fill").font(.headline)
            Chart(slices) { sample in
                BarMark(xStart: .value("开始", sample.start), xEnd: .value("结束", sample.end),
                        y: .value("阶段", sample.stage.title), height: .fixed(10))
                    .foregroundStyle(color(sample.stage))
                    .accessibilityLabel(sample.stage.title)
                    .accessibilityValue(sample.start.formatted(date: .omitted, time: .shortened)
                                        + "–" + sample.end.formatted(date: .omitted, time: .shortened))
            }
            .chartYScale(domain: SleepStageSlice.Stage.allCases.map(\.title).reversed().map { $0 })
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
            .frame(height: 155)
            if let first = slices.first, first.source != "示例数据" {
                Label(first.source, systemImage: "heart.text.clipboard").font(.subheadline)
            }
        }
    }
    private func color(_ stage: SleepStageSlice.Stage) -> Color {
        switch stage {
        case .awake: return PigTheme.rose
        case .rem: return PigTheme.mint
        case .core: return Color(red: 0.68, green: 0.77, blue: 1)
        case .deep: return Color(red: 0.67, green: 0.55, blue: 1)
        }
    }
}

enum PigMood: String, CaseIterable, Identifiable, Codable {
    case bright, calm, tired, down
    var id: Self { self }
    var title: String {
        switch self {
        case .bright: return "开心"
        case .calm: return "平静"
        case .tired: return "有点累"
        case .down: return "低落"
        }
    }
    var symbol: String {
        switch self {
        case .bright: return "sun.max.fill"
        case .calm: return "leaf.fill"
        case .tired: return "moon.fill"
        case .down: return "cloud.fill"
        }
    }
    var tint: Color {
        switch self {
        case .bright: return PigTheme.cream
        case .calm: return PigTheme.mint
        case .tired: return Color(red: 0.77, green: 0.77, blue: 1)
        case .down: return Color(red: 0.69, green: 0.83, blue: 1)
        }
    }
    var response: String {
        switch self {
        case .bright: return "一起记住这一刻"
        case .calm: return "陪你安静待一会"
        case .tired: return "可以慢一点"
        case .down: return "猪猪陪着你"
        }
    }
}

private struct MoodEntry: Identifiable, Codable {
    var id: Date { day }
    let day: Date
    let mood: PigMood
}

@MainActor private final class LocalMoodLog: ObservableObject {
    @Published private(set) var entries: [MoodEntry] = []
    @Published private(set) var failed = false
    private let url: URL
    private var readable = true
    init() {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--wellness-ui-test") {
            url = FileManager.default.temporaryDirectory.appendingPathComponent("wellness-moods-test.json")
        } else {
            url = Self.realURL()
        }
#else
        url = Self.realURL()
#endif
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do { entries = try JSONDecoder().decode([MoodEntry].self, from: Data(contentsOf: url)) }
        catch { readable = false; failed = true }
    }
    private static func realURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("wellness-moods.json")
    }
    func set(_ mood: PigMood?) {
        let today = Calendar.current.startOfDay(for: .now)
        var next = entries.filter { !Calendar.current.isDate($0.day, inSameDayAs: today) }
        if let mood { next.append(MoodEntry(day: today, mood: mood)) }
        save(next)
    }
    func remove(_ day: Date) { save(entries.filter { $0.day != day }) }
    private func save(_ next: [MoodEntry]) {
        guard readable else { return }
        do {
            let fm = FileManager.default
            let parent = url.deletingLastPathComponent()
            try fm.createDirectory(at: parent, withIntermediateDirectories: true)
            var excludedURL = url
            let values = try JSONEncoder().encode(next)
            try values.write(to: url, options: [.atomic, .completeFileProtection])
            var resources = URLResourceValues()
            resources.isExcludedFromBackup = true
            try? excludedURL.setResourceValues(resources)
            entries = next; failed = false
        } catch { failed = true }
    }
}

struct MoodCheckInView: View {
    let companion: PigCard?
    @StateObject private var log = LocalMoodLog()
    @State private var pendingRemoval: MoodEntry?
    private var today: MoodEntry? { log.entries.first { Calendar.current.isDateInToday($0.day) } }

    var body: some View {
        PigScreen {
            if let companion { PigArtwork(card: companion, size: 92).accessibilityHidden(true) }
            if let today { Label(today.mood.response, systemImage: "heart").font(.headline) }
#if os(iOS)
            NavigationLink { PigDivinationView(companion: companion) } label: {
                WellnessTile("猪猪占卜", symbol: "sparkles", tint: Color(red: 0.81, green: 0.73, blue: 1))
            }.buttonStyle(.plain).accessibilityIdentifier("divination.entry")
#endif
            ForEach(PigMood.allCases) { mood in
                Button { log.set(mood) } label: {
                    HStack {
                        Label(mood.title, systemImage: mood.symbol).foregroundStyle(mood.tint)
                        Spacer()
                        if today?.mood == mood { Image(systemName: "checkmark.circle.fill") }
                    }.frame(minHeight: 44).padding(.horizontal, 11)
                        .background(PigTheme.panel, in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain).accessibilityAddTraits(today?.mood == mood ? .isSelected : [])
                    .accessibilityIdentifier("wellness.mood." + mood.rawValue)
            }
            if !log.entries.isEmpty {
                Label("回顾", systemImage: "calendar").font(.headline)
                ForEach(log.entries.sorted { $0.day > $1.day }.prefix(7)) { entry in
                    HStack {
                        Label(entry.day.formatted(.dateTime.month().day()), systemImage: entry.mood.symbol)
                            .foregroundStyle(entry.mood.tint).accessibilityValue(entry.mood.title)
                        Spacer()
                        Button(role: .destructive) { pendingRemoval = entry } label: {
                            Image(systemName: "trash").frame(minWidth: 44, minHeight: 44)
                        }.buttonStyle(.plain).accessibilityLabel("删除心情记录")
                            .accessibilityIdentifier("wellness.delete-mood")
                    }
                }
            }
            if log.failed { Label("本机记录未能读取或保存", systemImage: "exclamationmark.circle").font(.subheadline) }
        }.navigationTitle("心情")
#if os(iOS)
            .toolbar(.hidden, for: .tabBar)
#endif
            .alert(item: $pendingRemoval) { entry in
                Alert(title: Text("删除这条心情？"),
                      primaryButton: .destructive(Text("删除")) { log.remove(entry.day) },
                      secondaryButton: .cancel(Text("取消")))
            }
    }
}

#if os(watchOS)
struct WatchQuickMoodView: View {
    let companion: PigCard?
    @Environment(\.dismiss) private var dismiss
    @StateObject private var log = LocalMoodLog()
    @State private var selection: PigMood?

    var body: some View {
        WatchFrame {
            if let selection, !log.failed {
                VStack(spacing: 8) {
                    if let companion { PigArtwork(card: companion, size: 49).accessibilityHidden(true) }
                    Text(selection.response).font(.headline)
                    Button("完成") { dismiss() }.buttonStyle(PigPrimaryButton())
                    Button("修改") { self.selection = nil }.buttonStyle(.bordered)
                }
            } else {
                VStack(spacing: 7) {
                    ForEach(0..<2) { row in
                        HStack(spacing: 7) {
                            ForEach(Array(PigMood.allCases[(row * 2)..<(row * 2 + 2)])) { mood in
                                Button {
                                    log.set(mood)
                                    if !log.failed { selection = mood }
                                } label: {
                                    WatchCompactButton(title: mood.title, symbol: mood.symbol)
                                }.buttonStyle(.plain).accessibilityIdentifier("watch.mood." + mood.rawValue)
                            }
                        }
                    }
                    if log.failed { Text("未能保存").font(.subheadline) }
                }
            }
        }.navigationTitle("此刻心情")
    }
}
#endif
