# WinUI 3 Desktop Widgets & System Tray Glance Live Polish (2026)

**Data:** 4 Noiembrie 2026  
**Componente:**
- **Taskbar Glance & Live Health Sync**: `WinUI/Daily.WinUI/Controls/TaskbarGlanceFlyoutControl.xaml.cs`, `WinUI/Daily.WinUI/TaskbarCompanionWindow.cs`, `WinUI/Daily.WinUI/Services/HealthHubService.cs`
- **Desktop Widgets 20pt Per-Pixel Liquid Glass**: `WinUI/Daily.WinUI/DesktopWidgets/TransparentSystemBackdrop.cs`, `WinUI/Daily.WinUI/DesktopWidgets/DesktopWidgetWindow.xaml`, `WinUI/Daily.WinUI/DesktopWidgets/DesktopWidgetWindow.xaml.cs`
- **System Tray Native Win32 Menu Commands**: `WinUI/Daily.WinUI/MainWindow.xaml`, `WinUI/Daily.WinUI/MainWindow.xaml.cs`, `WinUI/Daily.WinUI/DesktopWidgets/DesktopWidgetManager.cs`
- **Single-Instance Stale Takeover & Settings UI**: `WinUI/Daily.WinUI/App.xaml.cs`, `WinUI/Daily.WinUI/Package.appxmanifest`, `WinUI/Daily.WinUI/Views/AppearanceSettingsPage.xaml`, `WinUI/Daily.WinUI/Views/AppearanceSettingsPage.xaml.cs`  
**Platformă:** Windows 11 (`net10.0-windows10.0.26100.0`, ARM64 & x64)

---

## 1. Context & Diagnostic Tehnic

În urma testării pe Windows 11 (atât pe mașina virtuală Parallels ARM64 la 200% DPI, cât și pe o mașină nativă Windows 11), au fost identificate și rezolvate 4 probleme distincte în aplicația WinUI 3:

### 1.1. Ritmul cardiac din System Tray Glance nu se mai actualiza după lansare
- **Cauze rădăcină**:
  1. `TaskbarCompanionWindow` instanțiază `TaskbarGlanceFlyoutControl` o singură dată și îl ascunde/afișează prin `AppWindow.Hide()` / `AppWindow.Show()`. Evenimentul `Loaded` rula o singură dată la pornirea procesului.
  2. `TaskbarGlanceFlyoutControl` nu era abonat la `_healthHubService.OnDailySummaryChanged` sau `IRefreshService` și apela `GetDailySummaryAsync(DateTime.Today, forceRefresh: false)`, citind exclusiv cache-ul din memorie fără a declanșa pull remote la redeschidere.
  3. În `HealthHubService.cs`, metoda `DispatchToUI` folosea `DispatcherQueue.GetForCurrentThread()` (care este întotdeauna `null` pe thread-uri de background / WebSocket), iar `PullDeltasAsync()` reîncărca SQLite local peste cache-ul din memorie înainte ca fetch-ul remote să se termine.

### 1.2. Colțurile widget-urilor de pe desktop-ul Windows 11 erau aproape drepte (4pt)
- **Cauze rădăcină**:
  1. DWM-ul nativ din Windows 11 (`DWMWCP_ROUND`) aplică o rază fixă de 8 pixeli fizici = **4pt la 200% DPI**, împreună cu un contur dreptunghiular de 1px (`DWMWA_BORDER_COLOR`), contrastând puternic cu cardurile interioare (`10pt`) și cu widget-urile din aplicația WinUI / macOS (`20pt`).
  2. `OverlappedPresenter` + `ExtendsContentIntoTitleBar = true` lăsau stilul Win32 `WS_DLGFRAME | WS_SYSMENU` (`0x00480000`) pe `HWND`, desenând un chenar alb de 1px, iar bitmap-ul GDI al clasei `WinUIDesktopWin32WindowClass` era inițializat cu `WHITE_BRUSH` (`0x00FFFFFF`).

### 1.3. Meniul contextual „Desktop Widgets” din System Tray nu executa nicio acțiune
- **Cauze rădăcină**:
  1. Biblioteca `H.NotifyIcon.WinUI` (`2.4.1`) rulează implicit în `ContextMenuMode.PopupMenu` (meniu nativ Win32 `HMENU` prin `TrackPopupMenuEx`). În acest mod, `H.NotifyIcon` **ignoră complet atributele XAML `Click="..."`** de pe `MenuFlyoutItem` (deoarece evenimentul WinRT `Click` nu poate fi invocat din exterior) și execută **exclusiv proprietatea `MenuFlyoutItem.Command` (`ICommand`)**.
  2. În plus, `DesktopWidgetManager.ShowAll()` itera doar peste `_activeWidgets` fără a apela `LoadWidgets()` atunci când lista activă era goală.

