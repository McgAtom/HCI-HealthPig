import Foundation

@main struct CoreChecks {
    @MainActor static func main() async throws {
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message); checks += 1
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let catalog = try JSONDecoder().decode(PigCatalog.self, from: Data(contentsOf: root.appendingPathComponent("Resources/pig-catalog.json")))
        check(catalog.cards.count == 24, "24 cards")
        check(DailyPig.ordinal("2024-02-29") != nil, "leap date")
        check(DailyPig.ordinal("2026-02-29") == nil, "reject invalid date")
        check(DailyPig.ordinal("2026-10-17junk") == nil, "reject malformed key")
        let first = DailyPig.ordinal("2026-10-17")!
        let dates = (0..<24).map { DailyPig.dayKey(Date(timeIntervalSince1970: Double(first + $0) * 86400), timeZone: TimeZone(secondsFromGMT: 0)!) }
        check(Set(dates.compactMap(DailyPig.cardID)).count == 24, "full cycle covers all cards")
        let midnight = Date(timeIntervalSince1970: 1792195200)
        check(DailyPig.dayKey(midnight, timeZone: TimeZone(secondsFromGMT: 8 * 3600)!) != DailyPig.dayKey(midnight, timeZone: TimeZone(secondsFromGMT: -8 * 3600)!), "eligibility follows local date")
        let a = DailyClaim(day: dates[0], cardID: DailyPig.cardID(for: dates[0])!)
        let b = DailyClaim(day: dates[1], cardID: DailyPig.cardID(for: dates[1])!)
        let matcher = DivinationMatcher()
        let tired = await matcher.matches(" 累 ")
        let colloquialTired = await matcher.matches("好累")
        let joy = await matcher.matches("开心")
        let distant = await matcher.matches("苹果")
        let emptyDraw = await matcher.matches("")
        check(Set(DivinationCard.deck.map(\.id)).count == 24, "24 unique divination cards")
        check(DivinationCard.deck.flatMap(\.anchors).allSatisfy { DivinationVocabulary.vectors[$0] != nil },
              "every editorial anchor has an offline project vector")
        check(DivinationDraw.cosine([1, 0], [0, 1]) == 0 && DivinationDraw.cosine([0, 0], [1, 1]) == nil,
              "divination cosine accepts valid vectors and rejects zero vectors")
        check(Set(tired.map(\.card.id)) == ["breath", "boundary", "loosen"], "tired uses the three relevant cards")
        check(tired.map(\.card.id) == colloquialTired.map(\.card.id), "curated colloquial alias uses the same core candidates")
        check(Set(joy.map(\.card.id)) == ["keep", "glow", "share"], "joy does not draw cards about sadness")
        check(distant.isEmpty && emptyDraw.isEmpty, "weak or missing term uses the fallback pool")
        let baseline = DivinationDraw.probabilities(from: tired, recentIDs: [])
        let repeated = DivinationDraw.probabilities(from: tired, recentIDs: ["nest"])
        let breathIndex = tired.firstIndex { $0.card.id == "breath" }!
        check(abs(repeated.reduce(0, +) - 1) < 1e-9 && repeated.allSatisfy { $0 > 0 }
              && repeated[breathIndex] < baseline[breathIndex], "recent angle gets less weight while all candidates remain reachable")
        let next = DivinationDraw.pick(from: tired, recentIDs: ["breath"])
        check(next != nil && next?.id != "breath", "result excludes most recent card while alternatives remain")
        var divination = DivinationJournal()
        let draw = DivinationRecord(cardID: "breath", wordMatched: true)
        check(divination.record(draw, on: dates[0]) && !divination.record(draw, on: dates[0]) && divination.record(draw, on: dates[1]),
              "divination permits one record per date and opens on the next date")
        let encoded = try JSONEncoder().encode(divination)
        let decoded = try JSONDecoder().decode(DivinationJournal.self, from: encoded)
        check(decoded.days[dates[0]] == draw && decoded.recentCards(before: dates[2]) == ["breath", "breath"],
              "daily divination and recent cards survive serialization")
        var left = PigLedger(claims: [a], selection: PigSelection(cardID: a.cardID, counter: 1, device: "A"))
        let right = PigLedger(claims: [b], selection: PigSelection(cardID: b.cardID, counter: 1, device: "B"))
        let union = try left.merging(right)
        check(union.claims.count == 2, "offline claims retained")
        check(try union.merging(union) == union, "duplicate snapshot idempotent")
        check(try right.merging(left) == union, "merging commutative")
        check(union.selection?.cardID == b.cardID, "equal revision deterministic tie-break")
        left.selection = PigSelection(cardID: a.cardID, counter: 2, device: "A")
        check(try left.merging(union).selection?.cardID == a.cardID, "higher revision wins")
        do {
            _ = try union.merging(PigLedger(claims: [DailyClaim(day: dates[0], cardID: "pig-999")]))
            preconditionFailure("invalid claims accepted")
        } catch { checks += 1 }
        let date = Date(timeIntervalSince1970: 1792200000)
        let fullRings = DailyRings(day: DailyPig.dayKey(date), readAt: date,
            move: RingValue(value: 500, goal: 400), exercise: RingValue(value: 30, goal: 30), stand: RingValue(value: 10, goal: 10))
        check(fullRings.canUnlock(now: date), "all three system goals required")
        check(!fullRings.canUnlock(now: date.addingTimeInterval(301)), "stale reading cannot unlock")
        check(!fullRings.canUnlock(now: date.addingTimeInterval(-1)), "future reading cannot unlock")
        check(!fullRings.canUnlock(now: date.addingTimeInterval(86400)), "previous day cannot unlock")
        var paused = fullRings; paused.paused = true
        check(!paused.canUnlock(now: date), "paused rings do not unlock")
        let partial = DailyRings(day: fullRings.day, readAt: date, move: fullRings.move, exercise: RingValue(value: 29.99, goal: 30), stand: fullRings.stand)
        check(!partial.canUnlock(now: date) && partial.closedCount == 2, "rounding cannot close incomplete ring")
        check(partial.energy(now: date) == 99 && fullRings.energy(now: date) == 100, "only all rings can reach 100")
        check(paused.energy(now: date) == nil && fullRings.energy(now: date.addingTimeInterval(301)) == nil, "paused or stale energy hidden")
        let midway = DailyRings(day: fullRings.day, readAt: date, move: RingValue(value: 200, goal: 400),
            exercise: RingValue(value: 15, goal: 30), stand: RingValue(value: 5, goal: 10))
        check(midway.energy(now: date) == 50, "mean capped progress of move and exercise")
        let standOnly = DailyRings(day: fullRings.day, readAt: date, move: RingValue(value: 0, goal: 400),
            exercise: RingValue(value: 0, goal: 30), stand: fullRings.stand)
        check(standOnly.energy(now: date) == 0 && !standOnly.canUnlock(now: date), "stand alone does not charge energy")
        let missingStand = DailyRings(day: fullRings.day, readAt: date, move: fullRings.move,
            exercise: fullRings.exercise, stand: RingValue(value: 9, goal: 10))
        check(missingStand.energy(now: date) == 99 && !missingStand.canUnlock(now: date), "stand is required to reach 100")

        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let noon = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 12))!
        var timeline: [SleepSchedule.Interval] = []
        for offset in 0...4 {
            let end = noon.addingTimeInterval(Double(-offset * 24 - 5) * 3600)
            if offset < 3 {
                timeline.append(.init(start: end.addingTimeInterval(-7 * 3600), end: end, source: "Watch"))
                timeline.append(.init(start: end.addingTimeInterval(-1800), end: end, source: "Watch"))
                timeline.append(.init(start: end.addingTimeInterval(7200), end: end.addingTimeInterval(9000), source: "Watch"))
            }
            if offset < 2 { timeline.append(.init(start: end.addingTimeInterval(-9 * 3600), end: end, source: "Phone")) }
        }
        let nights = SleepSchedule.recentNights(timeline, now: noon, calendar: calendar)
        check(nights == [420, 420, 420], "deduplicates overlap, excludes naps, selects one source")
        let plan = SleepSchedule(target: 480, nights: nights)
        check(plan.duration == 510 && plan.typicalDuration == 420, "recent short nights add a bounded planning buffer")
        check(SleepSchedule(target: 480, nights: [420, 420]).duration == 480, "fewer than three nights uses chosen goal")
        check(SleepSchedule(target: 480, nights: [600, 570, 500]).duration == 480, "does not reduce user goal")
        check(SleepSchedule.bedtime(wake: 420, duration: 510) == 1350, "bedtime wraps across midnight")
        check(!RingValue(value: 0, goal: 0).closed, "missing goal is unknown not completed")
        check(!RingValue(value: .nan, goal: 10).valid && !RingValue(value: -1, goal: 10).valid, "invalid ring values rejected")
        check(RingValue(value: 900, goal: 400).fraction == 1, "overachieving cannot compensate other rings")
        let reading = WatchReading(id: UUID(), date: date, verdict: .walking, score: 0.9, threshold: 0.5, sampleCount: 210, actualHz: 20)
        check(reading.valid, "valid reading")
        let wrong = WatchReading(id: UUID(), date: date, verdict: .still, score: 0.9, threshold: 0.5, sampleCount: 210, actualHz: 20)
        check(!wrong.valid, "reject inconsistent verdict")
        check(MotionVerdict.decide(score: 0.53, threshold: 0.5) == .uncertain, "borderline unchanged")
        check(MotionVerdict.decide(score: nil, threshold: 0.5) == .waiting, "no data is waiting")

        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("healthpig-checks-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let store = PigStore(directory: temp, catalog: catalog)
        check(store.ready && store.ledger.claims.isEmpty, "empty initial store")
        check(store.claimToday(rings: nil, now: date) == nil && store.ledger.claims.isEmpty, "unknown activity never unlocks a card")
        check(store.claimToday(rings: partial, now: date) == nil && store.ledger.claims.isEmpty, "partial rings never unlock a card")
        let card = store.claimToday(rings: fullRings, now: date)
        check(card != nil && store.ledger.claims.count == 1, "claim saved")
        check(store.claimToday(rings: nil, now: date)?.id == card?.id && store.ledger.claims.count == 1, "existing claim survives unavailable data without reroll")
        store.wear(card!)
        let reopened = PigStore(directory: temp, catalog: catalog)
        check(reopened.ledger == store.ledger, "restart retains claim and selection")
        store.record(reading)
        check(store.addFeedback(readingID: reading.id, answer: "不符合"), "feedback saved")
        check(store.addFeedback(readingID: reading.id, answer: "符合") && store.feedback.count == 1, "feedback editable without duplication")
        let otherData = try JSONEncoder().encode(right)
        try store.merge(otherData)
        check(store.ledger.ownedIDs.contains(card!.id), "sync cannot erase local card")
        let blocked = temp.appendingPathComponent("not-a-directory")
        try Data("blocked".utf8).write(to: blocked)
        let cannotSave = PigStore(directory: blocked, catalog: catalog)
        check(cannotSave.claimToday(rings: fullRings, now: date) == nil && cannotSave.ledger.claims.isEmpty && !cannotSave.error.isEmpty, "failed write never reports claimed")
        try Data("broken JSON".utf8).write(to: temp.appendingPathComponent("collection-v1.json"))
        let corrupt = PigStore(directory: temp, catalog: catalog)
        check(!corrupt.ready && corrupt.claimToday(rings: fullRings, now: date) == nil, "corruption blocks overwrite")

        check(corrupt.canRestoreBackup, "valid previous backup retained")
        corrupt.restoreBackup()
        check(corrupt.ready && corrupt.ledger.ownedIDs.contains(card!.id), "corrupt primary recovers from previous backup")

        let model = try JSONDecoder().decode(MotionModel.self, from: Data(contentsOf: root.appendingPathComponent("Resources/motion-model.json")))
        let points = (0..<200).map { i in MotionPoint(time: Double(i)/20, x: 0.08 * sin(Double(i)*0.6), y: 0.03 * cos(Double(i)*0.6), z: 1 + 0.12 * sin(Double(i)*0.6)) }
        let features = MotionFeatures.compute(points)
        check(features.count == 24 && features.allSatisfy(\.isFinite), "feature pipeline finite")
        check(model.score(features).isFinite, "frozen model executes")
        let demo = try JSONDecoder().decode(DemoExamples.self, from: Data(contentsOf: root.appendingPathComponent("Resources/demo-examples.json"))).validated()
        check(demo.examples.count == 2, "two attributed public examples")
        check(MotionVerdict.decide(score: model.score(demo.examples[0].features), threshold: model.threshold) == .walking, "public walking example executes real model")
        check(MotionVerdict.decide(score: model.score(demo.examples[1].features), threshold: model.threshold) == .still, "public sitting example executes real model")
        let vector = demo.examples[0].features.map { String($0) }.joined(separator: ", ")
        let parsed = try FeatureInput.parse(vector)
        check(parsed == demo.examples[0].features, "editable feature input preserves values")
        for (invalid, label) in [("", "empty"), ("1,2", "missing"), (Array(repeating: "1", count: 25).joined(separator: ","), "extra"), ("NaN," + Array(repeating: "1", count: 23).joined(separator: ","), "nonfinite"), ("abc," + Array(repeating: "1", count: 23).joined(separator: ","), "nonnumeric"), ("," + vector, "empty field")] {
            do { _ = try FeatureInput.parse(invalid); check(false, "reject \(label)") }
            catch { check(true, "reject \(label)") }
        }
        var segments = CompanionSegments()
        check(segments.append(reading), "valid companion segment accepted")
        check(!segments.append(reading) && segments.readings.count == 1, "duplicate segment not counted twice")
        check(!segments.append(wrong), "invalid model segment rejected")
        let still = WatchReading(id: UUID(), date: date.addingTimeInterval(11), verdict: .still, score: 0.1, threshold: 0.5, sampleCount: 210, actualHz: 20)
        check(segments.append(still) && segments.walking == 1 && segments.still == 1, "only sampled windows counted by actual verdict")
        let old = WatchReading(id: UUID(), date: date, verdict: .walking, score: 0.9, threshold: 0.5, sampleCount: 210, actualHz: 20)
        check(!segments.append(old), "out of order segment not counted")
        print("PASS · \(checks) checks: daily dates, ring energy, sleep scheduling, 24-card cycle, offline merge, persistent storage, feedback edits, frozen model")
    }
}
