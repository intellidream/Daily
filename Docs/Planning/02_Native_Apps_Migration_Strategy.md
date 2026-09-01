# Native Apps Migration Strategy (MAUI to SwiftUI & Kotlin)

Acest document descrie viziunea arhitecturală de tranziție de la .NET MAUI către o flotă de aplicații **100% Native**, folosind experiența dobândită și design-ul rafinat al versiunii WinUI ca **Standard de Aur**.

## De ce migram de la MAUI?
Deși MAUI a oferit un start rapid, constrângerile de performanță, bug-urile de layout cross-platform (în special pe complex UI, Glassmorphism, tab-uri), instabilitatea binding-urilor pe iOS și suportul slab pentru background tasks justifică mutarea către development nativ pe ecosistemele Apple și Android.

## Standardul WinUI ("The Gold Standard")
Varianta de Windows (Daily.WinUI) este considerată implementarea de referință. Următoarele elemente trebuie transpuse 1:1 în viitoarele versiuni native:
* **The Glassy UI:** Background-uri de sticlă cu noise SVG, border-uri subtile, și opacități nucleare.
* **Arhitectura Single Source of Truth:** Interfața citește DOAR din baza de date locală (SQLite), niciodată din Cloud.
* **Sync-ul Hibrid:** Background worker care descarcă datele din Supabase și le varsă în SQLite tăcut, în timp real (prin Supabase Realtime).

---

## 1. Ecosistemul Apple (iOS, iPadOS, macOS)

Aici vom dezvolta aplicația de mobil și tabletă folosind **SwiftUI**, pentru o experiență perfect fluidă în ecosistemul Apple. 

### Arhitectura iOS / iPadOS
* **Limbaj:** Swift 6.
* **UI Framework:** SwiftUI.
* **Baza de Date Locală:** CoreData sau GRDB.swift (recomandat GRDB pentru control SQL direct și similaritate cu setup-ul nostru curent SQLite).
* **Networking:** Supabase-Swift SDK.

### Obiective Majore:
1. **Design Adaptiv (iPad):** Utilizarea `NavigationSplitView` pe iPad pentru a emula meniul lateral WinUI. Pe iPhone, trecere fluidă spre un `TabView` de bază.
2. **Companion pentru Apple Watch:** Această aplicație va juca rolul de setare și asistență pentru DayOne Orbit, chiar dacă ceasul va comunica independent prin Wi-Fi.
3. **Migrarea modulelor:**
   - **SmartBriefing:** Reproducere carusele și cache offline.
   - **SmartLedger (Money):** Implementare Donut Charts folosind noul `Swift Charts` framework (iOS 16+).

### Arhitectura macOS
Odată implementată versiunea de iPad, vom aduce aplicația pe Mac folosind:
* **Mac Catalyst:** Dacă aplicația de iPad e suficient de matură și se adaptează bine.
* **Sau SwiftUI for Mac:** Dacă dorim să folosim windowing avansat, titlebars transparente și blur (Material) nativ (echivalentul a ceea ce am făcut pe WinUI cu Mica).

---

## 2. Ecosistemul Android (Telefoane & Tablete)

Android rămâne crucial pentru acoperirea pieței, mai ales ca și companion app pentru viitoarea aplicație de WearOS.

### Arhitectura Android
* **Limbaj:** Kotlin.
* **UI Framework:** Jetpack Compose.
* **Baza de Date Locală:** Room Database (o abstractizare robustă peste SQLite, cu suport excelent pentru fluxuri de date / Kotlin Flow).
* **Networking:** Supabase-kt.

### Obiective Majore:
1. **Jetpack Compose UI:** Transpunerea design language-ului Glassmorphism de pe WinUI este posibilă folosind modifier-e de Blur (disponibile pe Android 12+) sau fallback-uri de gradient pe versiuni mai vechi.
2. **Offline-First:** Room va acționa perfect pe principiile noastre din WinUI, emițând `Flow` update-uri spre UI imediat ce serviciul de Supabase background workers varsă date.
3. **Companion WearOS:** Permite managementul notificărilor și onboarding-ului pentru viitoarea aplicație de WearOS.

---

## Etape de Tranziție (Roadmap Executiv)
1. Înghețăm funcționalitățile majore pe ramura de .NET MAUI (doar bugfix-uri pentru Android/iOS MAUI actual, dacă e în producție).
2. Start implementare Swift / iOS ca "First Native Mobile Port".
3. Validare parity (Smart Ledger, Habits, Health) între iOS SwiftUI și WinUI.
4. Lansare macOS (Catalyst/SwiftUI).
5. Start implementare Kotlin / Jetpack Compose Android.
