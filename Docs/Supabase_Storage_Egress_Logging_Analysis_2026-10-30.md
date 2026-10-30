# Analiză Tehnică Supabase: Storage, Egress și Logging

**Data:** 30 Octombrie 2026  
**Proiect:** Daily (`akkfouifxztnfwwiclwg`)  
**Context:** Evaluare detaliată a consumului de resurse în Supabase după implementarea și livrarea noilor funcționalități pe toate platformele native (iOS Schmitz, macOS MenuBar & Desktop, Android Pixel 9 Pro Trapper & Foldable Radar, Windows 11 WinUI 3, watchOS și WearOS).

---

## 1. Rezumat Executiv

Pentru un singur cont de utilizator autentificat (`32b8b75f-a0b0-4686-8519-f790f0b3822a`) rulând pe multiple dispozitive sincronizate în timp real, infrastructura Supabase a procesat în ultimele ~3 săptămâni:
* **~887.500 cereri HTTP PostgREST** (medie de ~40.000 cereri/zi).
* **6.883.196 apeluri interne `realtime.list_changes`** (reprezentând **67,9%** din timpul total de execuție al instanței PostgreSQL).
* **1.600.000+ tranzacții de scriere / ștergere** (596k inserări și 530k ștergeri în `health_telemetry`, 382k actualizări în `health_day_dirty`, 71k ștergeri în `habits_logs`, 16k scrieri în `refresh_tokens`).
* **26.296 înregistrări de subscriere Realtime** (`realtime.subscription`).

**Concluzie principală:** Creșterea este direct corelată cu adăugarea noilor clienți nativi activi (în special daemon-ul de macOS și aplicația WinUI 3 cu refresh silențios), combinată cu câteva bucle de sincronizare excesiv de agresive pe client și broadcast-ul integral al unor payload-uri JSON mari prin WebSockets. Datele reale sunt integre și curate, însă există risipă masivă de apeluri și transfer ce poate fi eliminată fără a degrada experiența fluidă de utilizare.

---

## 2. Metrici Cheie Extrase din PostgreSQL

### A. Dimensiunea Tabelelor și a Indecșilor (`pg_total_relation_size`)

Baza de date are în total **95 MB**. Datele brute din tabele reprezintă doar **6,7 MB**, restul de **72 MB fiind indecși**, din care **67 MB este spațiu mort (bloat)**:

| Schemă | Tabelă | Mărime Date | Mărime Indecși | Mărime Totală | Rânduri Live | Rânduri Dead | Note |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `public` | `health_telemetry` | 3.152 kB | **69 MB** | **73 MB** | ~3.552 | 1 | **67 MB bloat în indecși (33x)** |
| `public` | `habits_logs` | 2.208 kB | 1.656 kB | 3,9 MB | 3.972 | 144 | 1,6 MB bloat din 27k ștergeri |
| `public` | `habits_daily_summaries` | 624 kB | 304 kB | 968 kB | 2.471 | 177 | Normal |
| `auth` | `refresh_tokens` | 224 kB | 552 kB | 816 kB | 1.377 | 173 | 16k scrieri token churn |
| `public` | `health_daily_summary` | 56 kB | 32 kB | 792 kB | 43 | 28 | Include JSONB TOAST |
| `public` | `calendar_accounts` | 152 kB | 32 kB | 376 kB | 8 | 33 | Normal |
| `public` | `behavior_events` | 152 kB | 120 kB | 304 kB | 686 | 12 | Normal |
| `realtime` | `subscription` | 80 kB | 48 kB | 168 kB | 7 | 0 | 26.296 scrieri de subscription |
| `storage` | `objects` | 0 bytes | 64 kB | 72 kB | 0 | 0 | 0 fișiere stocate |
| **Total DB**| — | **6,7 MB** | **72 MB** | **95 MB** | — | — | **WAL: 144 MB** |

### B. Defalcarea Bloat-ului pe Indecșii `health_telemetry` (`inspect db bloat`)

