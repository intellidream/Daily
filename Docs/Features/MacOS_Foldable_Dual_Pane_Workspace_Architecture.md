# macOS Foldable Dual-Pane Workspace ("The Hybrid Co-Pilot") Architecture

## 1. Executive Summary & Vision

As part of the cross-platform unified architecture across **macOS**, **iOS (iPhone Duo)**, and **Android (Galaxy Z Fold 8 "RADAR")**, the macOS desktop app features the signature **Foldable Dual-Pane Workspace ("The Hybrid Co-Pilot")**.

On a desktop canvas, having a single narrow mobile-width column wastes valuable horizontal screen real estate. The Dual-Pane Workspace solves this by transforming DayOne macOS into a dual-column productivity powerhouse:
- **Left Column (Master Cockpit)**: Real-time telemetry, quick-log actions (`+150ml`, `+Cig`, quick notes), widget rows, and anchored `FloatingGlassCapsule`.
- **Right Column (Companion & Detail)**:
  - When on `.dashboard`: Hosts the **Hybrid Co-Pilot** (`DailyFoldableCompanionPane`), offering deep synthetic intelligence, Concentric Recovery Rings, Mascot readiness, and an interactive Co-Pilot prompt studio.
  - When navigating to any Hub (`Weather`, `News`, `Health`, `Habits`, `Finances`, `Tagdos`, `Settings`): Embeds the active Hub directly into the secondary pane seamlessly on the native window background, keeping the Master Cockpit persistently accessible on the left.

Users retain total freedom to seamlessly toggle between the **Dual-Pane Co-Pilot (Wide - 1040pt)** and **Single-Column (Compact - 480pt)** anytime via the toolbar split button, the `⌘D` shortcut, or app Settings.

---

## 2. Core Architectural Pillars

### A. The Master Cockpit (Left Column)
- **Width**: `minWidth: 420pt, maxWidth: 500pt`.
- **Contents**: Full `DashboardView` containing Hero greeting, biometric recovery overview, quick habit actions, widget feeds, and the floating glass pill navigation capsule.
- **Top Alignment**: Aligned at `padding(.top, 8)` to establish a clean, continuous horizontal baseline with the secondary Companion header and Hub navigation bars.
- **Glass Crease**: A delicate 1px glass line (`Color.white.opacity(0.08)`) separates the master cockpit from the companion detail pane.

### B. The Hybrid Co-Pilot & Detail Pane (Right Column)
- **Width**: `minWidth: 440pt, maxWidth: .infinity` (fluid full-width scaling when window is resized).
- **Modes**:
  1. **Co-Pilot Overview (`selectedTab == .dashboard`)**:
     - **Diurnal Intelligence Header**: Real-time daytime/nighttime status, active date, and live telemetry pulse badge.
     - **Concentric Recovery Rings Hero**: 3 layered progress rings (Steps, Sleep Score, Hydration) surrounding the animated Monkey Mascot (`.mini`, 44pt), plus an interactive metrics legend and shadow-backed typography.
     - **Monkey Co-Pilot Studio**: 5 prefabricated prompt chips (*Sleep & Readiness*, *Circadian Hydration*, *Urgent Focus*, *Stress & Breathing*, *Cashflow Pulse*) with conversational turn history, key actionable highlights, a free-form question input bar, and direct Hub portal buttons.
     - **Daily Spotlight & Portals Cards**: Non-redundant composite cards covering Focus Streams, Circadian Bio-Guidance, Cashflow Momentum, and Radar & Sky with 1-click Hub transitions.
  2. **Direct Embedded Hub Detail (`selectedTab != .dashboard`)**:
     - **Clean Native Navigation**: Direct rendering without redundant secondary headers (no duplicate titles or close buttons); the active Hub's native back button (`chevron.left`) smoothly returns to the Co-Pilot Overview.
     - **Unified Window Backdrop**: Zero nested/duplicate `LiquidGlassBackground` wrappers; hub views render directly on the root window material.
     - **Fluid Desktop Scalability**: Hardcoded max-width barriers (`maxWidth: 880` / `740`) removed in favor of `.frame(maxWidth: .infinity)`, allowing Hubs to stretch across the full available canvas upon window expansion.

