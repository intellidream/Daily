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
    public var defaultUnitHeight: CGFloat
    
    public init(spacing: CGFloat = 14, defaultUnitHeight: CGFloat = 150) {
        self.spacing = spacing
        self.defaultUnitHeight = defaultUnitHeight
    }
    
    struct GridCoord: Hashable {
        let row: Int
        let col: Int
    }
    
    struct PlacementPlan {
        let index: Int
        let startRow: Int
        let col: Int
        let colSpan: Int
        let rowSpan: Int
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
        // Invalidate on data/subview change so fresh measurements are computed
        cache.lastWidth = -1
    }
    
    private func computePlacements(
        subviews: Subviews,
        width: CGFloat
    ) -> (items: [PlacedItem], totalHeight: CGFloat) {
        guard !subviews.isEmpty else { return ([], 0) }
        
        let colWidth = floor(max((width - spacing) / 2.0, 80.0))
        var occupied = Set<GridCoord>()
        var plans: [PlacementPlan] = []
        
        // 1. Assign grid coordinates using deterministic 2-column bin-packing
        for index in subviews.indices {
            let span = subviews[index][WidgetSpanKey.self]
            let colSpan = min(max(span.colSpan, 1), 2)
            let rowSpan = min(max(span.rowSpan, 1), 2)
            
            if colSpan == 2 {
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
                
                for dr in 0..<rowSpan {
                    let r = targetRow + dr
                    occupied.insert(GridCoord(row: r, col: 0))
                    occupied.insert(GridCoord(row: r, col: 1))
                }
                
                plans.append(PlacementPlan(index: index, startRow: targetRow, col: 0, colSpan: 2, rowSpan: rowSpan))
            } else {
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
                
                for dr in 0..<rowSpan {
                    let r = targetRow + dr
                    occupied.insert(GridCoord(row: r, col: targetCol))
                }
                
                plans.append(PlacementPlan(index: index, startRow: targetRow, col: targetCol, colSpan: 1, rowSpan: rowSpan))
            }
        }
        
        let maxRow = occupied.map(\.row).max() ?? -1
        guard maxRow >= 0 else { return ([], 0) }
        let totalRows = maxRow + 1
        
        // 2. Measure dynamic row heights based on subview contents
        var rowHeights = [CGFloat](repeating: 0, count: totalRows)
        
        // Pass A: Single-row items (colSpan == 2 for Wide, colSpan == 1 for Small)
        for plan in plans where plan.rowSpan == 1 {
            let itemWidth = (plan.colSpan == 2) ? width : colWidth
            let measured = subviews[plan.index].sizeThatFits(ProposedViewSize(width: itemWidth, height: nil))
            if plan.colSpan == 2 {
                // Wide items span both columns: height is exactly their natural content height
                rowHeights[plan.startRow] = ceil(max(rowHeights[plan.startRow], max(measured.height, 80)))
            } else {
                // Small items: use at least defaultUnitHeight (150)
                rowHeights[plan.startRow] = ceil(max(rowHeights[plan.startRow], max(measured.height, defaultUnitHeight)))
            }
        }
        
        // Pass B: Multi-row items (Tall and Large, rowSpan == 2)
        for plan in plans where plan.rowSpan == 2 {
            let r0 = plan.startRow
            let r1 = r0 + 1
            if r1 < totalRows {
                let itemWidth = (plan.colSpan == 2) ? width : colWidth
                let measured = subviews[plan.index].sizeThatFits(ProposedViewSize(width: itemWidth, height: nil))
                
                if rowHeights[r0] == 0 && rowHeights[r1] == 0 {
                    let half = ceil(max((measured.height - spacing) / 2.0, defaultUnitHeight))
                    rowHeights[r0] = half
                    rowHeights[r1] = half
                } else if rowHeights[r0] == 0 {
                    rowHeights[r0] = ceil(max(measured.height - spacing - rowHeights[r1], defaultUnitHeight))
                } else if rowHeights[r1] == 0 {
                    rowHeights[r1] = ceil(max(measured.height - spacing - rowHeights[r0], defaultUnitHeight))
                } else {
                    let currentSum = rowHeights[r0] + spacing + rowHeights[r1]
                    if measured.height > currentSum {
                        let diff = ceil((measured.height - currentSum) / 2.0)
                        rowHeights[r0] += diff
                        rowHeights[r1] += diff
                    }
                }
            }
        }
        
        // Fallback for any unmeasured rows
        for r in 0..<totalRows {
            if rowHeights[r] <= 0 {
                rowHeights[r] = defaultUnitHeight
            }
        }
        
        // 3. Compute row cumulative Y positions
        var rowY = [CGFloat](repeating: 0, count: totalRows)
        var currentY: CGFloat = 0
        for r in 0..<totalRows {
            rowY[r] = currentY
            currentY += rowHeights[r] + spacing
        }
        let totalHeight = currentY > 0 ? ceil(currentY - spacing) : 0
        
        // 4. Compute exact frame rectangles for each placed item (pixel-aligned)
        var items: [PlacedItem] = []
        for plan in plans {
            let x = floor((plan.col == 0) ? 0 : colWidth + spacing)
            let y = floor(rowY[plan.startRow])
            let w = floor((plan.colSpan == 2) ? width : colWidth)
            
            let h: CGFloat
            if plan.rowSpan == 1 {
                h = floor(rowHeights[plan.startRow])
            } else {
                let r1 = plan.startRow + 1
                if r1 < totalRows {
                    h = floor(rowHeights[plan.startRow] + spacing + rowHeights[r1])
                } else {
                    h = floor(rowHeights[plan.startRow])
                }
            }
            
            let rect = CGRect(x: x, y: y, width: w, height: h)
            items.append(PlacedItem(index: plan.index, rect: rect))
        }
        
        return (items, totalHeight)
    }
    
    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let width = floor(proposal.width ?? 353)
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
            let origin = CGPoint(x: floor(bounds.origin.x + item.rect.origin.x), y: floor(bounds.origin.y + item.rect.origin.y))
            subviews[item.index].place(
                at: origin,
                proposal: ProposedViewSize(item.rect.size)
            )
        }
    }
}
