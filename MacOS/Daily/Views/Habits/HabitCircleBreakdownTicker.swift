import SwiftUI
import DailyCore

/// A sleek, compact horizontal ticker capsule designed to fit comfortably inside
/// circular progress gauges (Bubbles and Smokes) to display breakdown totals per liquid or smoke type.
public struct HabitCircleBreakdownTicker: View {
    public let items: [HabitDrinkBreakdown]
    public let habitType: HabitType
    
    @State private var autoScrollOffset: CGFloat = 0
    
    public init(items: [HabitDrinkBreakdown], habitType: HabitType = .water) {
        self.items = items
        self.habitType = habitType
    }
    
    /// Aggregate items by primary beverage / tobacco category for clean, non-fragmented totals
    public var aggregatedItems: [AggregatedItem] {
        var map: [String: (amount: Double, unit: String, hexColor: String, iconName: String)] = [:]
        
        for item in items {
            let norm: (category: String, color: String, icon: String)
            if habitType == .water {
                norm = normalizeDrink(name: item.drink, defaultColor: item.hexColor, defaultIcon: item.iconName)
            } else {
                norm = normalizeSmoke(name: item.drink, defaultColor: item.hexColor, defaultIcon: item.iconName)
            }
            
            if let existing = map[norm.category] {
                map[norm.category] = (existing.amount + item.amount, existing.unit, existing.hexColor, existing.iconName)
            } else {
                map[norm.category] = (item.amount, item.unit, norm.color, norm.icon)
            }
        }
        
        return map.map { key, val in
            AggregatedItem(
                id: key,
                name: key,
                amount: val.amount,
                unit: val.unit,
                hexColor: val.hexColor,
                iconName: val.iconName
            )
        }.sorted { $0.amount > $1.amount }
    }
    
    public struct AggregatedItem: Identifiable {
        public let id: String
        public let name: String
        public let amount: Double
        public let unit: String
        public let hexColor: String
        public let iconName: String
    }
    
    private func normalizeDrink(name: String, defaultColor: String, defaultIcon: String) -> (category: String, color: String, icon: String) {
        let lower = name.lowercased()
        if lower.contains("coffee") || lower.contains("espresso") || lower.contains("cappuccino") || lower.contains("latte") {
            return ("Coffee", "#F59E0B", "cup.and.saucer.fill")
        } else if lower.contains("tea") || lower.contains("matcha") || lower.contains("infusion") {
            return ("Tea", "#84CC16", "mug.fill")
        } else if lower.contains("water") || lower.contains("glass") || lower.contains("bottle") {
            return ("Water", "#00E5FF", "drop.fill")
        } else {
            return (name, defaultColor, defaultIcon)
        }
    }
    
    private func normalizeSmoke(name: String, defaultColor: String, defaultIcon: String) -> (category: String, color: String, icon: String) {
        let lower = name.lowercased()
        if lower.contains("cigarette") || lower == "cig" || lower.contains("standard") {
            return ("Cigarette", "#EF4444", "flame.fill")
        } else if lower.contains("cigarillo") || (lower.contains("cigar") && !lower.contains("cigarette")) {
            return ("Cigarillo", "#A855F7", "flame")
        } else if lower.contains("heat") || lower.contains("iqos") || lower.contains("glo") || lower.contains("vape") {
            return ("Heated", "#3B82F6", "bolt.fill")
        } else if lower.contains("roll") {
            return ("Rolled", "#F97316", "leaf.fill")
        } else {
            return ("Cigarette", "#EF4444", "flame.fill")
        }
    }
    
    private func itemBadgeText(item: AggregatedItem, isSingle: Bool) -> String {
        let formattedAmount = item.unit == "ml" ? "\(Int(item.amount)) ml" : "\(Int(item.amount))"
        if isSingle {
            return "\(item.name): \(formattedAmount)"
        }
        
        if habitType == .water {
            if item.name == "Water" {
                return "\(formattedAmount)"
            } else {
                return "\(item.name) \(formattedAmount)"
            }
        } else {
            switch item.name {
            case "Cigarette": return "\(Int(item.amount)) Cig"
            case "Heated": return "\(Int(item.amount)) Heat"
            case "Rolled": return "\(Int(item.amount)) Roll"
            case "Cigarillo": return "\(Int(item.amount)) Cigar"
            default: return "\(Int(item.amount)) \(item.name)"
            }
        }
    }
    
    public var body: some View {
        let activeItems = aggregatedItems
        if !activeItems.isEmpty {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(Array(activeItems.enumerated()), id: \.element.id) { index, item in
                            HStack(spacing: 3) {
                                Image(systemName: item.iconName)
                                    .font(.system(size: 8.5, weight: .bold))
                                    .foregroundColor(Color(hex: item.hexColor))
                                
                                Text(itemBadgeText(item: item, isSingle: activeItems.count == 1))
                                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                    .foregroundColor(.white.opacity(0.92))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(
                                Color(hex: item.hexColor).opacity(0.22)
                            )
                            .clipShape(Capsule())
                            .overlay {
                                Capsule()
                                    .strokeBorder(Color(hex: item.hexColor).opacity(0.4), lineWidth: 0.8)
                            }
                            .id(index)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                }
                .frame(maxWidth: 175)
                .frame(height: 22)
                .background(Color.black.opacity(0.40))
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .overlay {
                    Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
                }
                .shadow(color: Color.black.opacity(0.35), radius: 3, x: 0, y: 1)
            }
        }
    }
}
