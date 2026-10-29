# Cosmos Observatory — iOS & macOS Golden Standard Architecture

**Last Updated:** October 29, 2026  
**Verified Targets:** iOS 18+ (`SimulaPhone`, `SimulaDuo`, Physical **iPhone 16 Pro "Schmitz"**) & macOS 15+ (`Daily.app` Native ARM64 on Apple Silicon)

---

## 1. Architectural Overview

The Apple **Cosmos & Night Sky Observatory** combines a shared high-precision `DailyCore` scientific backend with platform-tailored SwiftUI/Canvas GPU rendering, CoreMotion quaternion AR sky-tracking on iOS, desktop `58% / 42%` Observatory Deck ergonomics on macOS, WidgetKit Home/Lock Screen widgets, MenuBarExtra companion telemetry, and Supabase Realtime cloud persistence.

### Core Apple Files
- **Shared Core (`DailyCore`):**
  - [`CosmosModels.swift`](../../DailyCore/Sources/DailyCore/Models/CosmosModels.swift) — Packed binary star SoA (`CosmosPackedStarCatalog`), IAU 88 constellations, 219 Messier+Caldwell DSOs, 22 IAU meteor showers, Milky Way isophotes, ISS SGP4 models, live weather/aurora/APOD payloads, and cloud bookmarks/sighting records.
  - [`AstronomyService.swift`](../../DailyCore/Sources/DailyCore/Services/AstronomyService.swift) — `SkyProjectionMatrix`, CosineKitty solar-system ephemeris, parallactic lunar bright-limb angle $\chi$, Saturn ring inclination, 4 Galilean moons, local night Rise/Transit/Set solver, and `0–100` Stargazing Score + 15-min Best Dark Window.
  - [`SGP4Propagator.swift`](../../DailyCore/Sources/DailyCore/Services/SGP4Propagator.swift) — Deterministic NORAD SGP4 propagator for ISS (`NORAD 25544`) with sunlit/umbra pass prediction.
  - [`CosmosCatalogService.swift`](../../DailyCore/Sources/DailyCore/Services/CosmosCatalogService.swift) — Zero-JSON-overhead `DCS2` (`15,544` stars) + `DCB1` (`720×360` Bortle grid) binary loaders and instant multi-catalog search index.
  - [`CosmosLiveService.swift`](../../DailyCore/Sources/DailyCore/Services/CosmosLiveService.swift) — Live Open-Meteo (`timezone=UTC`) + `7Timer! ASTRO` seeing/transparency + NOAA SWPC (`Kp`, `IMF Bz`, solar wind) + CelesTrak OMM + NASA APOD orchestrator with disk TTL cache.
  - [`CosmosSyncService.swift`](../../DailyCore/Sources/DailyCore/Services/CosmosSyncService.swift) — Supabase `cosmos_bookmarks` & `cosmos_observations` CRUD + TagDoS `#sky` quick-note mirror.
- **iOS Presentation & Widgets:**
  - [`iOS/Daily/Views/Cosmos/CosmosDetailView.swift`](../../iOS/Daily/Views/Cosmos/CosmosDetailView.swift) & [`CosmosViewModel.swift`](../../iOS/Daily/Views/Cosmos/CosmosViewModel.swift)
  - [`iOS/Daily/Services/CosmosMotionService.swift`](../../iOS/Daily/Services/CosmosMotionService.swift)
  - [`iOS/Daily/Views/Dashboard/CosmosDashboardCard.swift`](../../iOS/Daily/Views/Dashboard/CosmosDashboardCard.swift)
  - [`iOS/DailyWidgets/CosmosWidget.swift`](../../iOS/DailyWidgets/CosmosWidget.swift) (`systemSmall`, `systemMedium`, `accessoryCircular`, `accessoryRectangular`)
- **macOS Presentation & Companion:**
  - [`MacOS/Daily/Views/Cosmos/CosmosDetailView.swift`](../../MacOS/Daily/Views/Cosmos/CosmosDetailView.swift) & [`CosmosViewModel.swift`](../../MacOS/Daily/Views/Cosmos/CosmosViewModel.swift)
  - [`MacOS/Daily/Views/MenuBar/MenuBarCompanionView.swift`](../../MacOS/Daily/Views/MenuBar/MenuBarCompanionView.swift)
  - [`MacOS/Daily/Views/Main/RootView.swift`](../../MacOS/Daily/Views/Main/RootView.swift) (retractable Dashboard capsule while in Cosmos)

---

## 2. Planetarium Visual Fidelity & Optical Zoom Pipeline

