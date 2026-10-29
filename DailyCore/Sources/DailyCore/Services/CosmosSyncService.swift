import Foundation
import Combine
import Supabase
#if canImport(UserNotifications)
import UserNotifications
#endif

/// Offline-first + Supabase cloud sync service for Cosmos Bookmarks, Sky Observations,
/// 1-tap TagDoS `#sky` note mirroring, and opt-in local astronomical alerts.
@MainActor
public final class CosmosSyncService: ObservableObject {
    public static let shared = CosmosSyncService()

    @Published public private(set) var bookmarks: [CosmosBookmark] = []
    @Published public private(set) var observations: [CosmosObservation] = []
    @Published public private(set) var isSyncing: Bool = false

    private let bookmarksStorageKey = "daily_cosmos_bookmarks_v1"
    private let observationsStorageKey = "daily_cosmos_observations_v1"

    private var defaults: UserDefaults {
        UserDefaults(suiteName: GroupDefaults.suiteName) ?? .standard
    }

    private init() {
        loadFromLocalStorage()
        Task {
            await syncWithSupabase()
        }
    }

    // MARK: - Local Persistence

    private func loadFromLocalStorage() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let bData = defaults.data(forKey: bookmarksStorageKey),
           let decoded = try? decoder.decode([CosmosBookmark].self, from: bData) {
            self.bookmarks = decoded
        }
        if let oData = defaults.data(forKey: observationsStorageKey),
           let decoded = try? decoder.decode([CosmosObservation].self, from: oData) {
            self.observations = decoded
        }
    }

    private func saveToLocalStorage() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let bData = try? encoder.encode(bookmarks) {
            defaults.set(bData, forKey: bookmarksStorageKey)
        }
        if let oData = try? encoder.encode(observations) {
            defaults.set(oData, forKey: observationsStorageKey)
        }
    }

    private func effectiveUserIdAsync() async -> String? {
        if let id = AuthService.shared.currentUser?.id, id != "guest" {
            return id.lowercased()
        }
        if let stored = GroupDefaults.shared.userDefaults.string(forKey: "supabase_user_id"), stored != "guest" {
            return stored.lowercased()
        }
        if let session = try? await SupabaseService.shared.client.auth.session {
            let uid = session.user.id.uuidString.lowercased()
            if uid != "guest" { return uid }
        }
        return nil
    }

    // MARK: - Bookmark Mutations

    public func isBookmarked(objectId: String) -> Bool {
        bookmarks.contains { $0.objectId.caseInsensitiveCompare(objectId) == .orderedSame }
    }

    public func toggleBookmark(
        objectId: String,
        objectName: String,
        category: String,
        raHours: Double? = nil,
        decDeg: Double? = nil,
        magnitude: Double? = nil,
        constellation: String? = nil,
        notes: String = ""
    ) {
        if let idx = bookmarks.firstIndex(where: { $0.objectId.caseInsensitiveCompare(objectId) == .orderedSame }) {
            let removed = bookmarks.remove(at: idx)
            saveToLocalStorage()
            Task { await deleteRemoteBookmark(removed) }
        } else {
            let bookmark = CosmosBookmark(
                userId: AuthService.shared.currentUser?.id,
                objectId: objectId,
                objectName: objectName,
                category: category,
                raHours: raHours,
                decDeg: decDeg,
                magnitude: magnitude,
                constellation: constellation,
                notes: notes
            )
            bookmarks.insert(bookmark, at: 0)
            saveToLocalStorage()
            Task { await pushBookmarkToSupabase(bookmark) }
        }
    }

    // MARK: - Sky Sighting Logger (+ TagDoS #sky Mirror)

    @discardableResult
    public func logSighting(
        objectId: String,
        objectName: String,
        category: String,
        latitude: Double,
        longitude: Double,
        locationName: String,
        azimuthDeg: Double?,
        altitudeDeg: Double?,
        bortleClass: Int?,
        stargazingScore: Int?,
        optics: String = "Naked Eye",
        notes: String = "",
        mirrorToTagdos: Bool = true
    ) -> CosmosObservation {
        let now = Date()
        var createdTagdosId: UUID? = nil

        if mirrorToTagdos {
            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .short
            var lines: [String] = [
                "Observed \(objectName) (\(category)) on \(df.string(from: now))",
                "Location: \(locationName.isEmpty ? String(format: "%.3f°, %.3f°", latitude, longitude) : locationName)"
            ]
            if let az = azimuthDeg, let alt = altitudeDeg {
                lines.append(String(format: "Sky Position: Az %.1f° (%@) • Alt %.1f°", az, CelestialCoordinates.compassPoint(for: az), alt))
            }
            if let b = bortleClass, let sc = stargazingScore {
                lines.append("Conditions: Sky Score \(sc)/100 • Bortle \(b) • Optics: \(optics)")
            } else {
                lines.append("Optics: \(optics)")
            }
            if !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append("Notes: \(notes)")
            }
            lines.append("#sky #cosmos")

            let quickNote = TagdosStore.shared.createQuickNote(
                title: "🌌 Sky Sighting: \(objectName)",
                content: lines.joined(separator: "\n"),
                tags: ["sky", "cosmos"]
            )
            createdTagdosId = quickNote.id
        }

        let obs = CosmosObservation(
            userId: AuthService.shared.currentUser?.id,
            objectId: objectId,
            objectName: objectName,
            category: category,
            observedAt: now,
            latitude: latitude,
            longitude: longitude,
            locationName: locationName,
            azimuthDeg: azimuthDeg,
            altitudeDeg: altitudeDeg,
            bortleClass: bortleClass,
            stargazingScore: stargazingScore,
            optics: optics,
            notes: notes,
            tagdosNoteId: createdTagdosId,
            createdAt: now,
            updatedAt: now
        )
        observations.insert(obs, at: 0)
        saveToLocalStorage()

        Task {
            await pushObservationToSupabase(obs)
        }
        return obs
    }

    // MARK: - Supabase Cloud Sync

    public func syncWithSupabase() async {
        guard SettingsService.shared.settings.cloudSyncEnabled,
              let userId = await effectiveUserIdAsync() else { return }

        isSyncing = true
        defer { isSyncing = false }

        let client = SupabaseService.shared.client
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let resBookmarks = try await client
                .from("cosmos_bookmarks")
                .select()
                .eq("user_id", value: userId)
                .order("updated_at", ascending: false)
                .execute()

            if let remoteBookmarks = try? decoder.decode([CosmosBookmark].self, from: resBookmarks.data) {
                var merged = self.bookmarks
                for rb in remoteBookmarks {
                    if let idx = merged.firstIndex(where: { $0.objectId == rb.objectId }) {
                        if rb.updatedAt >= merged[idx].updatedAt {
                            merged[idx] = rb
                        }
                    } else {
                        merged.append(rb)
                    }
                }
                self.bookmarks = merged.sorted { $0.updatedAt > $1.updatedAt }
            }

            let resObs = try await client
                .from("cosmos_observations")
                .select()
                .eq("user_id", value: userId)
                .order("observed_at", ascending: false)
                .limit(100)
                .execute()

            if let remoteObs = try? decoder.decode([CosmosObservation].self, from: resObs.data) {
                var mergedObs = self.observations
                for ro in remoteObs {
                    if let idx = mergedObs.firstIndex(where: { $0.id == ro.id }) {
                        if ro.updatedAt >= mergedObs[idx].updatedAt {
                            mergedObs[idx] = ro
                        }
                    } else {
                        mergedObs.append(ro)
                    }
                }
                self.observations = mergedObs.sorted { $0.observedAt > $1.observedAt }
            }

            saveToLocalStorage()
        } catch {
            // Gracefully stay offline if migration hasn't been applied on remote yet or network is offline
        }
    }

    private func pushBookmarkToSupabase(_ item: CosmosBookmark) async {
        guard SettingsService.shared.settings.cloudSyncEnabled,
              let userId = await effectiveUserIdAsync() else { return }
        var payload = item
        payload.userId = userId
        _ = try? await SupabaseService.shared.client
            .from("cosmos_bookmarks")
            .upsert(payload, onConflict: "user_id,object_id")
            .execute()
    }

    private func deleteRemoteBookmark(_ item: CosmosBookmark) async {
        guard SettingsService.shared.settings.cloudSyncEnabled,
              let userId = await effectiveUserIdAsync() else { return }
        _ = try? await SupabaseService.shared.client
            .from("cosmos_bookmarks")
            .delete()
            .eq("user_id", value: userId)
            .eq("object_id", value: item.objectId)
            .execute()
    }

    public func deleteObservation(id: UUID) {
        if let idx = observations.firstIndex(where: { $0.id == id }) {
            let removed = observations.remove(at: idx)
            saveToLocalStorage()
            Task { await deleteRemoteObservation(removed) }
        }
    }

    private func deleteRemoteObservation(_ item: CosmosObservation) async {
        guard SettingsService.shared.settings.cloudSyncEnabled,
              let userId = await effectiveUserIdAsync() else { return }
        _ = try? await SupabaseService.shared.client
            .from("cosmos_observations")
            .delete()
            .eq("user_id", value: userId)
            .eq("id", value: item.id.uuidString.lowercased())
            .execute()
    }

    private func pushObservationToSupabase(_ item: CosmosObservation) async {
        guard SettingsService.shared.settings.cloudSyncEnabled,
              let userId = await effectiveUserIdAsync() else { return }
        var payload = item
        payload.userId = userId
        _ = try? await SupabaseService.shared.client
            .from("cosmos_observations")
            .upsert(payload)
            .execute()
    }

    // MARK: - Opt-In Local Astronomical Notifications (ISS, Aurora Kp, Pristine Sky)

    public func evaluateOptInSkyAlerts(
        stargazing: StargazingConditions?,
        passes: [SatellitePass],
        spaceWeather: SpaceWeatherReport?
    ) async {
        #if canImport(UserNotifications)
        let settings = SettingsService.shared.settings
        guard settings.cosmosNotifyIssPasses || settings.cosmosNotifyAurora || settings.cosmosNotifyPristineSky else {
            return
        }

        // Guard against running inside unbundled xctest processes where Bundle.main has no bundleIdentifier
        guard Bundle.main.bundleIdentifier != nil else { return }

        let center = UNUserNotificationCenter.current()
        let auth = await center.notificationSettings()
        if auth.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        let refreshedAuth = await center.notificationSettings()
        guard refreshedAuth.authorizationStatus == .authorized || refreshedAuth.authorizationStatus == .provisional else {
            return
        }

        let cloudPct = stargazing?.cloudCoverTotalPercent ?? 20

        // 1. Bright ISS Pass Alert (15 min before pass if peak >= 40° and clouds < 35%)
        if settings.cosmosNotifyIssPasses && cloudPct < 35 {
            if let brightPass = passes.first(where: {
                $0.maxAltitudeDegrees >= 40.0
                    && $0.peakMagnitude <= -2.0
                    && $0.startTime.timeIntervalSinceNow > 960
                    && $0.startTime.timeIntervalSinceNow < 86400
            }) {
                let fireDate = brightPass.startTime.addingTimeInterval(-900)
                let content = UNMutableNotificationContent()
                content.title = "🛰️ Bright ISS Pass in 15 Minutes"
                content.body = String(
                    format: "%@ rises %@ and peaks at %.0f° (%+.1f mag).",
                    brightPass.satelliteName,
                    brightPass.startCompass,
                    brightPass.maxAltitudeDegrees,
                    brightPass.peakMagnitude
                )
                content.sound = .default
                let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate)
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                let req = UNNotificationRequest(identifier: "daily.cosmos.iss.\(brightPass.id)", content: content, trigger: trigger)
                try? await center.add(req)
            }
        }

        // 2. Geomagnetic / Aurora Alert (Kp >= 5 or Bz <= -7)
        if settings.cosmosNotifyAurora, let sw = spaceWeather, sw.isAuroraAlertActive {
            let content = UNMutableNotificationContent()
            content.title = "🌌 Geomagnetic Storm Alert"
            content.body = sw.statusMessage
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
            let dayStamp = ISO8601DateFormatter().string(from: Date()).prefix(10)
            let req = UNNotificationRequest(identifier: "daily.cosmos.aurora.\(dayStamp)", content: content, trigger: trigger)
            try? await center.add(req)
        }

        // 3. Pristine Sky Alert (Score >= 85)
        if settings.cosmosNotifyPristineSky, let sg = stargazing, sg.score >= 85 {
            let content = UNMutableNotificationContent()
            content.title = "✨ Pristine Stargazing Tonight (\(sg.score)/100)"
            content.body = "Optimal dark window: \(sg.bestWindowDescription ?? "Tonight") • Bortle \(sg.bortleClass)."
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false)
            let dayStamp = ISO8601DateFormatter().string(from: Date()).prefix(10)
            let req = UNNotificationRequest(identifier: "daily.cosmos.pristine.\(dayStamp)", content: content, trigger: trigger)
            try? await center.add(req)
        }
        #endif
    }
}
