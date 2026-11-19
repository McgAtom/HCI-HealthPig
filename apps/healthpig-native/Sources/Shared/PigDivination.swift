import Foundation
import NaturalLanguage

struct DivinationCard: Identifiable, Equatable, Sendable {
    enum Angle: Hashable, Sendable { case pause, reflect, connect, act }

    let id: String
    let title: String
    let angle: Angle
    let prompt: String
    let symbol: String
    let anchors: [String]

    static let deck: [Self] = [
        .init(id: "breath", title: "喘息", angle: .pause, prompt: "今晚哪件事可以留到明天？", symbol: "wind", anchors: ["累", "休息", "疲惫", "疲劳", "歇会儿"]),
        .init(id: "boundary", title: "边界", angle: .connect, prompt: "有哪些事可以请别人帮忙？", symbol: "square.dashed", anchors: ["累", "疲惫", "疲劳", "压力", "拒绝", "负担"]),
        .init(id: "loosen", title: "松开", angle: .reflect, prompt: "有哪件事，做到差不多就可以了？", symbol: "leaf", anchors: ["累", "疲惫", "疲劳", "紧张", "压力", "放松"]),
        .init(id: "ground", title: "落地", angle: .act, prompt: "眼前哪一件小事，是你现在能做的？", symbol: "shoeprints.fill", anchors: ["焦虑", "慌张", "担忧", "不安"]),
        .init(id: "pause", title: "暂停", angle: .pause, prompt: "如果空出五分钟，你想留给什么？", symbol: "pause.circle", anchors: ["焦虑", "压力", "紧张", "烦躁", "忙碌"]),
        .init(id: "tide", title: "退潮", angle: .reflect, prompt: "有没有一种感受，等一会儿也没关系？", symbol: "water.waves", anchors: ["焦虑", "担忧", "低落", "难过", "烦恼"]),
        .init(id: "echo", title: "回声", angle: .reflect, prompt: "你希望谁听见你今天想说的那句话？", symbol: "bubble.left.and.bubble.right", anchors: ["孤独", "想念", "朋友", "倾诉"]),
        .init(id: "close", title: "靠近", angle: .connect, prompt: "你想给谁发一条不用等回复的消息？", symbol: "paperplane", anchors: ["孤独", "陪伴", "友情", "想家"]),
        .init(id: "nest", title: "窝", angle: .pause, prompt: "哪一个地方让你觉得可以放松一点？", symbol: "house", anchors: ["想家", "孤独", "睡觉", "安心"]),
        .init(id: "keep", title: "留下", angle: .reflect, prompt: "今天有哪个瞬间值得你再想一遍？", symbol: "bookmark", anchors: ["开心", "快乐", "满足", "幸福"]),
        .init(id: "glow", title: "发光", angle: .act, prompt: "今天的哪件小事，是你亲手做成的？", symbol: "sparkles", anchors: ["开心", "兴奋", "成功", "自豪"]),
        .init(id: "share", title: "分享", angle: .connect, prompt: "这份开心，你想分给谁一点？", symbol: "gift", anchors: ["快乐", "开心", "朋友", "礼物"]),
        .init(id: "fork", title: "岔路", angle: .act, prompt: "如果今天只试一小步，你想往哪边走？", symbol: "arrow.triangle.branch", anchors: ["迷茫", "选择", "犹豫", "决定"]),
        .init(id: "question", title: "问号", angle: .reflect, prompt: "这个问题里，哪部分值得你再想一想？", symbol: "questionmark.circle", anchors: ["迷茫", "困惑", "问题", "犹豫"]),
        .init(id: "blank", title: "留白", angle: .pause, prompt: "有哪个答案，可以暂时留空？", symbol: "circle.dotted", anchors: ["迷茫", "困惑", "等待", "想不通"]),
        .init(id: "shore", title: "岸边", angle: .reflect, prompt: "此刻你最想听见什么声音？", symbol: "water.waves", anchors: ["大海", "海边", "潮汐", "风景"]),
        .init(id: "slow", title: "慢下来", angle: .act, prompt: "今天有没有一段路，你想慢慢走完？", symbol: "figure.walk", anchors: ["散步", "海边", "旅行", "放松"]),
        .init(id: "far", title: "远方", angle: .pause, prompt: "哪个地方，你愿意留给下一次出发？", symbol: "safari", anchors: ["海边", "大海", "旅行", "远方"]),
        .init(id: "cushion", title: "软垫", angle: .pause, prompt: "现在什么能让你觉得舒服一点？", symbol: "cloud", anchors: ["难过", "低落", "委屈", "伤心"]),
        .init(id: "after-rain", title: "雨停", angle: .reflect, prompt: "今天有哪一刻，心里稍微松了一点？", symbol: "cloud.sun", anchors: ["难过", "低落", "失落", "雨天"]),
        .init(id: "speak", title: "说出来", angle: .connect, prompt: "你想怎样开口说出心里话？", symbol: "quote.bubble", anchors: ["愤怒", "委屈", "烦躁", "生气"]),
        .init(id: "goodnight", title: "晚安", angle: .pause, prompt: "哪件事今天可以在这里打个句号？", symbol: "moon.stars", anchors: ["睡觉", "失眠", "夜晚", "困倦"]),
        .init(id: "light", title: "小灯", angle: .act, prompt: "今天有没有发生一件值得记住的小事？", symbol: "lightbulb", anchors: ["平静", "日常", "普通", "满足"]),
        .init(id: "cup", title: "空杯", angle: .reflect, prompt: "今天哪个念头可以先放一放？", symbol: "cup.and.saucer", anchors: ["放松", "平静", "失眠", "休息", "放空"]),
    ]
}

