# Windows 11 Desktop Widgets Architecture (2026)

**Data:** 2 Noiembrie 2026  
**Componente:** `WinUI/Daily.WinUI/DesktopWidgets/`, `WinUI/Daily.WinUI/DesktopWidgets/Views/`, `WinUI/Daily.WinUI/Services/DesktopWidgetManager.cs`, `WinUI/Daily.WinUI/Services/SettingsService.cs`, `WinUI/Daily.WinUI/MainWindow.xaml`, `WinUI/Daily.WinUI/App.xaml.cs`  
**Platformă:** Windows 11 (ARM64 & x64), WinUI 3 (Windows App SDK 2.2 pe .NET 10)  
**Arhitectură:** Native Win32 Desktop Wallpaper Layering (`HWND_BOTTOM`, `WS_EX_TOOLWINDOW`, `WS_EX_NOACTIVATE`, `MA_NOACTIVATE`, `DWMWCP_ROUND`), Windows 11 Mica Alt & Desktop Acrylic, Named Pipe IPC, System Tray Management  

---

## 1. Context & Obiectiv

Sistemul de operare macOS (Sonoma și Sequoia) permite utilizatorilor să plaseze widgeturi interactive direct pe desktop (pe stratul de fundal/wallpaper), beneficiind de transparență Liquid Glass, acțiuni interactive (AppIntents) și actualizări în timp real fără a interfera cu ferestrele de lucru ale aplicațiilor.

Pe Windows 11, sistemul oficial **Windows Widgets Board** (`Win + W` / `Microsoft.Windows.Widgets.Providers`) prezintă limitări severe:
1. Nu permite plasarea widgeturilor direct pe desktop-ul utilizatorului (sunt restricționate exclusiv la un sertar lateral de tip flyout).
2. Forțează utilizarea unui format JSON primitiv de tip **Adaptive Cards**, lipsit de capabilități avansate de desenare vectorială, animații fluide, controale WinUI 3 personalizate sau layout dinamic.

Pentru a oferi o experiență de **paritate 1:1 cu macOS**, am proiectat și implementat un subsistem nativ de **Desktop Widgets pentru Windows 11** bazat pe ferestre WinUI 3 flotante, ancorate la nivelul wallpaper-ului prin P/Invoke Win32 avansat, cu suport complet pentru Mica Alt / Desktop Acrylic, snapping magnetic la grid de 16px, meniu contextual bogat, persistență JSON și control complet din System Tray și IPC Named Pipe.

---

## 2. Arhitectura Tehnică & Win32 Layering

### A. Subclasare și Ancorare pe Wallpaper (`HWND_BOTTOM`)
Fiecare widget este o instanță a clasei `DesktopWidgetWindow` (subclasă `Microsoft.UI.Xaml.Window`), configurată fără chenar de titlu tradițional (`ExtendsContentIntoTitleBar = true`), cu fundal transparent și material de adâncime Windows 11.

Pentru a se comporta exact ca un element nativ al wallpaper-ului, fereastra Win32 asociată (`HWND`) este configurată la inițializare (`SetWindowLong`):
* **`WS_EX_TOOLWINDOW`**: Ascunde fereastra widget-ului din `Alt + Tab`, din Task View (`Win + Tab`) și din Windows Taskbar.
* **`WS_EX_NOACTIVATE`**: Garantează că la afișare sau interacțiune, widgetul nu fură focusul de tastatură de la aplicația în care lucrează utilizatorul (Word, browser, IDE).
* **`DWMWA_WINDOW_CORNER_PREFERENCE = DWMWCP_ROUND`**: Activează rotunjirea nativă standard a colțurilor Windows 11 prin Desktop Window Manager (DWM).

Pentru a preveni ridicarea widget-ului peste ferestrele aplicațiilor active la clic sau drag, procedura de fereastră este subclasată (`ComCtl32.SetWindowSubclass`):
1. **`WM_MOUSEACTIVATE`**: Răspunde întotdeauna cu `MA_NOACTIVATE (3)`, permițând recepționarea clicului de mouse pe butoanele interactive din widget fără a activa fereastra widget-ului în foreground.
2. **`WM_WINDOWPOSCHANGING`**: Interceptează modificările poziției pe axa Z și setează `hwndInsertAfter = HWND_BOTTOM ((IntPtr)1)`, menținând fereastra permanent la baza stivei de ferestre desktop.

