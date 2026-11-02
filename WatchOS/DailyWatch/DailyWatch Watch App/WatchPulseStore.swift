import Foundation
import SwiftUI
import Combine

public struct WatchPulseSnapshot: Codable, Equatable {
    public var localDate: String
    public var syncedAtEpoch: TimeInterval

    // Sleep & Recovery
    public var hasSleepData: Bool
    public var sleepScore: Int
    public var sleepDurationFormatted: String
    public var readinessHeadline: String
    public var readinessStatus: String
    public var sleepNarrative: String
    public var sleepSourceDevice: String?
    public var restingHrText: String
    public var hrvText: String
    public var deepFraction: Double
    public var remFraction: Double
    public var lightFraction: Double
    public var awakeFraction: Double
    public var readinessScore: Int?

    // Autonomic Stress (Engine v2.0)
    public var hasStressData: Bool
    public var stressScore: Int
    public var stressBadgeText: String
    public var stressLevel: String
    public var stressHeadline: String
    public var monkeyMoodText: String
    public var stepsText: String
    public var parasympatheticPercent: Int
    public var parasympatheticText: String
    public var adviceQuote: String
    public var recommendedBreathing: String

    public static func empty(for dateStr: String) -> WatchPulseSnapshot {
        WatchPulseSnapshot(
            localDate: dateStr,
            syncedAtEpoch: 0,
            hasSleepData: false,
            sleepScore: 0,
            sleepDurationFormatted: "--",
            readinessHeadline: "Awaiting Sleep Sync",
            readinessStatus: "Pending",
            sleepNarrative: "Tap Pulse Studio or open Daily on phone to sync recovery.",
            sleepSourceDevice: nil,
            restingHrText: "RHR: -- bpm",
            hrvText: "HRV: -- ms",
            deepFraction: 0.22,
            remFraction: 0.23,
            lightFraction: 0.47,
            awakeFraction: 0.08,
            readinessScore: nil,
            hasStressData: false,
            stressScore: 0,
            stressBadgeText: "--/100",
            stressLevel: "Calm",
            stressHeadline: "Calibrating Tone",
            monkeyMoodText: "MonkeyMood: Zen Monkey",
            stepsText: "-- steps",
            parasympatheticPercent: 0,
            parasympatheticText: "Parasym: --%",
            adviceQuote: "Syncing autonomic balance from your wearables.",
            recommendedBreathing: "Physiological Sigh"
        )
    }
}

public final class WatchPulseStore: ObservableObject {
    public static let shared = WatchPulseStore()

    @Published public private(set) var snapshot: WatchPulseSnapshot
    @Published public private(set) var isSyncing: Bool = false

    private let cacheKey = "watch_pulse_studio_cache_v2"
    private let lastSyncTsKey = "watch_pulse_last_sync_ts_v2"
    private let groupSuiteName = "group.com.intellidream.daily"

    // 10-minute smartwatch battery & network TTL policy
    private let cacheTTLSeconds: TimeInterval = 600
    // Retry sooner (2 min) if today's sleep hasn't arrived yet in the morning
    private let missingDataRetrySeconds: TimeInterval = 120
    // Recompute server summary via health-engine if summary is > 15 minutes old
    private let serverSummaryMaxAgeSeconds: TimeInterval = 900

    private static let localDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = Calendar.current.timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let stepsFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    private var defaults: UserDefaults {
        UserDefaults(suiteName: groupSuiteName) ?? UserDefaults.standard
    }

    private init() {
        let todayStr = Self.currentLocalDateString()
        let groupDefaults = UserDefaults(suiteName: "group.com.intellidream.daily") ?? UserDefaults.standard
        if let data = groupDefaults.data(forKey: "watch_pulse_studio_cache_v2") ?? UserDefaults.standard.data(forKey: "watch_pulse_studio_cache_v2"),
           let decoded = try? JSONDecoder().decode(WatchPulseSnapshot.self, from: data) {
            self.snapshot = decoded
        } else {
            self.snapshot = WatchPulseSnapshot.empty(for: todayStr)
        }
    }

