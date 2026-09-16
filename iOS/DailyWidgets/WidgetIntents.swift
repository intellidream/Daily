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

public struct LogCigaretteIntent: AppIntent {
    public static var title: LocalizedStringResource = "Log Cigarette"
    public static var description = IntentDescription("Logs 1 combustible cigarette directly to Smokes.")

    public init() {}

    public func perform() async throws -> some IntentResult {
        WidgetDataCoordinator.shared.logSmoke(preset: .cigarette)
        return .result()
    }
}

public struct LogHeatedIntent: AppIntent {
    public static var title: LocalizedStringResource = "Log Heated Tobacco"
    public static var description = IntentDescription("Logs 1 heated tobacco stick directly to Smokes.")

    public init() {}

    public func perform() async throws -> some IntentResult {
        WidgetDataCoordinator.shared.logSmoke(preset: .heated)
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
        if lower.contains("cigarette") || lower == "cig" || lower.contains("standard") {
            preset = .cigarette
        } else if lower.contains("heat") || lower.contains("iqos") {
            preset = .heated
        } else if lower.contains("cigarillo") || lower == "cgr" || (lower.contains("cigar") && !lower.contains("cigarette")) {
            preset = .cigarillo
        } else if lower.contains("roll") || lower == "rol" {
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
    public static var description = IntentDescription("Quickly adds or subtracts real amounts (in Lei) from Card or Cash accounts.")

    @Parameter(title: "Account Name")
    public var accountName: String

    @Parameter(title: "Delta (Lei)")
    public var deltaReal: Double

    public init() {
        self.accountName = "Card"
        self.deltaReal = 100
    }

    public init(accountName: String, deltaReal: Double) {
        self.accountName = accountName
        self.deltaReal = deltaReal
    }

    public init(accountName: String, deltaRaw: Double) {
        self.accountName = accountName
        self.deltaReal = deltaRaw
    }

    public func perform() async throws -> some IntentResult {
        WidgetDataCoordinator.shared.adjustLedgerAmount(accountName: accountName, deltaReal: deltaReal)
        return .result()
    }
}
