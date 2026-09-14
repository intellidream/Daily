import Foundation
import DailyCore

/// Represents a resolved row in the native modular dashboard.
public enum DashboardRow: Identifiable, Sendable {
    /// A full-width widget (Wide 2x1 or Large 2x2).
    case full(DashboardWidgetConfig)
    
    /// Two half-width widgets side-by-side (two Small 1x1 widgets or two Tall 1x2 widgets).
    case pair(DashboardWidgetConfig, DashboardWidgetConfig)
    
    /// A Tall (1x2) widget paired alongside one or two vertically stacked Small (1x1) widgets.
    case tallWithSmalls(tall: DashboardWidgetConfig, smalls: [DashboardWidgetConfig])
    
    /// An isolated half-width widget when no partner is available.
    case singleSmall(DashboardWidgetConfig)
    
    public var id: String {
        switch self {
        case .full(let config):
            return "full-\(config.id)"
        case .pair(let left, let right):
            return "pair-\(left.id)-\(right.id)"
        case .tallWithSmalls(let tall, let smalls):
            let smallIds = smalls.map(\.id).joined(separator: "-")
            return "tall-\(tall.id)-\(smallIds)"
        case .singleSmall(let config):
            return "single-\(config.id)"
        }
    }
}

/// Resolves an ordered list of widget configurations into cohesive, hole-free dashboard rows.
public struct DashboardRowBuilder {
    public static func buildRows(from configs: [DashboardWidgetConfig]) -> [DashboardRow] {
        var rows: [DashboardRow] = []
        var remaining = configs
        
        while !remaining.isEmpty {
            let current = remaining.removeFirst()
            
            switch current.size {
            case .wide, .large:
                // Wide and Large always take a full row
                rows.append(.full(current))
                
            case .small:
                // Look ahead for another Small widget to pair side-by-side
                if let nextSmallIndex = remaining.firstIndex(where: { $0.size == .small }) {
                    let partner = remaining.remove(at: nextSmallIndex)
                    rows.append(.pair(current, partner))
                } else if let nextTallIndex = remaining.firstIndex(where: { $0.size == .tall }) {
                    // Pair with a Tall widget
                    let tall = remaining.remove(at: nextTallIndex)
                    rows.append(.tallWithSmalls(tall: tall, smalls: [current]))
                } else {
                    // Isolated small widget
                    rows.append(.singleSmall(current))
                }
                
            case .tall:
                // Look for two Small widgets to fill the adjacent column
                var smalls: [DashboardWidgetConfig] = []
                while smalls.count < 2 {
                    if let smallIdx = remaining.firstIndex(where: { $0.size == .small }) {
                        smalls.append(remaining.remove(at: smallIdx))
                    } else {
                        break
                    }
                }
                
                if !smalls.isEmpty {
                    rows.append(.tallWithSmalls(tall: current, smalls: smalls))
                } else if let nextTallIndex = remaining.firstIndex(where: { $0.size == .tall }) {
                    // Two tall widgets side-by-side
                    let partner = remaining.remove(at: nextTallIndex)
                    rows.append(.pair(current, partner))
                } else {
                    // Isolated tall widget
                    rows.append(.singleSmall(current))
                }
            }
        }
        
        return rows
    }
}

import SwiftUI

public extension View {
    @ViewBuilder
    func dashboardCardFrame(for size: DashboardWidgetSize) -> some View {
        switch size {
        case .wide:
            self.frame(maxWidth: .infinity)
        case .small:
            self.frame(maxWidth: .infinity)
                .frame(height: 155)
        case .tall, .large:
            self.frame(maxWidth: .infinity)
                .frame(height: 324)
        }
    }
}