struct DivinationCandidate: Sendable {
    let card: DivinationCard
    let similarity: Double
}

enum DivinationVocabulary {
    private enum Dimension: Int, CaseIterable {
        case fatigue, workload, worry, solitude, joy, choice, outdoors, sadness, quiet, sleep, friendship, anger
    }

    private struct Topic {
        let dimension: Dimension
        let words: String
        let neighbors: [Dimension]
    }

    private static let topics: [Topic] = [
        .init(dimension: .fatigue, words: "累 疲惫 疲劳 歇会儿 好累 困 犯困 没电 精疲力尽", neighbors: [.workload, .quiet, .sleep]),
        .init(dimension: .workload, words: "压力 负担 拒绝 紧张 烦躁 忙碌 烦 心烦 内耗", neighbors: [.fatigue, .worry, .sadness]),
        .init(dimension: .worry, words: "焦虑 慌张 担忧 不安 忐忑 担心 着急", neighbors: [.workload, .choice]),
        .init(dimension: .solitude, words: "孤独 孤单 想念 陪伴 想家 倾诉 想你 寂寞", neighbors: [.sadness, .friendship]),
        .init(dimension: .joy, words: "开心 快乐 幸福 兴奋 成功 自豪 高兴 喜悦", neighbors: [.quiet, .friendship]),
        .init(dimension: .choice, words: "迷茫 选择 犹豫 决定 困惑 问题 想不通 等待 纠结", neighbors: [.worry, .quiet]),
        .init(dimension: .outdoors, words: "大海 海边 潮汐 风景 散步 旅行 远方 出发 海岸", neighbors: [.choice, .quiet]),
        .init(dimension: .sadness, words: "难过 低落 烦恼 委屈 伤心 失落 雨天 沮丧", neighbors: [.workload, .solitude]),
        .init(dimension: .quiet, words: "休息 放松 安心 平静 日常 普通 满足 放空 安静", neighbors: [.fatigue, .joy, .sleep]),
        .init(dimension: .sleep, words: "睡觉 失眠 夜晚 困倦 睡不着 晚安", neighbors: [.fatigue, .quiet]),
        .init(dimension: .friendship, words: "朋友 友情 礼物 人际 关系", neighbors: [.solitude, .joy]),
        .init(dimension: .anger, words: "愤怒 生气 火大 发火", neighbors: [.workload, .sadness]),
    ]

    static let vectors: [String: [Double]] = {
        var lexicon: [String: [Double]] = [:]
        for topic in topics {
            var vector = Array(repeating: 0.0, count: Dimension.allCases.count)
            vector[topic.dimension.rawValue] = 1
            for neighbor in topic.neighbors { vector[neighbor.rawValue] = 0.20 }
            for word in topic.words.split(separator: " ") { lexicon[String(word)] = vector }
        }
        return lexicon
    }()
}

enum DivinationDraw {
    static let maximumInputLength = 16
    static let minimumMatches = 3

    static func clean(_ input: String) -> String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func canSubmit(_ input: String) -> Bool {
        let trimmed = clean(input)
        return !trimmed.isEmpty && trimmed.count <= maximumInputLength
    }

    static func cosine(_ lhs: [Double], _ rhs: [Double]) -> Double? {
        guard !lhs.isEmpty, lhs.count == rhs.count else { return nil }
        var dot = 0.0, leftLength = 0.0, rightLength = 0.0
        for (left, right) in zip(lhs, rhs) {
            dot += left * right
            leftLength += left * left
            rightLength += right * right
        }
        let denominator = sqrt(leftLength * rightLength)
        guard denominator.isFinite, denominator > 0, dot.isFinite else { return nil }
        return min(1, max(-1, dot / denominator))
    }

    static func probabilities(from pool: [DivinationCandidate], recentIDs: [String]) -> [Double] {
        guard !pool.isEmpty else { return [] }
        let counts = Dictionary(grouping: pool, by: { $0.card.angle }).mapValues(\.count)
        let recentCards = recentIDs.compactMap { id in DivinationCard.deck.first { $0.id == id } }
        let repeats = Dictionary(grouping: recentCards, by: \.angle).mapValues(\.count)
        let weakest = pool.map(\.similarity).min() ?? 0
        let weights = pool.map { candidate in
            let angle = candidate.card.angle
            let relevance = 1 + (candidate.similarity - weakest) / 0.22
            return relevance / Double(counts[angle, default: 1]) / Double(1 + repeats[angle, default: 0])
        }
        let total = weights.reduce(0, +)
        // Reserve a quarter of the probability for equally likely exploration within the qualified pool.
        return weights.map { 0.75 * $0 / total + 0.25 / Double(pool.count) }
    }

