# Android Adaptive Icon & Modern Splash Screen Architecture

**Document Version:** 1.0  
**Date:** October 8, 2026  
**Status:** Completed, Verified on Emulator & Delivered Live on Physical Hardware  
**Scope:** Android Launcher Icons, Cold-Start Splash Transitions, Android 12+ SplashScreen API (`Android/app`)

---

## 1. Executive Summary

This implementation addresses visual inconsistencies in the Android app icon across modern OEM launchers and during application cold starts. Previously, legacy launcher icons could suffer from harsh clipping on modern Android launchers (squircle/circle adaptive mask layers), and the cold launch transition displayed an unstyled or uncentered icon while the Jetpack Compose runtime initialized.

The work introduced a complete Android Adaptive Icon architecture, legacy density-specific fallbacks, and the modern `androidx.core:core-splashscreen` API integration:
- **Adaptive Icon Implementation**: Compliant with Android 8.0+ (API 26+) adaptive icon specifications, separating the brand background (`#030609`) from the foreground glyph with safe-zone margins.
- **Modern Splash Screen Architecture**: Integrated `Theme.SplashScreen` from Android Jetpack, ensuring an instantaneous, branded, flicker-free cold start transition into the Compose root.
- **Complete Density Support**: Regenerated raster assets across `hdpi`, `mdpi`, `xhdpi`, `xxhdpi`, and `xxxhdpi` for legacy and round launcher configurations (`ic_launcher.png`, `ic_launcher_round.png`, `ic_launcher_foreground.png`).
- **Physical Device Delivery**: Verified and delivered across both the local emulator (`Medium_Phone_API_36.1`) and physical production devices:
  - **Google Pixel 9 Pro ("TRAPPER")**
  - **Samsung Galaxy Z Fold 8 ("RADAR")**

---

## 2. Architecture & Design Specifications

### 2.1 Adaptive Icon Specification (`res/mipmap-anydpi-v26/`)
Modern Android launchers enforce device-specific adaptive masks (circles, squircles, rounded squares). To prevent clipping of the Daily logo:
- The full canvas size is defined at **108 × 108 dp**.
- The inner safe zone is constrained within **72 × 72 dp** (centered 18dp margin buffer on all sides).
- **Background Layer**: Single uniform brand color `@color/ic_launcher_background` (`#030609`), matching Daily's dark OLED / Liquid Glass aesthetic.
- **Foreground Layer**: Centered Daily brand glyph `@mipmap/ic_launcher_foreground`.

Files:
- `Android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml`
- `Android/app/src/main/res/mipmap-anydpi-v26/ic_launcher_round.xml`
- `Android/app/src/main/res/values/colors.xml`:
  ```xml
  <resources>
      <color name="ic_launcher_background">#030609</color>
      <color name="splash_background">#030609</color>
  </resources>
  ```

### 2.2 Modern Splash Screen Integration (`androidx.core:core-splashscreen`)
On Android 12+ (API 31+), the system displays a splash window before the app process finishes initialization. The Jetpack `androidx.core:core-splashscreen` library backports and standardizes this behavior across all supported Android versions.

#### Theme Configuration (`res/values/themes.xml`)
```xml
<!-- Modern Splash Screen Theme powered by androidx.core.splashscreen -->
<style name="Theme.Daily.Starting" parent="Theme.SplashScreen">
    <item name="windowSplashScreenBackground">@color/splash_background</item>
    <item name="windowSplashScreenAnimatedIcon">@mipmap/ic_launcher_foreground</item>
    <item name="postSplashScreenTheme">@style/Theme.Daily</item>
</style>

<!-- Core Application Theme -->
<style name="Theme.Daily" parent="android:Theme.Material.NoActionBar">
    <item name="android:statusBarColor">@android:color/transparent</item>
    <item name="android:navigationBarColor">@android:color/transparent</item>
    <item name="android:windowSplashScreenBackground">@color/splash_background</item>
    <item name="android:windowSplashScreenAnimatedIcon">@mipmap/ic_launcher_foreground</item>
</style>
```

#### Manifest Wiring (`AndroidManifest.xml`)
- Set `android:roundIcon="@mipmap/ic_launcher_round"` on `<application>` for round-icon launcher support (e.g., Pixel Launcher).
- Configured `android:theme="@style/Theme.Daily.Starting"` on `MainActivity`:
```xml
<activity
    android:name=".MainActivity"
    android:exported="true"
    android:launchMode="singleTask"
    android:theme="@style/Theme.Daily.Starting"
    android:windowSoftInputMode="adjustResize">
```

#### Activity Entrypoint (`MainActivity.kt`)
Invoked `installSplashScreen()` immediately at the beginning of `onCreate()`, before `super.onCreate()` and `enableEdgeToEdge()`:
```kotlin
override fun onCreate(savedInstanceState: Bundle?) {
    installSplashScreen()
    super.onCreate(savedInstanceState)
    enableEdgeToEdge()
    // ... UI hydration and Compose root initialization
}
```
This ensures the splash screen smoothly holds until the first Compose frame renders, switching automatically to `postSplashScreenTheme` (`@style/Theme.Daily`) with zero flash or visual stutter.

---

## 3. Density & Asset Matrix

To support legacy devices, OEM customizations, and varied device pixel densities, all asset buckets were populated with high-fidelity assets:

| Density Bucket | Scale Factor | Foreground (`ic_launcher_foreground.png`) | Full Launcher (`ic_launcher.png`) | Round Icon (`ic_launcher_round.png`) |
| :--- | :--- | :--- | :--- | :--- |
| `mipmap-mdpi` | 1.0x (160 dpi) | 108 × 108 px | 48 × 48 px | 48 × 48 px |
| `mipmap-hdpi` | 1.5x (240 dpi) | 162 × 162 px | 72 × 72 px | 72 × 72 px |
| `mipmap-xhdpi` | 2.0x (320 dpi) | 216 × 216 px | 96 × 96 px | 96 × 96 px |
| `mipmap-xxhdpi` | 3.0x (480 dpi) | 324 × 324 px | 144 × 144 px | 144 × 144 px |
| `mipmap-xxxhdpi`| 4.0x (640 dpi) | 432 × 432 px | 192 × 192 px | 192 × 192 px |

---

## 4. Verification & Deployment

### 4.1 Build Verification
- Clean build executed via `./gradlew assembleDebug`.
- Verified APK generated at `Android/app/build/outputs/apk/debug/app-debug.apk`.

### 4.2 Emulator Verification
- Emulator: `Medium_Phone_API_36.1` (Android API 36)
- Verified:
  - App drawer icon renders inside squircle / circular mask without edge clipping.
  - Cold launch activates `Theme.Daily.Starting`, displaying the centered foreground icon against the dark `#030609` background.
  - Smooth, seamless transition into `MainActivity` Jetpack Compose content without flash.

### 4.3 Physical Hardware Verification & Delivery
- **Google Pixel 9 Pro ("TRAPPER")**:
  - Installed via adb (`adb -s 192.168.3.8:39221 install -r Android/app/build/outputs/apk/debug/app-debug.apk`).
  - Pixel Launcher home screen and app drawer verified with adaptive circle mask.
  - Cold start launch animation verified smooth with zero jank.
- **Samsung Galaxy Z Fold 8 ("RADAR")**:
  - Installed via adb (`adb -s 192.168.3.64:32995 install -r Android/app/build/outputs/apk/debug/app-debug.apk`).
  - Samsung OneUI launcher icon verified cleanly masked without distortion.
  - Verified cold launch on both folded cover display and unfolded tablet canvas.