---

## 3. Ergonomic Switching & Window Dynamics

### 1. Toolbar Split Button
A dedicated button is placed in the top navigation toolbar directly beside the sidebar toggle:
- When Dual-Pane is active: Renders `rectangle.split.2x1.fill` with cyan highlight.
- When Single-Column is active: Renders `rectangle.split.2x1` with semi-translucent white.
- Provides immediate visual feedback and AppKit haptic confirmation (`NSHapticFeedbackManager.defaultPerformer.perform(.generic, ...)`).

### 2. Window Frame Animation
`MacOSWindowManager.shared.setMainWindowDualPane(enabled:)` manages window sizing:
- **Enabling Dual-Pane**: Expands `NSWindow.frame.size.width` to `1040pt`, automatically adjusting origin `x` to remain centered on screen without jumping off display boundaries.
- **Enabling Compact Mode**: Smoothly shrinks `NSWindow.frame.size.width` to `480pt`, centering smoothly.
- Both transitions use AppKit animated frame set (`window.setFrame(currentFrame, display: true, animate: true)`).

### 3. Keyboard Shortcuts
- **`⌘ D`**: Instant toggle between Dual-Pane and Single-Column modes.
- **`Esc`**: When an embedded Hub is open in Dual-Pane mode, immediately returns the right pane to the Co-Pilot Overview (`selectedTab = .dashboard`).
- **`⌘ 1 – 7`**: Quickly switches the right pane to the corresponding Hub while keeping the left cockpit in place.
- **`⌘ S`**: Toggles the Desktop Sidebar, which seamlessly slides alongside the dual-pane workspace.

### 4. Settings Preference
In `SettingsView` -> `macOS Desktop Integration`:
- Added a segmented picker for **Workspace Layout**:
  - `Dual-Pane Co-Pilot (Wide)` (Default)
  - `Single-Column (Compact)`
- Persisted in `@AppStorage("useDualPaneWorkspace")`.

---

## 4. Cross-Platform Parity Details

### Android (Galaxy Z Fold 8 "RADAR")
- **Concentric Recovery Rings Mascot Scale**: Adjusted mascot size from `MonkeySize.CARD` (80dp) to `MonkeySize.MINI` (44dp). Previously, the 80dp mascot overflowed the innermost 102dp hydration circle, pushing the stress text awkwardly over the circular progress tracks.
- **Typography Shadow**: Added high-contrast black drop shadow (`Offset(0f, 2f)`, `blurRadius = 4f`) to ensure crisp legibility inside the concentric rings across all themes.

### iOS (iPhone Duo)
- **Top Alignment**: Balanced `DashboardView` top padding with the unfolded companion pane header (`10pt`).
- **Typography Shadow**: Synchronized text drop shadow across iOS mascot status labels.

---

## 5. Verification & Performance

1. **macOS Native Verification**:
   - Clean compilation on Apple Silicon (ARM64) macOS 15.0+ target (`xcodebuild ... CODE_SIGNING_ALLOWED=NO build`).
   - Window resize tested up to 1400pt wide; verified seamless fluid width scaling across Hubs (`macos_dualpane_health_wide_1400.png`).
   - Left hero card / right companion header top alignment verified (`macos_dualpane_aligned_dashboard.png`).
   - Redundant detail header and duplicate backgrounds eliminated (`macos_dualpane_health_no_extra_header.png`).
   - Keyboard return (`Esc` / back button) to Co-Pilot overview verified (`macos_dualpane_returned_copilot.png`).
   - Idle CPU verified at 0.0% - 1.8%.
2. **Android Verification**:
   - Clean build via `./gradlew assembleDebug` passed in 30s.
3. **iOS Verification**:
   - Clean build via `xcodebuild -project iOS/Daily.xcodeproj` passed for simulator destinations.
