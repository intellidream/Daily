# Feature: iOS Login & Settings (Liquid Glass Experience)

This document details the design, architecture, and implementation of the **Login & Settings** experience for the native DayOne iOS application, modeled after the WinUI 3 desktop application with modern tactile glassmorphism.

---

## 1. Functional Specification

### 1.1 Authentication Flows
The DayOne iOS app provides three distinct sign-in paths via `AuthService`:

1. **Sign in with Google**:
   - Initiates an OAuth PKCE authentication challenge with Supabase (`Provider.google`).
   - Uses `ASWebAuthenticationSession` to launch the Google consent portal with redirect scheme `com.intellidream.daily://login-callback`.
   - On completion, exchanges the authorization code for a session token and automatically persists it to hardware-backed Keychain storage (`KeychainManager`).
2. **Sign in with Apple**:
   - In accordance with App Store Review Guideline 4.8, Apple Sign-In is offered as a native option alongside Google.
   - Generates a cryptographically secure random SHA-256 nonce.
   - Leverages `AuthenticationServices` (`SignInWithAppleButton`) and validates the ID token directly with Supabase Auth (`supabase.auth.signInWithIdToken`).
3. **Continue Without Signing In (Guest Mode)**:
   - Faithfully ported from WinUI's `SkipButton_Click`.
   - Allows users and developers to explore the dashboard immediately without remote network authentication.
   - Stores the guest flag in App Group storage (`group.com.intellidream.daily`).

### 1.2 User Profile Resolution Heuristic
The app extracts user identity information using the exact algorithm established in WinUI `WinUIAuthService.cs`:
1. Inspects `user_metadata` for `full_name`, `name`, `first_name`, or `given_name`.
2. Splits multi-part names on whitespace and takes the leading component.
3. Fallback: Splits the user's email address by delimiters (`.`, `_`, `-`) and capitalizes the first word.
4. Default fallback: `"Friend"` in Guest mode, `"User"` otherwise.

---

## 2. Settings Architecture

The Settings experience is centralized in `SettingsView.swift` and subdivided into five focused, Liquid Glass sections:

### 2.1 Account Section (`AccountSettingsSection.swift`)
- **Visual Avatar**: Circular avatar with an electric cyan / sleek blue gradient stroke.
- **Identity**: Displays full name / greeting (`"Hi, [FirstName]!"`), email address, and an authentication provider badge (`Google`, `Apple`, or `Guest Mode`).
- **Sign Out**: Action button prompting for confirmation to invalidate cloud tokens and clear Keychain state.

### 2.2 Appearance Section (`AppearanceSettingsSection.swift`)
- **Theme Selection**: Segmented control switching between `System`, `Dark`, and `Light`.
  - **Dark**: Deep vertical background gradient (`#030609` to `#132B4A`).
  - **Light**: Warm paper/sand tone (`#D4C9B0`).
- **Liquid Glass Intensity**: Segmented control adjusting tactile fill opacities (`Subtle` 12%, `Medium` 20%, `Prominent` 32%).
- **Haptic Feedback**: System toggle enabling/disabling tactile feedback (`UIImpactFeedbackGenerator`).

### 2.3 Traditional Features Section (`FeaturesSettingsSection.swift`)
Ported from WinUI's `FeaturesPage.xaml`:
- **Weather**:
  - Auto-Location Detection toggle (`weatherAlwaysAutoLocation`).
  - Unit System selector (`Metric (°C, m/s)` vs `Imperial (°F, mph)`).
- **Health & Vitals**:
  - Mock Health Store toggle (`healthMockDataEnabled`).
  - Sleep Goal duration slider (6.0h to 10.0h in 0.5h increments, default 8.0h).
- **Habits & Hydration**:
  - Daily Hydration Target slider (1.0L to 4.0L in 0.25L increments, default 2.0L).
  - Habit logging reminders toggle.
- **News Reader**:
  - Auto-refresh on startup toggle.
  - Show article cover images toggle.

### 2.4 Cloud & Sync Section (`DataSyncSettingsSection.swift`)
- **Cloud Status**: Displays active connection to Supabase Cloud with an online badge.
- **Cloud Sync Toggle**: Enables/disables automatic cloud synchronization across devices.
- **Sync Now**: Immediate manual synchronization trigger.
- **Factory Reset**: Restores all local preferences and settings back to system defaults.

### 2.5 About Section (`AboutSettingsSection.swift`)
- Displays app branding, sparkling gem icon, Version 1.0.0 (Build 2026.1), and IntellIdream inc. copyright.

---

## 3. UI/UX Design System (Liquid Glass)

### 3.1 Material & Lighting Model
- **`LiquidGlassBackground`**: Multi-stop gradient overlaid with a diffused ambient radial glow (`blendMode(.screen)`).
- **`GlassCard`**: Combines `.ultraThinMaterial` blur, dynamic fill opacity, a custom multi-stop linear gradient stroke (`ThemeColors.glassDarkBorder`), and a deep drop shadow.
- **`FloatingGlassCapsule`**: Floating pill navigation bar anchored at the bottom viewport with an animated indicator pill and tactile haptics.
- **`GlassButton`**: Tactile interactive button with spring scale animations on press.
