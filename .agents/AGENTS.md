# Project Rules

- **Research First**: Research thoroughly before writing code, understanding existing architectures, data models, and contracts.
- **Maintain Stability & Prevent Regressions**: Never break existing functional features. Preserve comments, docstrings, and verified functionality.
- **Ask, Don't Assume**: If requirements, architecture, or designs are ambiguous or unknown, ask the user directly instead of making assumptions.
- **Simulator First, Physical Device Delivery**:
  - **iOS**: Rigorously test work on the iOS simulator (SimulaPhone) first (including mock/edge cases and visual inspection); once verified, build, deploy, and verify live on the physical iPhone ("Schmitz").
  - **Android**: Rigorously test work on the Android emulator (`Medium_Phone_API_36.1` on Mac) first (including mock/edge cases, UI dump, and visual inspection); once verified, build, deploy via `adb`, and verify live on the physical **Google Pixel 9 Pro**, **Samsung Galaxy Z Fold 8 ("RADAR")**, and **Samsung Galaxy S25 Edge** (if connected).
- **Modern Native Architecture**:
  - For Android: Pure Kotlin with Jetpack Compose (Liquid Glass design system, 120Hz smooth scrolling), local-first Room database cache (`synced_at` dirty tracking), WorkManager for background sync, Supabase Kotlin SDK, Android Health Connect integration, and Jetpack Glance widgets.
- **Android Stability & Anti-Hang Execution**:
  - Never chain interactive or blocking commands with `sleep` in shell invocations.
  - For Gradle builds, invoke cleanly (`./gradlew assembleDebug`) and do not mix multiple build, install, and sleep tasks in a single compound command.
  - Do not poll `manage_task status` in tight loops; wait for completion notifications.
  - When communicating with wireless adb devices (e.g. port 5038), specify direct targets cleanly and avoid hung background processes.
  - Avoid spamming full-resolution screenshot `view_file` calls in a single session to prevent context token exhaustion and model crashes.
- **Documentation**: After implementing features and verifying builds are functional, ALWAYS document the relevant changes in the `Docs/Features` directory.
- **Clean Commits & Push**: Create clean, well-structured git commits with descriptive titles and summaries, and push to remote.