| Index | Dimensiune Disc | Dimensiune Utilă Estimată | Risipă (Bloat) | Factor Bloat |
| :--- | :--- | :--- | :--- | :--- |
| `idx_health_telemetry_external_id` | 20 MB | ~600 kB | **20 MB** | **33.3x** |
| `idx_health_telemetry_user_type_start` | 18 MB | ~650 kB | **17 MB** | **29.2x** |
| `health_telemetry_pkey` | 15 MB | ~620 kB | **14 MB** | **24.4x** |
| `idx_health_telemetry_user_time` | 13 MB | ~600 kB | **13 MB** | **21.7x** |
| `idx_health_telemetry_user_local_date` | 3,2 MB | ~600 kB | **2,6 MB** | **5.2x** |
| **Total Indecși Telemetrie** | **69 MB** | **~3 MB** | **~67 MB** | — |

### C. Top Interogări după Numărul de Apeluri (`pg_stat_statements`)

```
1. realtime.list_changes(...)                                    -> 6.883.196 apeluri (67,9% CPU time)
2. PostgREST set_config(...) [Antet conexiune API]               ->   887.556 apeluri
3. SELECT habits_daily_summaries WHERE user_id = $1              ->   133.911 apeluri
4. pg_publication_tables (Realtime publication checks)           ->   108.637 apeluri
5. SELECT habits_logs ORDER BY logged_at DESC LIMIT $1           ->   104.900 apeluri
6. DELETE FROM habits_logs WHERE logged_at < $1 RETURNING *      ->    71.042 apeluri
7. SELECT habits_goals LIMIT $1                                  ->    63.723 apeluri
```

---

## 3. Analiza Detaliată a Celor 3 Dimensiuni

### A. STORAGE (De ce crește și de ce este stabilizat la 95 MB)

1. **Mecanismul Postgres B-Tree:**
   * Scriptul de retenție pe 48 de ore (`apply_health_data_retention` rulat de `pg_cron` zilnic la 03:00) funcționează perfect: tabela brută are doar ~3.550 rânduri active.
   * Totuși, în fiecare zi intră ~25.000 de înregistrări noi și se șterg ~25.000 de înregistrări vechi. În Postgres, `DELETE` eliberează sloturi în paginile de date, dar **nu reduce dimensiunea fizică a fișierelor B-tree de pe disc** (`.ibd` / relații de index).
   * Generarea de UUID-uri aleatorii și chei externe text distribuie cheile neuniform, provocând fragmentare masivă a paginilor de index.
2. **De ce nu este critic:**
   * 95 MB este o fracțiune mică din limita de 500 MB a tier-ului gratuit Supabase.
   * Nu există scurgere continuă către infinit; dimensiunea s-a plafonat în jurul valorii de 95-100 MB datorită autovacuum-ului care refolosește paginile interne.
   * O simplă comandă `REINDEX TABLE public.health_telemetry;` recuperează instantaneu 67 MB.

---

### B. EGRESS (Trafic de Rețea: Unde se consumă banda?)

Egress-ul a fost generat de două surse majore:

#### 1. Payload-ul mare al `health_daily_summary` difuzat prin Realtime WebSocket
* Tabela `health_daily_summary` face parte din publicația `supabase_realtime`.
* În cadrul tabelei, coloana `summary` stochează un arbore JSON complet (metrice orare, serii de ritm cardiac, stadii hipnice, scoruri agregate, recovery) care măsoară între **18 KB și 22 KB per rând**.
* În ultimele 22 de zile, tabela a înregistrat **7.245 de comenzi de UPDATE**.
* La fiecare recalculare sau salvare efectuată de `health-engine` ori de aplicațiile mobile, Supabase Realtime a împins payload-ul complet de ~20 KB pe conexiunile deschise ale tuturor dispozitivelor active (Mac, iPhone, Pixel, Z Fold, Windows 11).
* Calcul estimativ Egress WebSocket:
  $$7.245\text{ updates} \times 20\text{ KB} \times 4\text{ clienți activi} \approx \mathbf{580 - 750\text{ MB Egress}}$$

