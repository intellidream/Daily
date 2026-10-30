# macOS Desktop & Notification Center Widgets Architecture (2026)

**Data:** 30 Octombrie 2026  
**Componente:** `MacOS/DailyWidgets`, `MacOS/Daily.xcodeproj`, `DailyCore` (`WidgetDataCoordinator`, `WeatherService`), `MacOS/Daily` (`DailyMacOSApp`, `WidgetDarwinMutationListener`)  
**Platformă:** macOS 15.0+ (Apple Silicon arm64)  
**Semnătură & Identitate:** `Apple Development: MIHAI IONESCU (46P99RQF56)`, Team `7LZ9ZT2Z5B`, App Group `group.com.intellidream.daily`

---

## 1. Context & Obiectiv

Aplicația `DayOne` (`DailyMacOS`) oferă o suită completă de vizualizare și logare rapidă pentru 8 module esențiale (Habits/Bubbles, Smokes, Finances/SmartLedger, Health/Sleep, Health/Stress, TagDoS, Cosmos și Weather). Pentru a asigura paritate arhitecturală cu experiența iOS (`iOS/DailyWidgets`), a fost creată extensia nativă WidgetKit pentru desktopul macOS Sonoma și Sequoia, permițând utilizatorului să plaseze widgeturi direct pe desktop și în Notification Center.

Obiective cheie atinse:
1. **Păstrarea integrității semnăturii de cod**: Păstrarea exactă a configurării `Apple Development` și a Team ID-ului `7LZ9ZT2Z5B` fără erori de Keychain sau profile de provisioning lipsă.
2. **0ms Fast Local Cache**: Consum instantaneu al datelor din App Group `group.com.intellidream.daily` via `WidgetDataCoordinator`.
3. **Logare interactivă direct de pe Desktop**: Butoane interactive SwiftUI cu `AppIntents` (`LogWaterIntent`, `LogCigaretteIntent`, `LogHeatedIntent`, `AdjustLedgerIntent`) executate direct în widget fără a necesita deschiderea aplicației.
4. **Sincronizare inter-proces în timp real (Darwin IPC)**: Notificări de sistem Darwin (`com.intellidream.daily.widgetDidMutateData`) ascultate de `WidgetDarwinMutationListener` în aplicația gazdă macOS pentru împrospătarea automată și imediată a interfeței și flush în Supabase.
5. **Suită completă de 9 widgeturi**: Suport dedicat pentru formatele desktop `.systemSmall`, `.systemMedium` și `.systemLarge`.

---

## 2. Arhitectura Extensiei macOS (`DailyWidgets`)

### A. Structura Target-ului și Proiectului Xcode
Extensia a fost adăugată în `MacOS/Daily.xcodeproj` ca target de tip `com.apple.product-type.app-extension`:
* **Bundle Identifier**: `com.intellidream.daily.macos.DailyWidgets` (subordonat direct bundle-ului gazdă `com.intellidream.daily.macos`).
* **Destinație în Bundle**: `DayOne.app/Contents/PlugIns/DailyWidgetsExtension.appex`.
* **Build Phase**: `Embed Foundation Extensions` configurat în target-ul principal `Daily` cu `dstSubfolderSpec = 13` (`Contents/PlugIns`).
* **Dependințe**: Pachetul local `DailyCore` (linkează automat nucleul matematic, modelele și `CAstronomy`).

### B. Securitate și Entitlements
Fișierul `MacOS/DailyWidgets/DailyWidgets.entitlements` conține capabilitățile sandbox necesare:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<true/>
	<key>com.apple.security.network.client</key>
	<true/>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>group.com.intellidream.daily</string>
	</array>
