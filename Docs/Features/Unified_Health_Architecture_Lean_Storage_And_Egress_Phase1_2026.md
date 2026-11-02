# Unified Health Architecture: Lean Storage, Egress & Discrete Sleep (Phase 1)

**Data:** 2 Noiembrie 2026  
**Document:** Livrare & Implementare Tehnică Faza 1  
**Platforme:** Supabase (PostgreSQL), DailyCore (iOS & macOS), Android (core-model, core-network, core-health), macOS App  
**Status:** Implementat, Validat prin Teste Unitare & Build-uri Native Reușite  

---

## 1. Context & Obiectiv

Conform deciziilor de arhitectură stabilite în [`Docs/Health_Architecture_Redesign_Lean_Storage_And_Egress_2026.md`](file:///Users/mihai/Source/Daily/Docs/Health_Architecture_Redesign_Lean_Storage_And_Egress_2026.md), am inițiat implementarea **Fazei 1 (Schema Lean, Backfill Istoric & Integrare Clienți)**:

1. **Eliminarea dependenței de buffer-ul de telemetrie de înaltă frecvență** (`health_telemetry`), care genera ~25.000 de rânduri/zi și 67 MB de bloat în indecși B-Tree.
2. **Crearea tabelei dedicate de somn** (`health_sleep_sessions`), izolând stadiile hipnice de telemetria brută și stocând fiecare sesiune ca un singur rând cu stadii `stages jsonb`.
3. **Crearea tabelei de vitals zilnice unificate** (`health_daily_vitals`), aplicând regula de suprascriere în loc (UPSERT) pentru metricele fără curbă intraday (1 rând per zi per dispozitiv).
4. **Curba de puls intraday bucket-uită la 5 minute** (`health_intraday_heart_rate`), reducând probele de la 15.000 la maximum 288 puncte per zi per dispozitiv.
5. **Rezolvarea vizibilității globale a dispozitivelor** (`health_sources`), oferind un catalog centralizat ce previne izolarea surselor pe dispozitive individuale (ex: problema Trapper).
6. **Păstrarea 100% a datelor istorice**: datele de azi (2026-11-02, Oura Ring cu 82 de stadii hipnice, scor 75) și din zilele anterioare au fost migrate și sunt active în noile tabele.

---

## 2. Componente Implementate în Baza de Date (Supabase)

### A. Migrația Schemelor Noii Arhitecturi ([`20261102000000_lean_health_architecture_v1.sql`](file:///Users/mihai/Source/Daily/supabase/migrations/20261102000000_lean_health_architecture_v1.sql))

* **`health_sources`**: Catalogul hardware al utilizatorului cu `priority_sleep`, `priority_activity`, `color`, `host_device_name`.
* **`health_sleep_sessions`**: Stochează discrete sesiuni nocturne și sieste, cu `stages jsonb`, start/end, scor de somn, eficiență, durată în pat. Adăugat la publicația `supabase_realtime`.
* **`health_daily_vitals`**: Metrice compozite per zi per dispozitiv (pași, calorii active, RHR, SpO2, HRV, greutate, pași orari `hourly_steps jsonb`). Adăugat la `supabase_realtime`.
* **`health_intraday_heart_rate`**: Rezoluție de 5 minute (`bpm_avg`, `bpm_min`, `bpm_max`, `sample_count`).

### B. Migrația de Backfill & Salvare a Istoricului ([`20261102000001_backfill_lean_health.sql`](file:///Users/mihai/Source/Daily/supabase/migrations/20261102000001_backfill_lean_health.sql))

* Înregistrate 8 dispozitive standardizate în `health_sources`:
  * `schmitz_oura` (Oura Ring Gen 3 - Sleep Priority 1)
  * `schmitz_ultra2` (Apple Watch Ultra 2 - Activity Priority 1)
  * `trapper_pw5` (Pixel Watch 5 - Wear OS)
  * `schmitz_iphone` (iPhone 16 Pro Max - Host Schmitz)
  * `trapper_pixel9` (Pixel 9 Pro - Host Trapper)
  * `radar_fold8` (Galaxy Z Fold 8 - Host Radar)
  * `macos_desktop` (Mac Daily Desktop)
  * `windows_desktop` (Windows 11 PC Daily WinUI)
* Backfill sesiuni de somn din `health_daily_summary` în `health_sleep_sessions`:
  * `2026-11-02`: Oura Ring (8.75h, 82 stadii hipnice, scor 75)
  * `2026-11-01`: Oura Ring (4.40h, 30 stadii, scor 53)
  * `2026-10-30`: Oura Ring (7.63h, 68 stadii, scor 82)
  * `2026-10-27`: Oura Ring (8.25h, 71 stadii, scor 86)
  * `2026-10-24`: Pixel Watch 5 Fitbit (8.13h, 20 stadii, scor 98)
  * Sesiuni anterioare Apple Watch Ultra 2 și Pixel Watch 5 de pe Radar.
* Backfill vitals zilnice în `health_daily_vitals` (inclusiv pași orari).
* Backfill bucket-uri de 5 minute de ritm cardiac în `health_intraday_heart_rate`.

---

## 3. Implementare Client Multiplatformă

### A. Apple Ecosystem (`DailyCore` & macOS)
* Creat [`DailyCore/Sources/DailyCore/Models/LeanHealthModels.swift`](file:///Users/mihai/Source/Daily/DailyCore/Sources/DailyCore/Models/LeanHealthModels.swift):
  * `HealthSleepSessionRecord`: mapping 1:1 și metodă de conversie `.toSleepSession()`.
  * `HealthDailyVitalsRecord`: consolidare pași orari și metrice cardiovasculare.
  * `HealthIntradayHeartRateRecord`: metodă `.toPoint(for: Date)`.
  * `HealthSourceRecord`: catalog dispozitive.
* Actualizat [`DailyCore/Sources/DailyCore/Services/HealthDataService.swift`](file:///Users/mihai/Source/Daily/DailyCore/Sources/DailyCore/Services/HealthDataService.swift):
  * `performLoadDataForSelectedDate`: fetch concurent din tabelele lean (`health_sleep_sessions`, `health_daily_vitals`, `health_intraday_heart_rate`, `health_sources`).
  * Adăugate metodele applicatoare: `applyLeanSleepSessions`, `applyLeanDailyVitals`, `applyLeanIntradayHeartRate`, `applyLeanHealthSources`.
* Adăugat test unitar dedicat în `HealthServiceTests.swift` (`testLeanHealthModelsAndSessionConversion`).
* Toate cele 57 de teste unitare din `DailyCore` trec cu 0 erori.
* `Daily.app` pentru macOS recompilat complet nativ cu semnare Apple Development și repornit.

### B. Android Ecosystem (`core-model`, `core-network`, `core-health`, `app`)
* Creat [`Android/core-model/src/main/java/com/intellidream/daily/model/LeanHealthModels.kt`](file:///Users/mihai/Source/Daily/Android/core-model/src/main/java/com/intellidream/daily/model/LeanHealthModels.kt) cu adnotări de serializare kotlinx.
* Actualizat [`Android/core-network/src/main/java/com/intellidream/daily/network/HealthRemoteService.kt`](file:///Users/mihai/Source/Daily/Android/core-network/src/main/java/com/intellidream/daily/network/HealthRemoteService.kt):
  * Adăugate `fetchSleepSessions`, `fetchDailyVitals`, `fetchIntradayHeartRate`, `fetchHealthSources`, `pushSleepSession`, `pushDailyVitals`, `pushIntradayHeartRate`.
* Actualizat [`Android/core-health/src/main/java/com/intellidream/daily/health/HealthDataRepository.kt`](file:///Users/mihai/Source/Daily/Android/core-health/src/main/java/com/intellidream/daily/health/HealthDataRepository.kt):
  * `loadDataForSelectedDate` integrează interogarea noilor tabele lean cu aplicare automată pe StateFlows.
  * `applyLeanHealthSources` populează lista globală de surse, eliminând bug-ul prin care Trapper vedea doar dispozitivele proprii.
* Rulate testele unitare (`./gradlew :core-health:testDebugUnitTest` - BUILD SUCCESSFUL).
* Rulată asamblarea completă Android (`./gradlew :app:assembleDebug` - BUILD SUCCESSFUL).

---

## 4. Verificare & Rezultate

1. **Integritate Date:** Datele curente pe ziua de azi (2026-11-02) sunt vizibile și populate corect din `health_sleep_sessions` (Oura Ring, 8.75 ore de somn, 82 tranziții de stadii, scor 75).
2. **Backward Compatibility:** Tabelele vechi (`health_daily_summary` și `health_telemetry`) nu au fost modificate destructiv; clienții care încă se bazează pe `health_daily_summary` (ex: Windows WinUI) continuă să funcționeze fără degradare.
3. **Pregătire pentru Următorul Ciclu:** Când vor veni date noi de somn mâine dimineață sau date de telemetrie pe parcursul zilei de la ceasuri/telefoane, acestea vor fi procesate pe noile structuri fără suprascriere distructivă a istoricului.
