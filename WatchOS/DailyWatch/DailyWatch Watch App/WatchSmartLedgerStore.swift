import Foundation
import SwiftUI
import Combine
import WatchKit
import Supabase

public struct WatchSmartLedgerQuickItem: Identifiable, Codable, Equatable {
    public var id: String
    public var name: String
    public var count: Double
    public var unitPrice: Double
    public var isScaled: Bool
    public var currency: String

    public var calculatedTotal: Double {
        if isScaled {
            return count * unitPrice
        }
        return count
    }

    public var displayAmount: String {
        let total = calculatedTotal
        if total.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(total)) \(currency)"
        }
        return String(format: "%.1f %@", total, currency)
    }

    public var displaySubtitle: String {
        if isScaled {
            let countStr = count.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(count))" : String(format: "%.1f", count)
            return "\(countStr) × \(Int(unitPrice)) Lei"
        }
        return "Fix / Lunar"
    }
}

@MainActor
public final class WatchSmartLedgerStore: ObservableObject {
    public static let shared = WatchSmartLedgerStore()

    @Published public var netWorth: String = "128.450 Lei"
    @Published public var netWorthEUR: String = "~25.690 €"
    @Published public var deposits: String = "74.000 Lei"
    @Published public var sold: String = "53.156 Lei"
    @Published public var incoming: String = "3.500 Lei"
    @Published public var items: [WatchSmartLedgerQuickItem] = []
    @Published public var isSyncing: Bool = false
    @Published public var lastSyncDate: Date? = nil

    private let cacheKey = "watch_smart_ledger_cache_v1"
    private let groupSuiteName = "group.com.intellidream.daily"

    private var defaults: UserDefaults {
        UserDefaults(suiteName: groupSuiteName) ?? UserDefaults.standard
    }

    private init() {
        loadCachedData()
    }

    // MARK: - Local Cache (< 1ms load)

    private func loadCachedData() {
        if let data = defaults.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode([WatchSmartLedgerQuickItem].self, from: data),
           !cached.isEmpty {
            self.items = cached
        } else {
            // Baseline top quick-adjust items from golden Smart Ledger
            self.items = [
                WatchSmartLedgerQuickItem(id: "tigari", name: "Țigări", count: 10, unitPrice: 26.50, isScaled: true, currency: "Lei"),
                WatchSmartLedgerQuickItem(id: "cora", name: "Cora / Market", count: 1, unitPrice: 150.0, isScaled: true, currency: "Lei"),
                WatchSmartLedgerQuickItem(id: "car", name: "Benzină / Mașină", count: 500, unitPrice: 1.0, isScaled: false, currency: "Lei"),
                WatchSmartLedgerQuickItem(id: "vacante", name: "Vacanțe / Relax", count: 1000, unitPrice: 1.0, isScaled: false, currency: "Lei")
            ]
        }

        // Try reading raw text from group defaults to compute actual net worth
        if let rawText = defaults.string(forKey: "smart_ledger_raw_text"), !rawText.isEmpty {
            parseOverviewFromText(rawText)
        }
    }