Both iOS and macOS render an 11-layer interactive planetarium dome at 60–120 fps inside `TimelineView` + SwiftUI `Canvas`:
1. **Solar-Elevation Rayleigh Sky Shader:** Continuous atmospheric transition across broad daylight sapphire (`sunAlt > +4°`, keeping bright stars and planets legible), golden/cobalt civil twilight (`+4°` to `-6°`), indigo nautical/astronomical twilight (`-6°` to `-18°`), and obsidian night (`<= -18°`), with instant override to **620 nm Red Night-Vision Mode** (`0x050000` background, zero green/blue subpixel emission).
2. **5-Tier Milky Way Isophote Contours:** Rendered from `milky_way_isophotes.json` with opacity modulated by local Bortle class (`bortle_world_grid.bin`).
3. **Coordinate Grids & Ecliptic:** Toggleable Alt/Az horizon grid, Equatorial RA/Dec J2000 grid, IAU constellation boundaries (`257` arcs), and dashed golden Ecliptic plane.
4. **IAU 88 Constellations & 14 Classic Asterisms:** Full northern + southern sky coverage (`743` segments) indexed directly into `stars_mag70.bin` HIP unit vectors, plus toggleable asterism overlays (*Big Dipper*, *Summer Triangle*, *Winter Hexagon*, *Teapot*, etc.).
5. **15,544 Hipparcos Star Field:** Dynamic limiting magnitude scaling smoothly with FOV (`120° Wide` $\rightarrow$ `60° Eye` $\rightarrow$ `8° 7x50` $\rightarrow$ `2° Scope` down to `0.5°`), Ballesteros $B-V$ blackbody chromaticity, Pogson perceptual glow halos + diffraction spikes for brightest stars, and low-altitude airmass scintillation (`twinkle`).
6. **219 Messier & Caldwell Deep-Sky Objects:** Morphological symbols (tilted ellipses for galaxies by true PA, crosshaired circles for globular clusters, dotted circles for open clusters, rounded squares for nebulae) plus `20` bundled showcase plates in the Target Inspector.
7. **Solar System Disks & Subsystems:** Spherical lunar terminator rotated by exact topocentric bright-limb angle $\chi$, Saturn ring inclination ellipse, and live **4 Galilean moons** (`Io`, `Europa`, `Ganymede`, `Callisto`) around Jupiter when zoomed to $\text{FOV} \le 12^\circ$.
8. **Live SGP4 ISS Trajectory:** Real-time ground-range & topocentric marker for `NORAD 25544` plus sunlit (solid gold) vs. Earth-umbra (dashed slate) pass arc.
9. **Forward-Hemisphere Horizon Silhouette & 8 Cardinal Beacons:** Monotonic stereographic horizon curve and opaque dark landscape apron (`alt < 0°`) with `N, NE, E, SE, S, SW, W, NW` compass pills.

---

## 3. Sensor-Fused AR Sky-Tracking (iOS) & Desktop Ergonomics (macOS)

### iOS CoreMotion `xMagneticNorthZVertical` Quaternion Pipeline
- `CosmosMotionService` transforms the device's optical camera axis `(0, 0, -1)` through the transpose of `CMDeviceMotion.attitude.rotationMatrix` in the `.xMagneticNorthZVertical` frame (`X = North`, `Y = West`, `Z = Up`), extracting true pointing `(Azimuth, Altitude)` and optical axis `Roll` without Euler gimbal lock at zenith (`Alt -> +90°`).
- Automatically applies `CLHeading.trueHeading - magneticHeading` magnetic declination when available, exposes figure-8 compass calibration prompts when `magneticField.accuracy` degrades, and falls back gracefully to relative gyro attitude on hardware lacking magnetometers.

### macOS Desktop Observatory Deck (`>= 1080 pt`)
- **Two-Column `58% / 42%` Split Deck:** Interactive sky dome on the left (`58%`) paired with a persistent live **Observatory Telemetry Inspector** on the right (`42%`: Selected Target / Tonight's Score & Best Dark Window / Multi-Layer Clouds & Seeing / Lunar Distance & Angular Size / SGP4 ISS Sunlit Passes / NOAA `Kp`, `IMF Bz` & Solar Wind / NASA APOD), plus a 1-click full-bleed toggle.
- **Desktop Pointer & Keyboard Controls:** Two-finger trackpad scroll / mouse-wheel focal-point zoom (`0.5°`–`120°`), `MagnifyGesture` pinch zoom, hover reticle preview, keyboard shortcuts (`+`/`-` zoom, `Space` play/pause Time Machine, `L` reset to `LIVE`, `N` Night Vision, `G` grids, `/` search, `Esc` clear selection), and **auto-retracted Dashboard navigation capsule** in `RootView` so bottom Time Machine controls never collide with global navigation chrome.

---

## 4. Ecosystem Touchpoints

- **iOS Home & Lock Screen Widgets (`CosmosWidget`):** Dedicated WidgetKit families (`systemSmall`, `systemMedium`, `accessoryCircular`, `accessoryRectangular`) displaying tonight's Stargazing Score, Moon phase & illumination, Best Dark Window, and next sunlit ISS pass, deep-linking directly to `daily://cosmos`.
- **macOS `MenuBarExtra` Companion:** Live Cosmos quick-status row with Stargazing Score badge, lunar phase, visible planet count, and 1-click launch into the Cosmos Observatory.
- **Settings → Cosmos & Night Sky:** Configurable **NASA APOD API Key**, custom **Astronomical Weather Endpoint / API Key**, and notification toggles for sunlit ISS passes, Aurora (`Kp` threshold), and Pristine Dark-Sky windows.
- **Hybrid Co-Pilot, SmartBriefing, TagDoS & Calendar:** Astronomical context injected into `SmartBriefingService`, 1-tap `"Schedule in Calendar"` EventKit integration around target transit/pass peak, and 1-tap `"Log Sighting"` dual-writing to Supabase `cosmos_observations` and TagDoS `#sky` Quick Notes.