    private static func currentLocalDateString() -> String {
        localDateFormatter.timeZone = Calendar.current.timeZone
        return localDateFormatter.string(from: Date())
    }

    // MARK: - Cloud Refresh (Throttled 10m TTL + Explicit Force Support)

    public func fetchPulseData(force: Bool = false) async {
        guard !isSyncing else { return }

        let now = Date()
        let nowEpoch = now.timeIntervalSince1970
        let todayStr = Self.currentLocalDateString()
        let lastSyncEpoch = defaults.double(forKey: lastSyncTsKey)

        let isNewDay = snapshot.localDate != todayStr
        let neverSynced = lastSyncEpoch <= 0 || (!snapshot.hasSleepData && !snapshot.hasStressData)
        let ttlExpired = (nowEpoch - lastSyncEpoch) >= cacheTTLSeconds
        let missingSleepRetry = !snapshot.hasSleepData && (nowEpoch - lastSyncEpoch) >= missingDataRetrySeconds

        if !force && !isNewDay && !neverSynced && !ttlExpired && !missingSleepRetry {
            return
        }

        let session = WatchSessionManager.shared
        let token = session.activeAccessToken
            ?? KeychainHelper.shared.get(key: "supabase_access_token")
            ?? defaults.string(forKey: "supabase_access_token")
            ?? UserDefaults.standard.string(forKey: "supabase_access_token")

        guard let accessToken = token, !accessToken.isEmpty else { return }
        let userUUID = session.currentUserId ?? session.extractUserId(from: accessToken)
        guard let userId = userUUID?.uuidString.lowercased() else { return }

        isSyncing = true
        defer {
            isSyncing = false
        }

        // 1. Push any fresh watchOS HealthKit vitals/HR/sleep (honoring 10m throttle unless forced)
        let didPushWatchKit = await HealthTelemetryManager.shared.syncTelemetry(
            isDeepSync: force,
            force: force
        )

        // 2. Query canonical health_daily_summary for today
        var summaryRowJson = await fetchSummaryRowFromRest(
            supabaseUrl: session.supabaseUrl,
            anonKey: session.supabaseAnonKey,
            accessToken: accessToken,
            userId: userId,
            dateStr: todayStr
        )

        // 3. Determine whether server-side Stress v2.0 + Sleep recomputation is needed
        let needsEngineRecompute = shouldInvokeHealthEngine(
            row: summaryRowJson,
            force: force,
            didPushWatchKit: didPushWatchKit,
            now: now
        )

        if needsEngineRecompute {
            if let recomputedRow = await invokeHealthEngine(
                supabaseUrl: session.supabaseUrl,
                anonKey: session.supabaseAnonKey,
                accessToken: accessToken,
                userId: userId,
                dateStr: todayStr
            ) {
                summaryRowJson = recomputedRow
            } else if summaryRowJson == nil {
                summaryRowJson = await fetchSummaryRowFromRest(
                    supabaseUrl: session.supabaseUrl,
                    anonKey: session.supabaseAnonKey,
                    accessToken: accessToken,
                    userId: userId,
                    dateStr: todayStr
                )
            }
        }

        if let validRow = summaryRowJson {
            let parsed = buildSnapshot(from: validRow, fallbackDate: todayStr, syncedAt: nowEpoch)
            self.snapshot = parsed
            persistSnapshot(parsed, syncedAt: nowEpoch)
        } else if snapshot.localDate != todayStr {
            let emptyToday = WatchPulseSnapshot.empty(for: todayStr)
            self.snapshot = emptyToday
            defaults.set(nowEpoch, forKey: lastSyncTsKey)
        }
    }

    // MARK: - Network Helpers

