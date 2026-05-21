# DayOne WinUI Icon Rendering Playbook

This document captures the exact setup that produced crisp in-app icons (titlebar + Settings + About + Login) so it can be repeated safely after future icon changes.

## Goal

Keep app icons sharp in WinUI surfaces while supporting Light/Dark themes.

## 1) Asset Requirements (source files)

Use these files:

- `WinUI/Daily.WinUI/Assets/appicon.theme-dark.svg`
- `WinUI/Daily.WinUI/Assets/appicon.theme-light.svg`

### Mandatory checks

The SVGs must be **true vector paths**, not PNG-in-SVG wrappers.

Good signs:
- Contains `<path ...>` and/or vector geometry.

Bad signs (reject these):
- `<image ... xlink:href="data:image/png;base64,...">`
- `<use xlink:href="#_Image...">` that references embedded bitmap defs.

## 2) Theme Resource Wiring (App.xaml)

File:
- `WinUI/Daily.WinUI/App.xaml`

Use absolute package URIs for icons:

- Dark: `ms-appx:///Assets/appicon.theme-dark.svg`
- Light: `ms-appx:///Assets/appicon.theme-light.svg`

Current keys used:
- `AppIconSource`
- `IntellIdreamIconSource`

## 3) Proven Rasterization Values (the working set)

These values produced good visual quality:

- Main titlebar DayOne/Refresh icon (display ~16px): `64 x 64`
- Settings left nav About/DayOne icon (display ~20px): `64 x 64`
- About page app icon (display ~48px): `192 x 192`
- Login page app icon (display ~72px): `288 x 288`

This is a 4x supersampling pattern for the displayed size.

## 4) Files and expected bindings

### Main window titlebar icon
- File: `WinUI/Daily.WinUI/MainWindow.xaml`
- Binding: `UriSource="{ThemeResource AppIconSource}"`
- Rasterize: `64x64`

### Settings left menu (About/DayOne)
- File: `WinUI/Daily.WinUI/Views/SettingsPage.xaml`
- Binding: `UriSource="{ThemeResource AppIconSource}"`
- Rasterize: `64x64`

### About page app icon
- File: `WinUI/Daily.WinUI/Views/AboutPage.xaml`
- Binding: `UriSource="{ThemeResource AppIconSource}"`
- Rasterize: `192x192`

### Login page app icon
- File: `WinUI/Daily.WinUI/Views/LoginPage.xaml`
- Binding: `UriSource="{ThemeResource AppIconSource}"`
- Rasterize: `288x288`

## 5) Replication Checklist (when icon changes)

1. Replace both dark/light SVG files in `Assets`.
2. Verify they are true vector (no embedded PNG base64).
3. Keep `AppIconSource` in `App.xaml` pointing to `ms-appx:///...` URIs.
4. Keep the proven rasterization values above (4x supersampling).
5. Build solution.
6. Validate in app:
   - Main titlebar DayOne/Refresh icon
   - Settings About/DayOne left-nav icon
   - About page icon
   - Login icon
   - Both Light and Dark themes

## 6) Full App Asset Generation (GenerateIcons.csx)

File:
- `WinUI/Daily.WinUI/GenerateIcons.csx`

Purpose:
- Generates all WinUI manifest PNG assets, `AppIcon.ico`, and theme-specific multi-size system tray icons (`TrayIconDarkTheme.ico` and `TrayIconLightTheme.ico`) using high-quality vector sources:
  - Application icon source: `WinUI/Daily.WinUI/Assets/NewIcon.svg`
  - System tray dark-background source: `WinUI/Daily.WinUI/Assets/appicon.theme-dark.svg`
  - System tray light-background source: `WinUI/Daily.WinUI/Assets/appicon.theme-light.svg`

### What the script generates

- Core manifest assets (examples):
  - `Square44x44Logo.png`
  - `Square44x44Logo.scale-100.png`
  - `Square150x150Logo.scale-100.png`
  - `Wide310x150Logo.scale-200.png`
  - `SplashScreen.scale-200.png`
  - `StoreLogo.png`
- Extra target-size assets used by Windows shell:
  - `Square44x44Logo.targetsize-16_altform-unplated.png`
  - `Square44x44Logo.targetsize-20_altform-unplated.png`
  - `Square44x44Logo.targetsize-24_altform-unplated.png`
  - `Square44x44Logo.targetsize-32_altform-unplated.png`
  - `Square44x44Logo.targetsize-48_altform-lightunplated.png`
  - `Square44x44Logo.targetsize-256_altform-unplated.png`