    static func pick(from pool: [DivinationCandidate], recentIDs: [String]) -> DivinationCard? {
        let choices = pool.filter { $0.card.id != recentIDs.first }
        guard choices.count >= 2 else { return nil }
        let ticket = Double.random(in: 0..<1)
        var upperBound = 0.0
        for (candidate, probability) in zip(choices, probabilities(from: choices, recentIDs: recentIDs)) {
            upperBound += probability
            if ticket < upperBound { return candidate.card }
        }
        return choices.last?.card
    }
}

struct DivinationRecord: Codable, Equatable {
    let cardID: String
    let wordMatched: Bool
    var mood: String? = nil
    var artwork: DivinationArtwork? = nil

    func appearance(on day: String) -> DivinationArtwork {
        if let artwork { return artwork }
        let seed = (day + cardID).utf8.reduce(UInt32(2_166_136_261)) { ($0 ^ UInt32($1)) &* 16_777_619 }
        return DivinationArtwork(seed: seed)
    }
}

struct DivinationArtwork: Codable, Equatable {
    enum Frame: Int, CaseIterable { case orbit, garden, dawn }
    let seed: UInt32

    var frame: Frame { Frame.allCases[Int(seed % UInt32(Frame.allCases.count))] }
    var ornament: Int { Int((seed >> 16) % 3) }
    var flipped: Bool { (seed >> 24) % 2 == 1 }
}

struct DivinationJournal: Codable {
    private(set) var days: [String: DivinationRecord] = [:]

    mutating func record(_ result: DivinationRecord, on day: String) -> Bool {
        guard days[day] == nil else { return false }
        days[day] = result
        return true
    }

    func recentCards(before day: String) -> [String] {
        days.keys.filter { $0 < day }.sorted(by: >).prefix(3).compactMap { days[$0]?.cardID }
    }
}

actor DivinationMatcher {
    private struct Index {
        let model: NLEmbedding
        let anchors: [String: [Double]]
    }

    // The index stays with the actor. The first interactive draw loads it off the UI actor.
    private lazy var systemWords = Self.makeIndex(NLEmbedding.wordEmbedding(for: .simplifiedChinese))

    func matches(_ input: String) -> [DivinationCandidate] {
        guard DivinationDraw.canSubmit(input) else { return [] }
        let trimmed = DivinationDraw.clean(input)
        let term = trimmed.applyingTransform(StringTransform("Traditional-Simplified"), reverse: false) ?? trimmed
        guard term.unicodeScalars.contains(where: { (0x3400...0x9FFF).contains($0.value) }) else { return [] }
        let words = DivinationVocabulary.vectors
        if let query = words[term] { return Self.closest(query, anchors: words) }
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = term
        let tokens = tokenizer.tokens(for: term.startIndex..<term.endIndex)
            .map { String(term[$0]) }.filter { words[$0] != nil }
        let matches = tokens.isEmpty ? words.keys.filter { $0.count > 1 && term.contains($0) } : tokens
        if let token = matches.sorted(by: {
            $0.count == $1.count ? $0 < $1 : $0.count > $1.count
        }).first, let query = words[token] {
            let candidates = Self.closest(query, anchors: words)
            if !candidates.isEmpty { return candidates }
        }
        guard let systemWords, let query = systemWords.model.vector(for: term) else { return [] }
        return Self.closest(query, anchors: systemWords.anchors)
    }

    private static func makeIndex(_ model: NLEmbedding?) -> Index? {
        guard let model else { return nil }
        let terms = Set(DivinationCard.deck.flatMap(\.anchors))
        let pairs = terms.compactMap { term in model.vector(for: term).map { (term, $0) } }
        return Index(model: model, anchors: Dictionary(uniqueKeysWithValues: pairs))
    }

    private static func closest(_ query: [Double], anchors: [String: [Double]]) -> [DivinationCandidate] {
        let scores = DivinationCard.deck.compactMap { card -> DivinationCandidate? in
            let score = card.anchors.compactMap { anchor in anchors[anchor].flatMap { DivinationDraw.cosine(query, $0) } }.max()
            guard let score, score >= 0.40 else { return nil }
            return DivinationCandidate(card: card, similarity: score)
        }.sorted { $0.similarity == $1.similarity ? $0.card.id < $1.card.id : $0.similarity > $1.similarity }
        guard let best = scores.first?.similarity else { return [] }
        let candidates = scores.prefix { $0.similarity >= best - 0.22 }
        guard candidates.count >= DivinationDraw.minimumMatches else { return [] }
        return Array(candidates.prefix(5))
    }
}
