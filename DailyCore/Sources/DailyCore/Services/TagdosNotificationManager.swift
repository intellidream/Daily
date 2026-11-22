import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

/// Schedules and updates 100% local repeating daily notifications for TagDoS streams and clusters.
/// Zero background network calls or egress.
public final class TagdosNotificationManager: Sendable {
    public static let shared = TagdosNotificationManager()
    public static let identifierPrefix = "daily.tagdos."

    private init() {}

    /// Requests notification authorization (if undetermined) and reschedules all TagDoS stream & cluster reminders.
    public func requestAuthorizationAndReschedule(streams: [TagDoStream]) {
        #if canImport(UserNotifications)
        guard Bundle.main.bundleIdentifier != nil,
              !Bundle.main.bundlePath.hasSuffix(".appex") else { return }

        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            }
            await applySchedule(streams: streams, center: center)
        }
        #endif
    }

    /// Reschedules TagDoS reminders silently if authorization is already granted.
    public func rescheduleIfAuthorized(streams: [TagDoStream]) {
        #if canImport(UserNotifications)
        guard Bundle.main.bundleIdentifier != nil,
              !Bundle.main.bundlePath.hasSuffix(".appex") else { return }

        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                return
            }
            await applySchedule(streams: streams, center: center)
        }
        #endif
    }

    #if canImport(UserNotifications)
    private func applySchedule(streams: [TagDoStream], center: UNUserNotificationCenter) async {
        let pending = await center.pendingNotificationRequests()
        let oldIds = pending.map(\.identifier).filter { $0.hasPrefix(Self.identifierPrefix) }
        if !oldIds.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: oldIds)
        }

        let calendar = Calendar.current
        for stream in streams {
            // 1. Stream-level daily reminder
            if let remDate = stream.streamReminder {
                let comps = calendar.dateComponents([.hour, .minute], from: remDate)
                if comps.hour != nil, comps.minute != nil {
                    let content = UNMutableNotificationContent()
                    content.title = "TagDoS · \(stream.displayTitle)"
                    if let driving = stream.drivingPill?.rawText {
                        content.body = "Focus now: \(driving) (\(stream.activePills.count) active tags)"
                    } else {
                        content.body = "Check \(stream.displayTitle)"
                    }
                    content.sound = .default
                    content.userInfo = [
                        "deepLink": "daily://tagdos?streamId=\(stream.id.uuidString)"
                    ]
                    let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
                    let req = UNNotificationRequest(
                        identifier: "\(Self.identifierPrefix)stream.\(stream.id.uuidString)",
                        content: content,
                        trigger: trigger
                    )
                    try? await center.add(req)
                }
            }

            // 2. Per-cluster daily reminders
            for (cIdx, cluster) in stream.clusters.enumerated() {
                guard let cRem = cluster.reminderDate else { continue }
                let comps = calendar.dateComponents([.hour, .minute], from: cRem)
                guard comps.hour != nil, comps.minute != nil else { continue }

                let previewTags = (cluster.activePills.isEmpty ? cluster.pills : cluster.activePills)
                    .prefix(4)
                    .map(\.rawText)
                    .joined(separator: " / ")
                let content = UNMutableNotificationContent()
                content.title = "TagDoS · \(stream.displayTitle)"
                content.body = previewTags.isEmpty ? "Cluster reminder" : "Cluster: \(previewTags)"
                content.sound = .default
                content.userInfo = [
                    "deepLink": "daily://tagdos?streamId=\(stream.id.uuidString)&clusterIndex=\(cIdx)"
                ]
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
                let req = UNNotificationRequest(
                    identifier: "\(Self.identifierPrefix)cluster.\(stream.id.uuidString).\(cIdx)",
                    content: content,
                    trigger: trigger
                )
                try? await center.add(req)
            }
        }
    }
    #endif
}
