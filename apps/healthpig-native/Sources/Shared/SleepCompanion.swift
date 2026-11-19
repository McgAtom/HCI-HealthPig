import Combine
import Foundation

struct SleepPreferences: Codable, Equatable {
    var latest = 540
    var target = 480
    var revision = Date.distantPast

    static let wakeRange = 240...720

    func wakeLimit(now: Date, calendar: Calendar) -> Date? {
        guard let window = SleepSchedule.wakeWindow(now: now, calendar: calendar) else { return nil }
        return SleepSchedule.clockDate(latest, on: window.lowerBound, calendar: calendar)
    }

    func recommend(nights: [SleepSchedule.Night], now: Date, calendar: Calendar) -> SleepSchedule.Proposal? {
        guard let limit = wakeLimit(now: now, calendar: calendar) else { return nil }
        return SleepSchedule.recommend(nights: nights, target: target, latestWake: limit, now: now, calendar: calendar)
    }
}

struct SleepAlarmRequest: Codable, Equatable {
    let date: Date?
    var sent = Date.now
    var id = UUID()
}

struct SleepAlarmReply: Codable, Equatable {
    var requestID: UUID?
    var date: Date?
    var failed = false
    var updated = Date.now
    var commandSent: Date?
    var reminder: Bool?
    var permissionRequired: Bool?
}

private struct SleepProjection: Codable, Equatable {
    let plan: SleepSchedule.Proposal
    let revision: Date
    var generated: Date? = .now
}

private struct SleepCompanionSnapshot: Codable {
    var preferences = SleepPreferences()
    var projection: SleepProjection?
    var phoneProjection: SleepProjection?
    var request: SleepAlarmRequest?
    var alarm: SleepAlarmReply?
}

@MainActor final class SleepCompanion: ObservableObject {
    enum Device {
        case phone, watch

        static var current: Self {
#if os(watchOS)
            .watch
#else
            .phone
#endif
        }
    }

    private let device: Device
    @Published private var snapshot: SleepCompanionSnapshot
    private let defaults: UserDefaults
    private let key = "sleepCompanionV1"
    var onChange: (() -> Void)?

    var preferences: SleepPreferences { snapshot.preferences }
    var alarm: SleepAlarmReply? { snapshot.alarm }
    var pending: SleepAlarmRequest? {
        guard let request = snapshot.request, request.sent > (alarm?.commandSent ?? .distantPast),
              request.id != alarm?.requestID else { return nil }
        if let date = request.date, date <= .now { return nil }
        return request
    }

    init(device: Device = .current, defaults suppliedDefaults: UserDefaults? = nil) {
        self.device = device
        if let suppliedDefaults { defaults = suppliedDefaults }
        else { defaults = Self.appDefaults() }
        if let data = defaults.data(forKey: key),
           let stored = try? JSONDecoder().decode(SleepCompanionSnapshot.self, from: data) {
            snapshot = stored
        } else {
            snapshot = SleepCompanionSnapshot()
            let latest = defaults.integer(forKey: "wellnessWakeMinutes")
            let target = defaults.integer(forKey: "wellnessSleepTarget")
            if SleepPreferences.wakeRange.contains(latest) { snapshot.preferences.latest = latest }
            if SleepSchedule.targetRange.contains(target), target.isMultiple(of: 15) { snapshot.preferences.target = target }
            if device == .phone && (SleepPreferences.wakeRange.contains(latest) || SleepSchedule.targetRange.contains(target)) {
                snapshot.preferences.revision = .distantPast.addingTimeInterval(1)
            }
        }
    }

    private static func appDefaults() -> UserDefaults {
#if DEBUG
        let process = ProcessInfo.processInfo
        if process.arguments.contains("--wellness-ui-test") {
            let suite = process.environment["HEALTHPIG_SLEEP_TEST_SUITE"] ?? "healthpig.sleep-ui"
            if let isolated = UserDefaults(suiteName: suite) { return isolated }
        }
#endif
        return .standard
    }

    func set(latest: Int? = nil, target: Int? = nil) {
        var next = snapshot
        if let latest, SleepPreferences.wakeRange.contains(latest) { next.preferences.latest = latest }
        if let target, SleepSchedule.targetRange.contains(target), target.isMultiple(of: 15) { next.preferences.target = target }
        guard next.preferences != preferences else { return }
        next.preferences.revision = max(.now, preferences.revision.addingTimeInterval(0.001))
        update(next)
    }

    func plan(nights: [SleepSchedule.Night], now: Date, calendar: Calendar) -> SleepSchedule.Proposal? {
        let local = preferences.recommend(nights: nights, now: now, calendar: calendar)
        let peer = valid(device == .watch ? snapshot.phoneProjection : snapshot.projection, now: now, calendar: calendar)
        if let peer {
            let localNights = local?.nightsUsed ?? 0
            if peer.nightsUsed > localNights || (device == .phone && peer.nightsUsed == localNights) { return peer }
        }
        return local
    }

    private func valid(_ projection: SleepProjection?, now: Date, calendar: Calendar) -> SleepSchedule.Proposal? {
        guard let projection, projection.plan.basis != nil, projection.revision == preferences.revision,
              SleepSchedule.wakeWindow(now: now, calendar: calendar)?.contains(projection.plan.wake) == true,
              projection.plan.bedtime.addingTimeInterval(60) > now else { return nil }
        return projection.plan
    }

    func project(_ plan: SleepSchedule.Proposal) {
        let projection = SleepProjection(plan: plan, revision: preferences.revision)
        var next = snapshot
        let old = device == .watch ? snapshot.projection : snapshot.phoneProjection
        if device == .watch { next.projection = projection }
        else { next.phoneProjection = projection }
        guard projection.plan != old?.plan || projection.revision != old?.revision else { return }
        update(next)
    }

    func reply(_ alarm: SleepAlarmReply) {
        var next = snapshot; next.alarm = alarm; update(next)
    }

    func request(_ date: Date?) {
        var next = snapshot
        next.request = SleepAlarmRequest(date: date)
        update(next)
    }

    func payload() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try? encoder.encode(snapshot)
    }

    func receive(_ data: Data) {
        guard data.count < 8192, let other = try? JSONDecoder().decode(SleepCompanionSnapshot.self, from: data) else { return }
        var next = snapshot
        var changed = false
        if other.preferences.revision > preferences.revision,
           SleepPreferences.wakeRange.contains(other.preferences.latest),
           SleepSchedule.targetRange.contains(other.preferences.target),
           other.preferences.target.isMultiple(of: 15) {
            next.preferences = other.preferences; changed = true
        }
        if device == .watch {
            if let projection = other.phoneProjection, projection.revision == next.preferences.revision,
               (projection.generated ?? .distantPast) > (next.phoneProjection?.generated ?? .distantPast) {
                next.phoneProjection = projection; changed = true
            }
            if let request = other.request, request.sent > (snapshot.request?.sent ?? .distantPast) {
                next.request = request; changed = true
            }
        } else {
            if let projection = other.projection, projection.revision == next.preferences.revision,
               (projection.generated ?? .distantPast) > (next.projection?.generated ?? .distantPast) {
                next.projection = projection; changed = true
            }
            if let alarm = other.alarm, alarm.updated > (next.alarm?.updated ?? .distantPast) {
                next.alarm = alarm; changed = true
            }
        }
        if changed { update(next) }
    }

    private func update(_ next: SleepCompanionSnapshot) {
        guard let data = try? JSONEncoder().encode(next) else { return }
        defaults.set(data, forKey: key)
        snapshot = next
        onChange?()
    }
}
