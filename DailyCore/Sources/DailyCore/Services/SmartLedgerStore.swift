import Foundation
import Combine
import Supabase
#if canImport(WidgetKit)
import WidgetKit
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

/// Manages local persistence, reactive publishing, live re-calculation, and Supabase cloud synchronization
/// for the user's Smart Ledger text document across iOS, macOS, Android, WinUI, and Smartwatches.
@MainActor
public final class SmartLedgerStore: ObservableObject {
    public static let shared = SmartLedgerStore()
    
    // MARK: - Published State
    @Published public private(set) var parsedLedger: ParsedSmartLedger
    @Published public private(set) var rawText: String
    @Published public private(set) var isSyncing: Bool = false
    @Published public private(set) var lastSyncedAt: Date? = nil
    @Published public private(set) var cloudSyncError: String? = nil
    
    // MARK: - Persistence Keys
    private let storageKey = "daily_smart_ledger_raw_text_v1"
    private let localModifiedKey = "daily_smart_ledger_local_modified_at_v1"
    private let serverRecordIdKey = "daily_smart_ledger_server_id_v1"
    
    private var pushDebounceTask: Task<Void, Never>?
    private var realtimeChannel: RealtimeChannelV2?
    
    // MARK: - Default Starter Ledger Template
    nonisolated public static let defaultLedgerText: String = """
    **Incoming**

    ---

    Card = 151 (Rz/141/Ing/10/Rev/0/Mom/9/!!!!/9)

    Cash = 9 (SG-1/A/3M)

    ---

    Total = 160

    ---

    **Outgoing**

    Itp/Rvg/4.27//Ghs/Prk/Csc/Rca/1.27 = 0

    V/N/Y/O/AI/M/W/E/I/Ap/Am/Sy/Ad/Sp = 9

    Rata/Rds/Gaz/Înt/Hid/(45)/Mom/(4) = 49

    Cora/Mega/Bringo/Fresh (Edn/3) = 10

    Tigari (40/45) = 10

    Car/Benzina/Honda (1/4) = 3 (SPL!/CER?)

    Serviciu/(0/*100)/Outs/(0*200) = 0

    Acasa/Tuns/Cadouri = 10 (M&T=5/!!!!!/5)

    Vacante/Noi/Iesiri/Other = 68 (C$40/B$20)

    Subs (APL-21.01-$5/RED-14.03-$1/CSP-29.05-$5)(PRL-11.08-$6/365-25.08-$7/NSK-29.8-$2)(MRG-31.8-$2/STRS-22.09-$1)(EMG-13.12-$1) = 1

    ---

    Total = 160

    ---

    **Balance** 

    ---

    Total = 0

    ---

    **Dentist**

    ---

    (Total = 106)

    ---

    **Deposit**

    ---

    ECO/ME! = 44.000L(//~8.400€)

    ECO/B!A = 30.000L(//~5.600€)

    EUR = 0€

    ERO = 0€

    DEP = 0

    BIA = 0€

    ---

    INT = 53.156,47 (-IMP-VER)//(~10.200€)

    ---

    (Concediu = 14/23 (SEE/+5!))

    ---

    (Chirie x7y ~ 37.000€ // Plati x7y ~ 9.000€)

    (Mașini x8y~(x7-27.000€)+(x8+-27.000€)$
    """
    
    private var groupDefaults: UserDefaults {
        UserDefaults(suiteName: GroupDefaults.suiteName) ?? UserDefaults.standard
    }

    public init() {
        let savedText = UserDefaults(suiteName: GroupDefaults.suiteName)?.string(forKey: storageKey) ?? UserDefaults.standard.string(forKey: storageKey)
        let textToUse = (savedText != nil && !savedText!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ? savedText! : Self.defaultLedgerText
        self.rawText = textToUse
        self.parsedLedger = SmartLedgerParser.shared.parse(textToUse)
        
        setupLifecycleObservers()
        
        Task {
            await syncWithSupabase()
            await setupRealtimeSubscription()
        }
    }
    
    private func setupLifecycleObservers() {
        #if canImport(UIKit)
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reloadFromStorage()
                await self?.syncWithSupabase()
            }
        }
        #endif