#### 2. Bucla de interogări pe Habits Sync (Peste 370.000 cereri PostgREST)
* **În Windows (`WinUI/Daily.WinUI/MainPage.xaml.cs` & `Services/SyncService.cs`):**
  * La fiecare comutare între tab-uri, revenire din fundal sau refresh de widget-uri, se execută `RefreshWidgetsSilentAsync()`, care invocă `_syncService.SyncAsync(SyncScope.All)`.
  * `SyncService` apelează `PullSummariesInternalAsync` (care a adunat **133.911 apeluri** pe `habits_daily_summaries`) și `PullLogsInternalAsync` (**104.900 apeluri** pe `habits_logs`).
  * La fiecare rulare, `PushInternalAsync` execută pasul de mentenanță:
    ```csharp
    // Services/SyncService.cs linia 405 și 1233
    await _supabase.From<HabitLog>()
        .Where(x => x.LoggedAt < safePruneDate)
        .Delete();
    ```
    Această comandă s-a executat de **71.042 de ori**, iar prin natura PostgREST include implicit `RETURNING *`, transmițând înapoi prin HTTP rândurile șterse.
* **În Apple (`DailyCore/HabitsService.swift`) și Android (`HabitRemoteService.kt`):**
  * Dacă apelul RPC `get_habits_consistency` întâmpină parametri nealiniați sau latență, clienții intră pe ramura `4B. Fallback: Dual-Table Ingestion`, descărcând direct tabelele brute cu `limit(5000)`.
* **Bug-ul de deserializare (remediat la commit `598eeb62`):**
  * Până la corecția din 29 octombrie, `DailyCore` pe macOS și iOS eșua la parsarea `health_daily_summary` din cauza lipsei câmpului `id` din modelul de sleep recovery trimis de funcția Deno.
  * Drept urmare, la fiecare 5 minute (ciclul `startActiveSyncLoop`), ambele sisteme Apple considerau sumarele invalide, descărcau toată telemetria brută din `health_telemetry` și apelau Edge Function-ul `health-engine` pentru recalculare forțată.

---

### C. LOGGING (De ce a explodat volumul de loguri?)

Sistemul de Logging Supabase măsoară numărul total de evenimente și linii de jurnalizare generate de toate serviciile integrate:

1. **API Gateway Logs (PostgREST):**
   * Fiecare dintre cele **887.556 de cereri HTTP** trimise de clienți este contorizată cu un eveniment de log complet (metodă HTTP, cale, cod de stare, latență, IP client).
2. **Realtime Engine Logs:**
   * În PostgreSQL, motorul Realtime WALRUS a scanat tranzacțiile apelând `realtime.list_changes` de **6.883.196 de ori**.
   * Conexiunile clienților s-au înregistrat și re-subscris de **26.296 de ori** în tabela `realtime.subscription`. În WinUI, fiecare serviciu (`HabitsService`, `HealthHubService`, `FinancesService`, `TagdosService`, `CosmosLiveService`) instanțiază propriul canal separat și declanșează re-abonare (`forceRecreate: true`) la orice schimbare a stării de autentificare sau rețea.
3. **Auth Logs (GoTrue):**
   * Tabela `auth.refresh_tokens` a înregistrat **16.299 de scrieri**. 
   * Fiecare instanță client își reîmprospătează token-ul JWT la intervale regulate, generând mii de apeluri de refresh autentificare înregistrate în panoul de Auth Logs.
4. **PostgreSQL Autovacuum & Trigger Churn:**
   * Ca urmare a celor 1,6 milioane de operațiuni DML (inserări/ștergeri), autovacuum a rulat de sute de ori:
     * `realtime.subscription`: 227 rulări autovacuum
     * `auth.sessions`: 74 rulări autovacuum
     * `auth.refresh_tokens`: 68 rulări autovacuum
     * `health_telemetry`: 64 rulări autovacuum
   * Trigger-ul `mark_health_day_dirty()` a generat **382.377 de comenzi UPDATE** pe tabela `health_day_dirty` (un update declanșat la fiecare rând de telemetrie inserat).

---

## 4. Fișiere și Mecanisme Identificate în Cod

