# Windows 11 Desktop Widgets Architecture (2026)

**Data:** 2–3 Noiembrie 2026  
**Componente:** `WinUI/Daily.WinUI/DesktopWidgets/`, `WinUI/Daily.WinUI/DesktopWidgets/Views/`, `WinUI/Daily.WinUI/DesktopWidgets/DesktopWidgetManager.cs`, `WinUI/Daily.WinUI/DesktopWidgets/DesktopWidgetWindow.xaml.cs`, `WinUI/Daily.WinUI/Services/SettingsService.cs`, `WinUI/Daily.WinUI/Controls/TaskbarGlanceFlyoutControl.xaml`, `WinUI/Daily.WinUI/MainWindow.xaml`, `WinUI/Daily.WinUI/App.xaml.cs`  
**Platformă:** Windows 11 (ARM64 & x64), WinUI 3 (Windows App SDK 2.2 pe .NET 10)  
**Arhitectură:** Native Win32 Desktop Wallpaper Layering (`WS_EX_TOOLWINDOW`, `WS_EX_NOACTIVATE`, `MA_NOACTIVATE`, `DWMWCP_ROUND`, `SWP_HIDEWINDOW` stripping, DPI physical scaling), Windows 11 Desktop Acrylic & Mica Alt, Named Pipe IPC, System Tray Management & Taskbar Companion Header Integration  

---

## 1. Context & Obiectiv

Sistemul de operare macOS (Sonoma și Sequoia) permite utilizatorilor să plaseze widgeturi interactive direct pe desktop (pe stratul de fundal/wallpaper), beneficiind de transparență Liquid Glass, acțiuni interactive și actualizări în timp real fără a interfera cu ferestrele de lucru ale aplicațiilor.

Pe Windows 11, sistemul oficial **Windows Widgets Board** (`Win + W` / `Microsoft.Windows.Widgets.Providers`) prezintă limitări severe:
1. Nu permite plasarea widgeturilor direct pe desktop-ul utilizatorului (sunt restricționate exclusiv la un sertar lateral de tip flyout).
2. Forțează utilizarea unui format JSON primitiv de tip **Adaptive Cards**, lipsit de capabilități avansate de desenare vectorială, animații fluide, controale WinUI 3 personalizate sau layout dinamic.

Pentru a oferi o experiență de **paritate 1:1 cu macOS**, am proiectat și implementat un subsistem nativ de **Desktop Widgets pentru Windows 11** bazat pe ferestre WinUI 3 flotante, ancorate la nivelul wallpaper-ului prin P/Invoke Win32 avansat, cu suport complet pentru Mica Alt / Desktop Acrylic, snapping magnetic la grid de 16px, meniu contextual bogat, persistență JSON și control complet din System Tray, Taskbar Companion Flyout și IPC Named Pipe.

---

## 2. Arhitectura Tehnică & Win32 Layering

### A. Corecția Critică: Eliminarea `HWND_BOTTOM` și Fixarea pe Wallpaper
În implementările naive pe Windows, încercarea de a trimite ferestrele la `HWND_BOTTOM ((IntPtr)1)` le împinge în spatele procesului `Progman` / ferestrelor `WorkerW` (stratul DWM care desenează wallpaper-ul Windows 11), făcându-le complet invizibile sub imaginea de fundal a desktop-ului.

Soluția arhitecturală robustă implementată în `DesktopWidgetWindow`:
1. **`WS_EX_TOOLWINDOW`**: Ascunde fereastra widget-ului din `Alt + Tab`, din Task View (`Win + Tab`) și din Windows Taskbar.
2. **`WS_EX_NOACTIVATE`**: Garantează că la afișare sau interacțiune, widgetul nu fură focusul de tastatură de la aplicația în care lucrează utilizatorul (Word, browser, IDE).
3. **`DWMWA_WINDOW_CORNER_PREFERENCE = DWMWCP_ROUND`**: Activează rotunjirea nativă standard a colțurilor Windows 11 prin Desktop Window Manager (DWM).
4. **Subclasare via `SetWindowSubclass`**:
   - **`WM_MOUSEACTIVATE`**: Răspunde cu `MA_NOACTIVATE (3)`, permițând clicuri interactive pe butoanele din widget fără a fura focusul ferestrei active.
   - **`WM_SYSCOMMAND` `SC_MINIMIZE`**: Suprimat complet pentru a împiedica minimizarea accidentală a widgeturilor.
   - **`WM_WINDOWPOSCHANGING`**: Interceptează comenzile Windows Shell (`Win + D` sau "Show Desktop") care trimit ferestrele la coordonate negative (`pos.x <= -10000`) sau injectează flag-ul `SWP_HIDEWINDOW (0x0080)`. Fereastra curăță flag-ul de ascundere și aplică `SWP_SHOWWINDOW (0x0040)`, menținând widgeturile permanent vizibile pe desktop.

