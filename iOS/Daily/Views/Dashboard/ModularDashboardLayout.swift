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
                rowHeights[plan.startRow] = max(rowHeights[plan.startRow], max(measured.height, 80))
            } else {
                // Small items: use at least defaultUnitHeight (150)
                rowHeights[plan.startRow] = max(rowHeights[plan.startRow], max(measured.height, defaultUnitHeight))
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
                    let half = max((measured.height - spacing) / 2.0, defaultUnitHeight)
                    rowHeights[r0] = half
                    rowHeights[r1] = half
                } else if rowHeights[r0] == 0 {
                    rowHeights[r0] = max(measured.height - spacing - rowHeights[r1], defaultUnitHeight)
                } else if rowHeights[r1] == 0 {
                    rowHeights[r1] = max(measured.height - spacing - rowHeights[r0], defaultUnitHeight)
                } else {
                    let currentSum = rowHeights[r0] + spacing + rowHeights[r1]
                    if measured.height > currentSum {
                        let diff = (measured.height - currentSum) / 2.0
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
        var currentY = origin.y
        for r in 0..<totalRows {
            rowY[r] = currentY
            currentY += rowHeights[r] + spacing
        }
        let totalHeight = currentY > origin.y ? (currentY - spacing - origin.y) : 0
        
        // 4. Compute exact frame rectangles for each placed item
        var items: [PlacedItem] = []
        for plan in plans {
            let x = (plan.col == 0) ? origin.x : origin.x + colWidth + spacing
            let y = rowY[plan.startRow]
            let w = (plan.colSpan == 2) ? width : colWidth
            
            let h: CGFloat
            if plan.rowSpan == 1 {
                h = rowHeights[plan.startRow]
            } else {
                let r1 = plan.startRow + 1
                if r1 < totalRows {
                    h = rowHeights[plan.startRow] + spacing + rowHeights[r1]
                } else {
                    h = rowHeights[plan.startRow]
                }
            }
            
            let rect = CGRect(x: x, y: y, width: w, height: h)
            items.append(PlacedItem(index: plan.index, rect: rect))
        }
        
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
