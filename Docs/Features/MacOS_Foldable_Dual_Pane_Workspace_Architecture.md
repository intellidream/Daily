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

### 5. Hub Navigation Bar & Ergonomic Unification
- **Pinned Top Navigation Bar**:
  - Pinned top header navigation bars across all embedded hubs (`HabitsMainView`, `WeatherDetailView`, `SettingsView`, `FinancesMainView`, `TagdosNotesHubView`) with unified `padding(.top, 8)` and `padding(.horizontal, 20)`.
  - Eliminated legacy internal padding in `HabitsMainView` header (removed redundant `.padding(.top, 12)`), ensuring 100% pixel-perfect vertical baseline alignment with the other secondary hubs and the primary cockpit.
  - Content scrolling is decoupled below the header using `ScrollViewReader`, ensuring back navigation and action triggers remain accessible at all times without jumping during vertical scroll bounces.
  - Aligns top horizontal baseline with the left Hero card and Co-Pilot Studio header for a harmonious dual-pane visual balance.
- **Unified Action Control Language**:
  - Replaced divergent pill capsules or raw text buttons (such as in `TagdosNotesHubView`) with standardized `36x36` circular frosted glass buttons (`Circle().fill(Color.white.opacity(0.08)).overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))`).
  - Standardized font typography (`14pt .bold`) across all secondary hub back buttons and quick-action icons.
  - Eliminated native AppKit pop-up button / combo box bezel and preserved frosted glass circular styling on the macOS `NewsFeedView` category selector menu by architecting a `ZStack` containing a cyan frosted glass `Circle()` backdrop (`Circle().fill(ThemeColors.accentCyan.opacity(0.15))`) overlaid with a borderless AppKit `Menu` (`.menuStyle(.borderlessButton)`, `.menuIndicator(.hidden)`). This circumvents AppKit's flattening behavior (which stripped backgrounds inside `label:`) while maintaining right-margin alignment and clean circular geometry.
- **Elimination of Redundant Containers & Constraints**:
  - Removed duplicate header bars from the secondary pane; views render seamlessly and leverage their own native back controls to transition back to Co-Pilot overview.
  - Stripped redundant outer glass card backgrounds and hardcoded max-width constraints, allowing all hubs to fluidly fill expanded desktop windows up to ultrawide dimensions without letterboxing.
  - Removed nested `LiquidGlassBackground` wrappers from all hub views on both macOS and iOS (`HealthMainView`, `FinancesMainView`, `NewsFeedView`, `TagdosNotesHubView`), ensuring secondary hubs inherit the root backdrop seamlessly without rendering disjointed dark boxes or card seams.

### 6. DayOne Glance Companion Ergonomics & App Lifecycle
- **Auto-Hide / Dismiss on Full App Trigger**:
  - When the user taps the top-right **"Full App"** button or clicks any quick-jump card/button (Weather, Health, Money, Habits, TagDoS, News) in Glance, the Glance floating HUD window immediately hides/closes (`dismissWindow(id: "glance")` and `MacOSWindowManager.shared.closeGlanceWindow()`). This prevents the floating companion from awkwardly hovering over and occluding the primary full-sized workspace.
  - When summoned subsequently via `⌘ 0`, menu bar action, or URL `daily://glance`, `MacOSWindowManager.shared.activateGlanceWindow()` brings the companion window smoothly back to the foreground.
- **Exit DayOne Action Button (WinUI 1:1 Parity)**:
  - Integrated an **Exit DayOne** action button at the bottom of `MenuBarCompanionView`, positioned directly beneath the quick-jump navigation grid and separated by a subtle 1pt glass divider (`Color.white.opacity(0.1)`), matching the layout of the WinUI Taskbar Glance flyout.
  - Includes an SF Symbol `power` glyph, muted idle typography (`ThemeColors.fgMutedDark`), and an interactive liquid glass red hover highlight (`Color.red.opacity(0.12)` fill, `0.25` stroke, and `0.95` foreground).
  - Explicitly terminates the application through `NSApplication.shared.terminate(nil)` supported by `AppDelegate.applicationShouldTerminate(_:) -> .terminateNow` and fallback teardown, enabling complete application exit directly from Glance without requiring menu navigation.