### B. Standard de Dimensiuni & Scalare DPI în Pixeli Fizici
Procesele WinUI 3 Windows App SDK rulează în regim Per-Monitor V2 DPI aware. Apelurile Win32 `SystemParametersInfo(SPI_GETWORKAREA)` și WinUI 3 `AppWindow.MoveAndResize` operează în **pixeli fizici**, nu puncte logice (DIPs).

`DesktopWidgetManager` calculează factorul de scalare nativ via `GetDpiForSystem()`:
$$\text{scale} = \frac{\text{DPI}}{96.0}$$
* **Small**: `(int)(170 * scale)` × `(int)(170 * scale)`
* **Medium**: `(int)(360 * scale)` × `(int)(170 * scale)`
* **Large**: `(int)(360 * scale)` × `(int)(360 * scale)`

Coordonatele implicite sunt plasate precis pe marginea dreaptă a ecranului:
$$\text{rightX} = \text{workArea.X} + \text{workArea.Width} - \text{mediumWidth} - \text{padding}$$

### C. Drag & Drop cu Aliniere Magnetică (Snap-to-Grid) & Clamping
* Header-ul fiecărui widget conține un `DragHandle` subtil. La deblocare, utilizatorul poate trage widget-ul oriunde pe ecran.
* La eliberarea cursorului (`PointerReleased`), poziția este aliniată magnetic la un grid de **16px** și constrânsă automat (`ClampModelToWorkArea`) în interiorul `DisplayArea.Primary.WorkArea` pentru a preveni ieșirea widgeturilor în afara ecranului.
* Noile coordonate sunt serializate automat în JSON (`AppSettings.DesktopWidgetsConfigJson`).

---

## 3. Suita Completă de 9 Widgeturi Desktop

Toate widgeturile consumă date în mod **offline-first** din serviciile locale existente (`DailyCore`, `HabitsService`, `SmartLedgerStore`, `HealthHubService`, `AstronomyService`, `WeatherClient`), oferind viteză instantanee de afișare (< 1ms).

| Widget | Mărimi suportate | Tehnologie & Interacțiuni |
|---|---|---|
| **CombinedWidget** | Medium, Large | Dashboard executiv complet: combină Vremea (icoană + temperatură), Hidratarea (progres ml / țintă), Fumatul (stare fumat), SmartLedger (Net Worth în Lei) și Recuperarea Somnului. |
| **BubblesWidget** | Small, Medium, Large | Progres hidric cu inel circular de progres, volum curent / țintă ml, defalcare pe tipuri de băuturi (Apă, Cafea, Ceai) și butoane interactive rapide: `+150ml`, `+250ml`, `+500ml`. |
| **SmokesWidget** | Small, Medium, Large | Plămâni vectoriali anatomici (`LungsControl`) cu umplere dinamică a sănătății, numărător de țigări clasice și încălzite, badge pentru timpul scurs fără fumat și buton interactiv `+ 1 Smoke`. |
| **MoneyWidget** | Small, Medium, Large | SmartLedger Net Worth în Lei și echivalent EUR (~€), balanțe Card vs Cash și butoane interactive de ajustare rapidă: `+100 Card`, `-100 Card`, `+100 Cash`. |
| **SleepWidget** | Small, Medium, Large | Inel de scor recuperare somn, durată totală (`Xh Ym`), timeline orar culcat/trezit, hipnogramă proporțională pe stadii (Deep, REM, Light, Awake), puls de repaus (RHR) și HRV balance. |
| **StressWidget** | Small, Medium, Large | Scor de stres autonom /100, status vegetativ, puls curent, variație HRV față de baseline și buton interactiv pentru sesiune de respirație ghidată de 1 minut. |
| **CosmosWidget** | Small, Medium | Scor Stargazing /100, glyph și procent de iluminare pentru faza lunară, listă planete vizibile cu ochiul liber și predicție pentru următoarea trecere ISS. |
| **TagdosWidget** | Small, Medium, Large | Stream-uri active, număr taskuri deschise, stream focus și listă de taskuri prioritare cu indicatori colorați de stare. |
| **WeatherWidget** | Small, Medium, Large | Temperatură curentă, descriere și glyph condiție meteo, locație, temperatură resimțită, min/max zilnic, prognoză orară pe 5 ore (timeline) și senzori de umiditate și vânt. |

