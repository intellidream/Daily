# WinUI: fluiditate, design nativ și Smart Briefing

**Analiză comparativă cu macOS, bazată pe implementarea existentă**

- Data: **27 octombrie 2026**.
- Referință de cod: `main`, commit `ae49719`.
- Scop: analiză și propuneri pentru discuție; **nu implementare și nu migrare de framework**.
- Direcție: **experiența coerentă și rapidă a macOS, cu identitatea, reader-ul și avantajele desktop ale WinUI**.

## 1. Concluzia executivă

WinUI nu trebuie transformat într-o copie SwiftUI și nici rescris pentru a deveni sensibil mai fluid. Are deja o bază bună: WinUI 3 nativ, Mica, controale desktop, ferestre independente, docking, tray/Glance, dashboard configurabil, SQLite, sincronizare cu coalescing și un reader matur, cu SmartReader plus fallback WebView2 autentificat.

Diferența principală identificabilă în cod este **contractul dintre date, refresh și prezentare**:

1. Pornirea nu are încă o separare suficient de explicită între „identitate disponibilă”, „preferințe locale hidratate”, „conținut local afișabil” și „sincronizare cloud încheiată”.
2. „Refresh” înseamnă lucruri diferite în dashboard, într-un hub și într-o fereastră separată.
3. Există date păstrate în servicii, dar unele controale le ascund și reconstruiesc listele în timpul refresh-ului.
4. Finalizarea unui `Task` nu garantează întotdeauna că operația vizibilă sau actualizarea remote s-a terminat.
5. Timer-ele, reîncărcările și cererile nu sunt coordonate uniform cu vizibilitatea și durata de viață a interfeței.
6. Briefing-ul Windows are deja AI local și funcții valoroase, dar necesită mai întâi corectitudine a datelor, apoi o structură apropiată de macOS.

**Ordinea recomandată:**

> Date oneste și corecte → startup local predictibil → refresh coerent fără dispariția conținutului → anulare/coalescing/lifecycle → Smart Briefing structurat → polish vizual.

Nu aș începe cu alte umbre, blur-uri, o nouă bibliotecă de animații, schimbarea motorului de citire sau un upgrade general de pachete. Acestea nu rezolvă cauzele principale observabile.

### Primele intervenții cu cel mai bun raport valoare/risc

| Prioritate | Intervenție | Beneficiu urmărit |
|---|---|---|
| P0 | Corectarea ramurii `onlyLocal` din briefing și eliminarea datelor demonstrative din fallback-urile de producție | Briefing funcțional și credibil, inclusiv offline |
| P0 | Barieră explicită pentru preferințele locale înaintea layout-ului editabil | Fără layout implicit afișat/salvat înaintea hidratării |
| P1 | Contract unic de refresh și păstrarea conținutului deja afișat | Mai puține „goluri”, spinner-e și gesturi repetate |
| P1 | Snapshot-uri comune pentru widget, hub, Glance și briefing | Mai puține cereri și valori contradictorii |
| P1 | Anulare reală, protecție împotriva rezultatelor întârziate și actualizări incrementale | Navigare și reader predictibile sub latență |
| P1 | Briefing pe secțiuni, cu sinteză deterministă imediată și AI opțional | Paritate de experiență cu macOS, fără a aștepta modelul |
| P2 | Raționalizarea layout-ului, timer-elor, imaginilor și efectelor | Consum și frame pacing mai bune |
| P2 | Finisare Fluent, accesibilitate, densitate și master-detail opțional | Rafinament fără pierderea aspectului Windows |

P0 desemnează aici o problemă de corectitudine care blochează direcția propusă, nu o vulnerabilitate și nici o regresie de performanță măsurată.

## 2. Metodă, acoperire și limite

### Ce am verificat

- Inventarierea fișierelor versionate: **74 fișiere C# și 31 XAML** în proiectul WinUI; **60 fișiere C#** în directorul comun de servicii.
- Inventarierea implementării Apple: **80 fișiere Swift macOS** și **45 fișiere Swift în sursele DailyCore**.
- Citirea aprofundată a fluxurilor de startup, dashboard, refresh, health, finances, habits, calendar, TagDoS, news/reader, Glance și briefing.
- Compararea cu serviciile și prezentarea macOS, nu doar cu documentele de intenție.
- Scanare lexicală deterministă a surselor C# pentru familii de pattern-uri de performanță.
- Verificarea documentației oficiale pentru virtualizare WinUI, WebView2, Windows AI și Gemini.
- Inventarierea testelor existente și a golurilor de validare relevante.

**Inventariere/scanare integrală nu înseamnă citire semantică integrală a fiecărui fișier.** Analiza este exhaustivă pe suprafețele și scenariile cerute; nu pretinde demonstrarea absenței tuturor defectelor din aplicație.

### Ce nu am măsurat

Nu am lansat aplicațiile, nu am capturat trace-uri ETW, nu am comparat video-uri sau screenshot-uri, nu am executat inference și nu am folosit o cheie Gemini. Nu am interogat date personale sau un backend live. Nu am rulat build/test pentru această modificare exclusiv de documentație.

Prin urmare:

- „macOS este mai fluid” este observația utilizatorului, nu rezultatul unui benchmark efectuat aici.
- Timpii din comentarii precum „0 ms”, „<10 ms”, „<300 ms” sau „120 FPS” **nu sunt tratați drept măsurători**.
- Costul exact al blur-ului, al layout-ului, al SQLite și al modelelor locale rămâne de profilat.
- Problemele logice descrise ca „confirmate în cod” au o ramură concretă verificabilă; impactul lor în sesiunea reală trebuie reprodus.
- Disponibilitatea modelelor/API-urilor depinde de OS, SDK, hardware, regiune și proiectul cloud. Sursele oficiale sunt un reper la data analizei, nu o garanție pentru orice instalare.

### Convenții

- **C — confirmat în cod:** mecanismul există în implementarea analizată.
- **R — risc derivat:** implementarea permite un efect, dar nu avem reproducere runtime.
- **H — ipoteză de profilat:** impactul și amploarea trebuie măsurate.
- Efort: **S/M/L**, relativ la acest proiect; nu estimare calendaristică sau promisiune de viteză.

## 3. Harta surselor principale

Referințele sunt relative pentru a rămâne utile și în repository. Numerele de linie se raportează la commit-ul de mai sus.

