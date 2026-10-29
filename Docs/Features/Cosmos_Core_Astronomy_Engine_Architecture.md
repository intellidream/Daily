# Cosmos Core Astronomy Engine Architecture

**Last Updated:** October 29, 2026  
**Verified Implementations:**
- **Apple (`DailyCore`):** [`AstronomyService.swift`](../../DailyCore/Sources/DailyCore/Services/AstronomyService.swift), [`SGP4Propagator.swift`](../../DailyCore/Sources/DailyCore/Services/SGP4Propagator.swift), [`CosmosCatalogService.swift`](../../DailyCore/Sources/DailyCore/Services/CosmosCatalogService.swift), [`CosmosLiveService.swift`](../../DailyCore/Sources/DailyCore/Services/CosmosLiveService.swift)
- **Android (`:core-model` & `:app`):** [`AstronomyService.kt`](../../Android/core-model/src/main/java/com/intellidream/daily/model/AstronomyService.kt), [`SGP4Propagator.kt`](../../Android/core-model/src/main/java/com/intellidream/daily/model/SGP4Propagator.kt), [`CosmosCatalogRepository.kt`](../../Android/app/src/main/java/com/intellidream/daily/cosmos/CosmosCatalogRepository.kt), [`CosmosLiveRepository.kt`](../../Android/app/src/main/java/com/intellidream/daily/cosmos/CosmosLiveRepository.kt)
- **Windows (WinUI 3):** [`AstronomyEngine.cs`](../../WinUI/Daily.WinUI/Services/Cosmos/AstronomyEngine.cs), [`AstronomyService.cs`](../../WinUI/Daily.WinUI/Services/Cosmos/AstronomyService.cs), [`SGP4Propagator.cs`](../../WinUI/Daily.WinUI/Services/Cosmos/SGP4Propagator.cs), [`CosmosCatalogRepository.cs`](../../WinUI/Daily.WinUI/Services/Cosmos/CosmosCatalogRepository.cs), [`CosmosLiveService.cs`](../../WinUI/Daily.WinUI/Services/Cosmos/CosmosLiveService.cs)

---

## 1. Per-Frame `O(1)` 3×3 Matrix Rotation & Conformal Stereographic Projection

Instead of calling per-star trigonometric `asin`/`atan2` transformations across 15,544 stars every frame, all three native engines precompute a single `SkyProjectionMatrix` once per frame (`O(1)`) and project each star using pure floating-point dot products:

1. **Equatorial-to-Horizontal 3×3 Orthogonal Matrix (`EQJ_HOR`):**
   Given Greenwich Apparent Sidereal Time ($\text{GAST}$) and observer geodetic coordinates $(\varphi, \lambda)$, Local Sidereal Time is $\theta = \text{GAST} + \lambda$. Transforming J2000 equatorial unit vector $\mathbf{u}_{\text{EQJ}} = (u_x, u_y, u_z)$ into the right-handed local horizon frame **North-West-Zenith** $(h_x, h_y, h_z)$:
   $$h_x = -\sin\varphi\cos\theta\,u_x - \sin\varphi\sin\theta\,u_y + \cos\varphi\,u_z$$
   $$h_y = \sin\theta\,u_x - \cos\theta\,u_y$$
   $$h_z = \cos\varphi\cos\theta\,u_x + \cos\varphi\sin\theta\,u_y + \sin\varphi\,u_z$$
   where $\sin(\text{Alt}) = h_z$ and $\text{Az} = \operatorname{atan2}(-h_y, h_x) \pmod{360^\circ}$.

2. **Bennett (1982) Atmospheric Refraction Near Horizon:**
   For visible objects near the horizon ($h > -1^\circ$), apparent altitude is corrected via:
   $$R_{\text{arcmin}} = \frac{1.02}{\tan\!\left(h + \frac{10.3}{h + 5.11}\right)} \cdot \frac{P}{1010} \cdot \frac{283}{273 + T}$$

3. **Camera Orthonormal Basis & Singularity-Free Zenith Handling:**
   For camera pointing `(azimuth, altitude)` and sensor `rollDegrees`:
   - Forward axis $\mathbf{f} = (\cos\text{alt}\cos\text{az}, -\cos\text{alt}\sin\text{az}, \sin\text{alt})$.
   - Near zenith ($\text{alt} \ge 89.999^\circ$), the horizontal reference gracefully transitions so looking straight up (`90°`) places **North up** (`az = 0°` at screen top) and **East left** (proper sky chart handedness from inside the celestial sphere) without gimbal NaNs.
   - Conformal stereographic projection with focal scale $S = \frac{\min(W, H)}{2 \tan(\text{FOV}/4)}$:
     $$k = \frac{2 S}{1 + c_z}, \quad x_{\text{screen}} = \frac{W}{2} + k\,c_x, \quad y_{\text{screen}} = \frac{H}{2} - k\,c_y \quad (c_z > -0.85)$$
   - Constellations and circular structures preserve true angles across wide-field (`120°`) through telescopic (`0.5°`–`2°`) zoom levels.

---

## 2. Solar System Ephemeris & Observational Geometry

