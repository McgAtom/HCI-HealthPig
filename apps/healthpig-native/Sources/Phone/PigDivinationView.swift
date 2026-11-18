import SwiftUI

@MainActor private final class DivinationStore: ObservableObject {
    static let shared = DivinationStore()
    @Published private(set) var journal: DivinationJournal?
    @Published private(set) var drawing = false
    private let matcher = DivinationMatcher()
    private let defaults: UserDefaults
    private let key = "dailyDivinationJournalV1"

    private init() {
#if DEBUG && targetEnvironment(simulator)
        if let suite = ProcessInfo.processInfo.environment["HEALTHPIG_DIVINATION_TEST_SUITE"],
           let isolated = UserDefaults(suiteName: suite) {
            defaults = isolated
        } else {
            defaults = .standard
        }
#else
        defaults = .standard
#endif
        if let data = defaults.data(forKey: key) {
            journal = try? JSONDecoder().decode(DivinationJournal.self, from: data)
        } else {
            journal = DivinationJournal()
        }
    }

    func draw(_ word: String) async {
        let day = DailyPig.dayKey(.now)
        guard !drawing, var next = journal, next.days[day] == nil else { return }
        drawing = true
        defer { drawing = false }

        let matches = await matcher.matches(word)
        let wordMatched = !matches.isEmpty
        let pool = wordMatched ? matches : DivinationCard.deck.map { DivinationCandidate(card: $0, similarity: 0) }
        guard let card = DivinationDraw.pick(from: pool, recentIDs: next.recentCards(before: day)),
              next.record(DivinationRecord(cardID: card.id, wordMatched: wordMatched), on: day),
              let data = try? JSONEncoder().encode(next) else { return }
        defaults.set(data, forKey: key)
        journal = next
    }
}

struct PigDivinationView: View {
    let companion: PigCard?
    @StateObject private var store = DivinationStore.shared
    @State private var word = ""
    @FocusState private var editing: Bool

    private let violet = Color(red: 0.81, green: 0.73, blue: 1)

    var body: some View {
        PigScreen {
            TimelineView(.everyMinute) { context in
                let day = DailyPig.dayKey(context.date)
                if let record = store.journal?.days[day] {
                    revealedCard(record)
                } else if store.journal != nil {
                    drawForm
                } else {
                    Label("暂时读不到占卜记录", systemImage: "exclamationmark.circle").font(.headline)
                }
            }
        }.navigationTitle("猪猪占卜")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .scrollDismissesKeyboard(.interactively)
    }

    private var drawForm: some View {
        VStack(spacing: 16) {
            cardArtwork(symbol: nil)
            TextField("输入一个词", text: $word,
                      prompt: Text("想一个词（可留空）").foregroundStyle(.white.opacity(0.72)))
                .font(.body).padding(15)
                .background(PigTheme.panel, in: RoundedRectangle(cornerRadius: 18))
                .focused($editing).submitLabel(.go).onSubmit(draw)
                .disabled(store.drawing)
                .accessibilityIdentifier("divination.word")
            Button(action: draw) {
                if store.drawing {
                    HStack { ProgressView().tint(.black); Text("正在抽卡") }
                } else {
                    Label("抽一张", systemImage: "sparkles")
                }
            }.buttonStyle(PigPrimaryButton()).disabled(store.drawing)
                .accessibilityIdentifier("divination.draw")
        }
    }

    private func revealedCard(_ record: DivinationRecord) -> some View {
        VStack(spacing: 14) {
            if let card = DivinationCard.deck.first(where: { $0.id == record.cardID }) {
                cardArtwork(symbol: card.symbol)
                Text(card.title).font(.largeTitle.bold()).foregroundStyle(violet)
                    .accessibilityAddTraits(.isHeader).accessibilityIdentifier("divination.card-title")
                Text(card.prompt).font(.title3.weight(.medium)).multilineTextAlignment(.center)
                    .accessibilityIdentifier("divination.card-prompt")
            }
            Label(record.wordMatched ? "今日已抽" : "今日已抽 · 随机卡", systemImage: "checkmark.circle")
                .font(.headline).foregroundStyle(violet)
                .accessibilityIdentifier("divination.claimed")
        }.padding(20).frame(maxWidth: .infinity)
            .background(PigTheme.panel, in: RoundedRectangle(cornerRadius: 24))
    }

    private func cardArtwork(symbol: String?) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(LinearGradient(colors: [violet.opacity(0.24), PigTheme.panel],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 24).strokeBorder(violet.opacity(0.55))
            if let symbol {
                Image(systemName: symbol).font(.system(size: 58, weight: .light)).foregroundStyle(violet)
            } else if let companion {
                PigArtwork(card: companion, size: 122)
            } else {
                Image(systemName: "sparkles").font(.system(size: 48)).foregroundStyle(violet)
            }
        }.frame(width: 160, height: 178).accessibilityHidden(true)
    }

    private func draw() {
        editing = false
        let input = word
        word = ""
        Task { await store.draw(input) }
    }
}