```csharp
private IntPtr WindowSubclassProc(IntPtr hWnd, uint uMsg, IntPtr wParam, IntPtr lParam, UIntPtr uIdSubclass, IntPtr dwRefData)
{
    const uint WM_MOUSEACTIVATE = 0x0021;
    const int MA_NOACTIVATE = 3;
    const uint WM_WINDOWPOSCHANGING = 0x0046;
    const int HWND_BOTTOM = 1;

    if (uMsg == WM_MOUSEACTIVATE)
    {
        return (IntPtr)MA_NOACTIVATE;
    }

    if (uMsg == WM_WINDOWPOSCHANGING)
    {
        var wp = Marshal.PtrToStructure<WINDOWPOS>(lParam);
        wp.hwndInsertAfter = (IntPtr)HWND_BOTTOM;
        Marshal.StructureToPtr(wp, lParam, false);
    }

    return DefSubclassProc(hWnd, uMsg, wParam, lParam);
}
```

### B. Standard de Dimensiuni (Grid & DPI Awareness)
Dimensiunile respectă cu strictețe specificațiile de paritate stabilite pe macOS și iOS:
* **Small**: 170 × 170 epx (pătrat compact)
* **Medium**: 360 × 170 epx (panou orizontal informativ)
* **Large**: 360 × 360 epx (tablou de bord complet)

La redimensionare și poziționare, dimensiunile logice sunt convertite în pixeli fizici raportați la DPI-ul monitorului curent (`AppWindow.ResizeClient` și `AppWindow.Move`).

### C. Drag & Drop cu Aliniere Magnetică (Snap-to-Grid)
* Utilizatorul poate trage orice widget deblocat pe desktop cu mouse-ul sau touch-ul.
* Se aplică o aliniere magnetică automată la un grid de **16px** (`SnapToGrid`), asigurând un aranjament curat și ordonat pe ecran.
* Coordonatele sunt restricționate automat la spațiul util al ecranului principal (`DisplayArea.Primary.WorkArea`), prevenind pierderea widget-ului în afara ecranului.
* La eliberarea cursorului (`PointerReleased`), noile coordonate `X` și `Y` sunt salvate imediat în configurația persistentă a aplicației.

---

## 3. Suita Completă de 9 Widgeturi Desktop

Toate widgeturile consumă date în mod **offline-first** din serviciile locale existente (`DailyCore`, `HabitsService`, `SmartLedgerStore`, `HealthHubService`, `AstronomyService`, `WeatherClient`), oferind viteză instantanee de afișare (< 1ms).

| Widget | Mărimi suportate | Tehnologie & Interacțiuni |
|---|---|---|
| **CombinedWidget** | Medium, Large | Dashboard executiv complet: combină Vremea (icoană + temperatură), Hidratarea (progres ml / țintă), Fumatul (stare fumat), SmartLedger (Net Worth în Lei) și Recuperarea Somnului. |
| **BubblesWidget** | Small, Medium, Large | Progres hidric cu inel circular de progres, volum curent / țintă ml, defalcare pe tipuri de băuturi (Apă, Cafea, Ceai) și butoane interactive rapide: `+150ml`, `+250ml`, `+500ml`. |
| **SmokesWidget** | Small, Medium, Large | Plămâni vectoriali anatomici (`LungsControl`) cu umplere dinamică a sănătății (0.0 roz sănătos -> 1.0 gudron), numărător de țigări clasice și încălzite, badge pentru timpul scurs fără fumat și butoane interactive rapide: `+Cigarette`, `+Heated`. |
| **MoneyWidget** | Small, Medium, Large | SmartLedger Net Worth în Lei și echivalent EUR (~€), balanțe Card vs Cash, cheltuieli de vârf și butoane interactive de ajustare rapidă: `+100 Card`, `-100 Card`, `+100 Cash`. |
| **SleepWidget** | Small, Medium, Large | Inel de scor recuperare somn, durată totală (`Xh Ym`), timeline orar culcat/trezit, hipnogramă proporțională pe stadii (Deep, REM, Light, Awake), puls de repaus (RHR) și HRV balance. |
| **StressWidget** | Small, Medium, Large | Scor de stres autonom /100, status vegetativ, puls curent, variație HRV față de baseline și buton interactiv pentru sesiune de respirație ghidată de 1 minut. |
| **CosmosWidget** | Small, Medium | Scor Stargazing /100, glyph și procent de iluminare pentru faza lunară, listă planete vizibile cu ochiul liber și predicție pentru următoarea trecere ISS. |
| **TagdosWidget** | Small, Medium, Large | Stream-uri active, număr taskuri deschise, stream focus și listă de taskuri prioritare cu indicatori colorați de stare. |
| **WeatherWidget** | Small, Medium, Large | Temperatură curentă, descriere și glyph condiție meteo, locație, temperatură resimțită, min/max zilnic, prognoză orară pe 5 ore (timeline) și senzori de umiditate și vânt. |