| ID | Sursă | Rol în analiză |
|---|---|---|
| W01 | [Proiect WinUI](../WinUI/Daily.WinUI/Daily.WinUI.csproj) | .NET 10, Windows App SDK 2.2.0, SmartReader, LLamaSharp și surse comune linkate |
| W02 | [App: launch și inițializare](../WinUI/Daily.WinUI/App.xaml.cs#L317) | DI, identitate, inițializare servicii, reconnect |
| W03 | [MainWindow: hidratare](../WinUI/Daily.WinUI/MainWindow.xaml.cs#L372) | Alegerea paginii după sesiune |
| W04 | [MainPage: încărcare](../WinUI/Daily.WinUI/MainPage.xaml.cs#L140) | Bariera de widget-uri, pre-generare și prezentare |
| W05 | [MainPage: refresh](../WinUI/Daily.WinUI/MainPage.xaml.cs#L282) | Refresh in-place și la revenirea pe dashboard |
| W06 | [MainWindow: comenzi](../WinUI/Daily.WinUI/MainWindow.xaml.cs#L244) | Acțiunile title bar și `Ctrl+R` |
| W07 | [Dashboard XAML](../WinUI/Daily.WinUI/MainPage.xaml#L167) | Scroll exterior, panel variabil, overlay briefing |
| W08 | [GlassWidgetContainer](../WinUI/Daily.WinUI/Controls/GlassWidgetContainer.cs) | Aging, timer, wipe și finalizarea refresh-ului |
| W09 | [Setări locale Windows](../WinUI/Daily.WinUI/Services/SettingsService.cs) | Cache în memorie, JSON, opțiuni AI și aging |
| W10 | [HealthHubService](../WinUI/Daily.WinUI/Services/HealthHubService.cs) | Summary canonic, cache, realtime, delta și dispatch |
| W11 | [News hub/reader](../WinUI/Daily.WinUI/Views/RssFeedDetailPage.xaml.cs) | Selecție feed, agregare, reader și recomandări |
| W12 | [Widget News](../WinUI/Daily.WinUI/Controls/RssFeedWidgetControl.xaml.cs) | Loading, liste și integrarea cu serviciul comun |
| W13 | [Briefing Windows](../WinUI/Daily.WinUI/Services/SmartBriefingService.cs) | Agregare metrici, fallback și generare locală |
| W14 | [Cache briefing Windows](../WinUI/Daily.WinUI/Services/SmartBriefingCacheManager.cs) | Praguri, sloturi, SQLite, JSON și Supabase |
| W15 | [Coordonare AI](../WinUI/Daily.WinUI/Services/SmartIntelligenceService.cs) | Readiness, prompt templates și interfață comună |
| W16 | [AIManager](../WinUI/Daily.WinUI/Services/AIManager.cs) | Selecție NPU/GPU/CPU și inițializare |
| W17 | [LLamaUniversalEngine](../WinUI/Daily.WinUI/Services/LLamaUniversalEngine.cs) | GGUF, context, tokeni și lifecycle |
| W18 | [PhiSilicaNpuEngine](../WinUI/Daily.WinUI/Services/PhiSilicaNpuEngine.cs) | Readiness Windows AI și limitare Qualcomm în cod |
| W19 | [Glance Windows](../WinUI/Daily.WinUI/Controls/TaskbarGlanceFlyoutControl.xaml.cs) | Acces rapid și încărcare telemetrie |
| C01 | [SyncService](../Services/SyncService.cs) | Coalescing existent, push/pull și timer |
| C02 | [SettingsService comun](../Services/SettingsService.cs) | Preferințe locale, migrare guest și pull inițial |
| C03 | [RssFeedService](../Services/RssFeedService.cs) | HTTP, feed state, SmartReader |
| C04 | [RefreshService](../Services/RefreshService.cs) | Așteptarea handler-elor și timeout de 15 s |
| C05 | [RssArticleService](../Services/RssArticleService.cs) | Favorites/Read Later și deduplicare |
| M01 | [RootView macOS](../MacOS/Daily/Views/Main/RootView.swift) | Shell, refresh paralel și dual-pane |
| M02 | [Dashboard macOS](../MacOS/Daily/Views/Dashboard/DashboardView.swift) | Model observabil și refresh concurent |
| M03 | [NewsService Apple](../DailyCore/Sources/DailyCore/Services/NewsService.swift) | Cache feed 15 minute și parsing detached |
| M04 | [NewsFeedView macOS](../MacOS/Daily/Views/News/NewsFeedView.swift) | Lazy list și păstrarea conținutului |
| M05 | [Briefing DailyCore](../DailyCore/Sources/DailyCore/Services/SmartBriefingService.swift) | Sinteză, hash, prezentare și sync |
| M06 | [Modele briefing](../DailyCore/Sources/DailyCore/Models/SmartBriefingModels.swift) | Sloturi, secțiuni și metrici |
| M07 | [Overlay briefing macOS](../MacOS/Daily/Views/Briefing/SmartBriefingOverlayView.swift) | Carduri și reveal progresiv |
| M08 | [GeminiApiService](../DailyCore/Sources/DailyCore/Services/GeminiApiService.swift) | Integrarea cloud efectivă |
| M09 | [Cache imagini macOS](../MacOS/Daily/DesignSystem/CachedAsyncImage.swift) | Cache decodat cu limite |
| D01 | [Arhitectura WinUI existentă](WinUI_Architecture_2026.md) | Context și decizii care trebuie păstrate |
| D02 | [Remedierea realtime documentată](Supabase_Realtime_WinUI_Sync_Fixes.md) | Precedent pentru delegate și token propagation |
| D03 | [Briefing Next-Gen](Features/SmartBriefing_NextGen.md) | Intenție de produs; verificată față de cod |
| D04 | [Schema daily_smart_summaries](SQL/20260916_DailySmartSummaries.sql) | Contract cloud deja pregătit |

## 4. Checklist-ul scanării de performanță

Acest inventar precedă clasificarea constatărilor. Numerele reprezintă **linii care corespund expresiilor**, nu număr de bug-uri, obiecte alocate sau operații efectuate.

- **A:** toate cele 74 surse C# versionate din WinUI, fără `bin`, `obj`, `.vs`.
- **B:** toate cele 60 surse C# versionate din directorul comun de servicii.
- B este un superset de descoperire: include și servicii MAUI care nu sunt compilate în WinUI. Nu atribuim automat toate rezultatele B aplicației Windows.
- Scanarea lexicală poate include comentarii și fragmente HTML/JavaScript din string-uri.
- Instanțierile target-typed `new()` nu sunt numărate de rețetele literale `new HttpClient(` etc.; au fost inspectate separat în traseele citite.

| Rețetă executată | A | B | Interpretare |
|---|---:|---:|---|
| `IndexOf("literal")`, fără argument de comparație | 2 | 9 | Candidați; nu verdict cultural universal |
| `Substring(` | 92 | 18 | Include tăieri pentru afișare, nu doar parsare |
| `StartsWith/EndsWith("literal")`, fără comparație | 16 | 16 | De verificat pe hot paths |
| `Contains("literal")`, fără comparație | 119 | 32 | Candidați lexicali, inclusiv string-uri de script |
| `ToLower()/ToUpper()` | 7 | 13 | Cultură și alocări de verificat |
| Minimum trei `Replace` pe aceeași linie | 0 | 0 | Nu exclude lanțuri pe linii multiple |
| `params` | 2 | 1 | Nu justifică schimbare fără profilare |
| `All/Any(char.` | 0 | 0 | Pattern-ul căutat lipsește |
| `static readonly Dictionary<` | 3 | 3 | Unele sunt cache-uri mutabile, nu candidate Frozen |
| `static readonly FrozenDictionary<` | 0 | 0 | Absența nu este singură o problemă |
| `new List<`, fără `static/readonly` pe linie | 68 | 73 | Euristică lexicală, nu toate sunt per-call |
| `new Dictionary<`, aceeași euristică | 5 | 22 | Necesită context |
| `StringComparer.CurrentCulture` | 0 | 0 | Pattern-ul căutat lipsește |
| `Select/Where/Cast/Take/Aggregate(` | 145 | 158 | Nu interzicem LINQ în bloc |
| `RegexOptions.Compiled` | 0 | 1 | Costul concret depinde de inițializare |
| `GeneratedRegex` | 0 | 0 | Comparat cu pattern-urile statice efective |
| `new Regex(` | 0 | 0 | Nu exclude apeluri statice `Regex.Replace/Match` |
| `new HttpClient(` | 0 | 4 | Cele patru B inspectate sunt în constructori |
| `new JsonSerializerOptions`, fără `static/readonly` | 1 | 3 | Nu include toate inițializările target-typed |
| `async void` | 114 | 1 | Majoritatea pot fi event handlers legitimi |
| `.Result`, `.Wait(`, `GetAwaiter().GetResult` | 20 | 5 | Include rezultate deja completate și proprietăți non-Task |
| `stackalloc` | 0 | 0 | Nu există risc „stackalloc în buclă” în acest scope |
| `ValueTask` | 0 | 0 | Nu există risc de await repetat al unui ValueTask aici |
| `new byte[` | 2 | 9 | Nu recomandăm pooling pentru fiecare buffer mic |
| `JsonSerializer.Serialize/Deserialize` literal, fără generice intercalate | 4 | 4 | Rețetă îngustă; nu totalul serializărilor |
| `ResponseHeadersRead` | 2 | 0 | Există utilizare pozitivă pentru download |
| `File.ReadAllText/WriteAllText/AppendAllText` | 17 | 3 | Separăm cold path de UI path |
| Clase nesealed, nonabstract, nonstatic, după expresia de declarație | 55 | 43 | Nu toate sunt leaf classes |
| Clase sealed, inclusiv `sealed partial class` | 63 | 0 | A: 63 din 118 declarații numărate de cele două rețete |
| `IEquatable` | 0 | 0 | Nu dovedește o problemă de equality |
| `Task.Delay` | 27 | 16 | Include debounce și timeout-uri legitime |
| `DispatcherTimer` | 8 | 0 | Linii, nu opt timer-e active simultan |
| `File.AppendAllText` | 7 | 1 | Necesită analiza frecvenței și a thread-ului |

### Verificare semantică și a inversului

- `Task.Result` din agregarea briefing-ului apare și **după `await Task.WhenAll`**. Acele utilizări nu sunt dovezi de deadlock.
- Blocări reale există în [statusul AI din Settings](../WinUI/Daily.WinUI/Views/FeaturesPage.xaml.cs#L250), cu `Task.Run(...).GetAwaiter().GetResult()`, și în [importul de calendar](../WinUI/Daily.WinUI/Services/CalendarService.cs#L907), cu `InsertAsync(...).Wait()`. Impactul exact depinde de traseul de apel.
- Cele patru `new HttpClient(` din B inspectate sunt în constructori; `RssFeedService` este singleton în DI. Nu există dovadă de creare a unui client pentru fiecare articol pe acel traseu.
- În Windows, `WeatherClient` și `LocationService` au clienți target-typed per instanță. Există mai mulți consumatori, dar problema de evaluat este reutilizarea/lifetime-ul, nu „socket exhaustion demonstrat”.
- Setările Windows au deja `JsonSerializerOptions` static și cache de obiect în memorie. Timer-ul aging nu recitește fișierul în fiecare secundă după hidratare.
- Dicționarele de cache sunt modificate în runtime. Nu trebuie înlocuite cu `FrozenDictionary` doar pentru a îmbunătăți raportul 0/3.
- Nu recomand „sealing” în masă pentru cele 55 de declarații nesealed din A. Moștenirea, clasele de framework și impactul JIT trebuie verificate; aceasta nu este sursa principală a experienței lente.
- Pe lanțul de extragere a unui articol există **patru apeluri `Replace` pentru curățarea autorului, pe linii diferite**, urmate de două `Regex.Replace` și trim-uri, în [RssFeedService](../Services/RssFeedService.cs#L772). Sunt șase operații potențial alocatoare, nu șase alocări garantate. Nu justifică înlocuirea motorului de extracție.
- În typewriter există concatenare repetată a textului unui `Run`, la fiecare cuvânt. Este mai relevantă pentru UI decât conversiile unor titluri executate o singură dată.

## 5. Ce are WinUI bun și trebuie păstrat

| Activ existent | De ce contează | Politică recomandată |
|---|---|---|
| SmartReader + fallback WebView2 | Acoperă HTML static și pagini care necesită browser/autentificare | Optimizăm învelișul și orchestrarea, nu înlocuim extractorul |
| Profil WebView2 persistent pentru Medium | Păstrează contextul de autentificare al utilizatorului | Profilul și login-ul rămân independente de cache-ul de articole |
| Reader HTML dedicat, font Segoe UI, temă light/dark | Lectură focalizată și consistentă cu Windows | Păstrăm template-ul și validăm orice schimbare pe un corpus fix |
| Favorites și Read Later cu SQLite/sync/deduplicare | Valoare reală cross-device | Nu confundăm metadatele salvate cu disponibilitatea integrală offline |
| Dashboard configurabil și drag/drop cu span-uri | Personalizare desktop mai bogată decât o grilă rigidă | Layout-ul se schimbă separat de refresh-ul datelor |
| Calendar desktop și integrarea de conturi | Diferențiator important față de un briefing cu doar șase hub-uri | Calendarul și task-urile rămân secțiuni de primă clasă |
| Ferestre separate, docking, tray și Glance | Multitasking autentic Windows | Păstrăm, dar alimentăm toate suprafețele din aceleași snapshot-uri |
| Mica, controale WinUI și resurse de temă | Identitate nativă, nu pagină web împachetată | Nu înlocuim shell-ul cu WebView sau alt toolkit |
| Glass aging și wipe | Semnătură vizuală distinctă | Opționale, mai subtile, cu lifecycle corect și fără a falsifica freshness |
| AI local NPU/GPU/CPU și chat după briefing | Avantaj de confidențialitate și utilizare offline | Păstrăm ca provider real, nu ca opțiune secundară ascunsă |
| Coalescing în SyncService | Cererile pending își reunesc scope/action, în loc de a rula toate separat | Extindem prior art existent; nu construim încă un sync engine |
| Cache-uri weather/location și summary canonic health | Piese utile pentru un model local-first coerent | Reutilizăm și corectăm contractele, nu pornim de la zero |

**Observație importantă:** semantica „AI local” nu este echivalentă astăzi cu „nimic nu ajunge în cloud”. Cache-ul briefing-ului este trimis în Supabase pentru utilizatorii autentificați, iar Smart Behavior are opțiuni proprii de sincronizare. UX-ul viitor trebuie să distingă procesarea AI de sincronizarea datelor.

## 6. Ce preluăm de la macOS — și ce nu

### Aspecte bune, observabile în implementare

1. **Servicii observabile de lungă durată.** Dashboard-ul și hub-urile citesc starea serviciilor comune, în loc să coordoneze totul prin controale vizuale.
2. **Concurență între domenii independente.** Dashboard-ul și refresh-ul global pornesc weather/health/habits/news/finances cu `async let`.
3. **News păstrează lista în timpul refresh-ului.** Spinner-ul de primă încărcare este condiționat și de absența articolelor.
4. **Cache de feed de 15 minute**, cu cheie de feed; operațiile de fetch/parsing sunt mutate pe un task detached.
5. **LazyVStack în feed**, identități de articole și cache decodat de imagini cu limite explicite.
6. **Briefing pe secțiuni**, sloturi temporale, metrici lângă text, closing contextual și priorități TagDoS.
7. **Master-detail/dual-pane opțional**, fără a obliga utilizatorul să piardă dashboard-ul când consultă un hub.
8. **Reveal cu posibilitatea de skip**, util ca polish, nu ca precondiție pentru a citi.

### Limite ale macOS care nu trebuie portate

| Constatare în cod | Implicație pentru Windows |
|---|---|
| Briefing-ul construiește Tier 1, dar salvează/publică rezultatul după încercarea Gemini | „Determinist instant” nu înseamnă că UI-ul primește imediat acel rezultat |
| Overlay-ul cere `forceRefresh: true` la deschidere | Nu copiem invalidarea cache-ului la fiecare afișare |
| Sunt două încercări cloud secvențiale, fiecare cu timeout de 3,5 s | Nu există o garanție de 3,5 s end-to-end; timpul total poate depăși 7 s cu procesare |
| Request-ul Gemini folosește MIME JSON și schema descrisă în prompt, fără o schemă efectivă în request | Folosim structured output real și validare locală, nu doar instrucțiuni text |
| Hash-ul nu include toate câmpurile care influențează narațiunea, de exemplu conținutul efectiv al priorităților TagDoS | Schimbarea unei priorități trebuie să invalideze secțiunea chiar dacă numărul stream-urilor nu se schimbă |
| Lipsa vremii poate deveni `20.0`/`Clear` în payload, iar sinteza stress folosește implicit scorul 32 | Nu importăm date implicite prezentate ca observații reale |
| Prompt-ul impune engleză și Lei | Windows trebuie să respecte limba, moneda și unitățile configurate |
| Clientul conține fallback `gemini-1.5-flash` | Nu portăm automat un model vechi; disponibilitatea se verifică separat |
| Deschiderea automată pregătește briefing-ul, apoi overlay-ul poate cere din nou force refresh | Necesită deduplicare, nu două generări succesive |
| `NewsReaderView.loadArticle` creează un task fără identitate de cerere verificată la final | Și macOS are risc de rezultat întârziat; Windows trebuie să implementeze „latest selection wins” |
| `NewsService` publică rezultatul după fetch fără verificarea feed-ului încă selectat | Nu este un exemplu complet de concurență robustă |

Separăm deci **paritatea de experiență** de **copierea implementării**. Mai multe culori din design system-ul macOS sunt chiar descrise ca derivând din WinUI; nu este necesar un rebranding pentru a obține coerență.

## 7. Startup: cel mai important traseu de simplificat

### 7.1 Fluxul Windows actual

```text
OnLaunched
  -> construiește DI
  -> InitializeAsync pe background
       -> Supabase.InitializeAsync, așteptare limitată la 3,5 s
       -> restaurare manuală sesiune
       -> SessionRestoredTask completat
       -> SQLite
       -> preferințe
       -> seed feed-uri
       -> RSS / saved articles / habits / health
       -> background sync
  -> creează MainWindow în paralel
       -> așteaptă SessionRestoredTask, maximum 6 s
       -> MainPage
            -> încarcă layout din Settings
            -> ține conținutul la Opacity 0
            -> întârziere 200 ms pentru înregistrarea widget-urilor
            -> WhenAny(WhenAll(widget tasks), 2,5 s)
            -> pull-uri și pre-generare briefing
            -> fade overlay, cu așteptare de 750 ms
```

Surse: W02, W03, W04 și [fade-ul MainWindow](../WinUI/Daily.WinUI/MainWindow.xaml.cs#L327).

### 7.2 Problemele de contract

**S01 — Identitate disponibilă nu înseamnă preferințe disponibile. C/R, P0.**

`SessionRestoredTask` este completat înaintea inițializării SQLite și a preferințelor. Navigarea așteaptă acest task, iar `LoadWidgetsAsync` citește direct `WinUIWidgetService`, fără o barieră explicită de hidratare a preferințelor.

Riscul este afișarea layout-ului implicit și, dacă acesta devine editabil înaintea hidratării, salvarea unei configurații nedorite. Documentul D01 descrie o protecție mai strictă decât cea demonstrată de traseul curent. Nu eliminăm hidratarea pentru a obține o pornire aparent mai rapidă; o facem explicită și granulară.

**S02 — Conținutul local este ținut ascuns pentru operații eterogene. C, P1.**

Un widget lent poate întârzia prezentarea întregului dashboard până la limita orchestrării. Cele 200 ms și fade-ul final sunt costuri de politică UX, nu cerințe de date.

Nu însumăm mecanic toate limitele: o parte din operații se suprapun. Dar nici „maxim 2,5 s” nu este un buget real de startup, deoarece nu include restaurarea sesiunii și restul pașilor.

**S03 — `WhenAny` nu înseamnă anulare sau tratarea rezultatului. C, P1.**

Atât inițializarea Supabase, cât și agregarea task-urilor folosesc `WhenAny` fără a aștepta apoi task-ul câștigător pentru a-i observa rezultatul. Operația pierzătoare poate continua. Catch-ul din jur nu capturează automat excepția task-ului agregat.

**S04 — Înregistrarea widget-urilor după o întârziere fixă este fragilă. C, P1.**

Nu toate widget-urile își înregistrează la fel încărcarea: de exemplu Calendar și TagDoS au trasee diferite față de widget-urile urmărite explicit. „Toate datele încărcate” nu este un invariant garantat de această fereastră de 200 ms.

**S05 — „Minimum boot time” nu este în prezent o întârziere suplimentară. C.**

În constructorul curent, `_minBootTimeTask` este `Task.CompletedTask` pe ambele ramuri. Nu recomand eliminarea unei întârzieri inexistente; problema reală este bariera globală și fade-ul, nu numele metodei.

### 7.3 Flux propus

```text
Shell WinUI vizibil
  -> restore local identity + local preferences
  -> layout sigur, deja configurat
  -> snapshot-uri locale independente pentru fiecare card
  -> shell interactiv, fără barieră globală de rețea
  -> revalidare background per domeniu
  -> actualizări incrementale, fără resetare de layout/scroll
  -> briefing pregătit separat, fără drept de a bloca dashboard-ul
```

În practică:

- Introducem faze de readiness în orchestrarea existentă, nu o infrastructură generică de workflow.
- Până la hidratarea preferințelor: shell/skeleton simplu, layout needitabil; nu persistăm fallback-ul ca preferință.
- Revalidarea token-ului rulează fără a împiedica citirea datelor locale ale identității restaurate în siguranță.
- Prima instalare fără cache are stări explicite per card. O bază goală nu este echivalentă cu „0 pași” sau „niciun task”.
- Seed-ul, deduplicările istorice și sync-ul complet nu trebuie să fie obligatorii pentru primul frame util.
- Logo-ul/fade-ul pot rămâne discrete, dar nu impun o așteptare artificială când conținutul este disponibil.

## 8. Refresh: o singură semantică, mai multe scope-uri

### 8.1 Diferențele actuale

| Suprafață | Comportament din cod | Problemă |
|---|---|---|
| Butonul din title bar principal | Apelează refresh doar când pagina este dashboard | Pe hub poate să nu facă nimic, deși controlul există |
| `Ctrl+R` pe dashboard | Refresh direct al widget-urilor realizate | Nu este echivalent cu un sync global complet |
| `Ctrl+R` pe alt hub | Pornește `SyncAsync` în background | Nu așteaptă explicit refresh-ul paginii active și nu oferă același feedback |
| Title bar fereastră detail | Așteaptă `RefreshFromTitleBarAsync` al hub-ului | Alt traseu și alte garanții |
| Revenirea pe dashboard | `RefreshWidgetsSilentAsync` | „Silent” este doar lipsa animației wrapper-ului, nu neapărat lipsa rețelei |
| Glass wipe | Pornește înaintea refresh-ului | Widget-ul poate părea proaspăt chiar dacă fetch-ul eșuează |
| RefreshService | Așteaptă task-urile delegate, maximum 15 s | Unele delegate returnează `CompletedTask` imediat după enqueue pe UI |

Ultimul caz este verificat în widget-urile [Health](../WinUI/Daily.WinUI/Controls/HealthWidgetControl.xaml.cs#L76), [Finances](../WinUI/Daily.WinUI/Controls/FinancesWidgetControl.xaml.cs#L165), [Calendar](../WinUI/Daily.WinUI/Controls/CalendarWidgetControl.xaml.cs#L175) și în [Health hub](../WinUI/Daily.WinUI/Views/HealthDetailPage.xaml.cs#L177).

**Important:** SyncService are deja queue/coalescing. Problema nu este lipsa absolută a unei coordonări, ci faptul că refresh-ul UI, cache-urile și acel sync nu au un contract comun de finalizare.

### 8.2 Contract recomandat

Patru operații distincte, cu nume și feedback clare:

1. **Load local:** numai cache/memorie/SQLite; fără a porni implicit fetch de rețea.
2. **Revalidate if stale:** prezintă imediat ce există, apoi actualizează dacă sursa este expirată.
3. **Refresh active scope:** cerere manuală pentru hub-ul activ; returnează task-ul operației reale.
4. **Sync all:** acțiune explicită globală, cu stare agregată și rezultate parțiale pe domenii.

Butonul title bar și `Ctrl+R` trebuie să invoce aceeași comandă contextuală. „Sync all” poate avea comandă separată în meniu; nu trebuie ascuns în spatele unei diferențe de context.

Comanda:

- reunește cererile identice aflate deja în curs;
- nu serializează inutil două surse independente;
- păstrează conținutul afișat;
- actualizează `IsRefreshing`, nu reinițializează toată pagina;
- întoarce rezultat explicit: succes, parțial, offline, timeout, autentificare necesară sau anulare;
- nu marchează refresh-ul drept încheiat doar pentru că o acțiune a fost pusă în dispatcher;
- nu lasă un timeout de așteptare să devină operație zombie neobservată.

### 8.3 Model de stare minim

Nu este nevoie de un store global complex. Un snapshot tipizat per domeniu, deținut de serviciul existent, este suficient:

```text
Data + Identity + Scope + ObservedAt + LastSuccessfulRefresh
Availability: NotLoaded / Available / Empty / Unavailable
Freshness: Fresh / Stale
Activity: Idle / Loading / Refreshing
LastError + SourceVersion
```

`Empty` trebuie să însemne „sursa a răspuns și este goală”, nu „request-ul a eșuat”. Freshness și activitatea sunt axe separate: putem avea date stale, vizibile, în timp ce refresh-ul rulează.

## 9. Fluiditatea UI: ce merită optimizat efectiv

### 9.1 Păstrarea listelor și identităților

**C:** `UpdateArticles` în News face `Clear()` și reconstruiește view model-urile; în loading ascunde lista. Finances golește și repopulează colecții, iar hub-ul poate goli datele chiar la începutul încărcării. Health și TagDoS reconstruiesc mai multe colecții sau subarbori.

**Recomandare:**

- Actualizare după cheie stabilă, nu clear/re-add pentru orice refresh.
- Păstrarea elementelor nemodificate și a scroll anchor-ului.
- Un singur set coerent de proprietăți UI per rezultat, nu multe repaint-uri intermediare.
- Pentru grafice: actualizăm numai seria/intervalul schimbat; nu reanimăm întregul chart la fiecare eveniment.
- Păstrăm controalele native virtualizate ale feed-ului. Nu există bază pentru afirmația că toate listele WinUI sunt nevirtualizate.

### 9.2 Layout-ul dashboard-ului

**C:** dashboard-ul folosește `VariableSizedWrapGrid` în interiorul unui ScrollViewer exterior. Conform Microsoft, acest panel **nu oferă virtualizare UI**. Customizarea span-urilor repară comportamente de layout, nu transformă panel-ul într-unul virtualizat.

Totuși, sunt șapte widget-uri în configurația implicită. **Nu recomand o rescriere complexă de layout doar pentru această cifră.**

Ordinea corectă:

1. Măsurăm costul arborelui vizual și al resize-ului.
2. Amânăm subarborii grei, de exemplu briefing-ul ascuns, cu mecanismul XAML adecvat.
3. Limităm măsurările repetate și reaplicarea span-urilor la schimbări relevante.
4. Dacă extindem dashboard-ul cu multe widget-uri, evaluăm un layout WinUI virtualizabil care păstrează span-urile și drag/drop-ul.

Înlocuirea simplă cu `ItemsWrapGrid` fără rezolvarea span-urilor ar fi o regresie funcțională.

### 9.3 Timer-e și animații

**C:** fiecare `GlassWidgetContainer` pornește un timer de o secundă în constructor; nu are oprire explicită la `Unloaded` în implementarea analizată. Timer-ul continuă să ticăie și când aging-ul este dezactivat, chiar dacă handler-ul iese rapid.

Recomandări:

- Timer doar pentru instanțe vizibile, încărcate și cu efect activ.
- Oprire/pornire idempotentă la lifecycle; nu presupunem că page cache înseamnă vizibilitate.
- Oprirea tick-urilor când raportul de aging a ajuns la capăt.
- Dacă rămân multe containere active, un clock comun ușor; nu introducem scheduler complex pentru șapte carduri fără măsurători.
- Wipe-ul rămâne semnătură vizuală, dar indicatorul de freshness se modifică numai după un rezultat valid.
- Animațiile decorative de opacity/transform merg preferabil pe Composition; datele și layout-ul rămân pe UI thread.
- Reduced motion, transparență dezactivată, fereastră minimizată și battery saver trebuie să reducă efectele.

### 9.4 Typewriter-ul briefing-ului

**C:** timer de 20 ms, concatenare în `Run.Text`, actualizări de scale/glow și declanșarea cardurilor după procentul de cuvinte.

Efectele de urmărit: reflow repetat al textului, alocări cumulative și cost pe UI thread. „20 ms” nu este sincronizare cu refresh rate-ul display-ului.

Propunere:

- Textul complet și geometria secțiunilor se stabilesc înainte de reveal.
- Animație de reveal opțională, scurtă, cu „Afișează tot”, fără a bloca chat-ul/acțiunile.
- Nu confundăm streaming-ul modelului cu animația unui text deja generat.
- O actualizare per frame/batch, nu neapărat per token.
- Nu schimbăm textul deja citit sub utilizator când enhancement-ul sosește; oferim versiunea îmbunătățită controlat.

### 9.5 Imagini, WebView și memorie

- macOS are cache decodat cu limite declarate; Windows are caching pentru avatar și anumite resurse, dar nu un contract comun pentru imaginile news.
- Pentru Windows: cache bounded, deduplicare request-uri, dimensiuni de decode potrivite cardului și placeholders cu geometrie stabilă.
- Nu aducem imagini de articol la rezoluție mare doar pentru icon-uri/carduri mici.
- WebView2 are memorie multiproces; măsurătorile trebuie să includă procesele Edge asociate, nu doar procesul WinUI.
- Reutilizăm environment/profile când este corect, dar nu menținem inutil două WebView-uri inițializate pentru un articol static.
- Prewarm-ul se face oportunist după afișarea shell-ului sau la intenție de citire, nu ca blocaj la startup.

### 9.6 I/O și lucru CPU pe UI thread

- `SettingsService.Load()` este deja cached; nu îl raportăm drept citire de fișier la fiecare apel.
- `SettingsService.Save()` și unele log-uri folosesc I/O sincron. Coalescing/debounce pentru mutări de fereastră, resize și preferințe repetate este mai util decât micro-optimizarea JSON.
- Parsarea SmartReader a HTML-ului deja primit este sincronă. Pe traseele care revin în UI context, poate consuma bugetul de frame: separăm fetch-ul async de parsarea CPU-bound pe worker.
- Nu mutăm obiecte XAML/WebView/Composition pe thread pool. Pe background se calculează DTO-uri, nu se ating controale.
- Remediem cele două blocări sync-over-async verificate; nu facem un „replace all” al `.Result`.

## 10. Încărcarea pe domenii: plan țintit

| Domeniu | Mecanism actual relevant | Îmbunătățire propusă | De păstrat / atenție |
|---|---|---|---|
| Weather | Cache static 15 min, toleranță de locație, cache coordonate și timeout-uri GPS/IP | Același snapshot pentru widget/hub/Glance/briefing; request in-flight comun | Nu cerem permisiunea GPS la fiecare prezentare; păstrăm locația manuală |
| Health | Summary canonic, SQLite/memorie, realtime și API-uri pentru detalii | Publicarea distinctă local/remote, batch de derivări, refresh pe data/sursa cerută | Fără regresie la sleep sessions, hypnogram și device attribution |
| Habits | Date locale, RPC-uri/cache și `SyncScope.Habits` | Coalescing al evenimentelor, reîncărcări incrementale, UI optimist după scriere locală | Nu rescriem un eveniment local nou cu un snapshot vechi |
| Finances | Widget-ul încarcă serial macro, heatmap, net worth, accounts, holdings și crypto | Afișăm ledger-ul local imediat; world/stocks în paralel când independente; lazy pentru pagini nevizibile | Moneda configurată; fără cotații demonstrative prezentate drept live |
| Calendar | Cache local și sync conturi, lock per încărcare | Un snapshot comun pentru widget și hub; refresh incremental și import async | Recurring events, all-day și timezone-urile trebuie conservate |
| TagDoS | Citește streams/notes, reconstruiește pills | Actualizări pe ID, păstrarea editorului/focusului, priorități comune cu briefing-ul | Parser-ul și acțiunile specifice TagDoS rămân sursa de adevăr |
| News | Cache și agregare distribuite între control, hub și briefing | Serviciu comun de feed aggregation/cache, rezultate parțiale și selecție protejată | SmartReader/WebView2, Medium login și preferințele de feed |
| Glance/tray | Weather este încărcat înaintea health/habits în același flux | Snapshot imediat; fetch-uri independente și actualizare numai cât suprafața e relevantă | Quick-add water/smokes și quick note rămân native |

### Health: trei contracte care merită corectate înainte de polish

1. **`PullDeltasAsync` nu așteaptă în prezent rezultatul remote.** Golește cache-ul de memorie și așteaptă o metodă care afișează localul și pornește refresh-ul remote fire-and-forget. Un apelant poate crede că are deja date cloud proaspete. Nu trebuie etichetat succes de sync la acel moment.
2. **`DispatchToUI` folosește dispatcher-ul thread-ului curent.** Într-un callback background poate să nu existe, iar fallback-ul execută acțiunea direct. Widget-ul Health își face propriul dispatch, dar contractul serviciului rămâne ambiguu și poate afecta alți consumatori. Dispatcher-ul UI trebuie capturat explicit sau fiecare consumator trebuie să aibă un contract documentat.
3. **Listener-ele serviciului nou nu urmează complet precedentul remediat.** În constructorul HealthHubService sunt lambda-uri inline pentru auth/socket, cu re-creare la `TokenRefreshed`. D02 explică de ce alte servicii păstrează delegate puternice și evită re-creări redundante. Este un risc de regresie de investigat prin GC/reconnect tests, nu dovada că se pierde conexiunea în orice sesiune.

În plus, cache-urile memorie/SQLite pentru health sunt adresate în implementarea citită prin data locală. Introducem teste de schimbare a contului și resetare a stării înainte de a le reutiliza pentru briefing. Nu declarăm izolare cross-account doar pentru că request-ul remote filtrează `user_id`.

## 11. News și reader: optimizăm fără a pierde avantajul WinUI

### 11.1 Ce este deja solid

Traseul Windows încearcă HTTP + SmartReader, apoi browser real când extragerea nu reușește. Pentru Medium preferă browser-ul pentru a păstra autentificarea. Curăță metadate, deduplică imaginea principală, generează un template de lectură propriu și integrează recomandări și salvare.

Aceste mecanisme sunt mai importante decât „paritatea vizuală” a cardului de știre. Chiar implementarea Apple descrie explicit mai multe elemente ca paritate cu Windows.

**Nu avem un corpus comparativ măsurat care să demonstreze un clasament al motoarelor**, dar există suficientă valoare verificabilă pentru a trata reader-ul Windows ca activ de protejat.

### 11.2 Probleme concrete de orchestrat

**N01 — Schimbarea rapidă a feed-ului. C/R, P1.**

`SelectFeed` pornește încărcarea fire-and-forget, iar pagina încearcă și ea să o aștepte. Flag-ul global `IsLoading` poate ignora cererea noului feed dacă există una în curs. Rezultatul precedent poate publica `Items` după ce selecția s-a schimbat.

Soluție: task per feed/cache key, selecție separată de fetch, generation ID și verificare înaintea publicării. Anulăm interesul consumatorului vechi; cererea comună poate rămâne activă pentru alți consumatori.

**N02 — Cache distribuit și fără freshness uniformă. C, P1.**

Hub-ul are dicționar static `_allFeedsCache`, widget-ul are propriile trasee pentru All News/Medium, iar briefing-ul poate colecta din nou feed-uri. Cache-ul hub-ului nu are timestamp/TTL în valoare, iar `_isPreFetchingAllFeeds` nu este resetat la încheierea batch-ului.

Soluție: promovarea cache-ului în serviciul news, cu cheie normalizată, TTL, invalidare la editarea abonamentelor și scope de cont unde este necesar. Nu păstrăm o copie per suprafață.

**N03 — Toate feed-urile sunt așteptate înaintea agregării. C, P1.**

All News face `WhenAll`, apoi afișează câte două articole/feed în ordinea selectorului. Un feed lent întârzie toate rezultatele.

Soluție: afișăm întâi cache-ul, apoi rezultatele disponibile în batch-uri mici, cu concurrency limit. Păstrăm echilibrul editorial și ordinea configurată; nu schimbăm automat în sortare cronologică globală doar fiindcă macOS o folosește.

**N04 — Reader-ul are așteptări fixe și polling costisitor. C/H, P1.**

Fallback-ul așteaptă două secunde după navigare, apoi poate verifica până la 20 de ori la interval de o secundă, cu limită exterioară de 30 s. La fast path se ascunde loading-ul imediat după `NavigateToString`, nu după confirmarea că documentul util este gata.

Soluție:

- mașină de stări explicită: metadate → extracție HTTP → extracție browser → document de lectură gata;
- readiness DOM/content cu praguri și deadline, nu eliminarea necondiționată a tuturor așteptărilor;
- `NavigationCompleted` și identificarea documentului corect;
- anulare la Back/închidere/selectarea altei recomandări;
- dezabonare handler în `finally`, inclusiv timeout înaintea unui eveniment de navigare;
- rezultat ignorat dacă article ID-ul nu mai este activ.

**N05 — Extragerea și prezentarea trebuie separate, nu simplificate excesiv. P1.**

Propunere minimă: extragem logica de operație într-un serviciu/testable coordinator care returnează un rezultat tipizat și progres de etapă. UI-ul păstrează WebView-ul și controalele native.

Nu recomand „doar HTTP” sau „doar browser”: primul pierde paginile dinamice și autentificarea, al doilea scumpește inutil articolele simple.

### 11.3 Cache și citire offline

Read Later/Favorites persistă metadate; asta nu dovedește că HTML-ul complet și imaginile necesare sunt salvate pentru citire offline.

O îmbunătățire separată, utilă:

- cache de articol extras după URL canonic, versiune extractor și profil relevant;
- buget pe disc și evacuare LRU;
- starea „disponibil offline” explicită;
- persistență prioritară pentru articolele salvate, nu scraping agresiv al tuturor feed-urilor;
- respectarea autentificării, drepturilor de acces și termenilor sursei; nu folosim optimizarea ca mecanism de ocolire a paywall-urilor.

### 11.4 Gate obligatoriu pentru reader

Înainte și după schimbări, comparăm un corpus stabil, licit, cu HTML fixtures proprii sau permise:

- RSS/Atom și WordPress JSON;
- articol scurt, foarte lung, cu imagini, listă, tabel și blocuri de cod;
- diacritice, encodări diferite, link-uri/imagine relative;
- pagină JavaScript și pagină indisponibilă;
- Medium autentificat/neautentificat;
- timeout, redirect, lipsa articolului și eroare de extragere;
- Back/recomandări/pop-out în timp ce extracția este în curs.

Gate-ul cere aceeași sau mai bună fidelitate a conținutului accesibil, fără regresie de autor, data publicării, imagine, link-uri și sesiune. Viteza nu compensează pierderea conținutului.

## 12. Design: mai coerent, nu mai „macOS”

### 12.1 Principiul vizual

**Păstrăm Fluent/WinUI la nivel de shell și interacțiune; rafinăm ierarhia, densitatea și mișcarea la nivel de produs.**

| Păstrăm | Rafinăm | Nu copiem |
|---|---|---|
| Mica și title bar Windows | Mai puține straturi de glow/border simultane | Butoane „traffic lights” |
| Segoe UI/Fluent icons și controale native | Tipografie și spacing tokenizate | SF Symbols sau font rounded peste tot |
| Sidebar/capsule și scurtături Windows | Comportament identic al comenzilor în toate ferestrele | Convenții exclusiv Command/macOS |
| Glass aging/wipe ca opțiune | Intensitate mai mică, fără afectarea contrastului | Blur permanent pe fiecare suprafață |
| Docking și multiwindow | Restaurare focus/poziție coerentă, DPI și monitor changes | Sheet/modal impus pentru orice acțiune |
| Dashboard cu span-uri | Hierarchy: informație principală, supporting metric, acțiune | Grilă fixă doar pentru a semăna cu Apple |

### 12.2 Un set mic de tokens

Recomand centralizarea token-urilor deja răspândite în resurse:

- spacing pe o scară coerentă, nu corecții individuale;
- trei niveluri de text: principal, secundar, metadata;
- două-trei raze de colț, cu excepții explicite pentru capsule;
- separarea accentului de culoarea semantică success/warning/error;
- durate de mișcare scurte pentru navigare și ceva mai ample doar pentru momentele de expresie;
- stări hover/pressed/focus coerente între controale proprii și native.

Nu propun un design system nou sau o temă terță. Există deja resurse light/dark în WinUI.

### 12.3 Adaptive layout

Trei moduri de discutat, nu breakpoints impuse fără testare:

1. **Compact/docked:** o singură coloană, navigație condensată, reader prioritar.
2. **Desktop standard:** dashboard flexibil și hub în aceeași fereastră.
3. **Wide/master-detail opțional:** dashboard sau context în stânga, hub/reader în dreapta.

WinUI are deja ferestre separate și docking. Master-detail trebuie să fie **o opțiune suplimentară**, nu înlocuitorul lor și nici un proiect prealabil obligatoriu pentru performanță.

Recomand aplicarea graduală: mai întâi News, unde lista + reader este naturală; apoi evaluăm dacă dashboard + hub merită costul vizual și de memorie.

### 12.4 UX de încărcare

- Refresh cu date existente: indicator discret, conținut utilizabil.
- Prima încărcare fără date: skeleton limitat sau placeholders de dimensiune stabilă.
- Offline cu cache: datele rămân, timestamp și avertizare neintruzivă.
- Eroare fără cache: stare utilă și Retry; fără exemplu inventat.
- Succes parțial: cardurile bune nu sunt penalizate de o sursă lentă.
- Scroll-ul, selecția și focusul nu sar după refresh.

### 12.5 Accesibilitate și „nativ”

De verificat runtime, nu presupus din prezența controalelor native:

- Narrator/UI Automation, nume accesibile pentru butoanele icon-only;
- navigare Tab, focus vizibil, Enter/Space și Escape;
- focus trap și restaurare focus pentru overlay-ul briefing;
- contrast light/dark/high contrast, inclusiv în reader HTML;
- text scaling 100–200%, DPI 100/150/200% și mutare între monitoare;
- reduced motion și setarea de transparență;
- touch targets adecvate și mouse wheel/trackpad previzibile;
- shortcut-urile existente păstrate, iar acțiunile disponibile indiferent de pagina activă.

Nu avem în această analiză dovada unui eșec de contrast măsurat. Acesta este un gate de validare, nu un verdict vizual.

## 13. Smart Briefing Windows: punctul de plecare real

WinUI nu pornește de la zero. Are deja:

- agregare weather, health, habits, finances, calendar, todos și news;
- cache local SQLite, fallback JSON și sync în `smart_briefings`;
- praguri de schimbare a metricilor;
- modele locale și selecție accelerator;
- fallback determinist;
- overlay adaptiv, carduri și chat contextual.

Ce lipsește față de direcția macOS este mai ales **un record structurat stabil, o prezentare pe secțiuni și o strategie de livrare care nu condiționează afișarea de AI**.

### 13.1 Defecte care preced portarea experienței

#### B01 — Ramura `onlyLocal` poate eșua pentru un ledger existent

**C, P0, încredere ridicată din cod.**

În `LoadBriefingMetricsAsync`:

1. `WatchlistStocks` începe ca listă goală.
2. Atât fetch-ul cotațiilor, cât și completarea fallback se fac numai când `onlyLocal == false`.
3. Dacă există accounts/holdings, `hasLedgerData` poate fi `true`.
4. Construirea `financeSentence` accesează `WatchlistStocks[0]`, în afara catch-ului de agregare financiară.
5. Cache manager-ul începe tocmai cu `onlyLocal: true`.

Rezultatul permis de cod: excepție de index pe această ramură, task de pre-generare faulted și închiderea overlay-ului prin catch-ul UI. Nu afirm că procesul întreg se prăbușește; UI-ul are handler de eroare.

**Remediu propus:** independența narațiunii de ledger față de existența cotațiilor; zero acces pe index fără verificare și test „accounts există, quotes lipsesc, onlyLocal”.

Surse: [colectare financiară](../WinUI/Daily.WinUI/Services/SmartBriefingService.cs#L495), [accesul pe index](../WinUI/Daily.WinUI/Services/SmartBriefingService.cs#L551), W14.

#### B02 — Fallback-uri demonstrative se pot prezenta ca date reale

**C, P0.**

În Windows există:

- vreme inițială `21.5`/`sunny` și forecast generat prin offset-uri;
- cotații MSFT/AAPL hardcodate în briefing;
- titluri de știri demonstrative dacă lipsesc recomandările;
- cotații hardcodate în widget-ul Finances dacă API-ul nu livrează date.

Acestea nu sunt doar skeleton-uri: intră în modele, text și pot ajunge în cache/cloud.

**Remediu propus:** `null`/unavailable și sursă/timestamp; exemple numai într-un mod demo explicit. „Nu am cotații actualizate” este preferabil unei valori plauzibile, dar false.

Surse: [weather fallback](../WinUI/Daily.WinUI/Services/SmartBriefingService.cs#L243), [forecast](../WinUI/Daily.WinUI/Services/SmartBriefingService.cs#L385), [quotes](../WinUI/Daily.WinUI/Services/SmartBriefingService.cs#L542), [news](../WinUI/Daily.WinUI/Services/SmartBriefingService.cs#L885), [Finances widget](../WinUI/Daily.WinUI/Controls/FinancesWidgetControl.xaml.cs#L224).

#### B03 — „Doar local” nu este garantat de interfețele folosite

**C/R, P1.**

Agregarea locală apelează API-uri generale de metrici health și holdings. Health poate ajunge la remote când nu există cache, iar holdings pot necesita quotes. Numele flag-ului nu garantează lipsa rețelei.

**Remediu propus:** briefing-ul citește snapshot-urile deja colectate, cu availability/freshness, fără să orchestreze el fetch-uri ascunse.

#### B04 — Pre-generarea pornește și înaintea verificării opțiunii de afișare

**C, P1.**

MainPage pornește task-ul de pre-generare, apoi verifică `EnableSmartBriefing` pentru prezentarea automată. Dezactivarea opțiunii nu oprește automat munca de colectare/inference pe acest traseu.

**Remediu propus:** opțiuni separate și clare pentru funcție, prezentare automată și pregătire în background; dezactivarea funcției oprește și lucrul inutil.

#### B05 — Invalidation-ul nu acoperă coerent identitatea, data și toate secțiunile

**C/R, P1.**

Cache-ul are praguri utile, dar schimbarea slotului este comparată fără o regulă generală explicită „aceeași zi”. Date neschimbate pot prelungi o narațiune; fallback-ul din Settings nu este indexat explicit prin user. Alte câmpuri, de exemplu finance/sleep și modificări în sens descrescător ale progresului, nu sunt tratate de toate pragurile locale.

În plus, la reutilizarea narațiunii se actualizează metricile separat; textul poate rămâne în urmă față de valorile vizuale.

**Remediu propus:** cache key versionat și snapshot coerent, cu teste pentru zi nouă, schimbare cont, corecție de log și schimbarea configurării.

#### B06 — CancellationToken nu traversează motorul local

**C, P1.**

Interfața de intelligence primește token, dar apelul non-streaming către AIManager/engine nu îl transmite; interfața motorului nici nu are parametru de anulare. `WithCancellation` pe enumerator nu dovedește oprirea operației native. Închiderea overlay-ului oprește typewriter-ul, nu neapărat inference-ul.

**Remediu propus:** anulare end-to-end unde provider-ul permite; altfel rezultat ignorat sigur, task observat și nicio nouă inference concurentă până la terminarea/oprirea celei existente.

## 14. Experiența de briefing propusă

### 14.1 Paritate de produs

Păstrăm sloturile efective din codul comun:

| Slot | Interval local | Accent |
|---|---|---|
| Morning | 05:00–11:59 | Recuperare, vreme, calendar și focus |
| Intraday | 12:00–16:59 | Ritm, hidratare, priorități și schimbări relevante |
| Evening | 17:00–21:59 | Recapitulare și pregătirea încheierii zilei |
| Nightly | 22:00–04:59 | Ton calm, odihnă, fără presiune de productivitate |

Documentul D03 menționează în unele locuri granița de 18:00; modelele și testele Apple folosesc 17:00, la fel ca sloturile cache-ului Windows. Pentru implementare alegem un singur contract și actualizăm documentația, nu păstrăm ambele interpretări.

Secțiuni recomandate:

1. Salut și rezumat de context.
2. Weather.
3. Health/sleep și, separat unde există date, stress.
4. Habits: hidratare și reducerea consumului de tutun, cu limbaj empatic.
5. Finances: ledger/cash flow și piețe numai dacă există date proaspete.
6. Calendar și tasks — **extensie Windows păstrată**, nu sacrificată pentru șase carduri identice.
7. TagDoS: urgent/driving pills și note relevante, nu doar număr de stream-uri.
8. News radar cu link spre articolele reale și diversitate de surse.
9. Încheiere contextuală, fără recomandări medicale sau financiare prescriptive.

Un hub dezactivat sau fără informații nu produce un card plin de numere zero. Cardul se ascunde sau explică lipsa, după utilitate.

### 14.2 Livrare în două momente, cu trei surse posibile

```text
Snapshot-uri locale consistente
        |
        v
Reguli deterministe -> record util, afișabil imediat
        |
        +-> cache valid pentru aceeași identitate/zi/slot/versiune
        |
        +-> enhancement opțional: model local SAU Gemini
                 |
                 v
          validare de structură și fapte
                 |
          înlocuire controlată a textului
```

„Tier 0/1/2” sunt etichete de explicare, nu obligația de a executa trei generări succesive:

- **Baza deterministă:** funcționează fără model și fără cheie; nu există cost de download.
- **Model local:** îmbunătățește formularea și conexiunile între informații permise.
- **Gemini Flash:** opțional, cu cheie și acord explicit pentru datele trimise.

Nu pornim local și cloud în paralel la fiecare refresh doar pentru a alege câștigătorul. Crește costul, consumul și numărul rezultatelor concurente.

### 14.3 UI nativ Windows

- Carduri tipizate XAML, cu metrică/badge, timestamp și acțiune spre hub.
- Un rezumat scurt, nu un monolog care repetă fiecare metrică.
- Reveal opțional; conținutul disponibil integral printr-o acțiune și pentru Narrator.
- Layout o coloană în docked; două coloane numai când spațiul este suficient.
- Focus și Escape corecte; revenire la controlul care a deschis briefing-ul.
- Indicator explicit: „Sinteză locală”, „AI local — model/accelerator”, „Gemini — model”.
- Dacă enhancement-ul eșuează, păstrăm baza, dar explicăm discret că nu s-a aplicat AI-ul. Nu afișăm succes AI fictiv.
- Afișare automată propusă: cel mult o dată dimineața pe zi, opt-in/configurabilă; badge pentru celelalte sloturi. Nu întrerupem citirea sau editarea.
- Chat-ul Windows rămâne disponibil, cu istoric limitat la bugetul de context și cu citarea secțiunilor relevante.

### 14.4 Invariantele datelor

Numerele și starea de fapt vin din codul domeniului, nu sunt calculate de LLM:

- Litri/ml, ore/secunde, Celsius/Fahrenheit și currency code sunt explicite.
- Somnul se bazează pe sesiunea canonică, nu pe o valoare veche găsită fără context de zi.
- `0` este valoare numai când măsurătoarea există; lipsa este `null`/unavailable.
- Nu inventăm stress score, prognostic, forecast, preț sau titlu de știre.
- Fiecare secțiune are provenance și ultima actualizare reușită.
- O corecție de date poate invalida narațiunea și când valoarea scade.
- Sursa AI nu poate modifica metricile, configurația, tranzacțiile sau task-urile.
- Textul medical/financiar rămâne informativ și prudent; nu punem diagnostice sau instrucțiuni de tratament/investiții.

Pentru garanții mai bune decât „verificăm dacă LLM-ul a schimbat o cifră”, generăm afirmațiile numerice în C# și permitem modelului să selecteze/lege acele fapte sau să returneze referințe la ID-urile lor. Validarea semantică a unui text liber nu este infailibilă.

## 15. Modele locale: avantajul Windows, dar cu un buget real

### 15.1 Ce există

Download manager-ul definește Llama 3.2 1B, Qwen 2.5 1.5B, Gemma 3 1B și Phi 3.5 Mini, cu fișiere estimate de aproximativ 0,7 / 0,95 / 0,75 / 2,7 GB. Acestea sunt estimări din manifest, nu măsurători actuale sau RAM necesar.

Motorul GGUF folosește context de 8192 și maximum 1024 tokeni de output; nu putem considera limita de 10.000 caractere din prompt echivalentă cu un buget de tokeni.

### 15.2 Îmbunătățiri recomandate

| Zonă | Propunere |
|---|---|
| Readiness | Stări separate: unsupported, needs download, downloaded, loading, ready, generating, failed |
| Selecție provider | Alegere reală după capabilitate și preferință; fără a promite NPU tuturor PC-urilor |
| Context | Buget de tokeni per model; rezervă pentru răspuns și istoric; trunchiere pe secțiuni, nu tăiere arbitrară de string |
| Prompt template | Template din metadata/model când posibil; test per familie și backend, nu presupunere că orice GGUF acceptă același chat format |
| Concurență | Inițializare deduplicată și o politică explicită pentru inference; nu schimbăm/dispunem weights în timp ce sunt folosite |
| Responsivitate | Inference în afara UI thread-ului și limită CPU care nu sufocă scroll/reader |
| Memorie | Lazy load după primul frame util; unload după inactivitate unde este sigur; monitorizare RAM/VRAM |
| Energie | Background enhancement redus pe baterie; niciun model încărcat doar pentru a afișa Settings |
| Download | Progres, anulare, fișier temporar și validare a pachetului înainte de activare |
| Eșec | Fallback determinist imediat și stare vizibilă; fără reîncercare agresivă la fiecare randare |
| Măsurare | Warm/cold load, time-to-first-token, timp total, peak RAM/VRAM, consum și fidelitate factuală |

Nu recomand acum un „model câștigător” fără benchmark pe hardware-ul țintă și în română/engleză. Un model de 1B poate fi suficient pentru reformularea faptelor, nu neapărat pentru raționament medical sau corelații robuste.

### 15.3 Windows AI: atenție la schimbările platformei

Implementarea curentă restrânge Phi Silica la hardware detectat ca Qualcomm și tratează Intel/AMD NPU ca fallback. Aceasta este **politica aplicației curente**, nu o afirmație universală despre toate API-urile Windows AI.

Documentația Microsoft consultată la 27 octombrie 2026:

- descrie Phi Silica pe NPU și anumite GPU-uri, dar calea GPU are precondiții experimentale distincte de proiectul curent;
- anunță tranziția către **Aion Instruct**, cu rollout Insider în noiembrie 2026 și retail/removarea Phi Silica planificate pentru ianuarie 2027;
- cere atenție la readiness și acord pentru provisioning/download.

**Consecință:** păstrăm abstracția provider-ului Windows AI, dar nu investim într-un refactor rigid „Qualcomm-only Phi pentru totdeauna”. Pregătim un spike separat de compatibilitate înainte de schimbarea SDK/OS/modelului. Nu introducem dependențe Insider și nu facem upgrade de toolchain ca parte implicită a fluidizării.

Sursă: [Microsoft — Phi Silica](https://learn.microsoft.com/en-us/windows/ai/apis/phi-silica).

## 16. Gemini Flash: integrare Windows recomandată

### 16.1 Politica de utilizare

O cheie configurată face provider-ul disponibil; nu este suficientă pentru a presupune acordul trimiterii tuturor datelor personale.

Moduri propuse:

| Mod | Comportament |
|---|---|
| Standard/local rules | Fără LLM, fără cheie |
| AI local | Numai model disponibil pe dispozitiv |
| Gemini | Enhancement cloud când există cheie, acord și rețea |
| Automat, prefer local | Local dacă este pregătit; cloud numai dacă utilizatorul a permis explicit fallback-ul |

Este o propunere de politică pentru discuție, nu necesitatea a patru ecrane sau a unui routing framework generic.

### 16.2 Modelul cloud

Clientul Apple folosește în cod `gemini-2.5-flash` cu fallback `gemini-1.5-flash`. Nu trebuie portat mecanic.

La data consultării, documentația oficială enumeră și `gemini-3.8-flash`, fără dată de shutdown anunțată; nici pentru `gemini-2.5-flash` nu anunță shutdown în tabelul consultat. Pentru implementare:

1. Alegem un model Flash stabil și disponibil proiectului real.
2. Validăm schema, latența, costul și limba înainte de stabilirea default-ului.
3. Păstrăm model ID într-un loc central, cu migrare explicită dacă este retras.
4. Nu încercăm automat un model vechi la orice eroare, inclusiv cheie invalidă sau quota.

Nu este necesar cel mai nou model pentru orice briefing și nu presupunem că „Flash” garantează aceeași latență în toate condițiile.

### 16.3 Contract tehnic minim

- Client HTTP reutilizat; operația are `CancellationToken` și deadline total.
- Structured JSON output prin schema suportată de model/API, nu schema numai în prompt.
- DTO de secțiuni; limite de lungime și validare obligatorie la deserializare.
- Verificarea statusului HTTP, a candidatului, a motivului de terminare și a răspunsului blocat/trunchiat.
- Nu afișăm JSON parțial sau tokeni nevalidați drept narațiune finală.
- Deadline propus: **3,5 s pentru întreg enhancement-ul interactiv**, nu 3,5 s per încercare. Este un buget al aplicației, nu un SLA Google.
- La timeout, baza deterministă este deja vizibilă. Nu așteptăm un lanț local → primary cloud → fallback cloud.
- Reîncercări cu backoff numai pentru erori tranzitorii și numai dacă mai există buget; respectăm `Retry-After`.
- 401/403: notificare despre cheie/permisiuni; 429: quota/rate-limit; 5xx/rețea: stare temporară. Fără retry loops la fiecare deschidere.
- Dedupe pentru aceeași cheie de snapshot; nu apel cloud la fiecare click sau tick.
- Jurnal de usage minimal: provider/model, latență, tokeni raportați, rezultat și motiv de fallback.
- Buget zilnic/perioadă de cooldown propuse pentru protecție de cost; cifrele exacte se decid după utilizare.

Rate-limit-urile Google sunt în general per proiect, nu per cheie. O aplicație care își ține propriul contor nu poate garanta singură quota/costul total al proiectului utilizatorului.

### 16.4 Chei, date personale și sync

- Cheia utilizatorului într-un storage Windows adecvat, nu în `AppSettings` serializat, SQL, repo sau cache-ul briefing-ului.
- Există precedent de `PasswordVault` în [persistența sesiunii Windows](../WinUI/Daily.WinUI/Services/WinUISessionPersistence.cs#L101); îl evaluăm pentru reutilizare, fără a amesteca resursele/conturile.
- UI: key masked, test explicit, schimbare/ștergere și stare reală; „salvată” nu înseamnă „validă”.
- Payload minim: metrici agregate, nu tot ledger-ul sau istoricul de sănătate.
- Calendar, notes și titlurile TagDoS pot fi sensibile: opt-in pe domenii înaintea cloud-ului.
- Excludem sau anonimizăm locația exactă și identificatori neesențiali.
- Metadatele news/calendar/notes sunt date neîncrezute, nu instrucțiuni: fără tool execution și fără acțiuni automate dictate de textul lor.
- Logging fără cheie, prompt complet cu date private sau URL cu cheia în query string; preferăm mecanismul de autentificare în header suportat de API.
- Consimțământ separat pentru generare cloud, sync de narațiune și Smart Behavior.

Acestea sunt cerințe de proiectare pentru noua integrare, nu un audit de securitate complet al aplicației.

## 17. Cache, record și compatibilitate cross-platform

### 17.1 Snapshot și cheie de cache

Cheia recomandată:

```text
user/profile + local date + timezone + time slot
+ narrative schema version + prompt/rules version
+ locale + units + currency + enabled sections
+ semantic data fingerprint + generation policy/model
```

Nu toate componentele trebuie concatenate într-o cheie SQL; pot fi metadata validate explicit. Important este contractul.

Fingerprint-ul:

- folosește bucket-uri numai acolo unde o schimbare mică nu schimbă mesajul;
- include prioritățile TagDoS, calendar/tasks, sesiunea de somn și starea surselor;
- include scăderi/corecții, nu doar progres crescător;
- separă timestamp-ul ultimei observații de momentul generării textului;
- nu invalidează AI-ul numai fiindcă s-au schimbat secunde fără efect semantic.

Nu reutilizăm textul de ieri doar fiindcă pașii și temperatura se află în aceleași bucket-uri. La trecerea de slot/zi/timezone facem re-evaluare.

### 17.2 Record propus, fără rescriere de backend

Reutilizăm ideea existentă de `SmartBriefingRecord`:

- identitate, zi/slot și `generatedAt`;
- metrici tipizate, nullable, cu availability/provenance;
- secțiuni de narațiune cu ID stabil;
- provider/model, versiune de schemă și fingerprint;
- momentul ultimei citiri și politica de auto-show păstrate separat de date;
- extra secțiuni Windows pentru Calendar/Todos, compatibile cu clienți care nu le afișează.

Nu cerem un model comun binar C#/Swift. Contract JSON și fixtures comune sunt suficiente.

### 17.3 Tabelele existente și tranziția

Windows folosește [smart_briefings](../Models/SmartBriefingRemote.cs#L7). Apple face upsert în `daily_smart_summaries`, pentru care D04 definește:

- `narrative` și `metrics` JSONB;
- RLS per utilizator în script;
- unicitate **`(user_id, time_slot)`**, nu istoric pe fiecare zi.

Consecințe:

1. Nu declarăm că schema existentă oferă deja arhivă zilnică.
2. Dacă vrem numai ultimul briefing per slot, păstrăm cheia și validăm data recordului.
3. Dacă vrem istoric, este o decizie separată: cheie cu zi locală, retention și migrare.
4. Upsert-ul trebuie să țintească explicit conflictul corect și să reutilizeze identitatea recordului; UUID nou la fiecare generare nu rezolvă singur unicitatea user/slot.
5. Scriptul în repo nu dovedește că migrarea este aplicată sau identică în producție; verificarea deployment-ului se face într-o etapă autorizată.
6. În implementarea Apple analizată, serviciul de briefing publică recordul, dar nu am identificat în acel serviciu un pull echivalent cache manager-ului Windows. Nu presupunem sync bidirecțional complet doar fiindcă există un tabel comun.

### 17.4 Migrare fără regresie

- Citire compatibilă a recordurilor vechi, cu expirare și provenance „legacy”.
- Scriere nouă protejată prin feature flag/configurare de rollout.
- Fără suprascriere reciprocă între narațiuni cu scheme incompatibile.
- Nu ștergem imediat cache-ul/tabelul vechi.
- Test cu WinUI vechi, WinUI nou și client Apple activ simultan.
- Reset explicit la schimbarea contului; never reuse unscoped Settings cache pentru un alt utilizator.
- Păstrăm funcția de briefing veche disponibilă până la validarea celei noi, dar fără a perpetua datele demonstrative ca fallback.

## 18. Catalog prioritar de îmbunătățiri

| ID | Prioritate | Lucrare | Tip | Efort | Dependențe / criteriu de închidere |
|---|---|---|---|---|---|
| A01 | P0 | Corectarea indexării `WatchlistStocks` pe local-only | C | S | Test fără quotes și cu ledger existent |
| A02 | P0 | Eliminarea fallback-urilor demonstrative din weather/quotes/news | C | M | Stări unavailable și fixtures fără rețea |
| A03 | P0 | Readiness explicit pentru preferințe/layout | C/R | M | Zero salvări de layout implicit înainte de hidratare |
| A04 | P1 | Unificarea title bar / keyboard / detail refresh | C | M | Aceeași semantică și feedback pe fiecare hub |
| A05 | P1 | Finalizarea reală a delegate/task-urilor de refresh | C | M | Task complet numai după operația promisă; parțial separat |
| A06 | P1 | Snapshot-uri comune per domeniu | C/R | L | Widget/hub/Glance/briefing converg fără refetch identic |
| A07 | P1 | News cache/aggregation comun și selecție latest-wins | C/R | M | Feed rapid A→B→C fără overwrite întârziat |
| A08 | P1 | Reader cancellable și readiness pe document | C/R/H | M | Back/pop-out/timeout fără handler sau rezultat rămas activ |
| A09 | P1 | Audit HealthHub realtime/dispatch/identity/freshness | C/R | M | GC, token refresh, offline și account switch validate |
| A10 | P1 | Briefing determinist structurat, TagDoS și Calendar/Todos | C | L | Util fără model și fără cheie, cu date corecte |
| A11 | P1 | Provider local cancellable și cu buget de context | C/R | M | Close/disable oprește sau izolează sigur operația |
| A12 | P1 | Provider Gemini și control de date/cost | Propunere | M | A10, cheie protejată, schema și erorile testate |
| A13 | P1 | Cache briefing versionat și compatibilitate Supabase | C/R | M | A10; zi/cont/slot și clienți vechi validați |
| A14 | P2 | Actualizări incrementale colecții și grafice | C/H | M | Scroll/focus păstrate și layout work redus în trace |
| A15 | P2 | Lifecycle pentru aging/timer-e și reduced motion | C/H | S/M | Niciun tick decorativ pentru instanțe inactive |
| A16 | P2 | Lazy loading al UI-ului greu și imagini bounded | C/H | M | Startup/memorie măsurate; reader neafectat |
| A17 | P2 | Finisare Fluent, tokens și accesibilitate | Propunere | M | Matrice light/dark/contrast/DPI/keyboard |
| A18 | P2 | Master-detail opțional, întâi în News | Propunere | L | Nu condiționează A01–A17 și nu înlocuiește pop-out |
| A19 | P2 | Cache offline complet pentru articole salvate | Propunere | M/L | Retention și stare offline explicită |
| A20 | P2 | Spike Windows AI pentru tranziția Phi/Aion | Platformă | M | Separat de release-ul de fluiditate |
| A21 | P3 | Micro-optimizări string/regex/JSON/leaf classes | H | S/M | Numai hot paths demonstrate de profilare |

## 19. Roadmap incremental și sigur

### Valul 0 — Baseline și corectitudine

- Captură Release pe hardware reprezentativ.
- A01/A02/A03 și teste de regresie.
- Instrumentare fără date personale.
- Inventar al contractelor local/remote și al stărilor unavailable.

**Gate:** date reale, layout conservat și niciun cost AI obligatoriu la pornire.

### Valul 1 — Startup și refresh

- Shell local-first, fără barieră de rețea pentru toate cardurile.
- A04/A05 și primele snapshot-uri din A06.
- Nu ascundem datele existente în timpul refresh-ului.
- Coalescing și status comun, reutilizând SyncService.

**Gate:** experiența offline și refresh-ul parțial sunt previzibile; nu apar bucle de sync.

### Valul 2 — News și health robustness

- A07/A08/A09.
- Actualizări incrementale pe feed.
- Politică de lifecycle pentru task-uri și WebView.

**Gate:** corpusul reader-ului nu regresează; sesiuni lungi și resume validate.

### Valul 3 — Smart Briefing modern

- A10/A11/A13, apoi A12.
- UI XAML pe secțiuni și snapshot determinist imediat.
- Local AI și Gemini sunt enhancement-uri, nu condiții de funcționare.

**Gate:** fidelitate factuală, buget de latență și control de date. Nicio nevoie de Gemini pentru testarea bazei.

### Valul 4 — Polish și consum

- A14–A17.
- Profilare comparativă aging on/off, efecte reduse și cache rece/cald.
- Abia apoi A18/A19, dacă scenariile justifică.

**Gate:** păstrăm identitatea WinUI și închidem regresiile de accesibilitate/desktop.

Ordinea nu cere câte un proiect separat pentru fiecare rând. Recomand PR-uri verticale mici, cu comportament observabil și teste, nu un refactor gigantic de MVVM înaintea beneficiilor.

## 20. Ținte de performanță propuse

**Nu sunt rezultate măsurate.** Sunt criterii inițiale de acceptare, de calibrat după Valul 0, pe un PC x64 mainstream și pe ARM64, în build Release. Nu folosim Debug pentru a demonstra fluiditatea.

| Scenariu | Țintă inițială | Mod de verificare |
|---|---|---|
| Primul shell vizibil, warm launch | p95 ≤ 500 ms | Marker launch → frame shell |
| Dashboard util cu identitate și cache locale | p95 ≤ 1 s | Launch → date locale și input funcțional |
| Prima instalare/cache gol | Shell rapid, date progresive; fără deadline unic al tuturor provider-ilor | Trace pe etape, fără blocare globală |
| Navigare hub cu snapshot în memorie | p95 ≤ 100 ms pentru prima prezentare utilă | Input → frame cu date existente |
| Refresh cu date existente | Zero blank-out; feedback vizibil în ≤ 100 ms | Captură UI și test de vizibilitate |
| Scroll/resize pe 60 Hz | p95 frame time ≤ 16,7 ms în scenariile definite | Present/frame pacing și trace UI |
| Scroll pe display 120 Hz | Buget 8,3 ms unde hardware-ul permite | Se raportează separat, nu „120 FPS garantat” |
| UI stalls | Fără pauze > 100 ms în navigare/scroll obișnuite | ETW + CPU stacks |
| Briefing determinist din snapshot | p95 ≤ 50 ms de calcul; prezentare utilă ≤ 150 ms | Stopwatch logic separat de animație |
| Gemini enhancement | Deadline total 3,5 s; baza rămâne disponibilă | Fake server cu latență/error injection |
| Reader deja extras în cache | p95 ≤ 300 ms până la document util pe configurația țintă | Marker articol selectat → DOM de lectură gata |
| Reader nou / browser fallback | Distribuție separată și etape explicite, nu promisiune sub o secundă | Corpus, rețea controlată și timeout |
| Cereri duplicate | Un fetch logic activ per cheie/snapshot în testul concurent | Contor în fake provider |
| Idle după stabilizare, fereastră minimizată | Fără timer-e decorative active; CPU mediu orientativ < 0,5% fără AI/sync activ | 5 minute, proces + WebView, interval documentat |
| Memorie | Fără creștere monotonă după 50 de cicluri hub/reader/briefing | Managed heap, private bytes, WebView și GPU separate |

Latența unui serviciu extern și durata unui download nu sunt sub controlul UI. Acceptarea trebuie să măsoare și **cât de repede aplicația devine utilă**, nu doar când se termină toate operațiile.

### Instrumentare minimă

- `launch`, `identity.local.ready`, `preferences.local.ready`, `shell.first-frame`, `dashboard.local.ready`;
- `refresh.requested/coalesced/started/completed/partial/cancelled`;
- cache hit/miss/stale, cereri active și număr de actualizări UI;
- reader: HTTP, parse, browser nav, DOM ready, reader rendered;
- briefing: snapshot, rules, model load, inference, schema validation, publish;
- provider/model, duration și motiv de fallback, fără prompt-uri sau metrici personale în log.

Folosim un correlation ID per operație și timestamp-uri monotone pentru durate. Nu introducem sincron `File.AppendAllText` pe fiecare frame pentru a măsura frame-urile.

## 21. Plan de validare

### 21.1 Teste existente

- Proiectul .NET de teste identificat este [Daily.Health.Tests](../Tests/Daily.Health.Tests/Daily.Health.Tests.csproj), cu modele canonice, golden fixtures și HealthHubService.
- DailyCore conține teste pentru news, weather, health, habits, finances, layout și [Smart Briefing](../DailyCore/Tests/DailyCoreTests/SmartBriefingTests.swift).
- Testele Swift de briefing verifică sloturi, concatenare, reguli și hash, dar nu demonstrează deadline global cloud, anulare sau toate cazurile de cache.
- Nu am identificat un proiect .NET de teste dedicat orchestrării WinUI news/briefing/startup în inventarul proiectelor de teste.
- Nu am executat aceste suite în acest demers de documentare; existența lor nu este un verdict green.

### 21.2 Teste unitare/contract de adăugat odată cu implementarea

| Grup | Cazuri obligatorii |
|---|---|
| Startup | Sesiune locală cu preferințe lente; timeout auth; offline; prima instalare; zero write de layout înainte de readiness |
| Refresh | Dedupe, force refresh, partial failure, task real așteptat, dispatcher indisponibil, cancel și retry |
| News | Selecție A→B→C cu rezultate inversate, TTL, modificare feed, clear cache, cont schimbat |
| Reader | Fast path/fallback, document vechi întârziat, cancel, timeout, handler cleanup și pop-out |
| Health | GC al listener-elor, token rotation, reconnect, data selectată schimbată, identity reset și rezultat remote tardiv |
| Briefing rules | Null vs zero, ml/L, sleep sec/h, °C/°F, currency, no data, hub disabled și no demo data |
| Briefing cache | Zi nouă în același slot, DST, timezone schimbat, cont schimbat, corecție descrescătoare și versiune nouă |
| Local AI | Model lipsă, backend eșuat, context depășit, cancel la close, change model în timpul generării |
| Gemini | 401/403/429/5xx, timeout total, JSON invalid, secțiune absentă, output trunchiat/blocat și cheie ștearsă |
| Cross-platform | Fixtures JSON C#/Swift, câmpuri suplimentare, client vechi și conflict user/slot |

Pentru deadline/coalescing folosim ceas și provider fake, nu teste dependente de internet sau chei personale.

### 21.3 Scenarii manuale și performance

1. Warm/cold launch, cache valid/stale/gol.
2. Internet bun, offline și rețea lentă cu un provider blocat.
3. 10–20 refresh-uri rapide, în dashboard și în fiecare hub/fereastră.
4. Navigare repetată și reader deschis în timpul sync-ului.
5. Sleep/resume, schimbare rețea, expirare token, tray restore.
6. Fereastră principală, două ferestre detail și Glance deschise.
7. 50 de cicluri de deschidere/închidere reader/briefing și măsurarea memoriei.
8. News cu multe abonamente și articole; histoare health/habits mare.
9. x64 și ARM64; sistem fără NPU; model absent/descărcat; battery saver.
10. Light/dark/high contrast, text scaling, DPI mixt, keyboard-only și Narrator.
11. Gemini configurat/dezactivat/cheie invalidă, cu verificarea explicită a datelor care părăsesc dispozitivul.
12. AI local cu sync briefing dezactivat: niciun upload de narațiune din acea funcție.

Datele de stress test se pregătesc într-un profil de test. Nu activăm seedere istorice pe contul real al utilizatorului pentru a măsura fluiditatea.

## 22. Riscuri și ce nu recomand

| Abordare tentantă | De ce nu este prima alegere |
|---|---|
| Rescriere WinUI în MAUI/WebView/alt framework | Risc mare, pierdere de identitate, nu repară automat contractele async |
| Reproducerea exactă a macOS | Importă limite și convenții nepotrivite Windows |
| Mai multe animații ca „fluidizare” | Pot ascunde latența fără a o elimina și cresc costul UI |
| Înlocuirea SmartReader | Risc major pentru una dintre funcțiile cele mai bune |
| Eliminarea browser fallback | Pierde articole dinamice și sesiuni autentificate |
| Ștergerea tuturor delay-urilor | Unele sunt deadline/debounce legitime; readiness-ul trebuie înlocuit corect |
| `Task.Run` în jurul întregii pagini | Nu face XAML thread-safe și nu asigură consistență |
| `ConfigureAwait(false)` peste tot în controale | Poate muta accesul UI pe thread greșit |
| Paralelizarea tuturor cererilor fără limită | Poate crește contention, consum, quota și latența p95 |
| Un event bus/store global nou | Există servicii/cache/coalescing; începem cu un contract mic și reutilizare |
| `ValueTask`, `Span`, `FrozenDictionary`, sealing în masă | Nu rezolvă blank-out-ul și pot adăuga complexitate fără impact măsurat |
| AI ca sursă de metrici sau medical/financial advisor prescriptiv | Hallucination și risc pentru utilizator |
| Cloud automat doar pentru că există o cheie | Nu respectă neapărat intenția privind datele sensibile |
| Istoric briefing presupus din schema actuală | Unicitatea actuală este per user/slot, nu per zi |

## 23. Decizii propuse pentru discuția următoare

Acestea nu blochează documentul și nu sunt aprobări implicite de implementare:

1. **Acceptăm local-first și refresh fără blank-out drept obiectiv principal?** Recomand da.
2. **Păstrăm aging/wipe?** Recomand da, opțional și mai discret, separat de starea reală de freshness.
3. **Briefing automat numai dimineața?** Recomand default discret, cu badge pentru alte sloturi; utilizatorul poate modifica politica.
4. **Default AI: rules, local sau automat?** Recomand bază rules întotdeauna și enhancement local opt-in; cloud numai cu cheie și acord.
5. **Ce date pot merge la Gemini?** Recomand selecție explicită pe domenii și excluderea textelor sensibile până la opt-in.
6. **Dorim istoric zilnic de briefing sau numai ultimul per slot?** Ultimul per slot minimizează migrarea; istoricul este o funcție separată.
7. **Master-detail merită inclus în prima livrare?** Recomand nu; vine după stabilizarea startup/refresh/reader.
8. **Limba și moneda briefing-ului?** Recomand aceleași preferințe ca aplicația, nu engleză/Lei hardcodate.
9. **Ce hardware definește baseline-ul?** Trebuie ales înainte de fixarea SLA-urilor UI și a modelului local default.

### Prima livrare pe care aș propune-o

Un increment concentrat pe **A01–A05**, plus păstrarea listelor News la refresh și instrumentare:

- repară probleme de corectitudine;
- oferă beneficiu vizibil fără redesign;
- nu schimbă extractorul;
- creează fundația pentru briefing;
- se poate valida independent de orice model AI.

După acest increment discutăm măsurătorile și alegem următorul val. Nu este necesar să aprobăm de la început toate cele 21 de lucrări.

## 24. Sinteza constatărilor de performanță

Clasificarea de mai jos grupează **mecanismele de performanță**, nu toate rândurile backlog-ului și nu toate match-urile scanării.

### 🟡 Moderate — relevante pe traseele urmărite

1. **Barieră globală de startup și stări ascunse.** Impact: date locale existente pot rămâne neafișate până la fereastra de agregare/fade. Fix: readiness local și afișare independentă. Dovezi: W02–W04.
2. **Refresh/task completion neuniform.** Impact: operații suprapuse și feedback care nu reflectă munca reală. Fix: task-uri reale, scope comun și coalescing. Dovezi: W05, W06, C01, C04.
3. **Reconstrucție de colecții și loading cu blank-out.** Impact: layout/binding work și pierderea continuității. Fix: patch după chei și păstrarea conținutului. Dovezi: W11, W12, hub/widget Finances.
4. **Fetch/cache duplicat între suprafețe.** Impact: cereri și derivări repetate pentru aceleași date. Fix: snapshot-uri și request-uri comune. Dovezi: W10–W14, W19.
5. **Reader cu polling/delay și lifecycle incomplet al operației.** Impact: latență evitabilă și rezultate întârziate. Fix: readiness și anulare cu article generation ID. Dovezi: W11, C03.
6. **Decor și typewriter pe timer fără politică completă de vizibilitate.** Impact: muncă UI și consum în afara interacțiunii utile. Fix: lifecycle și Composition/batching unde se justifică. Dovezi: W08, MainPage typewriter.
7. **Blocări sync-over-async și I/O sincron pe trasee UI.** Impact: risc de pauze la Settings/import/persistență. Fix: async end-to-end și coalescing I/O. Dovezi: FeaturesPage, CalendarService, W09.

### ℹ️ Info — de profilat înainte de investiție

1. **Layout dashboard nevirtualizat.** Confirmat structural, dar cu șapte widget-uri implicit; optimizăm numai dacă trace-ul arată cost material sau crește numărul de carduri.
2. **Alocări string/regex/JSON.** Există pattern-uri și lanțuri compuse, dar ele nu justifică un cleanup general înaintea problemelor de orchestrare.
3. **Clase leaf nesealed și optimizări de colecții.** Necesită analiză de moștenire/hot path; nu reprezintă explicația principală a fluidității percepute.

| Severitate | Număr de grupuri | Problema principală |
|---|---:|---|
| 🔴 Critical | 0 confirmate prin măsurători/reproducere runtime | Nu declarăm deadlock, crash de proces sau regresie >10× fără dovadă |
| 🟡 Moderate | 7 | Startup/refresh/prezentare și lifecycle |
| ℹ️ Info | 3 | Optimizări condiționate de profilare |

Separat, B01/B02/A03 rămân priorități de corectitudine P0 în backlog. Lipsa unui „Critical” de performanță măsurat nu le reduce importanța.

### Practici pozitive verificate

- ✅ SyncService are coalescing al cererilor pending.
- ✅ RssFeedService păstrează `Items` până la obținerea noului rezultat și reutilizează clienți HTTP la nivel de serviciu.
- ✅ Weather și location au cache și bugete de timeout; health are citire locală înainte de remote.
- ✅ MainPage folosește navigation cache, iar refresh-ul principal nu reconstruiește în mod obligatoriu grila.
- ✅ Setările Windows au cache de obiect și opțiuni JSON reutilizate.
- ✅ Download manager-ul folosește streaming și expune progres/anulare.
- ✅ Există resurse light/dark, scurtături native, multiwindow și componente XAML compilate.
- ✅ Există teste canonice health și teste Swift de briefing care pot servi drept punct de plecare pentru fixtures comune.

## 25. Referințe oficiale și verificarea documentului

Consultate la 27 octombrie 2026:

- [Microsoft: ListView/GridView performance și virtualizare](https://learn.microsoft.com/en-us/windows/apps/develop/performance/optimize-gridview-and-listview).
- [Microsoft: WebView2 performance](https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/performance).
- [Microsoft: Phi Silica, readiness și tranziția Windows AI](https://learn.microsoft.com/en-us/windows/ai/apis/phi-silica).
- [Google: structured outputs](https://ai.google.dev/gemini-api/docs/structured-output).
- [Google: deprecations/model lifecycle](https://ai.google.dev/gemini-api/docs/deprecations).
- [Google: API keys](https://ai.google.dev/gemini-api/docs/api-key).
- [Google: rate limits](https://ai.google.dev/gemini-api/docs/rate-limits).

Validarea acestui livrabil este documentară: existența surselor referite, coerența ID-urilor și priorităților, inventarul scanării și integritatea diff-ului. Implementarea, trace-urile, benchmark-urile și testele de comportament descrise mai sus sunt lucrări viitoare, nu rezultate pretins obținute.

> **Notă de încredere:** analiza este asistată de AI și poate conține omisiuni sau interpretări greșite. Mecanismele confirmate în cod, riscurile și ipotezele sunt diferențiate intenționat. Recomandările de performanță se validează prin reproducere, profilare și review înainte de aplicarea în producție.