    private func persistData() {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: cacheKey)
        }
    }

    // MARK: - Quick Stepper Adjustments

    public func adjustItem(id: String, delta: Double) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        WKInterfaceDevice.current().play(.click)

        var item = items[idx]
        item.count = max(0, item.count + delta)
        items[idx] = item
        persistData()

        // Push update to Supabase in background
        Task {
            await pushLedgerAdjustment(item: item, delta: delta)
        }
    }

    // MARK: - Supabase Cloud Sync

    public func fetchLedgerData(force: Bool = false) async {
        if !force, let last = lastSyncDate, Date().timeIntervalSince(last) < 45 {
            return
        }
        guard let client = WatchSessionManager.shared.supabaseClient,
              let userId = WatchSessionManager.shared.currentUserId else {
            return
        }

        isSyncing = true
        defer {
            isSyncing = false
            lastSyncDate = Date()
        }

        do {
            struct RemoteLedgerDTO: Codable {
                let id: UUID
                let user_id: UUID
                let ledger_text: String
                let updated_at: Date
            }

            let res = try await client
                .from("smart_ledgers")
                .select("id, user_id, ledger_text, updated_at")
                .eq("user_id", value: userId.uuidString)
                .order("updated_at", ascending: false)
                .limit(1)
                .execute()

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let records = try decoder.decode([RemoteLedgerDTO].self, from: res.data)

            if let first = records.first {
                defaults.set(first.ledger_text, forKey: "smart_ledger_raw_text")
                parseOverviewFromText(first.ledger_text)
                lastSyncDate = first.updated_at
            }
        } catch {
            print("[WatchSmartLedgerStore] Fetch error: \(error)")
        }
    }

    private func pushLedgerAdjustment(item: WatchSmartLedgerQuickItem, delta: Double) async {
        guard let client = WatchSessionManager.shared.supabaseClient,
              let userId = WatchSessionManager.shared.currentUserId else {
            return
        }

        do {
            // Read current text, adjust line, push back
            var text = defaults.string(forKey: "smart_ledger_raw_text") ?? ""
            if text.isEmpty { return }

            let pattern: String
            if item.id == "tigari" {
                pattern = #"(?i)Tigari\s*=\s*([0-9\.]+)"#
            } else if item.id == "cora" {
                pattern = #"(?i)Cora\s*=\s*([0-9\.]+)"#
            } else {
                pattern = "(?i)" + NSRegularExpression.escapedPattern(for: item.name) + #"\s*=\s*([0-9\.]+)"#
            }

            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let nsText = text as NSString
                let range = NSRange(location: 0, length: nsText.length)
                if let match = regex.firstMatch(in: text, options: [], range: range), match.numberOfRanges > 1 {
                    let numRange = match.range(at: 1)
                    let currentStr = nsText.substring(with: numRange)
                    if let currentVal = Double(currentStr) {
                        let newVal = max(0, currentVal + delta)
                        let newNumStr = newVal.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(newVal))" : String(format: "%.1f", newVal)
                        text = nsText.replacingCharacters(in: numRange, with: newNumStr)

                        defaults.set(text, forKey: "smart_ledger_raw_text")
                        parseOverviewFromText(text)

                        struct UpdateDTO: Encodable {
                            let ledger_text: String
                            let updated_at: String
                        }
                        let nowISO = ISO8601DateFormatter().string(from: Date())
                        let payload = UpdateDTO(ledger_text: text, updated_at: nowISO)

                        _ = try await client
                            .from("smart_ledgers")
                            .update(payload)
                            .eq("user_id", value: userId.uuidString)
                            .execute()
                    }
                }
            }
        } catch {
            print("[WatchSmartLedgerStore] Push adjustment error: \(error)")
        }
    }

    private func parseOverviewFromText(_ text: String) {
        // Simple fast extraction of totals from header comments or lines
        // e.g. INT = 53.156, ECO = 74.000, etc.
        var depTotal = 74000.0
        var soldTotal = 53156.0
        var incTotal = 3500.0

        if let m = text.range(of: #"ECO\s*=\s*([0-9\.\,]+)"#, options: .regularExpression) {
            let sub = text[m]
            if let num = extractNumber(from: String(sub)) { depTotal = num }
        }
        if let m = text.range(of: #"INT\s*=\s*([0-9\.\,]+)"#, options: .regularExpression) {
            let sub = text[m]
            if let num = extractNumber(from: String(sub)) { soldTotal = num }
        }

        let nw = depTotal + soldTotal
        let eur = nw / 5.0

        self.netWorth = formatLei(nw)
        self.netWorthEUR = String(format: "~%@ €", formatEUR(eur))
        self.deposits = formatLei(depTotal)
        self.sold = formatLei(soldTotal)
        self.incoming = formatLei(incTotal)

        // Also update quick items counts if found in text
        if let m = text.range(of: #"(?i)Tigari\s*=\s*([0-9\.]+)"#, options: .regularExpression) {
            let sub = text[m]
            if let num = extractNumber(from: String(sub)), let idx = items.firstIndex(where: { $0.id == "tigari" }) {
                items[idx].count = num
            }
        }
        if let m = text.range(of: #"(?i)Cora\s*=\s*([0-9\.]+)"#, options: .regularExpression) {
            let sub = text[m]
            if let num = extractNumber(from: String(sub)), let idx = items.firstIndex(where: { $0.id == "cora" }) {
                items[idx].count = num
            }
        }
    }

    private func extractNumber(from str: String) -> Double? {
        let digits = str.components(separatedBy: CharacterSet(charactersIn: "0123456789.,").inverted).joined()
        let clean = digits.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        return Double(clean)
    }

    private func formatLei(_ val: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "."
        formatter.maximumFractionDigits = 0
        let str = formatter.string(from: NSNumber(value: val)) ?? "\(Int(val))"
        return "\(str) Lei"
    }

    private func formatEUR(_ val: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "."
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: val)) ?? "\(Int(val))"
    }
}
