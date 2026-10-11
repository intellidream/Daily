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
/// Features high-performance Layout.Cache to eliminate frame drops and layout oscillation on 120Hz ProMotion displays.
public struct ModularDashboardLayout: Layout {
    public var spacing: CGFloat
    public var unitHeight: CGFloat
    
    public init(spacing: CGFloat = 14, unitHeight: CGFloat = 155) {
        self.spacing = spacing
        self.unitHeight = unitHeight
    }
    
    struct GridCoord: Hashable {
        let row: Int
        let col: Int
    }
    
    public struct PlacedItem: Sendable {
        public let index: Int
        public let rect: CGRect
    }
    
    public struct Cache {
        var lastWidth: CGFloat = -1
        var items: [PlacedItem] = []
        var totalHeight: CGFloat = 0
    }
    
    public func makeCache(subviews: Subviews) -> Cache {
        Cache()
    }
    
    public func updateCache(_ cache: inout Cache, subviews: Subviews) {
        if cache.items.count != subviews.count {
            cache.lastWidth = -1
        }
    }
    
    private func computePlacements(
        subviews: Subviews,
        width: CGFloat
    ) -> (items: [PlacedItem], totalHeight: CGFloat) {
        guard !subviews.isEmpty else { return ([], 0) }
        
        let colWidth = floor(max((width - spacing) / 2.0, 80.0))
        var occupied = Set<GridCoord>()
        var items: [PlacedItem] = []
        var maxRow = -1
        
        // Pure closed-form 2-column mathematical bin-packing (0 subview size queries)
        for index in subviews.indices {
            let span = subviews[index][WidgetSpanKey.self]
            let colSpan = min(max(span.colSpan, 1), 2)
            let rowSpan = min(max(span.rowSpan, 1), 2)
            
            let targetRow: Int
            let targetCol: Int
            
            if colSpan == 2 {
                var r = 0
                while true {
                    var canFit = true
                    for dr in 0..<rowSpan {
                        let rowToCheck = r + dr
                        if occupied.contains(GridCoord(row: rowToCheck, col: 0)) || occupied.contains(GridCoord(row: rowToCheck, col: 1)) {
                            canFit = false
                            break
                        }
                    }
                    if canFit {
                        targetRow = r
                        targetCol = 0
                        break
                    }
                    r += 1
                }
                
                for dr in 0..<rowSpan {
                    let rowToOccupy = targetRow + dr
                    occupied.insert(GridCoord(row: rowToOccupy, col: 0))
                    occupied.insert(GridCoord(row: rowToOccupy, col: 1))
                    if rowToOccupy > maxRow { maxRow = rowToOccupy }
                }
            } else {
                var r = 0
                var c = 0
                var found = false
                
                while !found {
                    for colCandidate in 0..<2 {
                        var canFit = true
                        for dr in 0..<rowSpan {
                            let rowToCheck = r + dr
                            if occupied.contains(GridCoord(row: rowToCheck, col: colCandidate)) {
                                canFit = false
                                break
                            }
                        }
                        if canFit {
                            c = colCandidate
                            found = true
                            break
                        }
                    }
                    if !found {
                        r += 1
                    }
                }
                targetRow = r
                targetCol = c
                
                for dr in 0..<rowSpan {
                    let rowToOccupy = targetRow + dr
                    occupied.insert(GridCoord(row: rowToOccupy, col: targetCol))
                    if rowToOccupy > maxRow { maxRow = rowToOccupy }
                }
            }
            
            // Deterministic closed-form geometry: zero layout recursion, zero subpixel oscillation
            let x = floor((targetCol == 0) ? 0 : colWidth + spacing)
            let y = floor(CGFloat(targetRow) * (unitHeight + spacing))
            let w = floor((colSpan == 2) ? width : colWidth)
            let h = floor(CGFloat(rowSpan) * unitHeight + CGFloat(rowSpan - 1) * spacing)
            
            let rect = CGRect(x: x, y: y, width: w, height: h)
            items.append(PlacedItem(index: index, rect: rect))
        }
        
        let totalRows = maxRow + 1
        let totalHeight = totalRows > 0 ? floor(CGFloat(totalRows) * unitHeight + CGFloat(totalRows - 1) * spacing) : 0
        return (items, totalHeight)
    }
    
    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        #if canImport(UIKit)
        let defaultFallbackWidth = floor(UIScreen.main.bounds.width - 40)
        #else
        let defaultFallbackWidth: CGFloat = 353
        #endif
        let width = floor(proposal.width ?? defaultFallbackWidth)
        guard width > 0 else { return .zero }
        
        if abs(cache.lastWidth - width) > 0.5 || cache.items.isEmpty {
            let (items, height) = computePlacements(subviews: subviews, width: width)
            cache.lastWidth = width
            cache.items = items
            cache.totalHeight = height
        }
        return CGSize(width: width, height: cache.totalHeight)
    }
    
    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let width = floor(bounds.width)
        guard width > 0 else { return }
        
        if abs(cache.lastWidth - width) > 0.5 || cache.items.isEmpty {
            let (items, height) = computePlacements(subviews: subviews, width: width)
            cache.lastWidth = width
            cache.items = items
            cache.totalHeight = height
        }
        
        for item in cache.items {
            guard item.index < subviews.count else { continue }
            let origin = CGPoint(x: bounds.origin.x + item.rect.origin.x, y: bounds.origin.y + item.rect.origin.y)
            subviews[item.index].place(
                at: origin,
                proposal: ProposedViewSize(item.rect.size)
            )
        }
    }
}
