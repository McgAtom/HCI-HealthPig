import Foundation

struct PigCard: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let series: String
    let flavor: String
    let assetName: String
}

struct PigCatalog: Decodable {
    let version: String
    let cards: [PigCard]
    static func load(bundle: Bundle = .main) throws -> PigCatalog {
        guard let url = bundle.url(forResource: "pig-catalog", withExtension: "json") else {
            throw PigDataError.invalid("猪猪图鉴资源缺失，请重新安装完整应用。")
        }
        let catalog = try JSONDecoder().decode(PigCatalog.self, from: Data(contentsOf: url))
        guard catalog.cards.count == 24, Set(catalog.cards.map(\.id)).count == 24 else {
            throw PigDataError.invalid("猪猪图鉴不完整，请重新安装完整应用。")
        }
        return catalog
    }
    func card(_ id: String) -> PigCard? { cards.first { $0.id == id } }
    var series: [String] { cards.reduce(into: []) { if !$0.contains($1.series) { $0.append($1.series) } } }
}

enum PigDataError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case let .invalid(message) = self { return message }; return nil }
}

struct DailyClaim: Codable, Equatable, Identifiable {
    let day: String
    let cardID: String
    var id: String { day }
}

// Gregorian local day for eligibility; UTC is used only to map that date to a stable card.
// Both devices reveal the same card for a given day. A claim is a saved fact, never a reroll.
enum DailyPig {
    static func dayKey(_ date: Date, timeZone: TimeZone = .current) -> String {
        let parts = calendar(timeZone).dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
    static func calendar(_ zone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone; return calendar
    }
    static func ordinal(_ key: String) -> Int? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        guard key.count == 10, let date = formatter.date(from: key), formatter.string(from: date) == key else { return nil }
        return Int(floor(date.timeIntervalSince1970 / 86400))
    }
    static func cardID(for key: String) -> String? {
        guard let day = ordinal(key) else { return nil }
        // 7 and 24 are coprime: a complete 24-day cycle, without fabricated rarity odds.
        let index = ((day * 7 + 11) % 24 + 24) % 24 + 1
        return String(format: "pig-%03d", index)
    }
}

struct PigSelection: Codable, Equatable {
    let cardID: String
    let counter: Int
    let device: String
    func isNewer(than other: PigSelection) -> Bool {
        counter != other.counter ? counter > other.counter : device > other.device
    }
}

struct WatchReading: Codable, Equatable, Identifiable {
    let id: UUID
    let date: Date
    let verdict: MotionVerdict
    let score: Double
    let threshold: Double
    let sampleCount: Int
    let actualHz: Double
    var valid: Bool {
        score.isFinite && (0...1).contains(score) && threshold.isFinite && (0...1).contains(threshold)
            && sampleCount >= 160 && actualHz.isFinite && actualHz > 0
            && verdict == MotionVerdict.decide(score: score, threshold: threshold)
    }
}

struct PigLedger: Codable, Equatable {
    var version = 1
    var claims: [DailyClaim] = []
    var selection: PigSelection?
    var reading: WatchReading?
    var ownedIDs: Set<String> { Set(claims.map(\.cardID)) }
    func claim(on day: String) -> DailyClaim? { claims.first { $0.day == day } }

    func validated() throws -> PigLedger {
        guard version == 1, claims.count <= 20000, Set(claims.map(\.day)).count == claims.count,
              claims.allSatisfy({ DailyPig.cardID(for: $0.day) == $0.cardID }),
              reading?.valid != false else { throw PigDataError.invalid("记录格式不正确，未覆盖本机数据。") }
        if let selection {
            guard ownedIDs.contains(selection.cardID), selection.counter >= 0, selection.counter < Int.max - 1,
                  !selection.device.isEmpty, selection.device.count <= 80 else {
                throw PigDataError.invalid("佩戴记录不正确，未覆盖本机数据。")
            }
        }
        return self
    }
    func merging(_ incoming: PigLedger) throws -> PigLedger {
        _ = try incoming.validated()
        var result = self
        let all = Dictionary((claims + incoming.claims).map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
        result.claims = all.values.sorted { $0.day < $1.day }
        if let next = incoming.selection, result.selection == nil || next.isNewer(than: result.selection!) {
            result.selection = next
        }
        if let next = incoming.reading,
           result.reading == nil || next.date > result.reading!.date || (next.date == result.reading!.date && next.id.uuidString > result.reading!.id.uuidString) {
            result.reading = next
        }
        return try result.validated()
    }
}

struct ResultFeedback: Codable, Identifiable {
    let id: UUID
    let readingID: UUID
    let answer: String
    let date: Date
}