- Multi-size icon files:
  - `AppIcon.ico` (16,20,24,32,48,256) - Main application icon.
  - `TrayIconDarkTheme.ico` (16,20,24,32,48,256) - Pure white icon variant for dark taskbars.
  - `TrayIconLightTheme.ico` (16,20,24,32,48,256) - Dark/black icon variant for light taskbars.

### Rendering quality strategy used by the script

- Renders SVG with supersampling first (`4x`, and `8x` for very small sizes) then downsamples.
- Uses high-quality graphics settings (anti-aliasing + high-quality bicubic interpolation).
- This is intended to keep shell/manifest assets crisp in Windows surfaces.

### How to run

From `WinUI/Daily.WinUI` directory:

- `dotnet script GenerateIcons.csx`

Notes:
- Requires `dotnet-script` and the NuGet refs declared in script (`Svg`, `System.Drawing.Common`).
- Script writes outputs into `WinUI/Daily.WinUI/Assets`.

### Recommended workflow when app icon changes

1. Replace `Assets/NewIcon.svg` (for the main app icon) and `Assets/appicon.theme-dark.svg` / `Assets/appicon.theme-light.svg` (for the theme-specific vector paths) with the new master vector assets.
2. Run `dotnet script GenerateIcons.csx` to generate all manifest PNGs, `AppIcon.ico`, and `TrayIcon*.ico` files.
3. Rebuild the solution.
4. Verify generated files exist in `Assets` and the app build succeeds.
5. In-app icon surfaces (titlebar/settings/about/login) and tray icons will now display the updated version.

Important:
- `GenerateIcons.csx` controls shell/manifest PNG+ICO assets.
- In-app SVG icon rendering (this playbook’s main topic) is controlled separately via `AppIconSource` and page XAML bindings.

## 7) Troubleshooting

### Icon disappears
- Usually URI resolution issue.
- Confirm `ms-appx:///Assets/...` is used (not ambiguous relative paths in shared resources).

### Icon visible but blurry
- Check SVG is true vector.
- Check rasterization values were not reduced to exact tiny display size.
- Re-apply the 4x rasterization values listed above.

### Theme mismatch
- Ensure both dark and light files exist and `AppIconSource` has ThemeDictionary entries for both.

## 8) Optional automation idea

Add a small validation script that fails if either icon SVG contains `data:image/png;base64`.

## 9) WinUI System Tray Icons (Theme Adaptation)

### How it works:
1. **Target files**:
   - `Assets/TrayIconDarkTheme.ico` (multi-size: 16, 20, 24, 32, 48, 256) is a pure white icon visible on dark taskbar backgrounds.
   - `Assets/TrayIconLightTheme.ico` (multi-size: 16, 20, 24, 32, 48, 256) is a black icon visible on light taskbar backgrounds.
2. **Dynamic Adaptation Logic**:
   - The app monitors the Windows Registry key `Software\Microsoft\Windows\CurrentVersion\Themes\Personalize` under registry value `SystemUsesLightTheme` at runtime.
   - When the app starts, or when system color settings change (monitored via `Windows.UI.ViewManagement.UISettings.ColorValuesChanged`), the app queries this registry value.
   - If `SystemUsesLightTheme == 1` (meaning the taskbar background is light-colored), it switches the tray icon to `TrayIconLightTheme.ico` (black).
   - If `SystemUsesLightTheme == 0` (meaning the taskbar background is dark-colored), it switches the tray icon to `TrayIconDarkTheme.ico` (white).
3. **Execution Safety**:
   - Updates are enqueued onto the UI thread via `DispatcherQueue.TryEnqueue` because UI properties (`TrayIcon.Icon`) must only be modified from the main UI thread.
4. **Mouse Interaction Behavior**:
   - **Left-Click**: Invokes `LeftClickCommand` which immediately restores and activates the main app window (`ShowAndActivate()`).
   - **Right-Click**: Activates the `ContextFlyout` context menu (by setting `MenuActivation = PopupActivationMode.RightClick`).
   - **Double-Click**: Also mapped to restore the window (`DoubleClickCommand`).

---

Owner note: This playbook reflects the configuration that was confirmed visually as "looks really fine" in this repository state.
