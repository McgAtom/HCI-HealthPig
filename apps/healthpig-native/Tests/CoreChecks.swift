import Foundation

@main struct CoreChecks {
    @MainActor static func main() throws {
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
        print("PASS · \(checks) checks: daily dates, 24-card cycle, offline merge, conflict resolution, persistent storage, failed writes, feedback edits, frozen model")
    }
}
