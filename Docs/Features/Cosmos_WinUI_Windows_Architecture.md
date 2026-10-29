# Cosmos Observatory — Windows 11 (WinUI 3 & Win2D GPU) Architecture

**Last Updated:** October 29, 2026  
**Verified Target:** Windows 11 ARM64 (`dotnet build -c Debug -p:Platform=ARM64` — `0 Error(s)`)

---

## 1. Architectural Upgrade: GPU-Accelerated Direct2D (`Win2D`) Planetarium

In the October 29, 2026 remediation, the legacy CPU XAML `Shape` tree (`Ellipse` / `Line` / `Polygon` allocation per frame) was completely replaced with **Microsoft Win2D (`Microsoft.Graphics.Win2D 1.3.2`)** Direct2D GPU immediate-mode rendering via `CanvasControl` (`SkyCanvas`) on [`CosmosDetailPage.xaml`](../../WinUI/Daily.WinUI/Views/CosmosDetailPage.xaml) and `CanvasControl` (`MiniSkyCanvas`) on [`CosmosWidgetControl.xaml`](../../WinUI/Daily.WinUI/Controls/CosmosWidgetControl.xaml).

### Core WinUI 3 Files
- **Scientific & Telemetry Services (`WinUI/Daily.WinUI/Services/Cosmos/`):**
  - [`AstronomyEngine.cs`](../../WinUI/Daily.WinUI/Services/Cosmos/AstronomyEngine.cs) & [`AstronomyService.cs`](../../WinUI/Daily.WinUI/Services/Cosmos/AstronomyService.cs) — CosineKitty VSOP87/ELP2000 ephemeris, `SkyProjectionMatrix` (`EQJ_HOR` 3×3 matrix + Bennett refraction + conformal stereographic camera basis), parallactic bright-limb angle $\chi$, Saturn ring inclination, 4 Galilean moons, local-night Rise/Transit/Set solver, and `0–100` Stargazing Score + 15-min Best Dark Window.
  - [`SGP4Propagator.cs`](../../WinUI/Daily.WinUI/Services/Cosmos/SGP4Propagator.cs) — Native C# NORAD SGP4 propagator for `NORAD 25544` (ISS) with cylindrical solar umbra and pass magnitude modeling.
  - [`CosmosCatalogRepository.cs`](../../WinUI/Daily.WinUI/Services/Cosmos/CosmosCatalogRepository.cs) — Binary `DCS2` (`stars_mag70.bin`, `15,544` Hipparcos stars) & `DCB1` (`bortle_world_grid.bin`, `720×360`) loaders + IAU 88 constellations, 257 boundaries, 14 asterisms, 219 Messier+Caldwell DSOs, 22 meteor showers, and 5 Milky Way contour layers.
  - [`CosmosLiveService.cs`](../../WinUI/Daily.WinUI/Services/Cosmos/CosmosLiveService.cs) — Live Open-Meteo (`timezone=UTC`) + `7Timer! ASTRO` seeing/transparency + NOAA SWPC (`Kp`, `IMF Bz`, solar wind) + CelesTrak OMM + NASA APOD + Supabase `cosmos_bookmarks` / `cosmos_observations` sync + TagDoS `#sky` mirror.
- **Desktop Observatory Views & Companions:**
  - [`CosmosDetailPage.xaml`](../../WinUI/Daily.WinUI/Views/CosmosDetailPage.xaml) & [`CosmosDetailPage.xaml.cs`](../../WinUI/Daily.WinUI/Views/CosmosDetailPage.xaml.cs) — 60 Hz Win2D Planetarium + `58% / 42%` Desktop Observatory Deck (`>= 1080 px`).
  - [`CosmosWidgetControl.xaml`](../../WinUI/Daily.WinUI/Controls/CosmosWidgetControl.xaml) & [`CosmosWidgetControl.xaml.cs`](../../WinUI/Daily.WinUI/Controls/CosmosWidgetControl.xaml.cs) — Win2D mini sky dome Dashboard card.
  - [`TaskbarGlanceFlyoutControl.xaml`](../../WinUI/Daily.WinUI/Controls/TaskbarGlanceFlyoutControl.xaml) & [`TaskbarGlanceFlyoutControl.xaml.cs`](../../WinUI/Daily.WinUI/Controls/TaskbarGlanceFlyoutControl.xaml.cs) — Live Windows 11 System Tray / Taskbar companion Cosmos telemetry row.
  - [`CosmosSettingsPage.xaml`](../../WinUI/Daily.WinUI/Views/CosmosSettingsPage.xaml) & [`CosmosSettingsPage.xaml.cs`](../../WinUI/Daily.WinUI/Views/CosmosSettingsPage.xaml.cs) — Dedicated Settings subpage inside [`SettingsPage.xaml`](../../WinUI/Daily.WinUI/Views/SettingsPage.xaml).

---

## 2. Conformal Stereographic Projection & 360° Zenith Planisphere Scaling

`CosmosDetailPage.xaml.cs` supports two seamless optical projection postures on Windows desktops:
1. **Horizon-Looking Perspective (`3D Horizon`):** Forward-hemisphere stereographic horizon curve with opaque dark landscape apron (`Color.FromArgb(236, 4, 7, 15)`) and `8` cardinal/intercardinal beacons (`N, NE, E, SE, S, SW, W, NW`).
2. **360° Zenith Planisphere Mode (`360° Zenith`):** Camera locked straight overhead (`Altitude = +90°`), projecting `Alt = 0°` to exact stereographic radius $R_{\text{horizon}} = S \cdot \tan(90^\circ / 2) = S$. Exterior ground outside the circular horizon ring is masked cleanly via Direct2D `CanvasGeometryCombine.Exclude`, so **mouse-wheel and pinch zooming smoothly scale the entire horizon circle and star field together** without stars spilling outside a fixed-pixel border.

---

## 3. Desktop `58% / 42%` Observatory Deck & Navigation Ergonomics

- **Responsive Two-Column Split (`>= 1080 px`):** Interactive Win2D Sky Dome (`58%`) on the left paired with a scrollable Mica/Acrylic **Observatory Deck** (`42%`) on the right featuring:
  - Selected Celestial Target Inspector (showcase DSO thumbnail, Rise/Transit/Set, Az/Alt, RA/Dec, Bookmark, `"Schedule in Calendar"` via `ICalendarService`, and `"Log Sighting (#sky)"` via `ITagdosService` + Supabase).
  - Tonight's Stargazing Score (`0–100`), Best Dark Window, Bortle class, NELM, and multi-layer cloud / seeing breakdown.
  - Lunar Geometry (illumination, bright-limb angle, topocentric distance in `km`, angular size in `arcmin`).
  - Live SGP4 ISS Sunlit Passes & NOAA SWPC Space Weather (`Kp`, `IMF Bz`, Solar Wind `km/s`) & NASA APOD card.
- **Zero Chrome Collision:** Navigating to Cosmos (`Ctrl+9` or Dashboard widget click) automatically collapses the global bottom `NavCapsule` in `MainWindow.xaml.cs` and exposes a compact top-left Capsule Reveal toggle, keeping the bottom Continuous Time Machine (`-24h`, `-1h`, `-10m`, `Play/Pause`, `1x/60x/300x/1800x`, `LIVE`, `+10m`, `+1h`, `+24h`) completely unobstructed.
- **Hardware Sensor Support (Windows 2-in-1s / Tablets):** Integrates `Windows.Devices.Sensors.OrientationSensor` quaternion matrix when available on tablet hardware while gracefully hiding/disabling sensor lock on standard desktop workstations.
