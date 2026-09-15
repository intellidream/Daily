# Sleep Widget Progress Ring Inset & Stroke Clipping Fix

**Date**: 2026-09-15  
**Platform**: iOS (WidgetKit & SwiftUI)  
**Files Modified**: `iOS/DailyWidgets/SleepWidget.swift`  
**Target Device**: Physical iPhone "Schmitz" (`62990754-1EE9-5A95-A45E-F4A69DA6E591`)

---

## 1. Problem Overview
In SwiftUI WidgetKit views with `.clipped()` container bounds, progress rings drawn using `Circle().stroke(lineWidth: W)` center the stroke on the circle's bounding path. This causes `lineWidth / 2` (3.5pt to 4.5pt) to bleed outside the frame dimensions, resulting in clipped or flattened circular edges on the top, left, right, or bottom across all Sleep widget sizes (Small, Medium, Large, and No Data empty states).

---

## 2. Root Cause Analysis
- `Circle().stroke(lineWidth: W)` draws half the stroke width outside the frame.
- While `Circle().strokeBorder(...)` automatically insets the stroke by `lineWidth / 2`, it requires an `InsettableShape`. Calling `.trim(from:to:)` returns a shape that loses `InsettableShape` conformance.
- Therefore, calling `.inset(by: lineWidth / 2)` directly on `Circle()` **prior** to `.trim(...)` and `.stroke(...)` is the definitive SwiftUI solution to guarantee zero outer bleed while preserving full stroke width and round caps.

---

## 3. Changes Applied
In `iOS/DailyWidgets/SleepWidget.swift`:
1. **Small (1x1) Live View**:
   - Applied `.inset(by: 3.5)` to both background and progress circles (7.0pt stroke).
   - Adjusted top/leading padding to `2pt`.
2. **Medium (2x1) Live View**:
   - Applied `.inset(by: 3.75)` to both background and progress circles (7.5pt stroke).
   - Added `2pt` leading and vertical padding to prevent container clipping.
3. **Large (2x2) Live View**:
   - Applied `.inset(by: 4.5)` to both background and progress circles (9.0pt stroke).
   - Added `2pt` padding.
4. **Small (1x1) No Data View**:
   - Applied `.inset(by: 2.0)` to 4pt stroke circle.
   - Added `2pt` top/leading padding.
5. **Medium (2x1) No Data View**:
   - Applied `.inset(by: 3.0)` to 6pt stroke circle.
6. **Large (2x2) No Data View**:
   - Applied `.inset(by: 4.0)` to 8pt stroke circle.

---

## 4. Verification & Delivery
- **Direct Physical Device Delivery**: Built cleanly for ARM64 (`iphoneos`) and installed directly onto iPhone "Schmitz".
- **Execution**: Launched and verified live on device without crashes or layout truncation.
