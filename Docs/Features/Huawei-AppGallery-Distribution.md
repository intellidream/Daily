# Huawei Developers & AppGallery Connect Distribution Guide (DayOne Orbit)

Acest document descrie fluxul complet de configurare, semnare, compilare și distribuție a aplicației **DayOne Orbit** pentru ceasurile Huawei (inclusiv Huawei Watch GT 5 Pro) prin intermediul **AppGallery Connect** și **DevEco Studio**.

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

## 2. Navigarea în AppGallery Connect

După crearea unui App ID, AppGallery Connect te poate plasa în ecranul de **My Projects** (destinat serviciilor cloud proprietare Huawei HMS Core):
* **Important:** DayOne Orbit folosește direct backend-ul Supabase prin conexiuni REST/HTTPS (`http.createHttp()`). Prin urmare, **nu sunt necesare servicii HMS Core suplimentare** (Push Kit, Cloud DB, Auth etc.) în secțiunea de proiecte.
* Pentru încărcarea și distribuția pachetului, zona corectă este **My Apps (Aplicațiile mele)**.

---

## 3. Semnarea Pachetului în DevEco Studio (Signing Configs)

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

## 4. Compilarea Pachetului (.hap / .app)

1. În **DevEco Studio**, mergi în meniul de sus la:
   * **Build** $\rightarrow$ **Build Hap(s)/APP(s)** $\rightarrow$ **Build Hap(s)** (sau **Build App(s)**).
2. La finalizarea compilării, pachetul semnat se va genera în calea:
   ```
   HarmonyOS/DailyWear/entry/build/default/outputs/default/entry-default-signed.hap
   ```

---

## 5. Încărcarea în AppGallery Connect (Open Testing)

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

## 6. Instalarea pe Huawei Watch GT 5 Pro

1. Pe telefonul tău mobil (asociat cu ceasul), deschide aplicația **Huawei Health** (asigură-te că ești autentificat cu contul invitat la testare).
2. Mergi la tab-ul **Dispozitive (Devices)** $\rightarrow$ selectează **Huawei Watch GT 5 Pro**.
3. Apasă pe secțiunea **AppGallery** (sau *Aplicații*).
4. Aplicația **DayOne Orbit** va apărea marcată ca disponibilă pentru testare.
5. Apasă **Instalare**: pachetul se va descărca pe telefon și se va transmite automat prin Bluetooth către ceas.
