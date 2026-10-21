import Foundation
import Combine

@MainActor final class PigStore: ObservableObject {
    @Published private(set) var ledger = PigLedger()
    @Published private(set) var feedback: [ResultFeedback] = []
    @Published private(set) var catalog: PigCatalog?
    @Published var error = ""
    @Published private(set) var ready = false
    @Published private(set) var notice = ""
    @Published private(set) var currentDay = DailyPig.dayKey(.now)
    var onChange: (() -> Void)?
    private let directory: URL
    private let device: String
    private let suppliedCatalog: PigCatalog?
    private var file: URL { directory.appendingPathComponent("collection-v1.json") }
    private var backupFile: URL { directory.appendingPathComponent("collection-v1.previous.json") }
    var canRestoreBackup: Bool { !ready && FileManager.default.fileExists(atPath: backupFile.path) }
    private var feedbackFile: URL { directory.appendingPathComponent("feedback-v1.json") }

    init(directory: URL? = nil, catalog: PigCatalog? = nil) {
        self.suppliedCatalog = catalog
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HealthPigNative", isDirectory: true)
        if let existing = UserDefaults.standard.string(forKey: "nativeDeviceID") { device = existing }
        else { let id = UUID().uuidString; device = id; UserDefaults.standard.set(id, forKey: "nativeDeviceID") }
        reload()
    }
    func reload() {
        do {
            catalog = try suppliedCatalog ?? PigCatalog.load()
            ledger = FileManager.default.fileExists(atPath: file.path)
                ? try JSONDecoder().decode(PigLedger.self, from: Data(contentsOf: file)).validated() : PigLedger()
            if FileManager.default.fileExists(atPath: feedbackFile.path) {
                feedback = try JSONDecoder().decode([ResultFeedback].self, from: Data(contentsOf: feedbackFile))
            }
            ready = true; error = ""
        } catch { ready = false; self.error = "本机记录未能读取：\(error.localizedDescription)" }
    }
    func restoreBackup() {
        do {
            catalog = try suppliedCatalog ?? PigCatalog.load()
            let previous = try JSONDecoder().decode(PigLedger.self, from: Data(contentsOf: backupFile)).validated()
            if commit(previous) { ready = true; notice = "已恢复本机上一份有效备份，最近一次变更可能需要重新操作。" }
        } catch { self.error = "备份未能恢复：\(error.localizedDescription)" }
    }
    var companion: PigCard? {
        guard let catalog else { return nil }
        return ledger.selection.flatMap { catalog.card($0.cardID) } ?? catalog.card("pig-001")
    }
    func refreshDay() { currentDay = DailyPig.dayKey(.now) }
    func todayClaim(now: Date = .now) -> DailyClaim? { ledger.claim(on: DailyPig.dayKey(now)) }
    @discardableResult func claimToday(rings: DailyRings?, now: Date = .now) -> PigCard? {
        guard ready, let catalog else { return nil }
        let key = DailyPig.dayKey(now)
        if let claim = ledger.claim(on: key) { return catalog.card(claim.cardID) }
        guard rings?.canUnlock(now: now) == true else {
            error = "尚未确认今日三个圆环全部闭合，请读取最新活动摘要后重试。"; return nil
        }
        guard let id = DailyPig.cardID(for: key), let card = catalog.card(id) else { return nil }
        var next = ledger
        next.claims.append(DailyClaim(day: key, cardID: id)); next.claims.sort { $0.day < $1.day }
        if commit(next) { notice = "今天的猪猪已存入收藏"; return card }
        return nil
    }
    func wear(_ card: PigCard) {
        guard ready, ledger.ownedIDs.contains(card.id) else { return }
        var next = ledger
        next.selection = PigSelection(cardID: card.id, counter: (ledger.selection?.counter ?? 0) + 1, device: device)
        if commit(next) { notice = "已让\(card.name)陪伴你" }
    }
    func record(_ reading: WatchReading) {
        guard ready, reading.valid else { return }
        var next = ledger; next.reading = reading
        _ = commit(next)
    }
    func merge(_ data: Data) throws {
        guard ready else { throw PigDataError.invalid("本机记录尚未恢复，暂不接收同步。") }
        let incoming = try JSONDecoder().decode(PigLedger.self, from: data)
        let merged = try ledger.merging(incoming)
        if merged != ledger {
            guard commit(merged) else { throw PigDataError.invalid(error) }
        }
    }
    func addFeedback(readingID: UUID, answer: String) -> Bool {
        guard ready, ["符合", "不符合", "不确定"].contains(answer) else { return false }
        var next = feedback.filter { $0.readingID != readingID }
        next.append(ResultFeedback(id: UUID(), readingID: readingID, answer: answer, date: .now))
        next = Array(next.suffix(100))
        do { try write(next, to: feedbackFile); feedback = next; notice = "反馈已保存在本机，可重新选择修改"; return true }
        catch { self.error = "反馈未能保存，请重试：\(error.localizedDescription)"; return false }
    }
    func clearFeedback() {
        do { try write([ResultFeedback](), to: feedbackFile); feedback = []; notice = "本机反馈已清除" }
        catch { self.error = "未能清除反馈，请重试。" }
    }
    private func commit(_ next: PigLedger) -> Bool {
        do {
            _ = try next.validated(); try write(next, to: file)
            ledger = next; error = ""; onChange?(); return true
        } catch { self.error = "记录未能保存，请重试：\(error.localizedDescription)"; return false }
    }
    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var folder = directory; var folderValues = URLResourceValues(); folderValues.isExcludedFromBackup = true
        try? folder.setResourceValues(folderValues)
        let data = try JSONEncoder().encode(value)
        if url == file, let old = try? Data(contentsOf: file),
           let decoded = try? JSONDecoder().decode(PigLedger.self, from: old),
           (try? decoded.validated()) != nil {
            try old.write(to: backupFile, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var mutable = url; var values = URLResourceValues(); values.isExcludedFromBackup = true
        try? mutable.setResourceValues(values)
    }
}