| Componentă / Fișier | Mecanism Identificat | Impact Direct |
| :--- | :--- | :--- |
| `Services/SyncService.cs:405` | Apel necondiționat `PruneRemoteLogsAsync()` la fiecare sync | **71.042 cereri DELETE** pe `habits_logs` |
| `Services/SyncService.cs:1268` | Paginare de pull pe `DailySummary` fără cache local prealabil | **133.911 cereri SELECT** pe `habits_daily_summaries` |
| `WinUI/MainPage.xaml.cs:311,377` | `RefreshWidgetsSilentAsync` declanșat la navigare între pagini | Multiplică apelurile de sync de zeci de ori pe sesiune |
| `Services/HabitsService.cs:450` | Creare independentă de canale Realtime pe fiecare modul | Multiplică conexiunile și scrierile în `realtime.subscription` (26k) |
| `supabase/functions/health-engine` | Upsert complet de `summary` JSONB (20 KB) în tabelă publicată Realtime | Generează sute de MB Egress WebSocket către toți clienții |
| `DailyCore/HealthDataService.swift:513` | Fallback pe telemetrie brută când deserializarea sumarelor eșua | Sute de interogări masive de telemetrie și trigger-e Edge Function |
| `Postgres: health_telemetry` | Inserare/ștergere 25k rânduri/zi pe indecși B-tree fără REINDEX | **67 MB bloat în indecși** |

---

## 5. Recomandări și Plan de Îmbunătățire

Pentru momentul când se va dori optimizarea consumului, recomandăm abordarea în 3 etape clare:

### Etapa 1: Quick Wins cu Risc Zero (Imediat)
1. **Recuperare Storage (Index Defragmentation):**
   * Rularea comenzii:
     ```sql
     REINDEX TABLE public.health_telemetry;
     ```
   * Reduce instantaneu mărimea bazei de date de la 95 MB la ~25 MB, eliberând 67 MB de spațiu mort.
   * Se poate include un job lunar în `pg_cron` pentru a menține indecșii compacți.
2. **Mutarea Pruning-ului de Habits în Server-Side `pg_cron`:**
   * Eliminarea comenzii `DELETE FROM habits_logs WHERE logged_at < safePruneDate` din clientul WinUI (`SyncService.cs`).
   * Adăugarea unei linii simple în funcția de retenție zilnică existentă (`apply_health_data_retention`):
     ```sql
     DELETE FROM public.habits_logs WHERE logged_at < NOW() - INTERVAL '90 days';
     ```
   * Elimină dintr-un foc peste **70.000 de cereri DELETE** din PostgREST și din logurile API.

### Etapa 2: Optimizare Egress și Realtime (Impact Financiar / Cotă Maxim)
1. **Păstrarea sau Reducerea Payload-ului Realtime pe `health_daily_summary`:**
   * În loc să broadcastăm întregul JSON de 20 KB de mii de ori pe lună către toate telefoanele și computerele, tabela poate trimite un semnal ușor (ex: `local_date`, `computed_at`, `raw_watermark`), iar clienții să facă GET pe rândul complet doar dacă au pagina de Health deschisă pe ecran.
2. **Consolidarea Canalelor Realtime în WinUI:**
   * Gruparea abonamentelor într-un singur canal multiplexat sau inițializarea lor la cerere (*lazy*), doar când utilizatorul accesează hub-ul respectiv (ex: Cosmos, TagDos, Finances), reducând cele 26.000 de tranzacții de subscription.

### Etapa 3: Cooldown și Throttle pe Client Sync
1. **Debounce pe `SyncService.SyncAsync`:**
   * Adăugarea unui cooldown de 3-5 minute pe `SyncScope.All` în WinUI, astfel încât comutarea rapidă între tab-uri sau hub-uri să nu declanșeze interogări repetate către Supabase.
2. **Monitorizarea Deserializării Paritare (Corectată în commit `598eeb62`):**
   * Verificarea faptului că iOS și macOS citesc direct sumarele canonice fără a mai cădea pe fallback-ul de interogare brută a tabelei `health_telemetry`.

---
*Document salvat pentru referință în repo-ul Daily la `Docs/Supabase_Storage_Egress_Logging_Analysis_2026-10-30.md`.*
