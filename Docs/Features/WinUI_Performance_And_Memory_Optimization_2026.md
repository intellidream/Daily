# WinUI 3 Performance, Idle Efficiency & Memory Leak Hardening (2026)

**Data:** 9 Noiembrie 2026  
**Platformă:** Windows 11 (WinUI 3 / Windows App SDK 1.6 / .NET 10, ARM64 & x64)  
**Componente:** `GlassWidgetContainer.cs`, `MainWindow.xaml.cs`, `DesktopWidgetWindow.xaml.cs`, `Desktop*WidgetView.xaml.cs`, `WeatherClient.cs`, `RssFeedWidgetControl.xaml.cs`, `LlmDebugLogger.cs`

---

## 1. Diagnostic & Cauze Identificate

La testarea pe termen lung și lăsarea aplicației `Daily.WinUI` peste noapte în repaus (minimizată sau în System Tray), au fost observate două probleme majore:
1. **Consum continuu de procesor (CPU Churn)**: Nucleele CPU nu intrau în stări profunde de economisire a energiei (C-States), aplicația trezind periodic UI thread-ul.
2. **Creștere monotonă a memoriei (RAM Inflation)**: Amprenta de memorie (Working Set) urca treptat peste noapte.

### Cauze Rădăcină (Forensic Discovery):
* **20x 1Hz Runaway Timers în `GlassWidgetContainer`**:
  În `MainPage.xaml`, fiecare widget este îmbrăcat într-un `GlassWidgetContainer`. Fiecare container rula un `DispatcherTimer` la interval de 1 secundă (`_agingTimer`). Când raportul de îmbătrânire a sticlei ajungea la 1.0 (după 30s de la încărcare), timerul nu se oprea niciodată, continuând să scrie `Opacity` pe proprietăți de dependență de 20 de ori pe secundă (peste 570.000 de dispecerizări pe UI thread peste noapte). În plus, ascunderea ferestrei în System Tray (`AppWindow.Hide()`) nu descărca paginile din cache (`NavigationCacheMode="Required"`), astfel încât timerele băteau neîntrerupt în background.
* **Scurgeri de ferestre și controale XAML în `DesktopWidgetWindow`**:
  Controalele de widget-uri (`DesktopBubblesWidgetView`, `DesktopSmokesWidgetView`, `DesktopSleepWidgetView`, `DesktopTagdosWidgetView`, `DesktopMoneyWidgetView`) se abonau la evenimente pe servicii Singleton (`IHabitsService.OnHabitsUpdated`, `IHealthHubService.OnDailySummaryChanged`, `ITagdosService.DataChanged`, `IFinancesService.OnSmartLedgerUpdated`). La închiderea sau reîncărcarea ferestrelor secundare, WinUI 3 nu declanșa `Unloaded`, iar `DesktopWidgetWindow_Closed` era o metodă goală, menținând ferestrele vechi, swapchain-urile DirectX și copacii vizuali ancorați în GC root pe termen nedeterminat.
* **Alocare repetitivă de `HttpClient` în `WeatherClient`**:
  Fiecare apel către `WeatherClient` crea o instanță nouă `new HttpClient()`, lăsând socket-uri în starea `TIME_WAIT` și acumulând buffere de rețea unmanaged.
* **Memorie Edge Chromium WebView2 ne-eliberată**:
  Controalele care folosesc `WebView2` pentru scraping/autentificare rețineau texturile GPU și cache-ul JavaScript fără trimiterea semnalului de `MemoryUsageTarget.Low`.
* **Buffer nelimitat de loguri în `LlmDebugLogger`**:
  Lista statică `LlmDebugLogger.Logs` creștea fără plafon superior.

---

## 2. Soluții Implementate

### A. Oprirea și Managementul Ciclului de Viață `_agingTimer` (`GlassWidgetContainer.cs`)
1. **Oprire imediată la saturație**:
   În `AgingTimer_Tick`, când `ratio >= 1.0`, timerul apelează imediat `_agingTimer.Stop()`, eliminând 99.9% din trezirile de thread.
2. **Pornire doar când este necesar**:
   La `Loaded`, dacă timpul scurs a depășit deja durata de aging (`elapsed >= durationSeconds`), se aplică direct opacitatea statică via `ApplyStaticAging()` fără a mai porni timerul deloc.
3. **Pauză și Reluare la nivel de aplicație (`PauseAll` / `ResumeAll`)**:
   Folosind o listă internă de `WeakReference<GlassWidgetContainer>`, toate containerele sunt oprite instantaneu când `MainWindow` este minimizată sau ascunsă în System Tray (`AppWindow_Closing` / `AppWindow_Changed`), și repornite adaptiv când utilizatorul restaurează fereastra (`ShowAndActivate`).

### B. Arhitectura de Detașare `IDesktopWidgetView.Detach()` (`DesktopWidgetWindow.xaml.cs`)
1. **Contract explicit de detașare**:
   Interfața `IDesktopWidgetView` a fost extinsă cu metoda `void Detach();`.
2. **Dezabonare automată la închiderea ferestrei**:
   În `DesktopWidgetWindow_Closed`, se apelează `view.Detach()` și se decuplează `RootCard.Child = null`, rupând lanțul de referințe puternice:
   * `DesktopBubblesWidgetView`: `_habitsService.OnHabitsUpdated -= ...`
   * `DesktopSmokesWidgetView`: `_habitsService.OnHabitsUpdated -= ...`
   * `DesktopSleepWidgetView`: `_healthHubService.OnDailySummaryChanged -= ...`
   * `DesktopTagdosWidgetView`: `_tagdosService.DataChanged -= ...`
   * `DesktopMoneyWidgetView`: `_financesService.OnSmartLedgerUpdated -= ...`, `_financesService.OnQuotesUpdated -= ...`

### C. Singleton Socket Pool (`WeatherClient.cs`)
* Câmpul `_httpClient` a fost transformat în `private static readonly HttpClient _httpClient = new();`, reutilizând connection pool-ul nativ pe tot ciclul de viață al procesului și prevenind socket exhaustion.

### D. Plafonarea Logurilor și Eliberarea Resurselor
* În `LlmDebugLogger.cs`, lista de execuție a fost plafonată la ultimele 50 de rulări (`Logs.RemoveAt(0)`), prevenind acumularea nelimitată a bufferelor de text în memorie.

---

## 3. Verificare & Rezultate
* Compilat pe Windows 11 VM: ARM64 și x64 (`0 Error(s)`).
* La ascunderea ferestrei în System Tray, consumul UI thread scade la **0.0% CPU**.
* Ferestrele de widget-uri pot fi deschise/închise repetat fără reținere de obiecte moarte în Garbage Collector.
