import Foundation
import WatchConnectivity
import Combine

@MainActor final class CompanionBridge: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var status = "收藏保存在本机"
    @Published private(set) var lastReceivedAt: Date?
    private weak var store: PigStore?
    private let session: WCSession?

    init(store: PigStore) {
        self.store = store
        session = WCSession.isSupported() ? WCSession.default : nil
        super.init()
        session?.delegate = self
        store.onChange = { [weak self] in self?.publish() }
        session?.activate()
    }
    func publish() {
        guard let session, session.activationState == .activated, let store, store.ready else {
            status = "已存本机，连接可用后同步"; return
        }
#if os(iOS)
        guard session.isPaired else { status = "尚未配对手表，收藏仍在本机"; return }
        guard session.isWatchAppInstalled else { status = "尚未识别到手表配套应用，收藏仍在本机"; return }
#else
        guard session.isCompanionAppInstalled else { status = "尚未识别到 iPhone 配套应用，收藏仍在本机"; return }
#endif
        do {
            let snapshot = store.ledger
            let data = try JSONEncoder().encode(snapshot)
            guard data.count < 60_000 else { status = "已存本机，记录较多，暂未同步"; return }
            try session.updateApplicationContext(["ledger": data])
            status = "已存本机，等待对端接收"
            if session.isReachable {
                session.sendMessage(["ledger": data], replyHandler: { [weak self] reply in
                    Task { @MainActor [weak self] in
                        guard let self, self.store?.ledger == snapshot else { return }
                        self.status = reply["saved"] as? Bool == true ? "对端已保存本次同步" : "对端暂未保存，可再次同步"
                    }
                }, errorHandler: { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self, self.store?.ledger == snapshot else { return }
                        self.status = "已存本机，等待重新连接"
                    }
                })
            }
        } catch { status = "同步暂不可用，记录仍在本机" }
    }
    private func receive(_ message: [String: Any]) -> Bool {
        guard let data = message["ledger"] as? Data, data.count < 60_000, let store else { return false }
        do {
            try store.merge(data); lastReceivedAt = .now; status = "已接收并保存在本机"; return true
        } catch { status = "收到的记录未能保存，请重试"; return false }
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if error != nil { self.status = "连接暂不可用，记录保存在本机"; return }
            if !session.receivedApplicationContext.isEmpty { _ = self.receive(session.receivedApplicationContext) }
            self.publish()
        }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor [weak self] in _ = self?.receive(applicationContext) }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor [weak self] in replyHandler(["saved": self?.receive(message) ?? false]) }
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in if session.isReachable { self?.publish() } }
    }
#if os(iOS)
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in self?.publish() }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
#else
    nonisolated func sessionCompanionAppInstalledDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in self?.publish() }
    }
#endif
}
