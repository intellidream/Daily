# Cosmos Observatory — Data Sources, Binary Formats & Licensing Attribution

**Last Updated:** October 29, 2026  
**Catalog Schema Version:** `2` (`cosmos_catalog_manifest.json`)  
**Generator Pipeline:** [`Scripts/build_sky_catalogs.py`](../../Scripts/build_sky_catalogs.py)

---

## 1. Clean Permissive & Public Academic Licensing Strategy

Daily's **Cosmos & Night Sky Observatory** ships a self-contained, 100% offline-capable astronomical catalog (~1.25 MB total across binary tables, JSON metadata, and showcase plates) generated from public scientific standards, public academic VizieR catalogs, and BSD-3-Clause compilations — intentionally avoiding CC BY-SA copyleft obligations on proprietary application binaries.

### Primary Scientific & Permissive Lineage
1. **ESA Hipparcos Main Catalog (`I/239`) & Yale Bright Star Catalog (`V/50`)** — Public academic astrometric and photometric star measurements (ICRS / J2000 equatorial unit vectors, Johnson $V$ magnitudes, and $B-V$ color indices).
2. **`d3-celestial` Astronomical Compilation** — Copyright (c) 2015 Olaf Frohn, licensed under **BSD-3-Clause**. Used for cross-validated constellation stick-figure HIP topology, Milky Way isophote rings, and Messier/NGC cross-references.
3. **International Astronomical Union (IAU) Public Standards:**
   - **IAU Working Group on Star Names (WGSN)** — Official proper star names (`515` IAU-approved star names mapped to Hipparcos identifiers, plus Bayer/Flamsteed designations across `3,463` naked-eye stars).
   - **IAU 88 Official Constellations** — Complete northern, equatorial, and southern sky coverage (`88` constellations, `743` HIP-to-HIP stick segments).
   - **IAU Meteor Data Center (MDC)** — Canonical annual meteor shower calendar (`22` major showers with solar longitude peaks, radiant RA/Dec, drift rates, parent bodies, and ZHR).
4. **Davenhall & Leggett (1989), *Catalogue of Constellation Boundary Data* (`VizieR VI/49`)** — Public academic J2000 constellation boundary arcs (`257` deduplicated boundary polylines).
5. **José R. Vieira Milky Way Outline Catalog & Saguaro Astronomy Club (SAC v8.1)** — Multi-threshold Galactic diffuse surface brightness contours (`5` nested isophote layers) and curated Messier (`M1`–`M110`) + Caldwell (`C1`–`C109`) deep-sky measurements (`219` objects).
6. **Showcase Deep-Sky Plates (`thumbs/*.png`)** — `20` compact (`96×96` RGBA) offline showcase plates representing public-domain NASA / ESA / Hubble / Astronomical Heritage morphology for flagship Messier and Caldwell targets (`M1`, `M8`, `M13`, `M16`, `M20`, `M27`, `M31`, `M42`, `M45`, `M51`, `M57`, `M81`, `M82`, `M104`, `C14`, `C63`, `C65`, `C80`, `C92`, `C106`).
7. **Deterministic Global Sky Brightness Grid (`bortle_world_grid.bin`)** — `720×360` (`0.5°` resolution) offline Bortle `1`–`9` dark-sky lookup table modeled from global metropolitan/population radiative kernels, ocean dark-sky baselines, and desert/high-altitude reserve corrections.

---

## 2. Canonical Offline Asset Inventory

Identical byte-for-byte copies are bundled in:
- **Apple (`DailyCore`):** `DailyCore/Sources/DailyCore/Resources/Cosmos/`
- **Android:** `Android/app/src/main/assets/cosmos/`
- **Windows (WinUI 3):** `WinUI/Daily.WinUI/Assets/Cosmos/`

| File | Records / Dimensions | Size (Bytes) | SHA-256 Checksum | Purpose |
| :--- | :--- | ---: | :--- | :--- |
| `stars_mag70.bin` | `15,544` stars ($V \le 7.00$) | `497,424` | `549f3877...80074c9d` | Little-endian packed binary catalog sorted brightest-first for zero-JSON-overhead 60–120 fps projection |
| `star_names_iau.json` | `3,463` entries (`515` IAU names) | `301,916` | `f84c62ec...b732b3` | O(1) HIP lookup dictionary for IAU proper names, Bayer/Flamsteed designations, constellations & spectral classes |
| `bortle_world_grid.bin` | `720 × 360` (`0.5° × 0.5°`) | `129,616` | `c0883e2a...dc6e86` | Instant offline Bortle class (`1`–`9`) & SQM estimation for any GPS coordinate on Earth |
| `dso_catalog.json` | `219` (`110` Messier + `109` Caldwell) | `102,270` | `9f5f08ac...93ec9c` | Full Messier + Caldwell deep-sky catalog with angular dimensions, position angle, surface brightness & distances |
| `milky_way_isophotes.json` | `5` brightness tiers | `44,911` | `0aa7e45c...68b8215d` | Multi-layer Galactic band polygons rendered under low-Bortle dark skies |
| `constellations_iau88.json` | `88` constellations (`743` segments) | `35,743` | `9a3a0d23...fa8f5` | Complete IAU 88 stick-figure definitions indexed directly into `stars_mag70.bin` HIP IDs |
| `constellation_borders.json` | `257` boundary arcs | `26,944` | `8f68c955...dc99bd` | Official IAU J2000 equatorial boundary polylines |
| `meteor_showers_iau.json` | `22` annual showers | `9,471` | `e6b0bfa3...fe54ac` | Active radiant positions, daily radiant drift, peak dates, ZHR, entry velocity & parent comets/asteroids |
| `asterisms.json` | `14` classic asterisms | `4,477` | `43875bb7...949` | Big Dipper, Summer Triangle, Winter Hexagon, Teapot, Southern Cross Pointer, Square of Pegasus, etc. |
| `thumbs/*.png` | `20` plates (`96×96` PNG) | `149,818` | Verified in manifest | Offline Target Inspector thumbnails for flagship nebulae, galaxies, and globular clusters |

