# Cosmos Observatory — Android & Foldables Architecture

**Last Updated:** October 29, 2026  
**Verified Targets:** Android 16 (`Medium_Phone_API_36.1` Emulator), Physical **Google Pixel 9 Pro** (`caiman`), and Physical **Samsung Galaxy Z Fold 8 ("RADAR", `SM_F971B`)**

---

## 1. Module & Clean Architecture Overview

The Android **Cosmos & Night Sky Observatory** is implemented in 100% native Kotlin & Jetpack Compose (`120 Hz` smooth `Canvas` rendering), sharing identical scientific algorithms and binary catalogs (`stars_mag70.bin`, `bortle_world_grid.bin`, IAU 88 constellations, 219 Messier+Caldwell DSOs) with Apple and Windows:

- **`:core-model` Scientific Domain:**
  - [`CosmosModels.kt`](../../Android/core-model/src/main/java/com/intellidream/daily/model/CosmosModels.kt) — Packed primitive float/int SoA star catalog (`CosmosPackedStarCatalog`), IAU constellations/borders/asterisms, Messier+Caldwell DSOs, meteor showers, Milky Way contours, SGP4 ISS state, live weather/aurora/APOD models, and cloud observation models.
  - [`AstronomyService.kt`](../../Android/core-model/src/main/java/com/intellidream/daily/model/AstronomyService.kt) — Complete CosineKitty ephemeris port + `SkyProjectionMatrix` (`EQJ_HOR` 3×3 rotation + Bennett refraction + conformal stereographic projection), parallactic bright-limb angle $\chi$, Saturn ring tilt, 4 Galilean moons, iterative local-night Rise/Transit/Set solver, and `0–100` Stargazing Score + 15-min Best Dark Window.
  - [`SGP4Propagator.kt`](../../Android/core-model/src/main/java/com/intellidream/daily/model/SGP4Propagator.kt) — Pure Kotlin NORAD SGP4 orbital propagator for ISS (`NORAD 25544`) with sunlit/umbra pass solver.
- **`:app` Presentation, Sensors, Live Telemetry & Glance Widget:**
  - [`CosmosCatalogRepository.kt`](../../Android/app/src/main/java/com/intellidream/daily/cosmos/CosmosCatalogRepository.kt) — Little-endian `ByteBuffer` loader for `DCS2` (`15,544` stars) & `DCB1` (`720×360` Bortle grid) + JSON metadata & instant search.
  - [`CosmosLiveRepository.kt`](../../Android/app/src/main/java/com/intellidream/daily/cosmos/CosmosLiveRepository.kt) — Live Open-Meteo (`timezone=UTC`) + `7Timer! ASTRO` seeing/transparency + NOAA SWPC (`Kp`, `IMF Bz`, solar wind) + CelesTrak OMM + NASA APOD + Supabase `cosmos_bookmarks` / `cosmos_observations` sync.
  - [`CosmosMotionManager.kt`](../../Android/app/src/main/java/com/intellidream/daily/cosmos/CosmosMotionManager.kt) — Quaternion / `3×3` rotation-matrix AR sensor fusion (`TYPE_ROTATION_VECTOR` with `TYPE_GAME_ROTATION_VECTOR` fallback, `GeomagneticField` true-north declination, display rotation remapping `ROTATION_0/90/180/270`, and figure-8 compass accuracy detection).
  - [`CosmosViewModel.kt`](../../Android/app/src/main/java/com/intellidream/daily/cosmos/CosmosViewModel.kt) & [`CosmosScreen.kt`](../../Android/app/src/main/java/com/intellidream/daily/cosmos/CosmosScreen.kt) — 120 Hz Planetarium Canvas, continuous Time Machine, Target Inspector, Tonight's Observatory Deck, and adaptive Foldable layouts.
  - [`DailyCosmosGlanceWidget.kt`](../../Android/app/src/main/java/com/intellidream/daily/glance/DailyCosmosGlanceWidget.kt) — Standalone Jetpack Glance Home Screen widget registered in [`AndroidManifest.xml`](../../Android/app/src/main/AndroidManifest.xml) (`daily://cosmos` deep-link).

---

## 2. Adaptive Foldable & Multi-Posture UX (Galaxy Z Fold 8 / Pixel Pro Fold)

