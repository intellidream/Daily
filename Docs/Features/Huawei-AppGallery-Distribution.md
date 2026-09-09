# Huawei Developers & AppGallery Connect Distribution Guide (DayOne Orbit)

Acest document descrie fluxul complet de configurare, verificare cont dezvoltator, semnare, compilare și distribuție a aplicației **DayOne Orbit** pentru ceasurile Huawei (inclusiv Huawei Watch GT 5 Pro) prin intermediul **AppGallery Connect** și **DevEco Studio**.

---

## 1. Identificatori Aplicație (App ID & Bundle)

| Proprietate | Valoare |
| :--- | :--- |
| **App Name** | `DayOne Orbit` |
| **App Package / Bundle Name** | `com.intellidream.daily.orbit` |
| **Device Target** | `wearable` |
| **Category** | `Health & Fitness` |
| **Fișier Configurare Proiect** | `HarmonyOS/DailyWear/AppScope/app.json5` |

---

## 2. Verificarea Identității Contului Huawei Developer (Identity Verification)

Pentru a putea genera certificate de semnare (inclusiv semnături automate de debug) sau a încărca pachete în AppGallery Connect, Huawei impune verificarea identității reale (**Real-Name Authentication**).

### Tipul de cont recomandat:
* Alege **Individual Developer** (Persoană Fizică). *Nu alege Enterprise*, care solicită certificat fiscal (CUI), extras de cont comercial etc.

### Probleme cunoscute pe portalul Huawei și deblocarea lor:
Portalul de verificare Huawei Developer prezintă frecvent bug-uri de randare și funcționare a formularelor:
1. **Ad-Blockere și Extensii de Privacy:**
   * Scripturile dinamice și formularele de încărcare sunt servite prin CDN-uri Huawei (`hwcdn.net`, `dbankcdn.com`, `vmall.com`).
   * Extensii precum *uBlock Origin*, *AdGuard*, *Brave Shields* sau filtrele native de tracking blochează aceste apeluri, făcând ca dropdown-urile (țară, tip document) să fie goale sau butoanele să nu reacționeze.
2. **Traducerea automată a browserului (Auto-Translate):**
   * Dacă browserul (Chrome/Safari) încearcă să traducă automat pagina în română, framework-ul frontend (Vue/React) crapă, corupând valorile trimise sau blocând formularul.
3. **Incompatibilitate Safari pe macOS:**
   * Safari blochează din oficiu cookie-urile third-party și apelurile cross-domain între `developer.huawei.com` și `id5.cloud.huawei.com`.
4. **Diacritice românești:**
   * Validarea backend a Huawei respinge sau corupe caracterele cu diacritice (`ă, î, ș, ț, â`).

### Soluția pas cu pas pentru completarea formularului:
* **Browser:** Deschide **Google Chrome** sau **Microsoft Edge** (evită Safari).
* **Mod Incognito:** Deschide o fereastră Incognito (`Cmd + Shift + N`) pentru a suspenda toate extensiile și ad-blockerele.
* **Limbă:** Asigură-te că limba din colțul dreapta-sus al paginii este **English** și dezactivează traducerea automată.
* **Date text:** Completează numele, prenumele și adresa **strict fără diacritice** (ex: `Strada Timisoara`, `Bucuresti`).
* **Document:** Selectează **ID Card** (Buletin) sau **Passport** (Pașaport) și încarcă o fotografie clară (format `.jpg` sau `.png`, sub 5 MB, fără reflexii de lumină).
* **Aprobare:** Validarea pentru dezvoltatori individuali se realizează de obicei în 1 – 24 de ore lucrătoare.

---

## 3. Navigarea în AppGallery Connect

După crearea App ID-ului, AppGallery Connect te poate plasa în ecranul de **My Projects** (destinat serviciilor cloud proprietare Huawei HMS Core):
* **Important:** DayOne Orbit folosește direct backend-ul Supabase prin conexiuni REST/HTTPS (`http.createHttp()`). Prin urmare, **nu sunt necesare servicii HMS Core suplimentare** (Push Kit, Cloud DB, Auth etc.) în secțiunea de proiecte.
* Pentru încărcarea și distribuția pachetului, zona corectă este **My Apps (Aplicațiile mele)**.

---

## 4. Semnarea Pachetului în DevEco Studio (Signing Configs)

Ceasurile fizice și platforma AppGallery acceptă doar pachete semnate cu certificatul de dezvoltator Huawei asociat contului tău.

### Pași pentru semnare automată:
1. Deschide proiectul `HarmonyOS/DailyWear` în **DevEco Studio**.
2. Asigură-te că ești autentificat în DevEco Studio cu contul tău Huawei ID (colțul din dreapta sus sau meniul *Help* -> *Login*).
3. Mergi la **File** $\rightarrow$ **Project Structure...**
4. În panoul din stânga, selectează **Project** $\rightarrow$ tab-ul **Signing Configs**.
5. Bifează căsuța **Automatically generate signature**:
   * DevEco Studio va interoga AppGallery Connect, va recunoaște identificatorul `com.intellidream.daily.orbit` și va genera certificatele locale de debug/release.
6. Apasă **Apply** și **OK**.

---

## 5. Compilarea Pachetului (.hap / .app)

1. În **DevEco Studio**, mergi în meniul de sus la:
   * **Build** $\rightarrow$ **Build Hap(s)/APP(s)** $\rightarrow$ **Build Hap(s)** (sau **Build App(s)**).
2. La finalizarea compilării, pachetul semnat se va genera în calea:
   ```
   HarmonyOS/DailyWear/entry/build/default/outputs/default/entry-default-signed.hap
   ```

---

## 6. Încărcarea în AppGallery Connect (Open Testing)

1. Deschide [AppGallery Connect](https://developer.huawei.com/consumer/en/service/josp/agc/index.html).
2. Mergi la **My Apps (Aplicațiile mele)** $\rightarrow$ selectează **DayOne Orbit**.
3. În meniul din stânga, accesează **Distribute** $\rightarrow$ **Version information** (sau **Open Testing**):
4. În secțiunea **Software version / App packages**:
   * Apasă pe butonul **Manage software packages** $\rightarrow$ **Upload**.
   * Alege fișierul `entry-default-signed.hap` de pe calculator.
   * Selectează scopul: **Only testing** (pentru teste interne) sau **Testing and official release**.
5. La secțiunea de testeri (*Test Users*):
   * Adaugă adresa de email a contului tău Huawei ID (același cu care ești logat în aplicația **Huawei Health** de pe telefon).
6. Salvează și activează testarea.

---

## 7. Instalarea pe Huawei Watch GT 5 Pro

1. Pe telefonul tău mobil (asociat cu ceasul), deschide aplicația **Huawei Health** (asigură-te că ești autentificat cu contul invitat la testare).
2. Mergi la tab-ul **Dispozitive (Devices)** $\rightarrow$ selectează **Huawei Watch GT 5 Pro**.
3. Apasă pe secțiunea **AppGallery** (sau *Aplicații*).
4. Aplicația **DayOne Orbit** va apărea marcată ca disponibilă pentru testare.
5. Apasă **Instalare**: pachetul se va descărca pe telefon și se va transmite automat prin Bluetooth către ceas.
