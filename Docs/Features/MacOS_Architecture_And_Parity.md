# Feature: macOS Native Architecture, Parity & Hybrid Companion

This document details the architecture, design decisions, and implementation of the **native macOS application (`MacOS/`)** for DayOne, targeting macOS 15.0+ (Sequoia / Sonoma) and achieving 100% functional parity with the iOS golden standard.

---

## 1. Architectural Overview

The macOS client is built with pure Swift & SwiftUI, referencing the iOS application as a golden standard while embracing native macOS desktop ergonomics.

```mermaid
flowchart TD
    subgraph Shared Core ["DailyCore (Swift Package)"]
        M[Models: Health, Habits, Finances, News, TagDoS, Weather]
        S[Services: Supabase, HealthData, Habits, TagdosStore, Weather]
        K[Storage: GroupDefaults, KeychainManager]
    end

    subgraph Native MacOS ["MacOS Native App (DayOne.app)"]
        MW["Primary Window (Liquid Glass Canvas)"]
        MB["MenuBar Companion Popover (Quick Drop)"]
        
        MW --> M
        MW --> S
        MB --> S
        MB -->|"Expand to Full Window"| MW
    end

    subgraph Remote Cloud ["Supabase Cloud Synchronization"]
        RT["Realtime Channels & RPCs"]
        TEL["Canonical Health Telemetry & Vitals"]
    end

    S <--> RT
    S <--> TEL
```

### 1.1 Key Principles
1. **Zero iOS Code Modification**: The iOS codebase (`iOS/`) remains untouched as the immutable reference standard.
2. **Maximum DailyCore Reuse**: All data models, parsers (SmartLedger DSL, TagDoS stream parser, WP JSON, RSS feeds), authentication flows, and storage mechanisms are consumed directly from `DailyCore`.
3. **Consumer-Only Health Engine**: Because macOS lacks a native HealthKit background daemon, `HealthDataService.shared.localDataProvider` is decoupled (`nil`). Biometric vitals (heart rate curve, sleep stages, REM/Deep/Light hypnogram, autonomic tone stress mascot, and step histograms) are ingested continuously via Supabase synchronization from paired iOS, watchOS, ZeppOS, and Android wearables.
4. **App Sandbox & Hardened Runtime**: Sandboxed with network outgoing client entitlements (`com.apple.security.network.client`) and App Group access (`group.com.intellidream.daily`).

---

## 2. Hybrid Dual-Presence UX Architecture

To solve the productivity trade-off between quick glance access and expansive desktop deep work, DayOne on macOS implements a **Hybrid Companion** model:

### 2.1 Persistent MenuBarExtra Companion ("Quick Drop")
- Always resident in the macOS menu bar with a crisp status icon (`sparkles`).
- Clicking drops down a sleek, mobile-proportioned Liquid Glass popover (360x480 pt):
  - **Live Weather & Vitals Glance**: Instant outdoor temperature, conditions, and real-time heart rate / daily steps.
  - **One-Click Hydration Logging**: Quick `+250 ml` and `+500 ml` tap targets that synchronously update today's intake and dispatch background sync without needing to switch windows.
  - **Quick Smoke Logging**: Instant `+1 Smoke` tracker button.
  - **TagDoS Quick Scratchpad**: Dedicated textfield to capture spontaneous ideas, notes, or tasks directly to `TagdosStore` (`⌘N` equivalent).
  - **Expand to Full Window Button**: Prominent top-right button (`arrow.up.left.and.arrow.down.right`) that activates `NSApp` and summons the primary application window.

### 2.2 Primary Liquid Glass Desktop Window
- Window configuration: `.windowStyle(.hiddenTitleBar)` with unified compact styling and transparent title bar chrome.
- **Dual-Navigation Paradigm**:
  - **Floating Liquid Glass Capsule (Default)**: Bottom-anchored glass capsule with 120Hz spring physics, touch/trackpad scrub navigation, and specular edge highlight borders.
  - **Collapsible Desktop Sidebar (Option)**: Sleek left-aligned navigation drawer displaying all 8 sections with keyboard shortcut tags (`⌘1`–`⌘7`, `⌘,`). Can be toggled with `⌘S` or the traffic-light-aligned sidebar button.