        #if canImport(AppKit) && !targetEnvironment(macCatalyst)
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reloadFromStorage()
                await self?.syncWithSupabase()
            }
        }
        #endif
    }
    
    // MARK: - Effective User ID Resolution
    
    private func getEffectiveUserId() -> String? {
        if let stored = groupDefaults.string(forKey: "supabase_user_id"), !stored.isEmpty, stored.lowercased() != "guest" {
            return stored.lowercased()
        }
        if let authUid = groupDefaults.string(forKey: "authenticated_user_id"), !authUid.isEmpty, authUid.lowercased() != "guest" {
            return authUid.lowercased()
        }
        if let currentUid = groupDefaults.string(forKey: "current_user_id"), !currentUid.isEmpty, currentUid.lowercased() != "guest" {
            return currentUid.lowercased()
        }
        return nil
    }

    private func getEffectiveUserIdAsync() async -> String? {
        if let id = getEffectiveUserId() {
            return id
        }
        if let session = try? await SupabaseService.shared.client.auth.session {
            let uid = session.user.id.uuidString.lowercased()
            if uid != "guest" { return uid }
        }
        return nil
    }
    
    /// Reloads raw ledger text from shared App Group storage if changed externally.
    public func reloadFromStorage() {
        let savedText = groupDefaults.string(forKey: storageKey) ?? UserDefaults.standard.string(forKey: storageKey)
        let textToUse = (savedText != nil && !savedText!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ? savedText! : Self.defaultLedgerText
        if textToUse != self.rawText {
            self.rawText = textToUse
            self.parsedLedger = SmartLedgerParser.shared.parse(textToUse)
        }
    }
    
    /// Updates the raw ledger text, saves to UserDefaults, triggers live re-parsing, and queues Supabase push.
    public func saveLedgerText(_ newText: String, triggerCloudSync: Bool = true) {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        let textToSave = trimmed.isEmpty ? Self.defaultLedgerText : newText
        
        self.rawText = textToSave
        groupDefaults.set(textToSave, forKey: storageKey)
        UserDefaults.standard.set(textToSave, forKey: storageKey)
        
        let now = Date().timeIntervalSince1970
        groupDefaults.set(now, forKey: localModifiedKey)
        
        self.parsedLedger = SmartLedgerParser.shared.parse(textToSave)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
        
        if triggerCloudSync {
            scheduleSupabasePush()
        }
    }
    
    /// Resets the ledger text to the baseline template.
    public func resetToDefault() {
        saveLedgerText(Self.defaultLedgerText)
    }
    
    /// Re-parses the current raw text (e.g. if exchange rate changes).
    public func recalculate(eurRate: Double = 5.0) {
        self.parsedLedger = SmartLedgerParser.shared.parse(rawText, eurRate: eurRate)
    }
    
    // MARK: - Mutation Actions
    
    /// Increments or decrements an item's raw value in the DSL text document.
    public func adjustItem(item: SmartLedgerItem, deltaRaw: Double) {
        let updatedText = SmartLedgerParser.shared.adjustItemAmount(in: rawText, lineIndex: item.lineIndex, deltaRaw: deltaRaw)
        saveLedgerText(updatedText)
    }
    
    /// Updates an item's raw value directly in the DSL text document.
    public func setItemAmount(item: SmartLedgerItem, newRaw: Double) {
        let updatedText = SmartLedgerParser.shared.setItemAmount(in: rawText, lineIndex: item.lineIndex, newRaw: newRaw)
        saveLedgerText(updatedText)
    }
    
    /// Appends a new item into a designated section and recalculates totals.
    public func addItem(sectionName: String, key: String, rawAmount: Double, note: String?) {
        let updatedText = SmartLedgerParser.shared.addItem(to: rawText, sectionName: sectionName, key: key, rawAmount: rawAmount, note: note)
        saveLedgerText(updatedText)
    }
    
    /// Removes an item line completely and recalculates totals.
    public func deleteItem(item: SmartLedgerItem) {
        let updatedText = SmartLedgerParser.shared.deleteItem(from: rawText, lineIndex: item.lineIndex)
        saveLedgerText(updatedText)
    }
    
    // MARK: - Supabase Cloud Synchronization
    
    private struct RemoteSmartLedgerDTO: Codable {
        let id: UUID
        let user_id: UUID
        let ledger_text: String
        let created_at: Date
        let updated_at: Date
    }

    private struct SmartLedgerUpsertPayload: Codable {
        let id: UUID?
        let user_id: UUID
        let ledger_text: String
        let updated_at: String
    }

    public func syncWithSupabase() async {
        guard let userId = await getEffectiveUserIdAsync(), let userUuid = UUID(uuidString: userId) else {
            return
        }

        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        let client = SupabaseService.shared.client

        do {
            let res = try await client
                .from("smart_ledgers")
                .select()
                .eq("user_id", value: userId)
                .order("updated_at", ascending: false)
                .limit(1)
                .execute()

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let remoteRows = try decoder.decode([RemoteSmartLedgerDTO].self, from: res.data)

            let localModifiedEpoch = groupDefaults.double(forKey: localModifiedKey)
            let localModifiedDate = localModifiedEpoch > 0 ? Date(timeIntervalSince1970: localModifiedEpoch) : Date.distantPast

            if let latestRemote = remoteRows.first {
                groupDefaults.set(latestRemote.id.uuidString, forKey: serverRecordIdKey)

                if latestRemote.updated_at > localModifiedDate {
                    // Remote is strictly newer -> adopt remote text
                    self.saveLedgerText(latestRemote.ledger_text, triggerCloudSync: false)
                    self.lastSyncedAt = Date()
                } else if localModifiedDate > latestRemote.updated_at {
                    // Local is newer -> push up to Supabase
                    await pushLedgerToSupabase(recordId: latestRemote.id, userUuid: userUuid)
                } else {
                    self.lastSyncedAt = Date()
                }
            } else {
                // No row in Supabase -> initial push of golden iOS text!
                await pushLedgerToSupabase(recordId: nil, userUuid: userUuid)
            }
            self.cloudSyncError = nil
        } catch {
            print("[SmartLedgerStore] Supabase sync notice: \(error.localizedDescription)")
            self.cloudSyncError = error.localizedDescription
        }
    }

    private func scheduleSupabasePush() {
        pushDebounceTask?.cancel()
        pushDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms debounce
            guard !Task.isCancelled else { return }
            guard let userId = await getEffectiveUserIdAsync(), let userUuid = UUID(uuidString: userId) else { return }
            
            let recordId: UUID? = {
                guard let idStr = groupDefaults.string(forKey: serverRecordIdKey),
                      let uuid = UUID(uuidString: idStr) else { return nil }
                return uuid
            }()
            
            await pushLedgerToSupabase(recordId: recordId, userUuid: userUuid)
        }
    }

    private func pushLedgerToSupabase(recordId: UUID?, userUuid: UUID) async {
        let client = SupabaseService.shared.client
        let isoFormatter = ISO8601DateFormatter()
        let now = Date()

        let payload = SmartLedgerUpsertPayload(
            id: recordId,
            user_id: userUuid,
            ledger_text: self.rawText,
            updated_at: isoFormatter.string(from: now)
        )

        do {
            let res = try await client
                .from("smart_ledgers")
                .upsert(payload)
                .select()
                .execute()

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let created = try? decoder.decode([RemoteSmartLedgerDTO].self, from: res.data).first {
                groupDefaults.set(created.id.uuidString, forKey: serverRecordIdKey)
            }
            self.lastSyncedAt = now
            self.cloudSyncError = nil
        } catch {
            print("[SmartLedgerStore] Failed to push ledger to Supabase: \(error.localizedDescription)")
            self.cloudSyncError = error.localizedDescription
        }
    }

    // MARK: - Supabase Realtime Subscription

    private func setupRealtimeSubscription() async {
        guard let userId = await getEffectiveUserIdAsync() else { return }

        let client = SupabaseService.shared.client
        let channelName = "daily_smart_ledger_\(userId)"
        let channel = client.channel(channelName)

        let ledgerUpdates = channel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "smart_ledgers",
            filter: "user_id=eq.\(userId)"
        )

        let ledgerInserts = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "smart_ledgers",
            filter: "user_id=eq.\(userId)"
        )

        do {
            try await channel.subscribeWithError()
            self.realtimeChannel = channel

            Task { [weak self] in
                for await _ in ledgerUpdates {
                    await self?.syncWithSupabase()
                }
            }

            Task { [weak self] in
                for await _ in ledgerInserts {
                    await self?.syncWithSupabase()
                }
            }
        } catch {
            print("[SmartLedgerStore] Realtime subscription notice: \(error.localizedDescription)")
        }
    }
}
