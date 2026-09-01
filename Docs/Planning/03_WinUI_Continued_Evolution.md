# WinUI Continued Evolution (Native Windows)

Aplicația WinUI (`Daily.WinUI`) este considerată flagship-ul proiectului DayOne. Ea reprezintă baza arhitecturală, estetică și logică după care vor fi construite viitoarele aplicații native (iOS, macOS, Android). Prin urmare, mentenanța și evoluția sa continuă sunt prioritare.

## Starea Actuală
* Proiect complet separat de MAUI (nativ Windows App SDK / WinUI 3).
* Design "Glassy" robust.
* Mecanism de local DB integrat corect (`sqlite-net-base`).
* Arhitectură Cloud (Supabase) perfect sincronizată.
* Integrări avansate: Smart Ledger (Charts), Watch Pairing (DayOne Orbit).

## Obiective de Dezvoltare Continuă

### 1. Paritatea cu MAUI-ul Original (Backporting)
Există încă unele funcționalități din codul legacy MAUI pe care trebuie să le scriem/rafinăm nativ în WinUI:
* **Sistemul de Obiceiuri (Habits):** Trebuie finalizat designul modern, adăugând carusele (FlipView) pentru loguri și tracking complet (fumat, citit, apă, etc).
* **SmartBriefing & Agent LLM:** Rafinarea prompturilor și a UI-ului de chat. Implementarea unor efecte vizuale de "gândire" sau streaming text direct în interfața de sticlă.

### 2. Îmbunătățiri Arhitecturale (Windows-Specific)
* **Background Tasks:** Trecerea anumitor joburi de sync pe Windows Background Tasks (prin infrastructura pachetului MSIX), astfel încât Supabase să poată primi update-uri sau să descarce RSS / Vitals chiar și când aplicația nu e în prim-plan.
* **Notificări Sistem (Toast):** Implementarea notificărilor native Windows 11 (ex: reminder pentru obiceiuri, alerte pentru tranzacții mari descărcate, sumarul zilnic generat).
* **Performanța Chart-urilor:** Optimizări adiționale pe Syncfusion Circular Charts din secțiunea Smart Ledger, pentru a suporta sute de tranzacții agregate fără frame drops (posibil un sistem de virtualizare sau grupare pre-randată în SQL/SQLite).

### 3. Integrarea DayOne Orbit (Partea de Desktop)
* Deși mecanismul de Pairing este implementat (`FeaturesPage`), vom adăuga un Dashboard de Vitals & Telemetry generat de smartwatch direct pe desktop (pe un tab de Health separat).
* Afișarea stării de sincronizare a ceasului (ultima oară văzut activ în Supabase) pe Windows UI.

## Concluzie
Orice feature nou dezvoltat pe WinUI va dicta structura bazei de date `Daily.db3` și interfețele pe care le vom cere echipei (sau nouă) să le replice pe iOS (SwiftUI) și Android (Compose). Efortul investit în WinUI este efort validat pentru tot restul ecosistemului.
