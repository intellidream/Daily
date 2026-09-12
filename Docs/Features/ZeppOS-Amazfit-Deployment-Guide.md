# Zepp OS (Amazfit) Deployment & Delivery Guide

Ghid complet pas-cu-pas pentru pregătirea mediului de dezvoltare, compilarea și livrarea aplicației **DayOne Orbit** pe ceasurile inteligente **Amazfit** (cum ar fi Amazfit Balance și Amazfit Active 2) folosind Zepp CLI (`zeus`).

---

## 1. Arhitectura de Livrare Zepp OS

Aplicația DayOne Orbit pentru Zepp OS este compusă din două componente:
1. **Mini Program pe Ceas (`page/index.js`, `page/logs.js`)**: Rulează nativ pe sistemul de operare al ceasului (Zepp OS 3.0), gestionează interfața grafică, senzorii biometrici (puls, pași, somn, stres, PAI) și stocarea locală offline (`@zos/fs`, `@zos/storage`).
2. **Side Service pe Telefon (`app-side/index.js`)**: Rulează în fundal în interiorul aplicației **Zepp** de pe smartphone (iOS/Android). Deoarece ceasul nu poate deschide socket-uri HTTP/TCP arbitrare direct prin Wi-Fi, Side Service acționează ca un proxy securizat către backend-ul Supabase prin BLE (Bluetooth Low Energy) folosind `@zeppos/zml`.

Instalarea pe ceas se realizează prin **puntea de dezvoltator a aplicației Zepp de pe telefon** scanând un cod QR generat de comanda `npx zeus preview`.

---

## 2. Pregătirea Mediului pe o Mașină Curată (Fresh Machine / Reset)

Dacă ai reinstalat sistemul de operare sau rulezi pe un Mac/PC nou:

