import SwiftUI

@MainActor private final class WatchMoodStore: ObservableObject {
    @Published private(set) var journal: DivinationJournal?
    @Published private(set) var saving = false
    @Published private(set) var failed = false
    private let matcher = DivinationMatcher()
    private let url: URL

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var filename = "watch-mood-cards.json"
#if DEBUG && targetEnvironment(simulator)
        if let suite = ProcessInfo.processInfo.environment["HEALTHPIG_DIVINATION_TEST_SUITE"],
           let id = UUID(uuidString: suite) {
            filename = "watch-mood-cards-\(id).json"
        }
#endif
        url = directory.appendingPathComponent(filename)
        load()
    }

    func load() {
        if FileManager.default.fileExists(atPath: url.path) {
            journal = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(DivinationJournal.self, from: $0) }
        } else { journal = DivinationJournal() }
    }

    func record(_ input: String, companion: PigCard?) async {
        let mood = DivinationDraw.clean(input)
        let day = DailyPig.dayKey(.now)
        guard DivinationDraw.canSubmit(mood), !saving, var next = journal, next.days[day] == nil else { return }
        saving = true; failed = false
        defer { saving = false }

        let matches = await matcher.matches(mood)
        let pool = matches.isEmpty ? DivinationCard.deck.map { DivinationCandidate(card: $0, similarity: 0) } : matches
        let artwork = DivinationArtwork(seed: UInt32.random(in: .min ... .max), pigID: companion?.id)
        guard let card = DivinationDraw.pick(from: pool, recentIDs: next.recentCards(before: day)),
              next.record(DivinationRecord(cardID: card.id, wordMatched: !matches.isEmpty, mood: mood,
                                           artwork: artwork), on: day)
        else { failed = true; return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(next).write(to: url, options: [.atomic, .completeFileProtection])
            var file = url
            var resources = URLResourceValues()
            resources.isExcludedFromBackup = true
            try? file.setResourceValues(resources)
            journal = next
        } catch { failed = true }
    }
}

struct WatchMoodPage<DailyEntry: View>: View {
    let companion: PigCard?
    let catalog: PigCatalog?
    @ViewBuilder let dailyEntry: DailyEntry
    @StateObject private var store = WatchMoodStore()
    @State private var input = ""
    @State private var retryMood = ""

    var body: some View {
        WatchFrame {
            TimelineView(.everyMinute) { context in
                let day = DailyPig.dayKey(context.date)
                let today = store.journal?.days[day]
                VStack(spacing: 5) {
                    if let record = today,
                       let card = DivinationCard.deck.first(where: { $0.id == record.cardID }) {
                        let art = record.appearance(on: day)
                        let pig = art.pigID.flatMap { catalog?.card($0) } ?? catalog?.card("pig-001")
                        PigOracleFace(card: card, mood: record.mood, art: art, pig: pig)
                        dailyEntry
                    } else if store.journal != nil {
                        VStack(spacing: 5) {
                            if store.saving { ProgressView().accessibilityLabel("正在记录心情") }
                            else { Text("心情").font(.headline).accessibilityAddTraits(.isHeader) }
                            HStack(spacing: 4) {
                                ForEach([PigMood.bright, .down, .tired]) { mood in
                                    Button { save(mood.title) } label: {
                                        WatchCompactButton(title: mood.title, symbol: mood.symbol)
                                            .foregroundStyle(mood.tint)
                                    }.buttonStyle(.plain).accessibilityIdentifier("watch.mood." + mood.rawValue)
                                }
                            }
                            HStack(spacing: 5) {
                                TextField("自填", text: $input, prompt: Text("自填").foregroundStyle(PigTheme.rose))
                                    .frame(minHeight: 44)
                                    .accessibilityLabel("自填心情").accessibilityIdentifier("watch.mood.custom")
                                    .onChange(of: input) { _, value in
                                        let cleaned = DivinationDraw.clean(value)
                                        if !cleaned.isEmpty { save(String(cleaned.prefix(DivinationDraw.maximumInputLength))) }
                                    }
                                dailyEntry
                            }
                        }.disabled(store.saving)
                        if store.failed {
                            Button("重试") { save(retryMood) }.buttonStyle(.bordered)
                        }
                    } else {
                        Button { store.load() } label: { Label("重试", systemImage: "arrow.clockwise") }
                            .buttonStyle(.bordered)
                        dailyEntry
                    }
                }.padding(.top, today == nil ? 4 : 20)
            }
        }
    }

    private func save(_ mood: String) {
        retryMood = mood
        Task { await store.record(mood, companion: companion) }
    }
}