---

## 4. Gestiune, Meniu Contextual & System Tray

### A. Meniu Contextual pe Fiecare Widget (Right-Click Header)
Utilizatorul poate da clic dreapta direct pe bara superioară / `DragHandle` a oricărui widget de pe desktop:
* **Widget Size**: Comutare instantanee între Small, Medium și Large.
* **Glass Backdrop**: Comutare între **Desktop Acrylic** (sticlă translucidă blurată) și **Mica Alt** (nuanță profundă acordată la tema Windows 11).
* **Lock Position**: Blochează widget-ul pentru a ascunde drag handle-ul și a preveni deplasările accidentale.
* **Refresh Data**: Reîmprospătare forțată din baza de date SQLite locală.
* **Remove Widget**: Închide widget-ul și îl șterge din persistența JSON.

### B. Integrare în Meniul System Tray (`MainWindow.xaml`)
Iconița din System Tray (DayOne) oferă meniul contextual accesibil la **clic dreapta**:
* `Show DayOne` (restaurează fereastra principală).
* Submeniu **Desktop Widgets**:
  - `Show / Hide Desktop Widgets` (comută vizibilitatea tuturor widgeturilor deodată).
  - `Lock / Unlock Positions` (blochează/deblochează toate widgeturile).
  - `Refresh All Widgets` (forțează recalcularea metricilor).
  - `Reset to Default Layout` (recreează aranjamentul din fabrică: Combined, Bubbles, Smokes, Money).
  - `Add Widget` (permite adăugarea oricărui widget din suita celor 9).
* `Exit`.

### C. Integrare în Header-ul Taskbar Companion Flyout ("DayOne Glance")
La **clic stânga** pe iconița din System Tray, se deschide flyout-ul compact "DayOne Glance". În bara de sus a flyout-ului a fost integrat butonul dedicat **Desktop Widgets**, permițând accesul la aceleași comenzi de gestiune rapidă.

### D. Ciclu de Viață & Închidere la Tavă (`CloseToTray: true`)
Setarea `CloseToTray` a fost configurată implicit pe `true`. Când utilizatorul apasă butonul de închidere `X` al ferestrei principale, aplicația rămâne activă în System Tray, iar toate widgeturile desktop rămân active și interactive pe desktop wallpaper.

---

## 5. Rafinări Avansate, Paritate cu MacOS & Click-to-Hub Navigation

În etapa de finisare și paritate funcțională completă cu MacOS și Glance, au fost implementate următoarele îmbunătățiri majore:

### A. Transparență Configurăbilă (Glass Transparency)
* Fiecărui widget i s-a adăugat submeniul **Transparency** în meniul contextual (clic dreapta pe header):
  - `100% (Solid Glass)` ($\alpha = 1.0$)
  - `85% (Subtle Glass)` ($\alpha = 0.85$)
  - `70% (Balanced Glass)` ($\alpha = 0.70$)
  - `50% (Translucent)` ($\alpha = 0.50$)
  - `30% (Clear Glass)` ($\alpha = 0.30$)
* Nivelul de transparență este modulat prin canalul Alpha al fundalului cardului (`CardBorder.Background`), asigurând că textul, valorile numerice și butoanele rămân 100% vizibile, contrastante și lizibile pe fundalul de Desktop Acrylic blurat.

### B. Widget-ul Hero / Combined Brief
* A fost eliminat rândul de footer ("All systems nominal · Offline cache synced"), eliberând spațiu vertical prețios pentru matricea celor 4 carduri metrice (Vreme, Hidratare, Fumat, SmartLedger).
* Iconițele au fost corectate: picătură de apă `&#xEB42;` pentru Hidratare și glif Tabler `&#xEC2C;` pentru Fumat.
* Clic pe widget activează direct fereastra principală a aplicației (`ShowAndActivate()`).