---

## 4. Cross-Platform Parity Details

### Android (Galaxy Z Fold 8 "RADAR")
- **Concentric Recovery Rings Mascot Scale**: Adjusted mascot size from `MonkeySize.CARD` (80dp) to `MonkeySize.MINI` (44dp). Previously, the 80dp mascot overflowed the innermost 102dp hydration circle, pushing the stress text awkwardly over the circular progress tracks.
- **Typography Shadow**: Added high-contrast black drop shadow (`Offset(0f, 2f)`, `blurRadius = 4f`) to ensure crisp legibility inside the concentric rings across all themes.
- **Secondary Hub Consistency**: Parameterized `horizontalPadding` and `applyStatusBarsPadding` across all Android hubs, eliminating double outer margins and ensuring 1:1 proportional symmetry between master dashboard and detail hubs.

### iOS (iPhone Duo & Physical iPhone Schmitz)
- **Top Alignment**: Balanced `DashboardView` top padding with the unfolded companion pane header (`10pt`).
- **Typography Shadow**: Synchronized text drop shadow across iOS mascot status labels.
- **Unified Dual-Pane Backdrop**: Removed nested `LiquidGlassBackground` from all 4 secondary hub views (`HealthMainView`, `FinancesMainView`, `NewsFeedView`, `TagdosNotesHubView`). On iPhone Duo unfolded split-screen, secondary hubs now smoothly share the root `LiquidGlassBackground` without redundant card layers or hard cutoff gradients.
- **News Category Selector Parity**: Maintained circular frosted button with cyan accent tint and hidden indicator on both iPhone Duo and compact iPhones.

---

## 5. Verification & Deployment Matrix

| Platform / Target | Environment / Device | Test / Deployment Procedure | Status | Result & Live Telemetry |
| :--- | :--- | :--- | :--- | :--- |
| **macOS Desktop** | macOS 15.0+ (ARM64 Apple Silicon) | Xcodebuild native compilation + runtime inspection | **PASS** | 0.0% idle CPU; window toggle 1040pt <-> 480pt; fluid hub resize; pinned top bars; circular frosted News category menu verified; Glance auto-dismiss on full app verified; Exit DayOne full termination verified |
| **iOS (iPhone Duo)** | SimulaDuo (`6BB33377-B7BD-4306-9BBA-AACBD99FBC76`) | Xcodebuild + `simctl install` + launch | **PASS** | Launched live (PID 20720); dual-pane split verified; nested hub backgrounds eliminated; seamless root backdrop |
| **iOS Simulator** | SimulaPhone (`E618B1DA-82AC-477A-A6D6-CC11F969FA62`) | Xcodebuild + `simctl install` + launch | **PASS** | Launched live (PID 20766); verified clean single-screen rendering |
| **Physical iPhone** | iPhone 16 Pro ("Schmitz", `00008140-000E2C863EFB001C`) | Xcodebuild for device + `devicectl install` + launch | **VERIFIED LIVE** | Success; launched live via devicectl; verified category menu and seamless hub views |
| **Android Foldable Emulator** | Pixel 9 Pro Fold (`emulator-5554`) | `./gradlew assembleDebug` + `adb install` + launch | **PASS** | Launched live (PID 12548); concentric rings & MINI mascot verified |
| **Samsung Galaxy Z Fold 8** | Physical Device ("RADAR", `SM-F971B`) | Wireless ADB mDNS TLS (`port 5038`) + streamed install | **VERIFIED LIVE** | Success; launched PID 16404; zero fatal logcat crashes; rings verified |
| **Google Pixel 9 Pro** | Physical Device (`caiman`) | Wireless ADB mDNS TLS (`port 5038`) + streamed install | **VERIFIED LIVE** | Success; launched live |

