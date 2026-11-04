# Glance & Desktop Widgets Hydration Parity Architecture (2026)

**Data:** 4 Noiembrie 2026  
**Componente:**  
- **macOS**: `MacOS/Daily/Views/MenuBar/MenuBarCompanionView.swift`
- **WinUI 3**: `WinUI/Daily.WinUI/Controls/TaskbarGlanceFlyoutControl.xaml`, `WinUI/Daily.WinUI/DesktopWidgets/Views/DesktopBubblesWidgetView.xaml`  
**Platforme:** macOS 15.0+ (Sequoia) & Windows 11 (ARM64 & x64, WinUI 3 / Windows App SDK 2.2 pe .NET 10)  
**Obiectiv:** Consistență vizuală și funcțională 1:1 între macOS MenuBar Glance, macOS Desktop Widgets, WinUI Taskbar Glance și WinUI Desktop Widgets.

---

## 1. Context & Probleme Identificate

În urma inspecției comparative de design și funcționalitate între interfețele companion (Glance) și widgeturile desktop pe macOS și Windows 11, au fost identificate două discrepanțe majore de ergonomie și reprezentare grafică:

1. **Inversarea valorilor și a ordinii butoanelor în macOS MenuBar Companion (`MenuBarCompanionView.swift`)**:
   - Cardul de hidratare din meniul popover din Menu Bar avea butoanele ordonate ca: `100 ml Apă`, `150 ml Cafea`, `300 ml Apă`.
   - În contrast, `BubblesWidget.swift` (macOS Widgets), `HabitsDashboardCard.swift` (macOS Main Dashboard) și specificațiile de paritate impuneau: **Cafea 100 ml**, **Apă Mică 150 ml**, **Apă Mare 300 ml**, cu butonul de cafea plasat primul pe poziția stânga.
   - Astfel, valorile de volum erau inversate între Cafea și Apă mică, iar ordinea nu corespundea fluxului cognitiv standard.

2. **Glicf incorect pentru Cafea în WinUI 3 (`TaskbarGlanceFlyoutControl.xaml` & `DesktopBubblesWidgetView.xaml`)**:
   - Butonul de quick-log pentru cafea (100 ml) folosea gliful `&#xE706;` din `Segoe Fluent Icons`, care reprezintă simbolul de luminozitate/soare (*Brightness*), creând confuzie vizuală.
   - Restul aplicației WinUI (`HabitsWidgetControl.xaml`, `HabitsDetailPage.xaml`) folosea deja fontul vectorial Tabler Icons (`&#xef0e;` în `TablerIconsFont`) pentru ceașca de cafea.

---

## 2. Modificări Implementate

### A. macOS MenuBar Companion (`MenuBarCompanionView.swift`)
- Reordonat complet grupul de acțiuni rapide (`HStack(spacing: 8)`) în `waterIntakeCard`:
  1. **Poziția 1 (Cafea 100 ml)**:
     - Volum: `100 ml` (`habitsService.logWater(amountMl: 100, drink: "Coffee")`)
     - Pictogramă SF Symbol: `Image(systemName: "cup.and.saucer.fill")`
     - Culoare: `Color(hex: "#F59E0B")` (chihlimbar cald)
  2. **Poziția 2 (Apă Mică 150 ml)**:
     - Volum: `150 ml` (`habitsService.logWater(amountMl: 150, drink: "Water")`)
     - Pictogramă SF Symbol: `Image(systemName: "drop")`
     - Culoare: `ThemeColors.accentCyan`
  3. **Poziția 3 (Apă Mare 300 ml)**:
     - Volum: `300 ml` (`habitsService.logWater(amountMl: 300, drink: "Water")`)
     - Pictogramă SF Symbol: `Image(systemName: "drop.fill")`
     - Culoare: `ThemeColors.accentCyan`
- Actualizat comentariile de secțiune `MARK: - 2. Hydration Card (Bubbles: 100 Coffee, 150 Water, 300 Water)`.

### B. WinUI 3 Taskbar Companion & Desktop Bubbles Widget
- În `WinUI/Daily.WinUI/Controls/TaskbarGlanceFlyoutControl.xaml`:
  - Înlocuit gliful `&#xE706;` (Segoe Fluent Icons) cu `&#xef0e;` utilizând `{StaticResource TablerIconsFont}` la `FontSize="12"` și `Foreground="#FFF59E0B"`.
- În `WinUI/Daily.WinUI/DesktopWidgets/Views/DesktopBubblesWidgetView.xaml`:
  - Înlocuit `&#xE706;` la linia 48 (varianta compactă Small) cu `&#xef0e;` utilizând `{StaticResource TablerIconsFont}` la `FontSize="10"`.
  - Înlocuit `&#xE706;` la linia 143 (varianta extinsă Medium/Large) cu `&#xef0e;` utilizând `{StaticResource TablerIconsFont}` la `FontSize="12"`.

---

## 3. Matrice de Paritate Trans-Platformă

| Componentă | Poziție 1 (Cafea) | Poziție 2 (Apă Mică) | Poziție 3 (Apă Mare) | Sursă Pictogramă Cafea |
| :--- | :---: | :---: | :---: | :--- |
| **macOS MenuBar Glance** | 100 ml | 150 ml | 300 ml | SF Symbol `cup.and.saucer.fill` |
| **macOS Desktop Widget** | 100 ml | 150 ml | 300 ml | SF Symbol `cup.and.saucer.fill` |
| **macOS Dashboard** | 100 ml | 150 ml | 300 ml | SF Symbol `cup.and.saucer.fill` |
| **WinUI Taskbar Glance** | 100 ml | 150 ml | 300 ml | Tabler Icons `&#xef0e;` (Ceașcă cafea) |
| **WinUI Desktop Widget** | 100 ml | 150 ml | 300 ml | Tabler Icons `&#xef0e;` (Ceașcă cafea) |
| **WinUI Habits Hub** | 100/150 ml | 150 ml | 300 ml | Tabler Icons `&#xef0e;` (Ceașcă cafea) |

---

## 4. Verificare & Build

1. **macOS Build**:
   - `xcodebuild -project MacOS/Daily.xcodeproj -scheme Daily -configuration Debug -destination 'platform=macOS' build`
   - Rezultat: `** BUILD SUCCEEDED **` cu semnătură validă Apple Development (`DEVELOPMENT_TEAM = 7LZ9ZT2Z5B`).
2. **WinUI Build**:
   - `dotnet build WinUI/Daily.WinUI/Daily.WinUI.csproj -c Debug -p:Platform=ARM64` pe VM Parallels Windows 11.
   - Rezultat: `0 Warning(s), 0 Error(s)`.
