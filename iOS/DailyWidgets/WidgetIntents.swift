import Foundation
import AppIntents
import DailyCore

public struct LogWaterIntent: AppIntent {
    public static var title: LocalizedStringResource = "Log Water"
    public static var description = IntentDescription("Logs water or coffee intake directly to Bubbles.")

    @Parameter(title: "Amount (ml)")
    public var amountMl: Double

    @Parameter(title: "Drink Type")
    public var drinkType: String

    public init() {
        self.amountMl = 150
        self.drinkType = "Water"
    }

    public init(amountMl: Double, drinkType: String = "Water") {
        self.amountMl = amountMl
        self.drinkType = drinkType
    }

    public func perform() async throws -> some IntentResult {
        WidgetDataCoordinator.shared.logWater(amountMl: amountMl, drinkType: drinkType)
        return .result()
    }
}

public struct LogSmokeIntent: AppIntent {
    public static var title: LocalizedStringResource = "Log Smoke"
    public static var description = IntentDescription("Logs a cigarette or heated tobacco stick directly to Smokes.")

    @Parameter(title: "Type")
    public var smokeType: String

    public init() {
        self.smokeType = "Cigarette"
    }

    public init(smokeType: String) {
        self.smokeType = smokeType
    }

    public func perform() async throws -> some IntentResult {
        let lower = smokeType.lowercased()
        let preset: SmokePreset
        if lower.contains("heat") {
            preset = .heated
        } else if lower.contains("cgr") || lower.contains("cigar") {
            preset = .cigarillo
        } else if lower.contains("rol") {
            preset = .rolled
        } else {
            preset = .cigarette
        }
        WidgetDataCoordinator.shared.logSmoke(preset: preset)
        return .result()
    }
}

public struct AdjustLedgerIntent: AppIntent {
    public static var title: LocalizedStringResource = "Adjust Ledger"
    public static var description = IntentDescription("Quickly adds or subtracts amounts from Card or Cash accounts.")

    @Parameter(title: "Account Name")
    public var accountName: String

    @Parameter(title: "Delta (Lei)")
    public var deltaRaw: Double

    public init() {
        self.accountName = "Card"
        self.deltaRaw = -50
    }

    public init(accountName: String, deltaRaw: Double) {
        self.accountName = accountName
        self.deltaRaw = deltaRaw
    }

    public func perform() async throws -> some IntentResult {
        WidgetDataCoordinator.shared.adjustLedgerAmount(accountName: accountName, deltaRaw: deltaRaw)
        return .result()
    }
}