- **Apple & Android:** Driven by **CosineKitty Astronomy Engine** (`astronomy-swift` on Apple, pure Kotlin port in `AstronomyService.kt` on Android, and `AstronomyEngine.cs` on Windows) for sub-arcminute topocentric positions of **Sun, Moon, Mercury, Venus, Mars, Jupiter, Saturn, Uranus, Neptune, and Pluto**.
- **Topocentric Lunar Phase & Parallactic Bright-Limb Angle ($\chi$):**
  - Illuminated fraction $k = \frac{1 + \cos i}{2}$ from topocentric Sun–Moon elongation.
  - Position angle of the bright limb $\chi$ (Meeus Ch. 48) combined with parallactic angle $q$ yields the exact screen-space rotation of the sunlit crescent relative to local zenith—eliminating naive northern/southern hemisphere heuristic flips.
  - Exposes topocentric **Moon distance (`km`)**, **angular diameter (`arcmin`)**, and **lunar age (`days`)**.
- **Planetary Physical Ephemeris:**
  - **Saturn Ring System Inclination ($B$):** Sub-Earth ring tilt angle in degrees so planetarium renderers draw the true apparent ellipse opening for the simulated date.
  - **4 Galilean Moons of Jupiter (`Io`, `Europa`, `Ganymede`, `Callisto`):** Live Jovicentric sky-plane offsets $(X/R_J, Y/R_J)$ and occultation flags rendered dynamically when zooming into binocular/telescope FOV ($\le 12^\circ$).
- **Iterative Local Calendar-Night Rise / Transit / Set Solver:**
  - Bracketed 24-hour altitude scan with quadratic/bisection root refinement across standard refraction horizons (`-0.833°` Sun, `+0.125°` Moon parallax-adjusted, `-0.5667°` stars/planets/DSOs), explicitly classifying **Circumpolar** and **Never Rises** objects at high latitudes.

---

## 3. Native SGP4 Orbital Propagator (`NORAD 25544` — ISS)

All synthetic sine-wave pass placeholders have been eliminated and replaced with a deterministic **Vallado / NORAD SGP4 near-Earth orbital propagator** (`SGP4Propagator.swift`, `SGP4Propagator.kt`, `SGP4Propagator.cs`):
- Ingests CelesTrak GP **OMM JSON** (`MEAN_MOTION`, `ECCENTRICITY`, `INCLINATION`, `RA_OF_ASC_NODE`, `ARG_OF_PERICENTER`, `MEAN_ANOMALY`, `BSTAR`, `EPOCH`) or standard 2-line TLE fallback.
- Models $J_2, J_3, J_4$ zonal harmonics, atmospheric drag (`B*`), secular node regression, perigee advance, TEME $\rightarrow$ ECEF ($\text{GMST}$) $\rightarrow$ WGS-84 geodetic $(\varphi, \lambda, h_{\text{km}})$ $\rightarrow$ observer topocentric `(Az, Alt, Range_km)`.
- **Cylindrical / Conical Solar Umbra & Visual Magnitude:** Computes Earth shadow entry/exit along the Sun vector and phase-angle visual magnitude, filtering multi-hour pass predictions strictly to passes where the station reaches $\ge 10^\circ$ elevation while **sunlit** (`bestSunlitMag < 5.0`) under twilight/dark observer skies ($\text{Sun Alt} < -6^\circ$).

---

## 4. Stargazing Score (`0–100`) & Best Dark Window Engine

`evaluateStargazingConditions` computes an honest, deterministic `0–100` observability index and `15`-minute stepped **Best Dark Window**:
- **Inputs:** Multi-layer Open-Meteo cloud cover (`max(total, 0.9*high + 0.8*mid + 1.0*low)`), `7Timer! ASTRO` astronomical seeing (`arcsec FWHM`) and transparency, offline `bortle_world_grid.bin` Bortle class (`1`–`9`), solar depression angle, and Moon altitude × illuminated fraction.
- **Naked-Eye Limiting Magnitude (NELM):** Derived from Bortle class (`7.6` at Bortle 1 down to `4.0` at Bortle 9) minus lunar skyglow, twilight skyglow, and cloud extinction penalties.
- **Best Dark Window Scan:** Steps from local `16:00` to `07:00` next morning in `15`-minute increments, finding the contiguous interval maximizing darkness ($\text{Sun Alt} \le -12^\circ$, minimal lunar interference, and lowest hourly cloud forecast).

---

## 5. Cross-Platform Golden Vector Parity Suite

[`Tests/Fixtures/cosmos_golden_vectors.json`](../../Tests/Fixtures/cosmos_golden_vectors.json) locks numerical agreement across Swift (`DailyCoreTests`), Kotlin (`:core-model:testDebugUnitTest`), and C# (`Tests/Daily.Cosmos.Tests`):
1. Bucharest (`44.4268° N, 26.1025° E`) autumn night Sun/Moon/Venus/Jupiter/Sirius horizontal coordinates & lunar illumination.
2. Tromsø (`69.6492° N, 18.9553° E`) Arctic circumpolar & midnight-sun boundary handling.
3. Sydney (`-33.8688° S, 151.2093° E`) Southern Hemisphere bright-limb angle $\chi$ orientation.
4. Reference ISS OMM epoch propagation (`subpointLat`, `subpointLon`, `altitudeKm`, topocentric `Az/Alt/Range`).
5. Binary catalog integrity (`stars_mag70.bin` = `15,544` stars, `88` constellations, `219` DSOs, `bortle_world_grid.bin` lookup).