### C. Widget-ul de Hidratare (Bubbles) & Corecție în Glance Flyout
* În ambele dimensiuni (Small și Medium), widget-ul oferă cele 3 butoane standard:
  - **Cafea 100 ml** (Chihlimbar `#F59E0B`, icon `&#xE706;`)
  - **Apă Mică 150 ml** (Cian `#00E5FF`, icon `&#xEB42;`)
  - **Apă Mare 300 ml** (Cian `#00E5FF`, icon `&#xEB42;`)
* În Taskbar Glance Flyout (`TaskbarGlanceFlyoutControl.xaml`), a fost remediată inversarea butoanelor, aliniindu-se cu specificațiile din aplicația principală (Coloana 0 = Cafea 100ml, Coloana 1 = Apă 150ml, Coloana 2 = Apă 300ml).
* Clic pe cardul de hidratare navighează direct la **Habits Hub (Tab 5)**.

### D. Widget-ul Smokes (Plămâni & Tutun)
* Iconițe dedicate de tutun și țigaretă (`&#xEC2C;` și `&#xECC4;`).
* Butoane rapide conforme cu Glance: **`Cig`** (+1 Țigară) și **`Heat`** (+1 Tutun încălzit).
* Afișare metrică dinamică: `0 of 40 smokes` (preluat din `ISettingsService.Settings.SmokesBaselineDaily`, cu fallback 40).
* Corecție UTC pentru calculul timpului scurs de la ultima țigară (`DateTime.UtcNow - lastLog.LoggedAt.ToUniversalTime()`), eliminând decalajul de fus orar.
* Clic pe card navighează direct la **Habits Hub (Tab 5)**.

### E. Widget-ul Finances & SmartLedger
* Parsare directă a balanțelor `Card` și `Cash` din secțiunea `**Incoming**` a textului SmartLedger (`SmartLedgerParser.Parse`), la paritate 1:1 cu logica din `MoneyWidget.swift` și `WidgetDataCoordinator.swift` pe MacOS.
* Ajustare interactivă directă pe textul SmartLedger prin `SmartLedgerParser.AdjustValue`.
* Clic pe card navighează direct la **Finances Hub (Tab 2)**.

### F. Widget-ul Weather & TagDos
* **Weather**: Afișează denumirea exactă a locației auto-detectate (`weather.LocationName` din OpenWeatherMap API), iar clic pe card navighează la **Weather Hub (Tab 6)**.
* **TagDos**: Conectat la serviciul real `ITagdosService` (stream-uri active, taskuri necompletate, titlul stream-ului de focus), eliminând datele mock. Clic pe card navighează la **TagDos Hub (Tab 3)**.

### G. Arhitectură Click-to-Hub Navigation
* Fiecare widget suportă navigare directă prin atingere / clic pe card (`CardBorder_Tapped`), activând fereastra principală și deschizând tab-ul dedicat.
* Apăsarea pe butoanele interactive din interiorul widgeturilor (`ButtonBase`) este exclusă din evenimentul de navigare, permițând logarea rapidă fără părăsirea desktop-ului.

### H. Remediere Meniu System Tray (Add Widget)
* Metodele `TrayAdd*` din `MainWindow.xaml.cs` au fost encapsulate în `DispatcherQueue.TryEnqueue` și consolidate în `DesktopWidgetManager.AddWidget` pentru garantarea execuției pe thread-ul UI WinUI 3 și activarea automată a widgeturilor.

---

## 6. Verificare Live & Confirmare Vizuală pe Windows 11 VM

Toate componentele au fost compilate și verificate nativ pe mașina virtuală Parallels **Windows 11 (ARM64)**:
1. **Compilare Nativă**: `dotnet build WinUI/Daily.WinUI/Daily.WinUI.csproj -c Debug -p:Platform=ARM64` s-a finalizat cu **`0 Error(s)`** și `0 Critical Warnings`.
2. **Execuție & Stabilitate**: Binarul ARM64 actualizat a fost copiat și integrat în `bin\ARM64\Debug\net10.0-windows10.0.26100.0\win-arm64\Daily.WinUI.exe`.