### Pasul 2.1: Instalare Node.js
Asigură-te că ai instalat **Node.js (versiunea 18 LTS sau 20 LTS)**:
```bash
node -v
npm -v
```
*(Dacă nu este instalat: `brew install node` pe macOS sau descarcă de pe [nodejs.org](https://nodejs.org/)).*

### Pasul 2.2: Instalare Dependențe Proiect
Navighează în folderul `ZeppOS`:
```bash
cd /Users/mihai/Source/Daily/ZeppOS
npm install
```
Această comandă instalează:
- `@zeppos/zeus-cli` (`^1.9.3`): CLI-ul oficial Zepp OS pentru build, preview și ambalare.
- `@zeppos/zml` (`^0.0.43`): Biblioteca de mesagerie RPC între Ceas și Telefon.

> [!NOTE]
> Nu este nevoie de instalare globală (`npm install -g @zeppos/zeus-cli`). Proiectul utilizează direct binarul local prin `npx zeus`.

---

## 3. Pregătirea Telefonului și a Ceasului

### Pasul 3.1: Conexiunea la Aceeași Rețea Wi-Fi (CRUCIAL)
- **Calculatorul (Mac-ul)** și **Smartphone-ul (cu aplicația Zepp)** **TREBUIE să fie conectate la aceeași rețea Wi-Fi**.
- Telefonul va descărca pachetul compilat (`.zab`) direct de pe serverul HTTP local pornit de Mac.
- **Atenție la Firewall / VPN**: Dacă ai un VPN activ pe Mac sau pe telefon, oprește-l. Dacă rețeaua Wi-Fi are izolare AP (ex: rețele Guest), telefonul nu va putea accesa IP-ul Mac-ului.
  - *Alternativă sigură*: Pornește **Personal Hotspot** pe telefon și conectează Mac-ul la hotspot-ul telefonului.

### Pasul 3.2: Activarea Modului Dezvoltator în Aplicația Zepp (Telefon)
1. Deschide aplicația oficială **Zepp** pe iPhone sau Android.
2. Asigură-te că ceasul Amazfit este conectat prin Bluetooth.
3. Mergi la tab-ul **Profile** (dreapta-jos).
4. Selectează **Settings** (Setări) -> **About** (Despre).
5. Apasă repetat de **7 ori consecutiv pe logo-ul Zepp** din partea de sus a ecranului.
6. Va apărea un mesaj toast: *"Developer mode is turned on"* (sau *"Developer options unlocked"*).
7. Revino în ecranul **Profile**.
8. Vei găsi un nou meniu dedicat: **Developer options** (Opțiuni pentru dezvoltatori).
9. Intră în **Developer options** și asigură-te că switch-ul **Developer Mode** este activat (**ON**).

---

## 4. Procesul de Livrare (`npx zeus preview`)

Pentru a compila și trimite aplicația direct pe ceas:

### Pasul 4.1: Lansarea Comenzii
În terminal, din folderul `ZeppOS`:
```bash
cd /Users/mihai/Source/Daily/ZeppOS
npx zeus preview
```

### Pasul 4.2: Selectarea Dispozitivului (CRITICAL GOTCHA)
Zeus va afișa un meniu interactiv în terminal pentru selectarea modelului de ceas țintă.

> [!WARNING]
> **NU SELECTA DISPOZITIVUL DIN SECȚIUNEA DE SUS ("Suggested" / "Recently Used")!**
> Există un bug cunoscut în Zeus CLI: selectarea din lista sugerată produce frecvent pachete cu metadate corupte, rezultând în eroarea `Download failed : error code null` sau `Device does not support`.
>
> **Soluție**: Folosește tastele săgeți pentru a naviga în jos până la **catalogul complet de dispozitive** și selectează manual modelul ceasului tău:
> - Pentru **Amazfit Balance**: selectează `Amazfit Balance` (Round, 480x480)
> - Pentru **Amazfit Active 2**: selectează `Amazfit Active 2` (Square, 390x450)

### Pasul 4.3: Compilarea și Generarea Codului QR
CLI-ul va parcurge următoarele etape:
1. `[ROLLUP]` Transformă fișierele JavaScript.
2. `[PNG2TGA]` Convertește iconițele și imaginile PNG în format TGA optimizat pentru ecranul ceasului.
3. `[QJSC]` Compilează codul JS în bytecode QuickJS.
4. Pornește serverul local de distribuție și desenează un **cod QR ASCII** direct în consolă.

### Pasul 4.4: Scanarea și Instalarea de pe Telefon
1. Pe telefon, deschide aplicația **Zepp** -> **Profile** -> **Developer options**.
2. În colțul din dreapta-sus, apasă pe pictograma de **Scanare Cod QR** (sau butonul `+`).
3. Îndreaptă camera telefonului către codul QR din terminalul Mac-ului.
4. Aplicația Zepp va:
   - Descărca fișierul `.zab` prin Wi-Fi de pe Mac.
   - Transfera pachetul prin Bluetooth către ceas.
   - Instala și lansa automat aplicația **DayOne Orbit** pe ecranul ceasului!

### Pasul 4.5: Live Console Logs & Ieșire
- Atât timp cât comanda `npx zeus preview` rămâne activă în terminal, vei vedea în timp real logurile trimise de ceas și de telefon (`console.log`, sincronizările de telemetrie, erorile de rețea).
- Pentru a opri consola de debugging, apasă `Ctrl + C`. Aplicația rămâne instalată pe ceas și o poți lansa oricând din lista de aplicații a ceasului.

---

## 5. Compilarea unui Pachet de Producție / Distribuție (`npx zeus build`)

Dacă dorești doar să generezi fișierul pachet (`.zab`) fără să pornești serverul de preview:

```bash
cd /Users/mihai/Source/Daily/ZeppOS
npm run build
# sau: npx zeus build
```

Pachetul rezultat va fi salvat în folderul `ZeppOS/dist/`:
```text
ZeppOS/dist/20001-DayOne_Orbit-1.0.0-[Timestamp].zab
```
Acest pachet conține deja fișierele compilate pentru toate platformele configurate în `app.json`:
- `r` / 480 (Round - Amazfit Balance)
- `s` / 390 (Square - Amazfit Active 2)
- `b` / 194 (Band)

---

## 6. Ghid de Depanare (Troubleshooting)

| Problemă / Simptom | Cauză Probabilă | Soluție |
| :--- | :--- | :--- |
| `Download failed : error code null` sau `Device does not support` | S-a selectat dispozitivul din secțiunea "Suggested" din CLI. | Oprește comanda (`Ctrl+C`), rulează din nou `npx zeus preview`, derulează în jos în catalogul complet și alege manual modelul exact. |
| Scanarea QR rămâne blocată / `Network Timeout` | Mac-ul și telefonul nu sunt pe aceeași rețea locală sau există VPN/Firewall activ. | Dezactivează VPN-ul pe Mac și telefon. Dacă ești pe o rețea Wi-Fi cu izolare clienți, activează Personal Hotspot pe telefon și conectează Mac-ul la el. |
| Eroare de compilare QJSC / Hang infinit | S-a folosit sintaxă ES2020 (Optional Chaining `?.` sau Nullish Coalescing `??`). | QuickJS-ul din Zeus CLI nu suportă `?.`. Folosește verificări sigure tradiționale: `if (a && a.b)`. |
| Iconița aplicației apare neagră sau lipsește | Imaginea PNG nu are canal Alpha pe 32 de biți (RGBA). | Salvează iconițele în `assets/common.r/icon.png` (248x248) și `assets/common.s/icon.png` (124x124) strict ca PNG 32-bit RGBA. |
| Port ocupat (`Port 8080 already in use`) | Un alt proces local folosește portul 8080. | Specifică alt port: `npx zeus preview --port 8085`. |
| Datele nu se sincronizează pe ceas | Bluetooth-ul dintre telefon și ceas este deconectat sau aplicația Zepp este oprită forțat pe telefon. | Asigură-te că aplicația Zepp rulează pe telefon în fundal și că ceasul indică conexiune activă. |
| Eroare `EPERM: operation not permitted, open '~/.zepp/.zeus'` | Lipsă drepturi de scriere în folderul utilizatorului `~/.zepp`. | Asigură-te că terminalul are permisiuni normale de citire/scriere în home directory (`mkdir -p ~/.zepp`). |
