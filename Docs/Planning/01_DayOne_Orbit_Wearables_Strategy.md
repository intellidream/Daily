# DayOne Orbit: Wearables Strategy & Roadmap (2026-2027)

Acest document descrie planul detaliat pentru aducerea DayOne pe smartwatch-uri, decuplând complet ecosistemul de necesitatea unui telefon (Direct-to-Cloud). Folosim arhitectura stabilită prin **WinUI Pin Pairing** pentru distribuirea de JWT Tokens (`access_token`, `refresh_token`) către ceasuri, permițându-le să facă requests directe către Supabase.

> **Regulă Arhitecturală:** Toate ceasurile, indiferent de platformă, vor comunica exclusiv prin Wi-Fi / LTE direct către instanța de Supabase, până la lansarea aplicației native de telefon (companion app). Telemetria brută este trimisă în `health_telemetry`, iar baza de date Supabase va agrega automat aceste date în `health_vitals` prin triggere PostgreSQL.

## 1. Faza 1: ZeppOS (Amazfit) - [ÎN DESFĂȘURARE]

Am ales ZeppOS drept prima platformă datorită ușurinței de dezvoltare (JavaScript/ES6) și a expunerii excelente a API-urilor pentru senzori.

### Arhitectura ZeppOS
* **Limbaj:** JavaScript (ES6).
* **UI Framework:** Sistemul nativ ZeppOS pe bază de Pagini și Fișiere (Mini-program UI).
* **Toolchain necesar:** `Node.js` (pe macOS) și pachetul `@zeppos/zeus-cli` (sau structură curată gestionată manual dacă apar erori de environment).
* **Sync Strategy (Hybrid):** 
  - Pentru modele cu Wi-Fi: API-ul intern `fetch` de pe device către Supabase.
  - Pentru modele fără Wi-Fi (ex. Active 2): **App Side Service**. Ceasul comunică prin BLE (`@zeppos/zml`) cu aplicația Zepp de pe telefon. Scriptul de pe telefon (App Side) are acces la internet și execută request-urile REST către Supabase, funcționând ca un bridge transparent.
  - **Notă UX:** Sistemul de Pairing este condus de Ceas (Ceasul generează PIN-ul, Desktop-ul îl primește și îl validează), oferind un UX mult superior. (Atenție: Pe Apple WatchOS am făcut invers în trecut, trebuie refăcut conform acestui UX nou!).

### Pași de Execuție:
1. **Initializare Proiect:** Crearea folderului și a structurii de bază (`app.json`, `package.json`, `app.js`).
2. **UI Pairing (Device):** Crearea ecranului de preluare PIN din 6 cifre pe ceas (`page/index.js`).
3. **App Side Service (Phone Bridge):** Construirea serviciului de fundal pe telefon (`app-side/index.js`) care interceptează pachetele de telemetrie sau pairing de la ceas, le trimite la Supabase, și întoarce token-ul (`access_token`, `refresh_token`).
4. **Colectare Senzori:** Utilizarea pachetului `@zos/sensor` pentru a citi pulsul (HeartRate), Sleep Stages și calitatea respirației.
5. **Sync Service:** Expedierea automată a payload-ului senzorilor prin `@zeppos/zml` (BLE) către Side Service pentru sincronizarea cu baza de date cloud.

---

## 2. Faza 2: watchOS (Apple Watch) - [URMEAZĂ]

Continuăm integrarea DayOne Orbit începută, dar decuplând complet aplicația de `WCSession` (care forța iPhone-ul să proceseze datele). 

### Arhitectura watchOS
* **Limbaj:** Swift 6.
* **UI Framework:** SwiftUI.
* **Date Medicale:** HealthKit.
* **Sync Strategy:** URLSession configurat pentru background tasks, ce preia direct Refresh Token-ul prin funcția custom Supabase implementată pe WinUI.

### Pași de Execuție:
1. **Mecanismul de Pairing:** Validarea completă a view-ului SwiftUI care generează PIN-ul (deja începută în `ContentView.swift`).
2. **HealthKit Background Delivery:** Trecerea de la ascultarea pasivă cu trimitere prin `WCSession` la instanțierea unui request `URLSession` direct.
3. **Re-implementare Supabase-Swift:** Construirea pachetelor de push manual folosind structurile REST (din cauza lipsei suportului oficial complet pentru watchOS background url tasks din clientul standard).

---

## 3. Faza 3: WearOS (Android) - [PLANIFICAT]

WearOS reprezintă ecosistemul standard pentru ceasurile Samsung și Google Pixel.

### Arhitectura WearOS
* **Limbaj:** Kotlin.
* **UI Framework:** Jetpack Compose for Wear OS.
* **Date Medicale:** Health Services API (PassiveDataClient).
* **Sync Strategy:** Coroutines și Retrofit/Supabase-kt pentru network calls.

### Pași de Execuție:
1. **Scaffold:** Proiect Android Studio orientat exclusiv pe WearOS (fără mobile app).
2. **Health Services:** Folosim `PassiveDataClient` pentru a înregistra listenere care adună ritmul cardiac (HR) și sleep data fără a drena bateria.
3. **Direct Sync:** Trimitem datele prin WorkManager folosind rețeaua internă (Wi-Fi/LTE). 

---

## 4. Faza 4: HarmonyOS / LiteOS (Huawei) - [PLANIFICAT TÂRZIU]

Dezvoltarea pentru Huawei presupune izolarea față de GMS (Google Mobile Services). 

### Arhitectura Huawei
* **Limbaj:** ArkTS (TypeScript-based) sau JS.
* **UI Framework:** ArkUI.
* **Toolchain:** DevEco Studio (compatibil macOS ARM).
* **Sync Strategy:** Huawei Network Kit.

### Provocări:
* Huawei restricționează masiv background tasks pe ceasurile LiteOS (GT Series). S-ar putea să fim forțați să construim sincronizarea DayOne Orbit aici **exclusiv când utilizatorul deschide manual aplicația**. Vom documenta aceste restricții tehnic la începerea fazei.