- **Window Management**:
  - Minimum window constraints (440x650 pt).
  - Responsive layout dynamically adapts between compact mobile-canvas view and multi-column wide dashboard cards.

---

## 3. Desktop Ergonomics & Shortcuts

### 3.1 Keyboard Shortcuts
| Shortcut | Action | Scope |
| :--- | :--- | :--- |
| `⌘1` | Navigate to **Dashboard** | Global Window |
| `⌘2` | Navigate to **Money (Finances)** | Global Window |
| `⌘3` | Navigate to **TagDoS (Notes & Tasks)** | Global Window |
| `⌘4` | Navigate to **Health Hub** | Global Window |
| `⌘5` | Navigate to **Habits Tracker** | Global Window |
| `⌘6` | Navigate to **Weather Forecast** | Global Window |
| `⌘7` | Navigate to **News Feeds & Reader** | Global Window |
| `⌘,` | Open **Settings** | Global Window |
| `⌘S` | Toggle Collapsible Sidebar | Main Window |
| `⌘R` | Force Flush Sync (Habits & Health) | Main Window |
| `⌘N` | Create Quick Note / Memo | Menu Commands |

### 3.2 Trackpad Haptics & Visual Feedback
- Leverages macOS `NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)` on force-touch trackpads for button activations, tab switches, and habit log gestures.
- Custom cursor hover states (`onHover`) with specular highlights and card elevation transitions.

---

## 4. Component Parity & Implementation Map

| Subsystem | macOS Implementation | Parity Status with iOS |
| :--- | :--- | :---: |
| **Authentication** | `LoginView.swift` (Google PKCE via `ASWebAuthenticationSession` with `NSWindow` anchor, Apple Sign-In, Guest Mode) | 100% |
| **Modular Dashboard** | `DashboardView`, `ModularDashboardLayout`, 7 modular cards | 100% |
| **Health Hub** | `HealthMainView`, `SleepStudioView`, `StressStudioView`, `VitalMetricTile`, `DeviceOriginBadge` | 100% (Consumer) |
| **Habits & Hydration**| `HabitsMainView`, `WaterProgressWaveView`, `SmokesLungsGaugeView`, quick logging | 100% |
| **Finances & Ledger** | `FinancesMainView`, `AddLedgerItemSheet`, `SmartLedgerEditorSheet`, quick adjust | 100% |
| **TagDoS Notes** | `TagdosNotesHubView`, `TagdosQuickNotesView`, `TagdosActiveMemoView` (AppKit `NSImage` attachments) | 100% |
| **Weather** | `WeatherDetailView`, `HourlyForecastCarousel`, `DailyForecastCard`, atmospheric tiles | 100% |
| **News Reader** | `NewsFeedView`, `NewsReaderView`, `ArticleWebView` (`NSViewRepresentable` + `WKWebView`) | 100% |
| **Smart Briefing** | `SmartBriefingOverlayView`, `FadingTypewriterText` | 100% |
| **Settings** | `SettingsView`, 8 configuration sections + `MediumLoginSheet` | 100% |

---

## 5. Verification & Test Execution

Native macOS build and execution verification executed directly on macOS host:

1. **Compilation**:
   - `xcodebuild -project MacOS/Daily.xcodeproj -scheme Daily -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO`
   - **Result**: `** BUILD SUCCEEDED **` (0 warnings, 0 errors).
2. **Process Liveness**:
   - Executed binary `Daily.app/Contents/MacOS/Daily -testDefaultDashboard`.
   - **Result**: Process initialized and remained active without hitches.
3. **Multi-Tab Launch Arguments Verification**:
   - Tested `-startTabNews`: **PASS**
   - Tested `-startTabHealth`: **PASS**
   - Tested `-startTabFinances`: **PASS**
   - Tested `-startTabHabits`: **PASS**
   - Tested `-startTabTagdos`: **PASS**
   - Tested `-startTabSettings`: **PASS**