---

## 3. Binary Wire Formats

### 3.1 `stars_mag70.bin` (`DCS2` Binary Star Table)
- **Header (`16` bytes, little-endian):**
  - `0..3`: ASCII magic `"DCS2"` (`0x44, 0x43, 0x53, 0x32`)
  - `4..5`: `uint16` version (`2`)
  - `6..7`: `uint16` record stride (`32` bytes)
  - `8..11`: `uint32` star count (`15544`)
  - `12..15`: `float32` limiting magnitude (`7.00`)
- **Record (`32` bytes × `15,544`, sorted ascending by `vMag`):**
  - `0..3`: `int32` Hipparcos identifier (`HIP`, or synthetic negative ID for non-HIP companions)
  - `4..7`: `float32` `ux` — J2000 equatorial unit vector $x = \cos\delta \cos\alpha$
  - `8..11`: `float32` `uy` — J2000 equatorial unit vector $y = \cos\delta \sin\alpha$
  - `12..15`: `float32` `uz` — J2000 equatorial unit vector $z = \sin\delta$
  - `16..19`: `float32` `vMag` — Johnson visual magnitude $V$
  - `20..23`: `float32` `bv` — $B-V$ color index (mapped to Ballesteros 2012 blackbody temperature $T_{\text{eff}}$ and RGB chromaticity)
  - `24..25`: `uint16` `raMilliHours` (`RA_hours * 1000`)
  - `26..27`: `int16` `decCentiDeg` (`Dec_deg * 100`)
  - `28..31`: `uint32` flags (`bit 0`: has IAU proper name, `bit 1`: constellation vertex star)

### 3.2 `bortle_world_grid.bin` (`DCB1` Sky Brightness Grid)
- **Header (`16` bytes, little-endian):**
  - `0..3`: ASCII magic `"DCB1"`
  - `4..5`: `uint16` version (`1`)
  - `6..7`: `uint16` width (`720` columns, `-180°` to `+180°` at `0.5°` step)
  - `8..9`: `uint16` height (`360` rows, `-90°` to `+90°` at `0.5°` step)
  - `10..15`: reserved (`0`)
- **Payload (`259,200` nibbles packed `2` per byte = `129,600` bytes):**
  - High nibble `(byte >> 4) & 0x0F` = even column Bortle class (`1`–`9`), low nibble `byte & 0x0F` = odd column Bortle class (`1`–`9`).

---

## 4. Live External Telemetry Provenance & Caching Policy

All live endpoints are strictly optional enhancements over the deterministic offline ephemeris and SGP4 engines, with explicit disk caching, stale-age badges, and user-configurable keys in **Settings → Cosmos & Night Sky**:

| Telemetry Domain | Primary Endpoint | Refresh / TTL | Fallback Behavior |
| :--- | :--- | :--- | :--- |
| **ISS Orbital Elements (NORAD 25544)** | CelesTrak GP OMM JSON (`GROUP=stations&FORMAT=json`) | `6 hours` | Bundled reference OMM epoch + disk-cached OMM propagated locally via SGP4; marked `Stale OMM` if $>72\text{ h}$ |
| **Multi-Layer Cloud Cover & Visibility** | Open-Meteo Forecast API (`cloud_cover_low/mid/high`, `dew_point_2m`, `visibility`, `timezone=UTC`) | `30 minutes` | Disk-cached hourly forecast aligned by UTC epoch; falls back to Daily `WeatherService` total cloud cover |
| **Astronomical Seeing & Transparency** | `7Timer! ASTRO` JSON API (`seeing`, `transparency`) or custom weather endpoint in Settings | `60 minutes` | Heuristic seeing estimate from wind/boundary-layer humidity when offline |
| **Geomagnetic & Aurora Activity** | NOAA SWPC Planetary `Kp` (`noaa-planetary-k-index.json`) + DSCOVR Real-Time Solar Wind (`mag-1-day.json`, `plasma-1-day.json`) | `15 minutes` | Disk-cached NOAA snapshot with timestamp; displays `--` rather than fabricated numbers when unreachable |
| **Astronomy Picture of the Day** | NASA APOD REST API (`api.nasa.gov/planetary/apod`, supporting user API key in Settings) | `12 hours` | Last cached APOD entry on HTTP `429` or offline state |
