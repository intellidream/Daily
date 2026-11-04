# Foldable & Glance Heart Rate Parity Architecture (2026)

**Data:** 4 Noiembrie 2026  
**Componente:**
- **macOS & iOS (iPhone Duo)**: `MacOS/Daily/Views/Foldable/DailyFoldableCompanionPane.swift`, `iOS/Daily/Views/Foldable/DailyFoldableCompanionPane.swift`
- **Android (Samsung Galaxy Z Fold 8 / RADAR & Trapper)**: `Android/app/src/main/java/com/intellidream/daily/presentation/foldable/DailyFoldableCompanionPane.kt`
- **Windows 11 (WinUI 3)**: `WinUI/Daily.WinUI/Controls/TaskbarGlanceFlyoutControl.xaml.cs`  
**Platforme:** macOS 15.0+ (Sequoia), iOS 18.0+, Android 15 (Foldables / Phones), Windows 11 (WinUI 3 pe .NET 10)  
**Obiectiv:** Eliminarea discrepanțelor între ritmul cardiac afișat în Header-ul Companion / Diurnal (în dreapta salutului) pe Foldables/macOS și cel din Health Widgets / Glance, precum și aducerea ritmului cardiac real în Glance-ul din System Tray pe WinUI 3.

---

## 1. Context & Diagnostic

În cadrul inspecției comparative pe macOS (RootView dual-pane), pe foldable-urile **iPhone Duo** și **Samsung Galaxy Z Fold 8**, precum și în bara de sistem pe **Windows 11 (WinUI 3)**, a fost identificată o discrepanță flagrantă:

1. **Companion Header pe macOS și iPhone Duo (`DailyFoldableCompanionPane.swift`)**:
   - În `diurnalHeader`, la dreapta mesajului de salut (`diurnalWish` - ex: "Good morning, Mihai"), pilula interactivă de puls afișa `displayBpm`.
   - Implementarea anterioară calcula:
     ```swift
     private var displayBpm: Int {
         let val = healthService.restingBpm > 0 ? healthService.restingBpm : healthService.averageBpm
         return Int(val.rounded())
     }
     ```
   - Acest calcul prioritiza **Resting Heart Rate (RHR)** (valoare tipică 50–60 bpm) sau media zilnică, ignorând complet `healthService.latestBpm` (pulsul live/cel mai recent transmis de Apple Watch / senzori, de ex. 74–85 bpm).
   - În contrast, widget-ul din aplicație (`HealthDashboardCard.swift`) și meniul popover Glance (`MenuBarCompanionView.swift`) foloseau:
     ```swift
     healthService.latestBpm ?? (healthService.averageBpm > 0 ? healthService.averageBpm : nil)
     ```
   - Utilizatorul vedea astfel o valoare complet diferită în header (56 BPM) față de widgetul Health și Glance (74 BPM).

2. **Android Foldable Companion pe Galaxy Z Fold 8 (`DailyFoldableCompanionPane.kt`)**:
   - `displayBpm` făcea doar un simplu `latestBpm ?: averageBpm`. Dacă `latestBpm` era temporar null și `averageBpm` era 0.0, afișa `-- BPM` sau nu lua în calcul `currentVitals[HealthMetricType.HEART_RATE]`, generând desincronizări cu cardul principal de sănătate (`HealthDashboardCard.kt`).

3. **WinUI 3 System Tray Glance (`TaskbarGlanceFlyoutControl.xaml.cs`)**:
   - Încărca pulsul apelând exclusiv `_healthService.GetLatestMetricAsync(VitalType.HeartRate)`. În arhitectura modernă Supabase, telemetria intraday de ritm cardiac din Apple Watch Ultra 2 sau senzori este serializată în `health_daily_summary` (`Cardiovascular.IntradayHeartRate`).
   - `HealthWidgetControl.xaml.cs` (widget-ul Health din fereastra principală) citea corect ultimul punct din sumarul intraday (`_currentSummary?.Summary?.Cardiovascular?.IntradayHeartRate?.LastOrDefault(p => p.Bpm > 0)`), în timp ce Glance-ul din System Tray rămânea pe `--` sau pe o valoare învechită.

---

## 2. Soluții Tehnice Aplicate

### A. macOS & iOS Foldable Companion Pane (`DailyFoldableCompanionPane.swift`)
Calculul `displayBpm` a fost aliniat riguros la standardul canonic al widgetului Health și Glance:
```swift
private var displayBpm: Int {
    // 1. Prioritate absolută: Cel mai recent puls live măsurat (Apple Watch / Senzori)
    if let latest = healthService.latestBpm, latest > 0 {
        return Int(latest.rounded())
    }
    // 2. Fallback: Ultimul record valid din catalogul de vitale
    if let vitalsBpm = healthService.currentVitals[.heartRate]?.value, vitalsBpm > 0 {
        return Int(vitalsBpm.rounded())
    }
    // 3. Fallback: Medie zilnică sau RHR
    let val = healthService.averageBpm > 0 ? healthService.averageBpm : (healthService.restingBpm > 0 ? healthService.restingBpm : 0)
    return Int(val.rounded())
}
```

### B. Android Foldable Companion Pane (`DailyFoldableCompanionPane.kt`)
S-a adăugat colectarea stărilor `restingBpm` și `currentVitals`, iar `displayBpm` a fost unificat:
```kotlin
val displayBpm = (latestBpm
    ?: currentVitals[HealthMetricType.HEART_RATE]?.value?.takeIf { it > 0.0 }
    ?: if (averageBpm > 0.0) averageBpm else if (restingBpm > 0.0) restingBpm else null) ?: 0.0
```

### C. WinUI 3 Taskbar Companion Flyout (`TaskbarGlanceFlyoutControl.xaml.cs`)
S-a injectat `IHealthHubService` și s-a replicat 1:1 logica de extracție din `HealthWidgetControl.xaml.cs`:
1. **Prioritate 1**: Ultimul eșantion intraday cu BPM > 0 din `summary.Summary.Cardiovascular.IntradayHeartRate`.
2. **Prioritate 2**: Valoarea live din `GetLatestMetricAsync(VitalType.HeartRate)`.
3. **Prioritate 3**: Resting Heart Rate din sumar sau `VitalType.RestingHeartRate`.

---

## 3. Matrice de Validare și Livrare

| Țintă | Platformă | Metodă Livrare | Status Verificare |
| :--- | :--- | :--- | :--- |
| **macOS Native** | macOS 15.0+ | `xcodebuild ... platform=macOS` | **BUILD SUCCEEDED** (Apple Development) |
| **SimulaDuo** | iOS Simulator (iPhone Duo) | `xcodebuild` + `simctl install` | **INSTALAT & ACTIV** |
| **Schmitz** | iPhone 16 Pro Fizic | `xcodebuild ... generic/platform=iOS` | **COMPILED & SIGNED** (gata de install la deblocare) |
| **Android APK** | Android (Z Fold 8 & Trapper) | `./gradlew assembleDebug` | **BUILD SUCCESSFUL (13s)** |
| **WinUI 3 VM** | Windows 11 ARM64 | `git pull` + `dotnet build` | **0 Error(s)** |
