import Foundation
import WatchConnectivity
import Combine

@MainActor final class CompanionBridge: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var status = "收藏保存在本机"
    @Published private(set) var lastReceivedAt: Date?
    let sleep = SleepCompanion()
    @Published private(set) var hasWatch = false
    private weak var store: PigStore?
    private let session: WCSession?
#if os(iOS) && !targetEnvironment(simulator)
    private var lastTransferredAlarm: UUID?
#endif

    init(store: PigStore) {
        self.store = store
        session = WCSession.isSupported() ? WCSession.default : nil
        super.init()
#if os(watchOS)
        WristAlarm.shared.onReply = { [weak self] result in
            self?.sleep.reply(result)
            self?.applyWristRequest()
        }
#endif
        session?.delegate = self
        sleep.onChange = { [weak self] in self?.publishSleep() }
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
            var context = session.applicationContext
            context["ledger"] = data
            if let sleep = sleep.payload() { context["sleep"] = sleep }
            try session.updateApplicationContext(context)
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
    private func publishSleep(sendImmediately: Bool = false) {
        guard let session, session.activationState == .activated else { return }
#if os(iOS)
        hasWatch = session.isPaired && session.isWatchAppInstalled
        guard hasWatch else { return }
#else
        guard session.isCompanionAppInstalled else { return }
#endif
        guard let data = sleep.payload() else { return }
        var context = session.applicationContext
        let updated = context["sleep"] as? Data != data
        if updated {
            context["sleep"] = data
            try? session.updateApplicationContext(context)
        }
#if os(iOS) && !targetEnvironment(simulator)
        if let id = sleep.pending?.id, id != lastTransferredAlarm {
            lastTransferredAlarm = id
            session.transferUserInfo(["sleep": data])
        }
#endif
        if session.isReachable && (updated || sendImmediately) {
            session.sendMessage(["sleep": data], replyHandler: { _ in }, errorHandler: { _ in })
        }
    }
    private func receive(_ message: [String: Any]) -> Bool {
        if let data = message["sleep"] as? Data { sleep.receive(data) }
#if os(watchOS)
        applyWristRequest()
#endif
        guard let data = message["ledger"] as? Data, data.count < 60_000, let store else { return false }
        do {
            try store.merge(data); lastReceivedAt = .now; status = "已接收并保存在本机"; return true
        } catch { status = "收到的记录未能保存，请重试"; return false }
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if error != nil { self.status = "连接暂不可用，记录保存在本机"; return }
            self.publishSleep()
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
#if os(watchOS)
    func applyWristRequest() {
        if let request = sleep.pending { WristAlarm.shared.apply(request, fromPhone: true) }
    }

    func finishBackgroundDelivery() async {
        guard let session else { return }
        for _ in 0..<30 {
            if session.activationState == .activated {
                _ = receive(session.receivedApplicationContext)
                if !session.hasContentPending, !WristAlarm.shared.pending { return }
            }
            try? await Task.sleep(for: .milliseconds(200))
            if Task.isCancelled { return }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        Task { @MainActor [weak self] in _ = self?.receive(userInfo) }
    }
#endif
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in if session.isReachable { self?.publishSleep(sendImmediately: true); self?.publish() } }
    }
#if os(iOS)
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in self?.publishSleep(); self?.publish() }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
#else
    nonisolated func sessionCompanionAppInstalledDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in self?.publishSleep(); self?.publish() }
    }
#endif
}
