import SwiftUI
import DailyCore

/// Layout key specifying column and row span in the modular dashboard grid.
public struct WidgetSpan: Sendable {
    public let colSpan: Int
    public let rowSpan: Int
    
    public init(colSpan: Int = 2, rowSpan: Int = 1) {
        self.colSpan = colSpan
        self.rowSpan = rowSpan
    }
}

public struct WidgetSpanKey: LayoutValueKey {
    public static let defaultValue: WidgetSpan = WidgetSpan(colSpan: 2, rowSpan: 1)
}

extension View {
    public func widgetSpan(colSpan: Int, rowSpan: Int) -> some View {
        layoutValue(key: WidgetSpanKey.self, value: WidgetSpan(colSpan: colSpan, rowSpan: rowSpan))
    }
    
    public func widgetSpan(_ size: DashboardWidgetSize) -> some View {
        layoutValue(key: WidgetSpanKey.self, value: WidgetSpan(colSpan: size.columnSpan, rowSpan: size.rowSpan))
    }
}

/// A 2-column mathematical bin-packing grid layout for customizable dashboard widgets.
/// Smoothly arranges 1x1 (Small), 2x1 (Wide), 1x2 (Tall), and 2x2 (Large) widgets without gaps.
public struct ModularDashboardLayout: Layout {
    public var spacing: CGFloat
    public var unitHeight: CGFloat
    
    public init(spacing: CGFloat = 16, unitHeight: CGFloat = 165) {
        self.spacing = spacing
        self.unitHeight = unitHeight
    }
    
    struct GridCoord: Hashable {
        let row: Int
        let col: Int
    }
    
    struct PlacedItem {
        let index: Int
        let rect: CGRect
    }
    
    private func computePlacements(
        subviews: Subviews,
        width: CGFloat,
        origin: CGPoint = .zero
    ) -> (items: [PlacedItem], totalHeight: CGFloat) {
        guard !subviews.isEmpty else { return ([], 0) }
        
        let colWidth = max((width - spacing) / 2.0, 80.0)
        var occupied = Set<GridCoord>()
        var items: [PlacedItem] = []
        
        for index in subviews.indices {
            let span = subviews[index][WidgetSpanKey.self]
            let colSpan = min(max(span.colSpan, 1), 2)
            let rowSpan = min(max(span.rowSpan, 1), 2)
            
            if colSpan == 2 {
                // Find earliest row where both columns [0, 1] are free for all rowSpan units
                var targetRow = 0
                while true {
                    var canFit = true
                    for dr in 0..<rowSpan {
                        let r = targetRow + dr
                        if occupied.contains(GridCoord(row: r, col: 0)) || occupied.contains(GridCoord(row: r, col: 1)) {
                            canFit = false
                            break
                        }
                    }
                    if canFit { break }
                    targetRow += 1
                }
                
                // Mark occupied
                for dr in 0..<rowSpan {
                    let r = targetRow + dr
                    occupied.insert(GridCoord(row: r, col: 0))
                    occupied.insert(GridCoord(row: r, col: 1))
                }
                
                let x = origin.x
                let y = origin.y + CGFloat(targetRow) * (unitHeight + spacing)
                let h = CGFloat(rowSpan) * unitHeight + CGFloat(rowSpan - 1) * spacing
                let rect = CGRect(x: x, y: y, width: width, height: h)
                items.append(PlacedItem(index: index, rect: rect))
                
            } else {
                // colSpan == 1: check row by row, then col 0 then col 1
                var targetRow = 0
                var targetCol = 0
                var found = false
                
                while !found {
                    for c in 0..<2 {
                        var canFit = true
                        for dr in 0..<rowSpan {
                            let r = targetRow + dr
                            if occupied.contains(GridCoord(row: r, col: c)) {
                                canFit = false
                                break
                            }
                        }
                        if canFit {
                            targetCol = c
                            found = true
                            break
                        }
                    }
                    if !found {
                        targetRow += 1
                    }
                }
                
                // Mark occupied
                for dr in 0..<rowSpan {
                    let r = targetRow + dr
                    occupied.insert(GridCoord(row: r, col: targetCol))
                }
                
                let x = origin.x + CGFloat(targetCol) * (colWidth + spacing)
                let y = origin.y + CGFloat(targetRow) * (unitHeight + spacing)
                let h = CGFloat(rowSpan) * unitHeight + CGFloat(rowSpan - 1) * spacing
                let rect = CGRect(x: x, y: y, width: colWidth, height: h)
                items.append(PlacedItem(index: index, rect: rect))
            }
        }
        
        let maxRow = occupied.map(\.row).max() ?? -1
        let totalHeight = maxRow >= 0 ? CGFloat(maxRow + 1) * unitHeight + CGFloat(maxRow) * spacing : 0
        return (items, totalHeight)
    }
    
    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 353
        let (_, height) = computePlacements(subviews: subviews, width: width)
        return CGSize(width: width, height: height)
    }
    
    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (items, _) = computePlacements(subviews: subviews, width: bounds.width, origin: bounds.origin)
        for item in items {
            subviews[item.index].place(
                at: item.rect.origin,
                proposal: ProposedViewSize(item.rect.size)
            )
        }
    }
}
