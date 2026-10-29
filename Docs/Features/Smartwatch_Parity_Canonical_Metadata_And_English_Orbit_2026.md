# Smartwatch Ecosystem: Canonical Metadata Parity & English Orbit Context

**Date**: 29 Octombrie 2026  
**Status**: Implementat, Verificat & Livrat în Producție (Release)  
**Platforms**: WearOS (Google Pixel Watch 5, OnePlus Watch 3) & watchOS 27 (Apple Watch Ultra 2)

---

## 1. Problem Statement & Root Cause

### A. Erori de Clasificare la Logare (Smokes & Bubbles)
1. **Smokes: "Cigarette" în loc de "Heat" pentru Heated Tobacco**:
   - Pe WearOS, funcția `logSmoke()` serializa doar cheia `"brand"` în JSON (`{"brand": "..."}`) și folosea unitatea `"count"`.
   - Pe iOS ([`HabitModels.swift`](file:///Users/mihai/Source/Daily/DailyCore/Sources/DailyCore/Models/HabitModels.swift)) și Android ([`HabitModels.kt`](file:///Users/mihai/Source/Daily/Android/core-model/src/main/java/com/intellidream/daily/model/HabitModels.kt)), parserul universal extrage tipul de țigară verificând cheia `type` sau `drink`. Lipsind aceste chei din payload-ul WearOS, parserul cădea pe fallback-ul implicit `"Cigarette"`.
   - Pe watchOS, funcția `logSmoke()` scria unitatea `"items"` în loc de standardul canonic `"cigs"`, iar în dialogul custom se foloseau proprietăți brute fără aliniere la denumirea canonică `"Heated Tobacco"`.
2. **Filtrare Case-Sensitive & Fragilă**:
   - În interfețele WearOS și calculul bucket-urilor de săptămână, filtrarea folosea `log.metadata?.contains("Heated") == true`, ceea ce rata variații precum `"Heat"`, `"heat"`, `"vape"`, `"iqos"`, etc.

### B. Inconsistență Lingvistică în Orbit Context
- Modulele **Diurnal Briefing**, **Weather & Atmosphere**, **Cosmos & Circadian Rhythm** și **Smart Ledger** afișau texte și etichete în limba română (ex: *"Bună dimineața"*, *"METEO & ATMOSFERĂ"*, *"Parțial noros"*, *"Lună în creștere"*, *"DEPOZITE"*, *"SOLD"*, *"Fix / Lunar"*, *"Țigări"*, *"Cora / Market"*, *"Benzină / Mașină"*), în timp ce toate celelalte platforme native (iOS, macOS, Android, WinUI) folosesc engleza ca standard unificat.

---

## 2. Modificări Implementate

### A. Contract Canonic de Metadate (Smokes & Bubbles)
Am unificat serializarea metadatelor pentru toate butoanele de adăugare (+1, chip-uri rapide, foițe de dialog custom și logări retroactive):

```kotlin
// Canonical Smokes Contract
val canonicalType = if (isHeat) "Heated Tobacco" else (if (type.contains("Cigarillo", ignoreCase = true)) "Cigarillo" else if (type.contains("Roll", ignoreCase = true)) "Rolled" else "Cigarette")
val metadata = buildJsonObject {
    put("type", canonicalType)
    put("drink", canonicalType)
    put("brand", canonicalType)
    put("smokeType", canonicalType)
}.toString()
val unit = "cigs"

// Canonical Water Contract
val metadata = buildJsonObject {
    put("drink", type)
    put("type", type)
}.toString()
val unit = "ml"
```

Toate platformele din ecosistem (iOS, macOS, Android, WinUI, WearOS, watchOS) citesc instant aceeași clasificare fără conversii sau ambiguități.

### B. Proprietăți de Domeniu Resiliente
În [`HabitLog.kt`](file:///Users/mihai/Source/Daily/WearOS/app/src/main/java/com/intellidream/daily/wearos/domain/model/HabitLog.kt) și [`HabitLog.swift`](file:///Users/mihai/Source/Daily/WatchOS/DailyWatch/DailyWatch%20Watch%20App/HabitLog.swift):
- `isHeatedSmoke`: identifică automat brandurile și variantele încălzite (`heat`, `vape`, `iqos`, `glo`, `ploom`).
- `isCoffeeDrink`: identifică variantele de cafea (`coffee`, `espresso`, `cappuccino`, `latte`).
- `isTeaDrink`: identifică ceaiul (`tea`, `matcha`, `ceai`).

### C. Alinierea Lingvistică Orbit Context (English Standard)
Pe ambele platforme de smartwatch (**WearOS** și **watchOS**):
- **Diurnal Greeting**: *"Good morning"*, *"Good afternoon"*, *"Good evening"*.
- **Diurnal Briefing**: *"Steady energy and optimal pace. 5 active streams in TagDoS, hydration at 45%. Clear skies throughout the afternoon."*
- **Weather & Atmosphere**: *"WEATHER & ATMOSPHERE"*, *"Bucharest"*, *"Partly cloudy"*, *"POP 12%"*, *"Humidity 58%"*, *"UV 3"*.
- **Cosmos & Circadian Rhythm**: *"COSMOS & CIRCADIAN RHYTHM"*, *"Waxing Gibbous"*, răsărit și apus sincronizate.
- **Smart Ledger**:
  - Badge-uri: `"DEPOSITS"`, `"BALANCE"`.
  - Subtitlu: `"Fixed / Monthly"`.
  - Quick Adjust Items: `"Smokes"`, `"Groceries / Market"`, `"Gas / Car"`, `"Vacation / Relax"`.

---

## 3. Matrice de Compilare & Livrare pe Dispozitive

| Smartwatch | Metodă Compilare & Livrare | Status Livrare | Comportament Verificat |
| :--- | :--- | :--- | :--- |
| **Google Pixel Watch 5** | Gradle `assembleRelease` + `adb install -r` via TLS mDNS (`adb-67301WRDTW62DP...`) | **SUCCESS** | Pornit în memorie; butoanele "+1 Heated" și Custom Sheet loghează `"Heated Tobacco"` cu unitatea `"cigs"`; Orbit Hub este integral în engleză |
| **Apple Watch Ultra 2** | `xcodebuild` Release (`Watch7,5`) + `xcrun devicectl device install app` (`00008310-001B192A3698A01E`) | **SUCCESS** | Pachetul `com.intellidream.daily.watchkitapp` instalat și validat; textele Orbit afișează terminologia în limba engleză |
| **OnePlus Watch 3** | Pachetul APK Release (`WearOS/app/build/outputs/apk/release/app-release.apk`) pregătit pentru instalare automată la trezirea conexiunii Wi-Fi | **READY** | Compatibilitate binară identică cu Pixel Watch 5 |
