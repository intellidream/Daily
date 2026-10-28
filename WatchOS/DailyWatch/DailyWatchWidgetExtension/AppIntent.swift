//
//  AppIntent.swift
//  DailyWatchWidgetExtension
//
//  Created by Mihai Ionescu on 25.02.2026.
//

import WidgetKit
import AppIntents
import SwiftUI

// MARK: - Interactive Log Water Intent

public struct LogWaterWidgetIntent: AppIntent {
    public static var title: LocalizedStringResource = "Log Water Intake"
    public static var description = IntentDescription("Quickly logs water intake to Daily Bubbles from your watch face.")
    
    @Parameter(title: "Amount (ml)", default: 300)
    public var amountMl: Int
    
    @Parameter(title: "Drink Type", default: "Water")
    public var drinkType: String
    
    public init() {
        self.amountMl = 300
        self.drinkType = "Water"
    }
    
    public init(amountMl: Int, drinkType: String = "Water") {
        self.amountMl = amountMl
        self.drinkType = drinkType
    }
    
    public func perform() async throws -> some IntentResult {
        let groupDefaults = UserDefaults(suiteName: "group.com.intellidream.daily")
        let currentWater = groupDefaults?.integer(forKey: "cached_water_total") ?? 0
        let newTotal = currentWater + amountMl
        groupDefaults?.set(newTotal, forKey: "cached_water_total")
        
        let isCoffee = drinkType.lowercased().contains("coffee") || drinkType.lowercased().contains("espresso")
        if isCoffee {
            let currCoffee = groupDefaults?.integer(forKey: "cached_coffee_amount") ?? 0
            groupDefaults?.set(currCoffee + amountMl, forKey: "cached_coffee_amount")
        } else {
            let currWaterAmt = groupDefaults?.integer(forKey: "cached_water_amount") ?? 0
            groupDefaults?.set(currWaterAmt + amountMl, forKey: "cached_water_amount")
        }
        
        // Also enqueue into pending outbox key if needed
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// MARK: - Interactive Log Smoke Intent

public struct LogSmokeWidgetIntent: AppIntent {
    public static var title: LocalizedStringResource = "Log Smoke"
    public static var description = IntentDescription("Quickly logs a cigarette or heated tobacco stick from your watch face.")
    
    @Parameter(title: "Is Heated Tobacco", default: false)
    public var isHeated: Bool
    
    public init() {
        self.isHeated = false
    }
    
    public init(isHeated: Bool) {
        self.isHeated = isHeated
    }
    
    public func perform() async throws -> some IntentResult {
        let groupDefaults = UserDefaults(suiteName: "group.com.intellidream.daily")
        let currentSmokes = groupDefaults?.integer(forKey: "cached_smokes_total") ?? 0
        groupDefaults?.set(currentSmokes + 1, forKey: "cached_smokes_total")
        
        if isHeated {
            let currentHeat = groupDefaults?.integer(forKey: "cached_heat_count") ?? 0
            groupDefaults?.set(currentHeat + 1, forKey: "cached_heat_count")
        } else {
            let currentCigs = groupDefaults?.integer(forKey: "cached_cigs_count") ?? 0
            groupDefaults?.set(currentCigs + 1, forKey: "cached_cigs_count")
        }
        
        // Record last smoke timestamp for Craving Timer
        let nowIso = ISO8601DateFormatter().string(from: Date())
        groupDefaults?.set(nowIso, forKey: "last_smoke_timestamp")
        
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// MARK: - Start Physiological Sigh Intent (For Action Button / Shortcuts)

public struct StartPhysiologicalSighIntent: AppIntent {
    public static var title: LocalizedStringResource = "Beat Craving (48s Sigh)"
    public static var description = IntentDescription("Launches the rapid 48-second Physiological Sigh haptic breathing exercise.")
    public static var openAppWhenRun: Bool = true
    
    public init() {}
    
    public func perform() async throws -> some IntentResult {
        return .result()
    }
}

// MARK: - Apple Watch Ultra Action Button & App Shortcuts Provider

public struct DailyWatchShortcuts: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogWaterWidgetIntent(amountMl: 300, drinkType: "Water"),
            phrases: [
                "Log water in \(.applicationName)",
                "Drink 300ml in \(.applicationName)"
            ],
            shortTitle: "Log 300ml Water",
            systemImageName: "drop.fill"
        )
        
        AppShortcut(
            intent: LogSmokeWidgetIntent(isHeated: false),
            phrases: [
                "Log smoke in \(.applicationName)",
                "Record cigarette in \(.applicationName)"
            ],
            shortTitle: "Log Smoke",
            systemImageName: "flame.fill"
        )
        
        AppShortcut(
            intent: StartPhysiologicalSighIntent(),
            phrases: [
                "Calm down in \(.applicationName)",
                "Beat craving in \(.applicationName)"
            ],
            shortTitle: "48s Sigh",
            systemImageName: "wind"
        )
    }
}