### 1.4. Absența widget-urilor, meniurilor și setărilor pe a doua mașină Windows nativă
- **Cauze rădăcină**:
  1. **Capcana Single-Instance Mutex (`DailyWinUI_SingleInstance_Mutex`)**: Deoarece opțiunea `CloseToTray` este activă implicit, o instanță veche a `Daily.WinUI.exe` rămâne rezidentă invizibil în System Tray. La compilarea și lansarea noului `.exe`, `App.Main()` detecta `!createdNew`, trimitea mesajul `"show"` prin `DailyWinUI_ProtocolPipe` către **vechiul proces din RAM** (compilat înainte de adăugarea widget-urilor) și se închidea imediat.
  2. **Versiune MSIX neschimbată & căi de build divergente**: `Package.appxmanifest` avea `Version="1.0.0.0"`, iar `dotnet build` fără `-p:Platform=x64` scrie în `bin\Debug\...` în timp ce Visual Studio / `-p:Platform=x64` scrie în `bin\x64\Debug\...`.
  3. **Lipsa secțiunii UI în Settings**: `AppearanceSettingsPage.xaml` nu conținea cardul de configurare pentru Desktop Widgets.

---

## 2. Soluții Tehnice Implementate

### A. Live Heart Rate & Telemetry Refresh în Glance (`TaskbarGlanceFlyoutControl.xaml.cs`, `HealthHubService.cs`)
- `TaskbarCompanionWindow.ShowNearTray()` și `Hide()` notifică acum explicit `_glanceControl.OnFlyoutOpened()` și `OnFlyoutClosed()`.
- La fiecare deschidere a Glance-ului:
  1. Se afișează instantaneu (<5ms) datele din cache-ul local.
  2. Dacă au trecut >20s de la ultimul sync remote, se lansează asincron `GetDailySummaryAsync(DateTime.Today, forceRefresh: true)` și se actualizează UI-ul pe `DispatcherQueue`.
  3. Un `DispatcherTimer` de 45s menține telemetria vie cât timp flyout-ul rămâne deschis.
- Controlul s-a abonat la `_healthHubService.OnDailySummaryChanged` și `IRefreshService` (`RefreshRequested`, `HealthRefreshRequested`, `DetailRefreshRequested`), folosind aceeași ierarhie în 3 trepte ca `HealthWidgetControl`.
- În `HealthHubService`, `DispatchToUI` face fallback pe `App.Current.MainWindow.DispatcherQueue`, `PullDeltasAsync()` așteaptă `RefreshSummaryFromRemoteAsync(DateTime.Today)`, iar un timer intern de 3 minute menține vitalele sincronizate când aplicația stă în System Tray.

### B. Colțuri Rotunjite Reale de 20pt prin DirectComposition Per-Pixel Alpha (`TransparentSystemBackdrop.cs`, `DesktopWidgetWindow`)
- S-a creat `TransparentSystemBackdrop` (derivând din `Microsoft.UI.Xaml.Media.SystemBackdrop`), care atașează un `CompositionColorBrush` complet transparent (`Color.FromArgb(0, 0, 0, 0)`) pe `ICompositionSupportsSystemBackdrop` fără a folosi `WS_EX_LAYERED` (evitând crash-urile SwapChain) și fără `DesktopAcrylicController` (evitând ghosting-ul DWM).
- În `DesktopWidgetWindow.ConfigureTransparentWindowChrome()`:
  - Se elimină flag-urile `WS_CAPTION | WS_THICKFRAME | WS_BORDER | WS_DLGFRAME | WS_SYSMENU` și se aplică `WS_POPUP` + `SWP_FRAMECHANGED`.
  - Se setează `DWMWCP_DONOTROUND` și `DWMWA_BORDER_COLOR = DWMWA_COLOR_NONE`.
  - Se extinde cadrul DWM (`MARGINS(-1, -1, -1, -1)`) și se activează per-pixel alpha prin `DwmEnableBlurBehindWindow` (`Pack = 1`) cu o regiune off-screen `CreateRectRgn(-2, -2, -1, -1)`.
  - În `WM_ERASEBKGND` și `ClearGdiSurfaceToTransparentBlack()`, suprafața GDI este curățată cu `BLACK_BRUSH` (`0x00000000` în premultiplied alpha = 100% transparent).
- În `DesktopWidgetWindow.xaml`, un singur `<Border x:Name="RootCard" CornerRadius="20" BorderThickness="1">` definește silueta Liquid Glass cu rază concentrică față de cardurile interioare de `10pt`.