</dict>
</plist>
```

---

## 3. Suita de Widgeturi Implementate

| Widget | Mărimi suportate | Funcționalități & Tehnologie |
|---|---|---|
| **CombinedWidget** | Small, Medium, Large | Dashboard executiv complet: mod adaptiv dimineață (Briefing, somn, vreme) și mod de zi (hidratare, fumat, finanțe, TagDoS pipeline). |
| **BubblesWidget** | Small, Medium, Large | Inele stratificate multi-băuturi, progres hidric, butoane interactive rapide (150ml, 250ml, 500ml Apă, Cafea, Ceai). |
| **SmokesWidget** | Small, Medium, Large | Plămâni vectoriali anatomici cu colorare dinamică a sănătății, inel de gudron/intake, timp scurs și butoane de logare țigări/heated. |
| **MoneyWidget** | Small, Medium, Large | Net Worth în Lei și EUR estimat, split card/cash, cheltuieli de vârf și butoane rapide de ajustare cont. |
| **SleepWidget** | Small, Medium, Large | Inel de scor somn, calitatea recuperării, hipnogramă proporțională pe stadii (Deep, REM, Light, Awake) și timeline culcat/trezit. |
| **TagdosWidget** | Small, Medium, Large | Pipeline de taskuri și etichete mentale pe stream-uri, badge-uri stilizate, număr tags active și alerte. |
| **StressWidget** | Small, Medium | Scor stres autonom calculat pe HRV clinic, mascotă maimuță cu expresii adaptive și recomandări de relaxare. |
| **CosmosWidget** | Small, Medium | Scor Stargazing /100, faza lunară cu iluminare procentuală, planete vizibile și predicții trecere ISS. |
| **WeatherWidget** | Small, Medium, Large | Vreme locală în timp real, temperatură resimțită, min/max, umiditate, vânt, timeline orar 5h și prognoză extinsă 5 zile. |

---

## 4. Logare Interactivă și Coordonare Inter-Proces

### A. AppIntents Directe
Utilizatorul poate atinge oricare dintre butoanele rapide de pe desktop:
```swift
Button(intent: LogWaterIntent(amountMl: 250, drinkType: "Water")) { ... }
Button(intent: LogCigaretteIntent()) { ... }
Button(intent: LogHeatedIntent()) { ... }
Button(intent: AdjustLedgerIntent(accountName: "Card", deltaReal: 100)) { ... }
```
Fiecare intent apelează `WidgetDataCoordinator.shared`, care:
1. Actualizează stocarea persistentă `group.com.intellidream.daily`.
2. Adaugă evenimentul în coada offline pentru sincronizare Supabase.
3. Apelează `WidgetCenter.shared.reloadAllTimelines()` pentru reactualizarea vizuală imediată a widget-ului.
4. Trimite notificarea Darwin `com.intellidream.daily.widgetDidMutateData`.

### B. Receptorul Darwin în Aplicația Principală
În `DailyMacOSApp`, `WidgetDarwinMutationListener` interceptează mutațiile exterioare produse de procesul extensiei:
```swift
CFNotificationCenterAddObserver(
    center,
    Unmanaged.passUnretained(self).toOpaque(),
    { _, _, _, _, _ in
        DispatchQueue.main.async {
            Task { @MainActor in
                SmartLedgerStore.shared.reloadFromStorage()
                HabitsService.shared.reloadFromLocalStorage()
                await HabitsService.shared.flushOfflineQueue()
                await HabitsService.shared.loadDataForSelectedDate()
            }
        }
    },
    name.rawValue,
    nil,
    .deliverImmediately
)
```
Efect: Orice acțiune efectuată pe desktopul macOS se propagă în aplicația deschisă sau în iconița MenuBar fără nicio latență.

### C. Navigare prin Deep Links
Fiecare widget are atașat un deep link `daily://` (`daily://habits`, `daily://finances/money`, `daily://health/sleep`, `daily://weather`, `daily://cosmos`, `daily://tagdos`, `daily://dashboard`).  
La click pe widget, `handleIncomingURL` din `DailyMacOSApp` comută automat fereastra `DayOne` pe tabul corespunzător.

---

## 5. Verificare și Validare

1. **Compilare Nativă Xcode**:
   ```bash
   xcodebuild -project MacOS/Daily.xcodeproj -scheme Daily -configuration Debug build
   # ** BUILD SUCCEEDED **
   ```
2. **Embed Binary Validation**:
   `embeddedBinaryValidationUtility` a validat cu succes binarul extensiei în interiorul `DayOne.app/Contents/PlugIns/DailyWidgetsExtension.appex`.
3. **Audit Semnătură Digitală**:
   * Ambele binare (`DailyWidgetsExtension.appex` și `Daily.app`) sunt semnate cu certificatul:
     `Apple Development: MIHAI IONESCU (46P99RQF56)`
   * `TeamIdentifier=7LZ9ZT2Z5B`
   * Ambele conțin entitlement-ul de App Sandbox și grupul partajat `group.com.intellidream.daily`.
4. **Înregistrare LaunchServices / PlugInKit**:
   ```bash
   pluginkit -m -v -i com.intellidream.daily.macos.DailyWidgets
   # com.intellidream.daily.macos.DailyWidgets(1.0.0) /.../Daily.app/Contents/PlugIns/DailyWidgetsExtension.appex (1 plug-in)
   ```
5. **Teste Unitare DailyCore**:
   Toate cele 56 de teste din 8 suite trec cu 0 erori:
   ```bash
   swift test --package-path DailyCore
   # Test run with 56 tests in 8 suites passed after 0.062 seconds.
   ```
6. **Lansare Nativă și Navigare URL**:
   Aplicația rulează ca proces activ în macOS, răspunde la deschiderea URL-urilor de navigare și actualizează cache-ul de vreme în fundal.
