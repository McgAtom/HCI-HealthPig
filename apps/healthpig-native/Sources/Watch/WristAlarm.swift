import SwiftUI
import UserNotifications
import WatchKit

@MainActor final class WristAlarm: NSObject, ObservableObject, WKExtendedRuntimeSessionDelegate, UNUserNotificationCenterDelegate {
    static let shared = WristAlarm()
    @Published private(set) var pending = false
    @Published private(set) var ringing = false
    @Published private(set) var notificationAllowed = false
    var onReply: ((SleepAlarmReply) -> Void)?

    private var reply: SleepAlarmReply?
    private var session: WKExtendedRuntimeSession?
    private var request: SleepAlarmRequest?
    private var replacement: (command: SleepAlarmRequest, useReminder: Bool)?
    private var confirmation: Task<Void, Never>?
    private let savedState = "scheduledWristAlarm"
    private let reminderID = "healthpig.wrist-wake"
    private let notifications = UNUserNotificationCenter.current()

    private override init() {
        super.init()
        notifications.delegate = self
        if let data = UserDefaults.standard.data(forKey: savedState) {
            reply = try? JSONDecoder().decode(SleepAlarmReply.self, from: data)
        }
    }

    func refreshNotificationAccess() async {
        let settings = await notifications.notificationSettings()
        notificationAllowed = settings.authorizationStatus == .authorized && settings.alertSetting == .enabled
    }

    func authorizeReminders() async {
        _ = try? await notifications.requestAuthorization(options: [.alert, .sound])
        await refreshNotificationAccess()
    }

    func apply(_ command: SleepAlarmRequest, fromPhone: Bool = false) {
        let active = WKApplication.shared().applicationState == .active
        guard !pending, active || fromPhone else { return }
        let useReminder = !active
        if let date = command.date, date <= .now || date.timeIntervalSinceNow > 36 * 3600 {
            respond(to: command, with: reply?.date, failed: true, reminder: reply?.reminder == true)
            return
        }
        if let session, session.state == .scheduled || session.state == .running {
            if command.date != nil, reply?.date == command.date {
                respond(to: command, with: command.date)
            } else if useReminder, let date = command.date {
                pending = true
                Task { await scheduleReminder(command, at: date) }
            } else {
                pending = true
                replacement = (command, useReminder)
                session.invalidate()
            }
        } else if let date = reply?.date, date > .now, reply?.reminder != true {
            // The native session can be restored by the application delegate after launch.
            respond(to: command, with: date, failed: true)
        } else { start(command, useReminder: useReminder) }
    }

    func restore(_ session: WKExtendedRuntimeSession) {
        self.session = session
        session.delegate = self
        if session.state == .running { ring(session) }
    }

    func stop() { apply(SleepAlarmRequest(date: nil)) }

    private func start(_ command: SleepAlarmRequest, useReminder: Bool) {
        guard let date = command.date else {
            removeReminder()
            respond(to: command, with: nil)
            return
        }
        if useReminder || WKApplication.shared().applicationState != .active {
            pending = true
            Task { await scheduleReminder(command, at: date) }
            return
        }
        let session = WKExtendedRuntimeSession()
        session.delegate = self
        self.session = session; self.request = command; pending = true
        session.start(at: date)
        confirmation = Task { [weak self, weak session] in
            for _ in 0..<25 {
                guard !Task.isCancelled, let self, let session, self.session === session else { return }
                if session.state == .scheduled {
                    self.removeReminder()
                    self.respond(to: command, with: date)
                    return
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
            guard !Task.isCancelled, let self, let session, self.session === session else { return }
            let kept = self.reply?.reminder == true
            self.respond(to: command, with: kept ? self.reply?.date : nil, failed: true, reminder: kept)
        }
    }

    private func scheduleReminder(_ command: SleepAlarmRequest, at date: Date) async {
        let old = reply
        let settings = await notifications.notificationSettings()
        guard settings.authorizationStatus == .authorized, settings.alertSetting == .enabled else {
            respond(to: command, with: old?.date, failed: true, reminder: old?.reminder == true, permissionRequired: true)
            return
        }
        let interval = date.timeIntervalSinceNow
        guard interval > 0 else {
            respond(to: command, with: old?.date, failed: true, reminder: old?.reminder == true)
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "起床"
        content.sound = .default
        if settings.timeSensitiveSetting == .enabled { content.interruptionLevel = .timeSensitive }
        do {
            try await notifications.add(UNNotificationRequest(identifier: reminderID, content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)))
            if let current = session, current.state == .scheduled || current.state == .running {
                session = nil
                confirmation?.cancel()
                current.invalidate()
            }
            respond(to: command, with: date, reminder: true)
        } catch {
            respond(to: command, with: old?.date, failed: true, reminder: old?.reminder == true)
        }
    }

    private func removeReminder() {
        notifications.removePendingNotificationRequests(withIdentifiers: [reminderID])
        notifications.removeDeliveredNotifications(withIdentifiers: [reminderID])
    }

    private func ring(_ session: WKExtendedRuntimeSession) {
        guard !ringing, session.state == .running else { return }
        ringing = true
        confirmation?.cancel()
        pending = false
        session.notifyUser(hapticType: .notification, repeatHandler: nil)
    }

    private func respond(to command: SleepAlarmRequest?, with date: Date?, failed: Bool = false, reminder: Bool = false,
                         permissionRequired: Bool = false) {
        let result = SleepAlarmReply(requestID: command?.id ?? reply?.requestID, date: date, failed: failed,
                                     commandSent: command?.sent ?? reply?.commandSent, reminder: reminder,
                                     permissionRequired: permissionRequired)
        if date != nil, let data = try? JSONEncoder().encode(result) {
            UserDefaults.standard.set(data, forKey: savedState)
        } else { UserDefaults.standard.removeObject(forKey: savedState) }
        reply = result
        pending = false
        onReply?(result)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completion: @escaping (UNNotificationPresentationOptions) -> Void) {
        completion([.banner, .sound])
    }

    nonisolated func extendedRuntimeSessionDidStart(_ session: WKExtendedRuntimeSession) {
        Task { @MainActor [weak self] in
            guard let self, self.session === session else { return }
            self.ring(session)
        }
    }

    nonisolated func extendedRuntimeSessionWillExpire(_ session: WKExtendedRuntimeSession) {}

    nonisolated func extendedRuntimeSession(_ session: WKExtendedRuntimeSession,
                                          didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
                                          error: Error?) {
        Task { @MainActor [weak self] in
            guard let self, self.session === session else { return }
            self.confirmation?.cancel()
            self.session = nil
            self.ringing = false
            if let next = self.replacement {
                self.replacement = nil
                self.start(next.command, useReminder: next.useReminder)
            } else {
                let kept = self.reply?.reminder == true
                self.respond(to: self.request, with: kept ? self.reply?.date : nil,
                             failed: error != nil || reason == .suppressedBySystem, reminder: kept)
            }
        }
    }
}