    private func fetchSummaryRowFromRest(
        supabaseUrl: URL,
        anonKey: String,
        accessToken: String,
        userId: String,
        dateStr: String
    ) async -> [String: Any]? {
        guard var components = URLComponents(
            url: supabaseUrl.appendingPathComponent("rest/v1/health_daily_summary"),
            resolvingAgainstBaseURL: false
        ) else { return nil }

        components.queryItems = [
            URLQueryItem(name: "user_id", value: "eq.\(userId)"),
            URLQueryItem(name: "local_date", value: "eq.\(dateStr)"),
            URLQueryItem(
                name: "select",
                value: "local_date,computed_at,engine_version,steps,active_kcal,sleep_asleep_s,sleep_score,stress_avg,rhr,hrv_sdnn,hrv_rmssd,spo2,summary"
            ),
            URLQueryItem(name: "limit", value: "1")
        ]
        guard let url = components.url else { return nil }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 12
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return nil
            }
            return array.first
        } catch {
            return nil
        }
    }

    private func invokeHealthEngine(
        supabaseUrl: URL,
        anonKey: String,
        accessToken: String,
        userId: String,
        dateStr: String
    ) async -> [String: Any]? {
        let url = supabaseUrl.appendingPathComponent("functions/v1/health-engine")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let tzOffsetMin = Calendar.current.timeZone.secondsFromGMT() / 60
        let payload: [String: Any] = [
            "user_id": userId,
            "date": dateStr,
            "tz_offset_min": tzOffsetMin == 0 ? 120 : tzOffsetMin
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let summaryRow = root["summary"] as? [String: Any] else {
                return nil
            }
            return summaryRow
        } catch {
            return nil
        }
    }

    private func shouldInvokeHealthEngine(
        row: [String: Any]?,
        force: Bool,
        didPushWatchKit: Bool,
        now: Date
    ) -> Bool {
        if force || didPushWatchKit { return true }
        guard let row = row else { return true }

        let version = row["engine_version"] as? String ?? ""
        if version != "v2.0" { return true }

        if let computedStr = row["computed_at"] as? String,
           let computedDate = parseIsoDate(computedStr) {
            if now.timeIntervalSince(computedDate) > serverSummaryMaxAgeSeconds {
                return true
            }
        } else {
            return true
        }
        return false
    }

    private func parseIsoDate(_ raw: String) -> Date? {
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = isoFrac.date(from: raw) { return d }
        let isoPlain = ISO8601DateFormatter()
        if let d = isoPlain.date(from: raw) { return d }

        let sqlFmt = DateFormatter()
        sqlFmt.locale = Locale(identifier: "en_US_POSIX")
        sqlFmt.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSX"
        if let d = sqlFmt.date(from: raw) { return d }
        sqlFmt.dateFormat = "yyyy-MM-dd HH:mm:ssX"
        return sqlFmt.date(from: raw)
    }

    // MARK: - Deterministic v2.0 Snapshot Builder

    private func buildSnapshot(
        from row: [String: Any],
        fallbackDate: String,
        syncedAt: TimeInterval
    ) -> WatchPulseSnapshot {
        let localDate = (row["local_date"] as? String) ?? fallbackDate
        let summaryObj = row["summary"] as? [String: Any] ?? [:]

        // --- Sleep & Recovery ---
        let sleepContainer = summaryObj["sleep"] as? [String: Any] ?? [:]
        let primarySession = sleepContainer["primary_session"] as? [String: Any]
        let guidanceObj = sleepContainer["guidance"] as? [String: Any]
        let verdictObj = guidanceObj?["verdict"] as? [String: Any]

        let asleepSeconds = Self.intVal(primarySession?["asleep_seconds"])
            ?? Self.intVal(row["sleep_asleep_s"])
            ?? 0
        let sleepScore = Self.intVal(primarySession?["sleep_score"])
            ?? Self.intVal(row["sleep_score"])
            ?? 0
        let hasSleepData = asleepSeconds > 0 && sleepScore > 0

        let sleepDurationFormatted: String
        if asleepSeconds > 0 {
            let h = asleepSeconds / 3600
            let m = (asleepSeconds % 3600) / 60
            sleepDurationFormatted = h > 0 ? "\(h)h \(m)m" : "\(m)m"
        } else {
            sleepDurationFormatted = "--"
        }

        let readinessScore = Self.intVal(verdictObj?["readiness_score"])
        let verdictStatus = (verdictObj?["status"] as? String)
            ?? (primarySession?["quality_rating"] as? String)
            ?? (hasSleepData ? (sleepScore >= 85 ? "Optimal" : (sleepScore >= 75 ? "Good" : "Fair")) : "Pending")

        let readinessHeadline: String
        if !hasSleepData {
            readinessHeadline = "Awaiting Sleep Sync"
        } else if let rScore = readinessScore, rScore > 0 {
            readinessHeadline = "Readiness \(rScore) • \(verdictStatus)"
        } else {
            readinessHeadline = "\(verdictStatus) Recovery"
        }

        let rawNarrative = (verdictObj?["narrative"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let sleepNarrative: String
        if let narrative = rawNarrative, !narrative.isEmpty, hasSleepData {
            sleepNarrative = narrative
        } else if hasSleepData {
            let eff = Self.intVal(primarySession?["efficiency_percent"]) ?? 90
            let restPct = Self.intVal(primarySession?["restorative_percent"]) ?? 25
            sleepNarrative = "Efficiency \(eff)% • \(restPct)% restorative stages."
        } else {
            sleepNarrative = "Wear watch or ring overnight to populate recovery."
        }

        let sleepSourceDevice = primarySession?["source_device"] as? String

        let deepS = Double(Self.intVal(primarySession?["deep_seconds"]) ?? 0)
        let remS = Double(Self.intVal(primarySession?["rem_seconds"]) ?? 0)
        let lightS = Double(Self.intVal(primarySession?["light_seconds"]) ?? 0)
        let awakeS = Double(Self.intVal(primarySession?["awake_seconds"]) ?? 0)
        let stageTotal = deepS + remS + lightS + awakeS

        let deepFrac: Double
        let remFrac: Double
        let lightFrac: Double
        let awakeFrac: Double
        if stageTotal > 0 {
            let rDeep = max(0.03, deepS / stageTotal)
            let rRem = max(0.03, remS / stageTotal)
            let rLight = max(0.03, lightS / stageTotal)
            let rAwake = max(0.02, awakeS / stageTotal)
            let sum = rDeep + rRem + rLight + rAwake
            deepFrac = rDeep / sum
            remFrac = rRem / sum
            lightFrac = rLight / sum
            awakeFrac = rAwake / sum
        } else {
            deepFrac = 0.22
            remFrac = 0.23
            lightFrac = 0.47
            awakeFrac = 0.08
        }

        // --- Cardiovascular & Vitals ---
        let cardioObj = summaryObj["cardiovascular"] as? [String: Any]
        let stressObj = summaryObj["stress"] as? [String: Any]

        let rhrVal = Self.doubleVal(row["rhr"])
            ?? Self.doubleVal(cardioObj?["resting_bpm"])
            ?? Self.doubleVal(stressObj?["resting_heart_rate_bpm"])
        let restingHrText: String
        if let r = rhrVal, r > 0 {
            restingHrText = "RHR: \(Int(round(r))) bpm"
        } else {
            restingHrText = "RHR: -- bpm"
        }

        let hrvVal = Self.doubleVal(stressObj?["current_hrv_ms"])
            ?? Self.doubleVal(row["hrv_rmssd"])
            ?? Self.doubleVal(row["hrv_sdnn"])
        let hrvText: String
        if let h = hrvVal, h > 0 {
            hrvText = "HRV: \(Int(round(h))) ms"
        } else {
            hrvText = "HRV: -- ms"
        }

        // --- Autonomic Stress (Engine v2.0) ---
        let currentStressScore = Self.intVal(stressObj?["current_score"])
            ?? Self.intVal(row["stress_avg"])
        let hasStressData = (currentStressScore != nil)
        let finalStressScore = max(0, min(100, currentStressScore ?? 0))
        let stressBadgeText = hasStressData ? "\(finalStressScore)/100" : "--/100"

        let rawLevel = (stressObj?["current_level"] as? String)
            ?? Self.levelFromScore(finalStressScore)
        let dailyAvg = Self.intVal(stressObj?["daily_average"])
            ?? Self.intVal(row["stress_avg"])
            ?? finalStressScore

        let stressHeadline: String
        if !hasStressData {
            stressHeadline = "Calibrating Tone"
        } else if dailyAvg > 0 && dailyAvg != finalStressScore {
            stressHeadline = "\(rawLevel) • Avg \(dailyAvg)"
        } else {
            stressHeadline = "\(rawLevel) Tone"
        }

        let moodRaw = (stressObj?["monkey_mood"] as? String)
            ?? Self.moodFromScore(finalStressScore)
        let monkeyMoodText = moodRaw

        let activityObj = summaryObj["activity"] as? [String: Any]
        let totalSteps = Self.intVal(row["steps"])
            ?? Self.intVal(activityObj?["total_steps"])
            ?? 0
        let formattedSteps = Self.stepsFormatter.string(from: NSNumber(value: totalSteps)) ?? "\(totalSteps)"
        let stepsText = "\(formattedSteps) steps"

        let parasym = Self.intVal(stressObj?["parasympathetic_percent"])
            ?? (hasStressData ? max(0, min(100, 100 - finalStressScore)) : 0)
        let parasympatheticText = hasStressData ? "Parasym: \(parasym)%" : "Parasym: --%"

        let adviceQuote = (stressObj?["advice_quote"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "Autonomic tone is steady. Stay hydrated and pace calmly."
        let recommendedBreathing = (stressObj?["recommended_breathing"] as? String)
            ?? "Physiological Sigh"

        return WatchPulseSnapshot(
            localDate: localDate,
            syncedAtEpoch: syncedAt,
            hasSleepData: hasSleepData,
            sleepScore: sleepScore,
            sleepDurationFormatted: sleepDurationFormatted,
            readinessHeadline: readinessHeadline,
            readinessStatus: verdictStatus,
            sleepNarrative: sleepNarrative,
            sleepSourceDevice: sleepSourceDevice,
            restingHrText: restingHrText,
            hrvText: hrvText,
            deepFraction: deepFrac,
            remFraction: remFrac,
            lightFraction: lightFrac,
            awakeFraction: awakeFrac,
            readinessScore: readinessScore,
            hasStressData: hasStressData,
            stressScore: finalStressScore,
            stressBadgeText: stressBadgeText,
            stressLevel: rawLevel,
            stressHeadline: stressHeadline,
            monkeyMoodText: monkeyMoodText,
            stepsText: stepsText,
            parasympatheticPercent: parasym,
            parasympatheticText: parasympatheticText,
            adviceQuote: adviceQuote,
            recommendedBreathing: recommendedBreathing
        )
    }

    private func persistSnapshot(_ snap: WatchPulseSnapshot, syncedAt: TimeInterval) {
        if let encoded = try? JSONEncoder().encode(snap) {
            defaults.set(encoded, forKey: cacheKey)
            UserDefaults.standard.set(encoded, forKey: cacheKey)
        }
        defaults.set(syncedAt, forKey: lastSyncTsKey)
        UserDefaults.standard.set(syncedAt, forKey: lastSyncTsKey)

        // Keep legacy App Group sleep widget snapshot synchronized
        if snap.hasSleepData {
            let widgetDict: [String: Any] = [
                "sleepScore": snap.sleepScore,
                "totalAsleepFormatted": snap.sleepDurationFormatted,
                "updatedAt": syncedAt
            ]
            if let widgetData = try? JSONSerialization.data(withJSONObject: widgetDict) {
                defaults.set(widgetData, forKey: "daily_sleep_widget_snapshot_v1")
            }
        }
    }

    // MARK: - Primitive JSON Helpers

    private static func intVal(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let d = any as? Double { return Int(round(d)) }
        if let n = any as? NSNumber { return Int(round(n.doubleValue)) }
        if let s = any as? String, let d = Double(s) { return Int(round(d)) }
        return nil
    }

    private static func doubleVal(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let n = any as? NSNumber { return n.doubleValue }
        if let s = any as? String, let d = Double(s) { return d }
        return nil
    }

    private static func levelFromScore(_ score: Int) -> String {
        if score <= 25 { return "Restful" }
        if score <= 50 { return "Calm" }
        if score <= 75 { return "Moderate" }
        return "High"
    }

    private static func moodFromScore(_ score: Int) -> String {
        if score <= 25 { return "Zen Monkey" }
        if score <= 50 { return "Curious Monkey" }
        if score <= 75 { return "Busy Monkey" }
        return "Overheated Monkey"
    }
}