Using Jetpack `WindowInfoTracker` (`FoldingFeature`), `CosmosScreen.kt` adapts fluidly across four hardware postures without resetting camera or Time Machine state:

1. **Compact / Cover Screen (`FLAT` compact width):** Full-bleed interactive Sky Dome with floating top HUD, semantic FOV preset pills (`120° Wide`, `60° Eye`, `8° 7x50`, `2° Scope`), bottom Time Machine capsule (`-1h`, `Play/Pause`, `LIVE`, `+1h`, `Tonight`), and modal bottom-sheet Observatory Inspector.
2. **Unfolded Inner Display (`FLAT` expanded width $\ge 600\text{ dp}$):** Two-column `58% / 42%` Observatory Deck (Sky Dome left + persistent Telemetry & Tonight's Targets deck right) with a 1-tap **Full-Bleed Expand** toggle in the top HUD.
3. **Book Mode (`HALF_OPENED` + `FoldingFeature.Orientation.VERTICAL`):** Hinge-aware dual-pane split placing the interactive Sky Dome on the left leaf and the scrollable Observatory Inspector (Target details, Moon distance, SGP4 ISS passes, NOAA Aurora `Kp`/`Bz`, APOD) on the right leaf, respecting exact physical hinge occlusion bounds.
4. **Tabletop / Tripod Astro Mode (`HALF_OPENED` + `FoldingFeature.Orientation.HORIZONTAL`):** Designed for resting the foldable directly on a table or car hood outdoors—top tilted half renders the unobstructed Night Sky Dome while the flat bottom half becomes a dedicated **620 nm Red-Safe Touch Console** (continuous Time Machine scrubber, FOV optical presets, layer toggles, and quick object jump chips) with zero hand shake on the upper display.

Additionally, [`DailyFoldableCompanionPane.kt`](../../Android/app/src/main/java/com/intellidream/daily/presentation/foldable/DailyFoldableCompanionPane.kt) surfaces a live **Tonight's Sky** card when browsing other modules on unfolded screens.

---

## 3. Sensor-Fused AR Point-at-Sky Pipeline

`CosmosMotionManager` eliminates Euler pitch/roll singularities near zenith:
- Consumes `Sensor.TYPE_ROTATION_VECTOR` (falling back cleanly to `Sensor.TYPE_GAME_ROTATION_VECTOR` in relative-gyro mode if magnetometers are unavailable).
- Remaps axes for the active `Display.rotation` (`ROTATION_0`, `ROTATION_90`, `ROTATION_180`, `ROTATION_270` across portrait, unfolded landscape, and tabletop orientations).
- Projects the device's back-camera ray `(0, 0, -1)` into the East-North-Up world matrix, applies **WMM `GeomagneticField`** magnetic-to-true North declination for the observer's GPS latitude/longitude/altitude, and applies angular slerp smoothing (`alpha = 0.22`) for jitter-free 120 Hz tracking.

---

## 4. Accessibility, Deep Links & Ecosystem Integration

- **TalkBack & Screen-Reader Semantics:** Dynamic `contentDescription` on the Sky Dome summarizes current lunar phase/illumination, Stargazing Score, and visible above-horizon planets with cardinal directions, alongside labeled HUD controls (`Toggle Night Vision Mode`, `Toggle AR Sky Gyroscope`, `Toggle Continuous Time Machine`).
- **Jetpack Glance Home Screen Widget (`DailyCosmosGlanceWidget`):** Displays live Stargazing Score (`0–100`), Bortle class from `bortle_world_grid.bin`, lunar phase & illumination, and visible planet summary, launching directly into `daily://cosmos`.
- **Settings, SmartBriefing, TagDoS & Calendar:** Full **Cosmos & Night Sky** configuration card in [`SettingsScreen.kt`](../../Android/app/src/main/java/com/intellidream/daily/presentation/SettingsScreen.kt) (NASA API key, custom weather endpoint/key, ISS/Aurora/Pristine-Sky alerts), live briefing bullets in [`SmartBriefingRepository.kt`](../../Android/app/src/main/java/com/intellidream/daily/briefing/SmartBriefingRepository.kt), 1-tap Calendar scheduling, and 1-tap TagDoS `#sky` sighting logging synced via Supabase.

---

## 5. Modular In-App Dashboard Widget (All 4 Dimensions & Canonical Backfill)

The Cosmos module is directly embedded into the user's customizable daily grid via [`CosmosDashboardCard.kt`](../../Android/app/src/main/java/com/intellidream/daily/presentation/dashboard/CosmosDashboardCard.kt) across all 4 supported dimensions:

1. **`1×1 Small`:** Compact square tile featuring an interactive `MiniZenithSkyDomeCanvas` reticle, Stargazing Score badge (e.g. `71/100`), lunar phase symbol & illumination (`🌔 84%`), and count of above-horizon visible planets in green. Pairs seamlessly beside Weather or habits.
2. **`2×1 Wide` (Default):** Two-column card presenting the stereographic mini planisphere dome on the left and the Observatory score badge, Bortle class + NELM, lunar phase, next dark window, and visible bodies summary on the right.
3. **`1×2 Tall`:** Vertical column card presenting the mini sky dome at the top, Bortle telemetry, an elevated `Currently Above Local Horizon` sub-container with real-time target altitudes, magnitudes, and compass directions, and the dark sky window footer.
4. **`2×2 Large`:** Expansive quadrant card featuring an enlarged `96 dp` `MiniZenithSkyDomeCanvas`, Stargazing Score + quality pill, Bortle + NELM + provenance badge, lunar illumination, full visible planetary roster (sorted by altitude with IAU symbols and Alt/Az coordinates), multi-tier cloud coverage (`L / M / H %`), astronomical seeing (`arcsec FWHM`), and 1-tap navigation to the interactive 120Hz Sky Dome.

### Canonical Auto-Backfill Migration
Existing user configurations persisted in `daily_settings` DataStore lacking `DashboardWidgetType.Cosmos.id` are non-destructively migrated via `AppSettings.ensureCanonicalWidgets()`:
- Automatically injects `DashboardWidgetType.Cosmos` directly below `Weather` into the user's widget layout on initial load without wiping user preferences or resetting reordered cards.
- [`CustomizeDashboardScreen.kt`](../../Android/app/src/main/java/com/intellidream/daily/presentation/dashboard/CustomizeDashboardScreen.kt) fully exposes `Cosmos & Observatory` with real-time drag reordering, visibility toggling, and 1-tap dimension switching across `1×1 Small`, `2×1 Wide`, `1×2 Tall`, and `2×2 Large`.

---

## 6. Unified Reactive Telemetry & Live Stargazing Score Architecture

To eliminate fabricated or isolated calculations and ensure complete 1:1 parity between the Hub (`CosmosScreen` / `CosmosViewModel`) and the Dashboard widget (`CosmosDashboardCard` / `DashboardView` / `DailyCosmosGlanceWidget`):

- **Singleton `CosmosLiveRepository` with StateFlows:**
  - `DailyApp.instance.cosmosLiveRepository` manages a reactive `stargazingConditions: StateFlow<StargazingConditions?>` alongside `weatherOverlay`, `spaceWeather`, and `issPasses`.
  - Disk-backed SharedPreferences caching (`KEY_CONDITIONS_JSON`) ensures instant non-destructive score rendering on cold start without waiting for network I/O.
- **True Environmental Modeling:**
  - Evaluates actual `bortleClass(lat, lon)` from `bortle_world_grid.bin` (e.g. Bortle 9 / NELM 3.6 for central metropolitan regions like Bucharest) rather than hardcoded Bortle 5.
  - Multi-tier cloud layers (`low/mid/high %`) and astronomical seeing from Open-Meteo UTC + 7Timer! ASTRO are consumed identically by both the Hub and the Dashboard.
- **Reactive Dashboard & Pull-to-Refresh Sync:**
  - `DashboardView` observes `cosmosLiveRepo.stargazingConditions.collectAsState()` and launches non-blocking telemetry refreshes whenever observer coordinates change.
  - Pull-to-refresh (`pullRefreshState`) triggers `cosmosLiveRepo.refreshCosmosData(lat, lon, force = true)` concurrently with weather and health sync, keeping the Stargazing Score 100% synchronized in real time.