### C. Meniu System Tray bazat pe `ICommand` (`MainWindow.xaml`, `MainWindow.xaml.cs`, `DesktopWidgetManager.cs`)
- `TrayContextMenu` este definit în resursele `TrayIcon`, toate cele 15 opțiuni (`Show DayOne`, `Show / Hide`, `Lock / Unlock`, `Refresh All`, `Reset`, toate cele 9 tipuri din `Add Widget`, `Exit`) primesc instanțe `RelayCommand` marshalate prin `DispatcherQueue.TryEnqueue`, iar apoi `TrayIcon.ContextFlyout = TrayContextMenu` este atribuit o singură dată.
- `DesktopWidgetManager` marshalează toate operațiile pe UI thread, persistă `DesktopWidgetsEnabled`, apelează `LoadWidgets()` automat în `ShowAll()` dacă nu există ferestre active și expune evenimentul `StateChanged`.

### D. Auto-Înlocuire Instanță Veche & Card Desktop Widgets în Settings (`App.xaml.cs`, `AppearanceSettingsPage.xaml`)
- Când `Daily.WinUI.exe` este lansat direct (`message == "show"`) și detectează în `DailyWinUI_SingleInstance_Mutex` un proces existent cu alt path sau cu un timestamp `LastWriteTimeUtc` mai vechi, trimite `"exit"` prin `DailyWinUI_ProtocolPipe`, așteaptă închiderea procesului vechi (cu fallback `Kill()`), preia mutex-ul și pornește noua versiune.
- La finalul `InitializeAsync()`, `DesktopWidgetManager.Instance.RefreshAllWidgets()` reîmprospătează toate widget-urile imediat ce SQLite, Habits, Health și sesiunea Supabase sunt hidratate.
- `Package.appxmanifest` a fost incrementat la `Version="1.1.0.0"`, iar în `Settings -> Appearance` a fost adăugat cardul complet **Desktop Widgets** (toggle Show/Hide, toggle Lock Positions, meniu `Add Widget`, `Refresh All`, `Reset Default Layout`).

---

## 3. Arhitectură Comparativă: De ce pe macOS widget-urile rămân pe ecran când aplicația este oprită, iar pe Windows 11 nu?

| Dimensiune | macOS 15+ (`WidgetKit`) | Windows 11 (`WinUI 3` / `Widgets Board`) |
| :--- | :--- | :--- |
| **Procesul care randează widget-ul** | Daemon-uri ale sistemului de operare (`chronod` + `NotificationCenter` / `WindowServer`) | Procesul aplicației (`Daily.WinUI.exe`) pentru widget-uri pe desktop, sau `Widgets.exe` doar în panoul `Win+W` |
| **Format UI** | Snapshot-uri de timeline SwiftUI arhivate într-un App Extension separat (`DailyWidgetsExtension.appex`) | Ferestre native `HWND` DirectComposition XAML (pe desktop) sau JSON Adaptive Cards (în `Win+W`) |
| **Ce se întâmplă la Quit (`⌘Q` / `Exit`)** | `Daily.app` se închide, dar `NotificationCenter` și `chronod` continuă să ruleze și citesc cache-ul din `GroupDefaults` | Kernel-ul Win32 (`win32kfull.sys`) distruge automat toate ferestrele `HWND` deținute de un proces în momentul terminării sale |
| **Limitare OS Windows 11** | — | Microsoft **nu oferă niciun API** în Windows 11 pentru a fixa widget-uri `IWidgetProvider` direct pe wallpaper-ul desktop-ului (ele sunt blocate exclusiv în sertarul lateral `Win+W` și limitate la Adaptive Cards JSON, fără XAML Liquid Glass) |

**Concluzie și opțiuni pe Windows 11:**
1. Este o **limitare arhitecturală clară a sistemului de operare Windows 11**: Windows nu are un daemon echivalent cu `NotificationCenter` care să găzduiască widget-uri XAML direct pe suprafața desktop-ului (`Progman` / `WorkerW`). Orice widget real plasat pe desktop în Windows este o fereastră `HWND` care trebuie deținută de un proces activ.
2. De aceea există modul **Minimize to System Tray (`CloseToTray = true`)**: când închizi fereastra principală DayOne din butonul `X`, fereastra grea se ascunde, dar procesul ușor rămâne în System Tray și menține widget-urile vii pe ecran (și poate fi pornit automat la login cu `--tray`).
3. **Posibilitate viitoare (opțională)**: Dacă se dorește ca până și la `Exit` din aplicația principală widget-urile să rămână pe desktop (exact ca senzația de pe macOS), se poate separa un micro-proces invizibil dedicat (`Daily.WidgetsHost.exe`, fără fereastră principală și fără icon în taskbar) care să dețină exclusiv ferestrele `DesktopWidgetWindow` în fundal — însă la nivel de OS Windows tot va exista acel proces ușor activ în Task Manager.