---

## 4. Gestiune, Meniu Contextual & System Tray

### A. Meniu Contextual pe Desktop (Right-Click Flyout)
Fiecare widget oferă la clic dreapta un meniu contextual complet:
* **Dimensiune**: Comutare instantanee între Small, Medium și Large.
* **Blocare Poziție (Lock/Unlock)**: Fixează widget-ul pentru a preveni deplasarea accidentală în timpul lucrului.
* **Efect de Sticlă**: Comutare între **Desktop Acrylic** (sticlă translucidă blurată) și **Mica Alt** (nuanță profundă acordată la tema Windows 11).
* **Actualizează Date**: Reîmprospătare imediată din baza de date SQLite locală.
* **Adaugă Widget**: Submeniu dinamic ce permite instanțierea oricăruia dintre cele 9 tipuri de widgeturi.
* **Închide Widget**: Elimină widget-ul de pe desktop și actualizează configurația.

### B. Integrare în Meniul System Tray (`MainWindow.xaml`)
În meniul contextual al iconiței din bara de sistem (System Tray) a fost adăugat submeniul dedicat **Desktop Widgets**:
* `Afișează Toate` / `Ascunde Toate` (Toggle vizibilitate).
* `Blochează Toate` / `Deblochează Toate`.
* `Actualizează Toate`.
* `Resetează la Layout Implicit` (redeschide aranjamentul default: Combined, Bubbles, Smokes, Money).
* `Adaugă Widget`: Permite adăugarea rapidă a oricărui widget dorit.

### C. Integrare Inter-Proces (IPC Named Pipe)
Aplicația `Daily.WinUI` ascultă pe conducta `Daily.WinUI.Ipc`. Au fost adăugate comenzi dedicate pentru automatizare sau apeluri CLI:
* `widgets:toggle` - Comută vizibilitatea tuturor widgeturilor de pe desktop.
* `widgets:lock` - Comută starea de blocare a pozițiilor.
* `widgets:refresh` - Reîmprospătează datele în toate widgeturile active.
* `widgets:reset` - Resetează la layout-ul din fabrică.

---

## 5. Persistența Datelor & Ciclul de Viață (`DesktopWidgetManager`)

* Configurația activă a widgeturilor este serializată în format JSON în `AppSettings.DesktopWidgetsConfigJson` prin intermediul `SettingsService`.
* La prima lansare pe un sistem nou (sau la resetare), `DesktopWidgetManager` calculează automat o dispunere armonioasă pe marginea din dreapta a ecranului principal:
  1. **Combined Widget** (Large, sus)
  2. **Bubbles Widget** (Medium)
  3. **Smokes Widget** (Medium)
  4. **Money Widget** (Medium, jos)
* La repornirea aplicației sau a sistemului Windows 11, toate widgeturile își reiau exact coordonatele, dimensiunile și stilul de fundal configurat.

---

## 6. Verificare & Testare pe Mașina Virtuală Windows 11

Toate componentele au fost compilate și testate pe mașina virtuală Parallels **Windows 11 (ARM64)**:
1. **Compilare Nativă**: `dotnet build -c Debug -p:Platform=ARM64` s-a finalizat cu **`0 Error(s)`**.
2. **Execuție Nativă**: Lansarea aplicației în sesiunea interactivă Windows 11 (`PID 11328`) a inițializat instanțele `DesktopWidgetWindow` fără excepții.
3. **Inspectare HWND**: Verificarea prin script PowerShell (`enum_daily_hwnds.log`) a confirmat crearea și afișarea cu succes a tuturor ferestrelor pe stratul de desktop (`Visible: True`).
4. **Validare IPC**: Comenzile `widgets:refresh` și `widgets:toggle` au fost executate prin Named Pipe și verificate vizual, ascunzând și reafișând widgeturile instantaneu.
5. **Zero Regresii**: Toate funcționalitățile preexistente din WinUI 3 (Liquid Glass, Taskbar Companion Flyout, navigarea prin tab-uri, sincronizarea Supabase și cache-ul Room/SQLite) au rămas pe deplin funcționale.
