# Feature: Cosmos Core Astronomy Engine & Offline Ephemeris Architecture

**Status:** Validated, Built & Fully Tested in `DailyCore` (100% Zero-Regression across 62 tests)  
**Date:** October 28, 2026  
**Module:** `DailyCore` (`CAstronomy`, `CosmosModels`, `AstronomyService`, `CosmosCatalogService`, `CosmosLiveService`)

---

## 1. Executive Summary

This architecture establishes the foundational astronomical intelligence layer in **DailyCore**, powering the **Cosmos & Night Sky Observer** feature across iOS, macOS, Android, and Windows.

It delivers:
1. **Deterministic Offline Ephemeris (`CAstronomy`):** A C99 compilation target embedding the MIT-licensed `CosineKitty/astronomy` engine (VSOP87 / ELP/MPP02) with sub-arcminute accuracy ($\pm 1'$) relative to NASA JPL Horizons.
2. **Swift Concurrency Interface (`AstronomyService`):**
   - High-precision topocentric coordinates (`Azimuth`, `Altitude`, `RA`, `Dec`, distance in AU, apparent visual magnitude).
   - Real-time Moon phase angle, illuminated fraction, lunar age, and libration.
   - Chronological twilight sequences (Astronomical, Nautical, Civil, Sunrise, Solar Noon, Sunset).
   - Jovicentric coordinates for the 4 Galilean moons (*Io, Europa, Ganymede, Callisto*) and Saturn's ring tilt.
   - Conformal stereographic sky dome projection for 120Hz viewports.
   - Evaluator for the *Stargazing Conditions Index* (`0–100`).
3. **Offline Celestial Catalogs (`CosmosCatalogService` & `generate_cosmos_catalogs.swift`):**
   - 88 official IAU constellations with Romanian and English localization.
   - 110 Messier Deep-Sky Objects with coordinates, magnitudes, and optical recommendations.
   - Major annual meteor shower streams with peak dates and radiant coordinates.
   - Primary bright navigation stars with physical B-V color indices.
4. **Live Space & Atmospheric Telemetry (`CosmosLiveService`):**
   - Open-Meteo multi-layer cloud cover (`low`, `mid`, `high`), visibility, and dew point depression.
   - CelesTrak GP JSON orbital elements with SGP4-driven upcoming visible pass prediction for the **International Space Station (ISS)**.
   - NOAA Space Weather Prediction Center real-time geomagnetic storm index ($Kp$) and Aurora probability alerts.
   - NASA Astronomy Picture of the Day (APOD).

---

## 2. Verification Evidence

- **Compilation:** `swift build --package-path DailyCore` -> **Build complete!** with 0 warnings on Cosmos modules.
- **Unit Testing:** `swift test --package-path DailyCore` -> **62 tests in 9 suites passed with 0 failures** (including `AstronomyServiceTests` and `DashboardLayoutTests`).
