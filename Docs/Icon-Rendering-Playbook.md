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
- Generates all WinUI manifest PNG assets and `AppIcon.ico` from a single source SVG:
  - Source input: `WinUI/Daily.WinUI/Assets/NewIcon.svg`

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
- Multi-size icon file:
  - `AppIcon.ico` (16,20,24,32,48,256)

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

1. Replace `Assets/NewIcon.svg` with the new master icon.
2. Run `dotnet script GenerateIcons.csx`.
3. Rebuild solution.
4. Verify generated files exist in `Assets` and app build succeeds.
5. In-app icon surfaces (titlebar/settings/about/login) still come from:
   - `appicon.theme-dark.svg`
   - `appicon.theme-light.svg`

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

---

Owner note: This playbook reflects the configuration that was confirmed visually as "looks really fine" in this repository state.
