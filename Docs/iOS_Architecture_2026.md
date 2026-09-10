# DayOne Native iOS Application Architecture (2026)

This document outlines the architectural patterns, component structure, UI design system, and multiplatform integration for the native **DayOne iOS application** within the Daily ecosystem.

---

## 1. System Overview & Multiplatform Strategy

The iOS application is engineered as a high-performance, native SwiftUI application, modeled after the desktop experience of the **WinUI 3** app while adhering to modern iOS 18+ and iOS 26+ design conventions.

To support rapid future development of the native **macOS** application without code duplication, all shared business logic, domain models, database synchronization, and authentication are encapsulated in a multiplatform Swift package located at the repository root: **`DailyCore`**.

```
Daily/
├── DailyCore/                              <-- Shared Multiplatform Swift Package (iOS + macOS)
│   ├── Package.swift
│   └── Sources/DailyCore/
│       ├── Models/                         <-- AppSettings, UserProfile, HealthTelemetry, etc.
│       ├── Services/                       <-- SupabaseService, AuthService, SettingsService
│       ├── Storage/                        <-- KeychainManager, GroupDefaults
│       └── Utilities/
├── iOS/                                    <-- Native iOS Target
│   ├── Daily.xcodeproj
│   └── Daily/
│       ├── App/                            <-- DailyApp, lifecycle & URL handling
│       ├── DesignSystem/                   <-- Liquid Glass, ThemeColors, GlassCard, GlassButton
│       ├── Views/                          <-- Login, Dashboard, Settings
│       └── Resources/                      <-- Info.plist, Assets.xcassets, Entitlements
├── WatchOS/                                <-- Apple Watch Companion App (Swift / HealthKit)
├── WinUI/                                  <-- Windows Desktop Application (.NET 10 / WinUI 3)
└── Docs/                                   <-- Architecture & Feature Specifications
```

---

## 2. Shared Core (`DailyCore`) Architecture

### 2.1 Multiplatform Package
`DailyCore` compiles for both `iOS (.v18+)` and `macOS (.v15+)`. It has zero dependency on `UIKit` or `AppKit` presentation logic, making it completely reusable for both platforms.

- **Dependencies**: `supabase-swift` (v2.5.1+)
- **Concurrency**: Swift 6 structured concurrency (`async`/`await`, `@MainActor`, `Sendable`).

### 2.2 Secure Storage & App Group Sharing
To enable seamless data sharing between the iOS app, the Apple Watch companion (`DailyWatch`), widget extensions, and the upcoming macOS app, `DailyCore` uses:
1. **`KeychainManager`**: Hardware-backed credential store (`kSecClassGenericPassword`) configured with the App Group access group (`group.com.intellidream.daily`).
2. **`GroupDefaults`**: `UserDefaults(suiteName: "group.com.intellidream.daily")` used for storing serialized `AppSettings` and token mirrors.

### 2.3 Proactive Session & Supabase Client
- Uses the unified cloud project:
  - **URL**: `https://akkfouifxztnfwwiclwg.supabase.co`
  - **Anon Key**: `sb_publishable_6FzrRSdmsH4arDhZS09PSQ_QK_I31DG`
- Configured with `SupabaseKeychainStorage` adhering to `AuthLocalStorage` to persist Gotrue auth sessions securely.

---

## 3. Authentication Engine (`AuthService`)

Modeled after WinUI's `WinUIAuthService.cs`, `AuthService` provides three distinct entry points:

### 3.1 Google OAuth via PKCE Flow
- Initiates an OAuth PKCE challenge with Supabase Auth (`Provider.google`).
- Uses `ASWebAuthenticationSession` targeting the custom URL scheme `com.intellidream.daily://login-callback`.
- Intercepts the authorization code and exchanges it for a persistent cloud session.

### 3.2 Native Sign in with Apple
- In accordance with App Store Review Guideline 4.8, Apple Sign-In is provided alongside Google.
- Uses `SignInWithAppleButton` with cryptographic SHA-256 nonce generation.
- Validates the identity token directly via Supabase Auth `signInWithIdToken`.

### 3.3 Guest / Local Exploration Mode
- Mirrors WinUI's "Continue without signing in" (Skip option).
- Allows full interactive use of the application offline or in development without blocking on remote authentication.

### 3.4 User Profile & First Name Extraction Heuristic
Derives `CurrentUserFirstName` using the exact heuristic from the WinUI desktop app:
1. Splits `full_name` or `name` by spaces and picks the first segment.
2. If absent, parses the email local part (splitting on `.`, `_`, or `-`) and capitalizes the leading token.
3. Fallback: `"User"` (or `"Friend"` in Guest mode).

---

## 4. User Interface Architecture & Tactile Liquid Glass

The UI adapts WinUI's tactile glassmorphism into a fluid iOS experience.

### 4.1 Color System (`ThemeColors.swift`)
- **Background Gradient**: Multi-stop vertical stops (`#030609` -> `#050F1A` -> `#0D1A35` -> `#132B4A`).
- **Glow & Accents**: Electric Cyan (`#00E5FF`) and Sleek Blue (`#4A9EFF`).
- **Light Theme**: Warm sand paper tone (`#D4C9B0`).

### 4.2 Liquid Glass Card (`GlassCard.swift`)
Combines:
- Native `.ultraThinMaterial` blur.
- Dynamic fill opacity scaling with the user's `GlassIntensity` setting (`Subtle` 12%, `Medium` 20%, `Prominent` 32%).
- Specular edge reflection: Multi-stop linear border gradient (`white.opacity(0.35)` to `white.opacity(0.10)` to transparent).
- Diffused drop shadow (`radius: 12`, `opacity: 0.35`).

### 4.3 Floating Glass Capsule Navigation (`FloatingGlassCapsule.swift`)
- Replaces traditional iOS tab bars with a floating translucent glass pill anchored above the bottom safe area.
- Animated capsule indicator with spring physics (`.spring(response: 0.35, dampingFraction: 0.75)`).
- Tactile haptic feedback (`UIImpactFeedbackGenerator`) on tab transitions.

---

## 5. Next Implementation Phases

| Phase | Scope | Core Components |
| :--- | :--- | :--- |
| **Phase 1 (Complete)** | Architecture, Shared Package, Login, Settings, Dashboard Scaffold | `DailyCore`, `AuthService`, `SettingsService`, `LoginView`, `SettingsView`, `FloatingGlassCapsule` |
| **Phase 2** | Weather Feature | OpenWeatherMap API, CoreLocation + IP fallback (`freeipapi.com`), 5-day forecast view |
| **Phase 3** | News Feature | RSS/Atom + WP-JSON parser, Supabase favorites/read-later sync, clean reader view |
| **Phase 4** | Health Telemetry | HealthKit background queries, Supabase `health_telemetry` sync, 7-day vitals trends |
| **Phase 5** | macOS Target | AppKit/SwiftUI desktop UI sharing `DailyCore` |
