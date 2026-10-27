# Analiza performantei WearOS si comparatie cu watchOS

**Aplicatie:** DayOne Orbit / Daily  
**Data analizei:** 27 octombrie 2026  
**Dispozitive vizate:** Pixel Watch 5 si OnePlus Watch 3, conform dispozitivelor de test indicate de utilizator  
**Tipul analizei:** inspectie read-only a surselor, configuratiei, documentatiei si APK-ului local existent  
**Status:** diagnostic si recomandari; nicio optimizare implementata in cadrul acestei analize

## 1. Concluzia principala

**Nu recomand alte compromisuri vizuale inainte de corectarea configuratiei de performanta si a problemelor de arhitectura identificate.**

In implementarea actuala exista motive concrete pentru pornire lenta, tap-uri aparent ignorate, informatii care se actualizeaza tarziu si istoric care pare ca se incarca la nesfarsit.

Aceste simptome au cauze diferite:

1. **Performanta efectiva:** startup, compozitie/layout, initializari, serializare, presiune pe CPU si memorie.
2. **Latenta de interactiune:** urmatoarea actiune este conditionata de raspunsul serverului.
3. **Defecte de actualizare a datelor:** informatia exista, dar interfata nu este notificata corect.
4. **Defecte de incarcare:** utilizatorul poate naviga spre intervale pe care mecanismul de sincronizare nu le descarca niciodata.
5. **Ergonomie:** pe WearOS sunt necesare mai multe gesturi pentru aceeasi operatie decat pe watchOS.

O aplicatie cu doua tipuri de obiceiuri, cateva inele si grafice cu sapte bare nu justifica, prin complexitatea functionala, o experienta foarte slaba pe ceasurile de test. Din inspectia codului nu rezulta un motiv pentru a renunta acum la Compose, la grafice sau la animatiile simple.

**Prioritatea recomandata:** masurare pe un build Release optimizat, interactiuni local-first cu persistenta reala si eliminarea hidratarii complete a cache-ului din calea primului cadru. Defectele de istoric si de propagare a starii trebuie tratate ca buguri, nu ca probleme rezolvabile prin asteptare sau reducerea animatiilor.

## 2. Scop, metodologie si limite

### 2.1. Suprafete analizate

Au fost urmarite implementarile WearOS si watchOS pentru:

- pornire si restaurarea sesiunii;
- paginare, scroll si crown/rotary;
- adaugare si stergere;
- cache in memorie si persistenta;
- sincronizare, offline si concurenta;
- istoric zilnic si saptamanal;
- tiles, complications si actualizari in fundal;
- configuratia build-ului si bibliotecile;
- documentatia optimizarilor anterioare.

A fost inspectat si APK-ul existent, nu doar configuratia Gradle.

Analiza initiala nu a modificat fisiere si nu a executat build, instalare sau deployment. Working tree-ul a ramas curat la verificarile efectuate. Singura modificare solicitata ulterior este salvarea prezentei analize ca document.

### 2.2. Ce este demonstrat si ce necesita masurare

Nu a fost disponibil un ceas conectat pentru masuratori runtime. Serverul ADB verificat initial nu avea dispozitive atasate; verificarile ulterioare nu au furnizat dovezi runtime suplimentare.

Prin urmare:

- defectele descrise sunt verificabile din cod;
- dimensiunile si continutul APK-ului local sunt masurate;
- nu exista in aceasta analiza un procent de jank, timpi de startup sau un profil CPU actual de pe Pixel Watch 5 / OnePlus Watch 3;
- nu este confirmat ca APK-ul local este exact build-ul instalat pe fiecare ceas;
- nu se atribuie procente din lag unor cauze fara masuratori.

Nivelurile de certitudine folosite in document sunt:

- **Constatare:** comportament sau configuratie verificata in surse ori in APK.
- **Impact de masurat:** mecanism plauzibil de cost, fara durata sau contributie runtime cuantificata.
- **Recomandare:** schimbare propusa, neimplementata si nevalidata in aceasta analiza.

### 2.3. Dimensiunea implementarii inspectate

| Suprafata | Fisiere | Linii fizice |
|---|---:|---:|
| WearOS, surse Kotlin din aplicatie | 25 | 4.711 |
| watchOS, aplicatia principala Swift | 14 | 2.980 |
| watchOS, aplicatie si cele doua directoare de widget-uri | 21 | 3.515 |

Aceste numere exclud dependentele si output-ul generat inspectat ca atare. Numarul de linii nu este utilizat drept proxy pentru performanta.

## 3. Configuratia build-ului: primul lucru care trebuie pus in ordine

### 3.1. APK-ul local este Debug si contine mult cod neeliminat

Artefact inspectat: [app-debug.apk](../WearOS/app/build/outputs/apk/debug/app-debug.apk). Este un output local de build, care poate sa nu existe intr-un checkout nou.

| Indicator | Rezultat |
|---|---:|
| Dimensiune APK | 77.111.027 bytes, aproximativ 77,1 MB |
| Build debuggable | Da |
| Fisiere DEX | 17 |
| Dimensiune totala DEX necomprimata | 74.788.116 bytes, aproximativ 74,8 MB |
| Clase definite, aplicatie si biblioteci | 39.698 |
| Clase din familia Material Icons | 11.400 |
| Baseline Profile in APK | Nu a fost gasit |
| Compose UI / runtime efectiv in APK | 1.7.5 |
| Wear Compose efectiv in APK | 1.4.0 |
| ProfileInstaller efectiv in APK | 1.3.1 |
| Min SDK / target SDK | 30 / 34 |
| Data modificarii APK-ului | 13 octombrie 2026, 21:31:23 +0300 |

[Metadatele output-ului](../WearOS/app/build/outputs/apk/debug/output-metadata.json) confirma varianta `debug`.

Nuante importante:

- 77 MB pe disc nu inseamna 77 MB de RAM si nici ca toate clasele sunt incarcate la startup.
- Numarul de DEX-uri nu demonstreaza singur cauza sacadarii.
- Impreuna cu build-ul Debug si lipsa optimizarii, aceste date arata ca artefactul nu este potrivit pentru concluzii finale de performanta.
- APK-ul contine identificatori pentru incarcarea cache-ului si sincronizarea centralizata, dar prezenta lor nu demonstreaza identitatea completa cu sursele curente.
- Ultimul commit relevant a fost creat la aproximativ doua minute dupa timestamp-ul APK-ului. Nici aceasta ordine nu demonstreaza, singura, ca binarul difera de surse; arata necesitatea unei proveniente reproductibile.

### 3.2. Release nu activeaza R8

In [configuratia aplicatiei WearOS](../WearOS/app/build.gradle.kts), varianta Release are:

```kotlin
isMinifyEnabled = false
```

Simpla trecere de la Debug la Release nu ar activa eliminarea codului nefolosit si optimizarile R8.

Material Icons Extended este un exemplu relevant: aplicatia foloseste putine simboluri, dar build-ul actual include mii de clase de iconuri. Prima interventie recomandata este permiterea eliminarii codului nefolosit de catre R8, nu inlocuirea manuala a tuturor iconurilor sau simplificarea designului.

Activarea R8 trebuie insotita de verificarea serializarii, autentificarii si a integrarii serviciilor. Nu este suficienta modificarea unui flag fara validare.

### 3.3. Baseline Profiles nu fac parte din circuitul verificat

Nu a fost gasita infrastructura proprie de benchmark sau generare de profile in proiectul WearOS. APK-ul Debug inspectat nu contine profilul compilat.

Prezenta bibliotecii ProfileInstaller nu demonstreaza ca aplicatia beneficiaza de un profil instalat si aplicat.

Documentatia oficiala pentru [performanta WearOS](https://developer.android.com/training/wearables/compose/performance) recomanda:

- build Release;
- optimizare R8;
- Baseline Profiles, inclusiv trasee de startup;
- masuratori pe dispozitive reale.

**Recomandare:** comparatie controlata intre Debug, Release optimizat si Release cu profile aplicate. Nu se promite un castig procentual specific aplicatiei inainte de test.

### 3.4. ABI-urile si imaginile nu explica dimensiunea principala

APK-ul include biblioteci native pentru patru ABI-uri, dar toate fisierele `.so` identificate insumeaza numai aproximativ 60 KB.

Cele mai mari imagini individuale inspectate sunt sub 100 KB. Grosul artefactului este codul DEX, nu imaginile sau variantele native.

**Nu recomand eliminarea suportului ABI ca prima optimizare de performanta.**

## 4. Startup: cache-ul complet este incarcat inainte de primul cadru

### 4.1. Traseul actual

1. Interfata obtine singleton-ul de sesiune.
2. Constructorul citeste preferinte.
3. Sunt deserializate cache-urile zilnice si saptamanale.
4. Poate continua prima compozitie.

Surse:

- [DailyWearApp](../WearOS/app/src/main/java/com/intellidream/daily/wearos/presentation/DailyWearApp.kt);
- [WatchSessionManager](../WearOS/app/src/main/java/com/intellidream/daily/wearos/data/WatchSessionManager.kt), in special obtinerea instantei si incarcarea cache-urilor.

Citirea si deserializarea celor patru structuri JSON se fac sincron pe traseul UI-ului.

Este un progres ca initializarea clientului Supabase a fost amanata si pornita din corutine de fundal. Nu mai este corect sa atribuim automat startup-ul aceleiasi probleme vechi de creare a clientului pe Main.

Totusi, pentru evitarea unui loading vizibil, implementarea blocheaza primul cadru pana reconstruieste cache-ul complet. Aceasta operatiune nu este gratuita si nu reprezinta o hidratare de 0 ms.

### 4.2. Costul poate creste in timp

Cache-urile zilnice sunt completate la sincronizare, fara o politica identificata de eliminare a zilelor vechi.

Consecinte:

- fereastra descarcata este limitata;
- istoricul acumulat deja in cache nu este limitat in acelasi mod;
- volumul serializat si deserializat poate creste de la o saptamana la alta.

Impactul exact necesita dimensiunea cache-ului de pe ceas si un trace de startup.

### 4.3. Recomandari

- Separarea unui snapshot mic, datat, pentru ecranul initial de istoricul complet.
- Incarcarea istoricului in fundal, nu in prima compozitie.
- Retentie explicita pentru cache.
- Citiri pe interval, fara reconstruirea intregului istoric pentru afisarea zilei curente.

Mutarea acelorasi blob-uri mari in DataStore nu ar rezolva singura problema. Costul deserializarii intregului istoric ar ramane.

## 5. Interactiunile sunt conditionate de viteza retelei

### 5.1. Urmatoarele tap-uri sunt ignorate cat timp cererea este in curs

In [BubblesScreen](../WearOS/app/src/main/java/com/intellidream/daily/wearos/presentation/bubbles/BubblesScreen.kt) si [SmokesScreen](../WearOS/app/src/main/java/com/intellidream/daily/wearos/presentation/smokes/SmokesScreen.kt), adaugarea functioneaza astfel:

1. Primul tap actualizeaza optimist totalul.
2. Este activat un flag de blocare.
3. Cererea este trimisa serverului.
4. Flag-ul este eliberat abia cand cererea se termina.

Tap-urile urmatoare sunt ignorate intre timp. Chip-urile raman aparent utilizabile, fara explicarea clara a blocarii.

Rezultatul perceput:

- aplicatia nu a luat tap-ul;
- trebuie asteptat intre operatii;
- raspunsul variaza cu reteaua;
- experienta se degradeaza pe conexiune slaba sau prin Bluetooth proxy.

**Aceasta este o problema de flux al interactiunii, nu de FPS.**

### 5.2. Diferenta fata de watchOS

In [BubblesView](../WatchOS/DailyWatch/DailyWatch%20Watch%20App/BubblesView.swift) si [SmokesView](../WatchOS/DailyWatch/DailyWatch%20Watch%20App/SmokesView.swift), actualizarea locala nu este conditionata de terminarea cererii precedente in acelasi mod. Exista stare de sincronizare, nu acelasi blocaj al urmatorului tap.

Principiul recomandat pentru WearOS:

> Un tap este acceptat dupa salvarea locala sigura, nu dupa confirmarea cloud.

Daca este necesara protectie impotriva dublei atingeri accidentale, ea trebuie sa fie o regula scurta si explicita de interactiune, nu o blocare cu durata variabila a retelei.

### 5.3. Dispatcher-ele sunt folosite neuniform

Operatia de apa este lansata explicit pe IO, in timp ce smokes porneste corutina pe contextul UI.

Aceasta constatare nu inseamna ca socket-ul blocheaza sincron Main. Totusi, pregatirea operatiei si eventualele costuri anterioare suspendarii raman pe acel traseu.

**Recomandare:** executia trebuie uniformizata in stratul de date, nu decisa separat de fiecare ecran.

## 6. Offline-first: persistenta si reconcilierea sunt incomplete

### 6.1. Coada WearOS exista numai in memorie

[OfflineSyncManager WearOS](../WearOS/app/src/main/java/com/intellidream/daily/wearos/data/OfflineSyncManager.kt) pastreaza operatiile numai in RAM.

Consecinte:

- coada se pierde la terminarea procesului;
- operatia este pusa in coada abia dupa esecul cererii directe;
- sincronizarea face insert-uri unul cate unul;
- nu exista o protectie explicita echivalenta impotriva procesarii simultane;
- stergerile nu au un mecanism offline echivalent;
- un refresh de pe server poate inlocui date locale neconfirmate.

Utilizatorul poate vedea totalul crescand, revenind la o valoare veche si corectandu-se ulterior. Acest comportament este perceput ca instabilitate sau actualizare lenta.

### 6.2. Mutatiile depind de durata de viata a ecranului

Operatiile sunt lansate din scope-ul ecranului. Cand pagina iese din compozitie, acel scope este anulat.

O mutatie de business nu trebuie sa depinda de cat timp ramane pagina compusa. Anularea si tratarea ei drept esec de retea pot complica suplimentar retry-ul si confirmarea rezultatului.

### 6.3. Comparatie cu watchOS

[OfflineSyncManager watchOS](../WatchOS/DailyWatch/DailyWatch%20Watch%20App/OfflineSyncManager.swift):

- persista coada;
- are un guard de sincronizare;
- trimite batch-ul intr-o singura operatie.

Este mai bun in aceste puncte, dar nu trebuie copiat ca implementare perfecta. Citirea/scrierea cozii si golirea dupa upload necesita tratament tranzactional pentru concurenta, inclusiv operatii adaugate in timpul upload-ului.

### 6.4. Arhitectura recomandata

- Salvare locala a logului si operatiei de sincronizat in aceeasi tranzactie.
- Identificator stabil pentru retry idempotent.
- Upload independent de ecran.
- Reconciliere care pastreaza operatiile locale neconfirmate.
- Retry controlat la revenirea conectivitatii si prin mecanismele sistemului.
- Tratarea insert-urilor si a stergerilor ca operatii durabile.

Exista un precedent util in [HabitLogDao din Android](../Android/core-database/src/main/java/com/intellidream/daily/database/dao/HabitLogDao.kt).

Recomandarea nu este importarea intregului modul de telefon in ceas, ci reutilizarea principiilor potrivite.

## 7. Istoricul: unele intervale nu pot fi incarcate prin mecanismul actual

### 7.1. Navigarea si sincronizarea nu cer acelasi interval

Sincronizarea centralizata din [WatchSessionManager](../WearOS/app/src/main/java/com/intellidream/daily/wearos/data/WatchSessionManager.kt) descarca o fereastra fixa in jurul datei curente si construieste grafice numai pentru:

- saptamana curenta;
- saptamana trecuta.

Interfata permite navigarea tot mai in trecut.

Pentru o saptamana de acum trei saptamani:

1. Pagina cauta intervalul in cache.
2. Nu il gaseste.
3. Cere sincronizare.
4. Sincronizarea descarca tot fereastra din jurul zilei de azi.
5. Saptamana selectata nu este construita.

**Asteptarea nu poate rezolva problema. Nu este o cerere lenta, ci intervalul gresit.**

In [Bubbles7DaysScreen](../WearOS/app/src/main/java/com/intellidream/daily/wearos/presentation/bubbles/Bubbles7DaysScreen.kt) si [Smokes7DaysScreen](../WearOS/app/src/main/java/com/intellidream/daily/wearos/presentation/smokes/Smokes7DaysScreen.kt), un cache miss poate lasa graficul anterior sub noul titlu. Pentru zile, absenta cache-ului poate aparea ca zero.

Pe watchOS, [incarcarea saptamanala](../WatchOS/DailyWatch/DailyWatch%20Watch%20App/Bubbles7DaysView.swift) cere exact intervalul selectat.

### 7.2. Activarea paginii nu declanseaza intotdeauna incarcarea

Efectele de incarcare sunt legate de offset si trigger-ul global, dar nu de activarea paginii.

O pagina precompusa, inactiva, poate rata initierea incarcarii pe cache miss. Cand devine activa, simpla schimbare a flag-ului de activitate nu reporneste acel efect.

Rezultatul posibil este un ecran care pare ca asteapta fara sa faca progres.

### 7.3. Recomandari

- Cache hit: afisare locala imediata.
- Cache miss: cerere pentru intervalul selectat.
- Prefetch limitat pentru intervalele vecine.
- Distinctie intre interval neincarcat si interval confirmat gol.
- Declansare corecta la activarea paginii si schimbarea selectiei.

Nu recomand descarcarea intregului istoric la fiecare deschidere drept solutie.

## 8. Cache-ul nu este complet reactiv

### 8.1. Bucket-urile sunt modificate in loc

[Modelele bucket-urilor](../WearOS/app/src/main/java/com/intellidream/daily/wearos/domain/model/Buckets.kt) au campuri mutabile. Actualizarea optimista saptamanala modifica obiectul existent, fara publicarea unei noi stari reactive.

In acelasi timp:

- paginile pastreaza listele in state local;
- media saptamanala este memorata pe baza listei;
- aceeasi lista si aceleasi obiecte pot ramane ca identitate.

Compose nu observa automat modificarea unui camp obisnuit dintr-un obiect aflat intr-un map concurent.

Efecte posibile:

- totalul zilnic se actualizeaza, graficul nu;
- media ramane veche;
- refresh-ul sau reintrarea in pagina pare sa deblocheze datele.

Aceasta este o problema de propagare a starii, nu de viteza de desenare.

### 8.2. Zilele devenite goale pot pastra date vechi

Sincronizarea scrie in map zilele care apar in rezultatul gruparii.

Daca toate logurile unei zile sunt sterse pe alt dispozitiv, acea zi nu mai apare in grupare. Intrarea veche din cache poate ramane.

Absenta rezultatelor nu este reconciliata complet cu datele existente.

### 8.3. Saptamanile sunt persistate dupa offset relativ

Saptamana cu offset zero de azi nu este aceeasi saptamana calendaristica peste sapte zile.

In plus, informatia `isToday` este persistata in bucket. Fara invalidare si recalculare corecta la schimbarea zilei/saptamanii, exista riscul afisarii si actualizarii unui interval vechi.

Si unele valori derivate din data curenta sunt memorate numai dupa offset, ceea ce necesita invalidare explicita cand se schimba ziua fara recrearea ecranului.

### 8.4. Recomandari

- Chei calendaristice absolute.
- Rezultate imuabile sau state observabil corect.
- O singura sursa de adevar.
- Inlocuire atomica a intervalului sincronizat, inclusiv zilele goale.
- Invalidare la schimbarea datei, fusului orar si contului.
- Actualizari specifice intervalului si obiceiului afectat.

## 9. Persistenta face prea multa munca pentru fiecare actiune

Salvarea cache-urilor din [WatchSessionManager](../WearOS/app/src/main/java/com/intellidream/daily/wearos/data/WatchSessionManager.kt) serializeaza toate cele patru structuri:

1. Apa, zile.
2. Smokes, zile.
3. Apa, saptamani.
4. Smokes, saptamani.

La o adaugare in ziua curenta, actualizarea logurilor si actualizarea saptamanii declanseaza separat salvari.

**O actiune mica poate porni doua serializari ale intregului cache.**

Este bine ca acestea se executa in fundal. Totusi:

- consuma CPU si alocari;
- pot concura cu randarea;
- costul creste odata cu istoricul;
- joburile de salvare se pot suprapune;
- snapshot-urile celor patru structuri nu formeaza o tranzactie.

### Recomandari

Solutia preferata este persistenta incrementala intr-un store local structurat.

Pentru o interventie initiala mai mica:

- un singur writer;
- coalescing pentru salvarile cache-ului;
- salvarea numai a datelor afectate;
- retentie limitata.

**Nu trebuie amanata prin debounce salvarea durabila a operatiei utilizatorului.** Poate fi amanat un cache regenerabil, nu singura copie sigura a unui tap.

## 10. Sincronizarea centralizata: directie buna, implementare incompleta

### 10.1. Ce merita pastrat

Nu mai exista cate un fetch complet independent la fiecare swipe, asa cum descriu problemele istorice.

Sunt progrese reale:

- client reutilizat;
- cooldown;
- agregare principala in fundal;
- centralizarea fetch-urilor.

### 10.2. Single-flight-ul nu este atomic

Verificarea flag-ului si setarea lui sunt operatii separate. `@Volatile` ofera vizibilitate, nu exclusivitate.

Pornirea poate veni din restaurarea sesiunii, resume si pagini cu cache miss. Exista o cursa posibila intre ele.

**Recomandare:** exclusivitate reala si partajarea operatiei in curs.

### 10.3. Esecurile pot fi marcate drept sincronizare recenta

Cele doua fetch-uri pot esua si intoarce rezultat absent, dar timestamp-ul general este tot actualizat.

Urmatoarea incercare poate fi astfel amanata 60 de secunde, desi nu au fost obtinute datele.

Este necesara distinctia dintre succes complet, succes partial, esec si date deja actuale.

### 10.4. Resume-ul are dependente seriale costisitoare

In fluxul de resume:

- verificarea tokenurilor precede restul fluxului;
- golirea cozii offline precede sincronizarea obiceiurilor;
- coada trimite operatiile una cate una.

O retea slaba si un backlog mai mare pot intarzia refresh-ul.

Aceasta nu inseamna blocarea completa a UI-ului, dar datele pot ramane vechi.

Prioritizarea trebuie facuta fara a reintroduce curse intre upload, fetch si reconcilierea operatiilor locale.

### 10.5. Datele descarcate nu sunt diferentiate dupa nevoie

Sincronizarea cere randuri complete pentru ambele obiceiuri si intreaga fereastra, apoi sorteaza si grupeaza local.

Ar trebui separate:

- logurile detaliate necesare zilei vizibile;
- agregatele pentru grafice;
- reconcilierea operatiilor locale.

Nu exista paginare explicita pe acest traseu. Trebuie verificat plafonul de rezultate al API-ului, astfel incat un raspuns trunchiat sa nu fie tratat drept istoric complet.

Exista deja [RPC-ul pentru agregate](../supabase/migrations/habits_rpc_functions.sql), folosit ca precedent si in implementarea Android. Nu trebuie conectat fara adaptare:

- varianta din repository agrega dupa zi UTC;
- nu ofera direct toate subdiviziunile apa/cafea si cig/heat;
- trebuie pastrate semantica zilei locale si compatibilitatea datelor istorice.

### 10.6. Serverul necesita verificare, nu presupuneri

Nu se poate afirma ca serverului ii lipsesc indexuri numai din inspectia repository-ului.

Pentru o concluzie sunt necesare:

- schema efectiva;
- politicile si planul de executie relevante;
- numarul de randuri;
- latenta si dimensiunea raspunsurilor;
- eventualele plafoane de rezultate.

Nu se recomanda adaugarea de indexuri prin presupunere.

## 11. UI, paginare si randare

### 11.1. Paginile vecine sunt pastrate compuse

[DailyWearApp](../WearOS/app/src/main/java/com/intellidream/daily/wearos/presentation/DailyWearApp.kt) foloseste un pager care pastreaza si pagini in afara viewport-ului.

Este un compromis legitim: poate reduce costul urmatorului swipe, dar mentine mai mult UI si mai multi colectori activi.

In prezent:

- paginile vecine asculta trigger-ul global;
- refresh-ul nu este specific intervalului sau obiceiului;
- activitatea paginii nu suspenda complet munca ei;
- unele selectii istorice exista numai in state memorat in compozitie si se pot pierde cand pagina este eliminata.

Numarul optim de pagini precompuse trebuie masurat. Nu se recomanda pastrarea automata a tuturor celor cinci pagini permanent in memorie.

### 11.2. Stack-ul vizual nu este efectiv Wear Material 3

[Catalogul de biblioteci](../WearOS/gradle/libs.versions.toml) si [tema](../WearOS/app/src/main/java/com/intellidream/daily/wearos/presentation/theme/Theme.kt) arata Wear Material din generatia anterioara si componente custom stilizate ca Material 3.

Pager-ul provine din Foundation pentru mobil. Exista [componente Wear dedicate pentru paginare](https://developer.android.com/reference/kotlin/androidx/wear/compose/foundation/pager/package-summary).

Este recomandata evaluarea unei actualizari coerente a stack-ului si a integrarii Wear potrivite, separat de celelalte modificari, cu benchmark inainte/dupa.

O migrare Material 3 nu garanteaza automat performanta mai buna.

### 11.3. Inelele si graficele nu sunt demonstrat cauza principala

Exista deja alegeri bune:

- liste lazy;
- chei stabile pentru loguri;
- memorarea formatarii orei;
- inele Canvas simple;
- citirea valorilor animate in faza de desenare.

Nu a fost identificata o scena cu blur-uri complexe, imagini mari in fiecare rand sau animatii perpetue care sa explice evident o experienta foarte slaba.

**Nu recomand eliminarea inelelor sau graficelor inainte de trace.**

### 11.4. Adnotarile de stabilitate nu sunt un remediu universal

Kotlin-ul configurat beneficiaza deja implicit de strong skipping. Trebuie vazut ce se recompune efectiv.

Modelele mutabile nu trebuie declarate imuabile numai pentru a forta optimizari. Adaugarea mecanica de `@Stable` sau `@Immutable` poate ascunde un contract incorect, nu rezolva propagarea starii.

## 12. Feedback haptic si audio

### 12.1. Prima interactiune initializeaza si infrastructura audio

[SoundAndHapticFeedback](../WearOS/app/src/main/java/com/intellidream/daily/wearos/util/SoundAndHapticFeedback.kt) initializeaza un `ToneGenerator` la prima utilizare.

Aceasta se poate intampla chiar daca prima operatie este un simplu click care nu necesita sunet.

Costul exact necesita trace pentru prima interactiune.

### 12.2. Exista apeluri redundante de feedback

[TemporalNavHeader](../WearOS/app/src/main/java/com/intellidream/daily/wearos/presentation/components/TemporalNavHeader.kt) solicita feedback, apoi callback-ul solicita din nou feedback prin helper, care foloseste si vibratorul.

Nu rezulta neaparat trei vibratii distincte percepute: sistemul le poate suprapune. Totusi, exista apeluri redundante.

**Recomandare:** o singura cale de feedback pentru fiecare actiune si verificarea in trace a initializarii audio si apelurilor de sistem.

## 13. Tiles, complications, background si indicatoarele de stare

### 13.1. Ce este bine

[DailyTileService](../WearOS/app/src/main/java/com/intellidream/daily/wearos/presentation/tile/DailyTileService.kt), [WaterComplicationService](../WearOS/app/src/main/java/com/intellidream/daily/wearos/presentation/complication/WaterComplicationService.kt) si [SmokesComplicationService](../WearOS/app/src/main/java/com/intellidream/daily/wearos/presentation/complication/SmokesComplicationService.kt) citesc valori locale.

Nu declanseaza fiecare un fetch greu la randare. Nu reprezinta suspectul principal pentru sacadarea scroll-ului.

### 13.2. Lipsuri identificate

- Nu a fost gasita o cerere explicita de actualizare dupa fiecare modificare locala.
- Totalurile persistate nu sunt insotite de o cheie de zi pentru validarea schimbarii datei.
- Corutinele singleton-ului nu reprezinta un mecanism garantat de background scheduling dupa terminarea procesului.
- Modulul WearOS nu contine un colector Health echivalent cu cel watchOS.
- Fluxul de resume poate marca Health ca sincronizat dupa procesarea cozii de habits.
- [AboutScreen](../WearOS/app/src/main/java/com/intellidream/daily/wearos/presentation/about/AboutScreen.kt) afiseaza Connected fara sa reflecte o verificare reala a conectivitatii.

Aceste etichete fac diagnosticul dificil: aplicatia poate raporta succes desi datele relevante sunt vechi.

### 13.3. Pairing-ul

Polling-ul de pairing la 2,5 secunde merita limitat dupa lifecycle si expirarea PIN-ului.

Nu explica insa utilizarea normala dupa pairing reusit, deoarece traseul opreste polling-ul.

## 14. Comparatie consolidata cu watchOS

| Aspect | WearOS actual | watchOS actual | Interpretare |
|---|---|---|---|
| Acceptarea urmatorului tap | Blocata pana se termina request-ul | Nu are acelasi blocaj | Diferenta majora de responsivitate |
| Istoric selectat | Refresh cu fereastra fixa | Cere intervalul selectat | WearOS poate astepta inutil |
| Coada offline | Numai RAM, upload secvential | Persistenta, upload batch | watchOS este mai robust aici |
| Cache la pornire | Deserializare sincrona mai ampla | Cache zilnic mai restrans | WearOS face mai multa munca inainte de primul cadru |
| Actualizarea graficelor | Obiecte mutate in loc | Inlocuieste lista de valori | WearOS poate rata actualizari |
| Layout zilnic | Inel mare si actiuni pe verticala | Inel si actiuni alaturate | Mai mult scroll pe WearOS |
| Loguri | Lazy list | Lista intr-un stack obisnuit | WearOS are deja o alegere buna |
| Fetch-uri | Centralizate si cu cooldown | Pot fi repetate la aparitie/reactivare | Nu totul este mai optimizat pe watchOS |
| Integrare Health | Fara echivalent in modul | HealthKit cu ancore delta | watchOS face si munca suplimentara |
| Acces la habits | Direct cloud | Tot direct cloud | Diferenta nu poate fi explicata numai prin iPhone |

Surse watchOS principale:

- [DailyWatchApp](../WatchOS/DailyWatch/DailyWatch%20Watch%20App/DailyWatchApp.swift);
- [ContentView](../WatchOS/DailyWatch/DailyWatch%20Watch%20App/ContentView.swift);
- [WatchSessionManager](../WatchOS/DailyWatch/DailyWatch%20Watch%20App/WatchSessionManager.swift);
- [BubblesView](../WatchOS/DailyWatch/DailyWatch%20Watch%20App/BubblesView.swift);
- [SmokesView](../WatchOS/DailyWatch/DailyWatch%20Watch%20App/SmokesView.swift);
- [Bubbles7DaysView](../WatchOS/DailyWatch/DailyWatch%20Watch%20App/Bubbles7DaysView.swift);
- [Smokes7DaysView](../WatchOS/DailyWatch/DailyWatch%20Watch%20App/Smokes7DaysView.swift);
- [OfflineSyncManager](../WatchOS/DailyWatch/DailyWatch%20Watch%20App/OfflineSyncManager.swift);
- [HealthTelemetryManager](../WatchOS/DailyWatch/DailyWatch%20Watch%20App/HealthTelemetryManager.swift).

### 14.1. Ce merita preluat

Lectia nu este copierea integrala a implementarii watchOS, ci:

- separarea interactiunii locale de confirmarea retelei;
- incarcarea intervalului cerut;
- coada persistenta;
- publicarea corecta a noii stari.

### 14.2. Ce nu trebuie idealizat pe watchOS

Implementarea watchOS are si ea:

- fetch-uri repetate la aparitie si reactivare;
- cache zilnic limitat;
- aspecte de concurenta in procesarea cozii;
- formatare de date in randuri;
- dependente de cloud pentru actualizarea datelor.

Experienta buna raportata pe watchOS nu demonstreaza ca fiecare componenta a implementarii este mai eficienta.

### 14.3. Contracte de comportament care trebuie protejate

Exista diferente intre platforme:

- metadatele smokes folosesc chei diferite;
- clasificarea produselor incalzite nu este identica;
- inelul smokes reprezinta consumul pe WearOS si cantitatea ramasa pe watchOS.

Aceste contracte trebuie definite explicit inaintea refactorizarii, astfel incat o optimizare sa nu schimbe sensul datelor.

### 14.4. Navigarea catre loguri poate parea un tap fara raspuns

Traseul catre loguri este incomplet:

- callback-ul pentru deschiderea lor nu este conectat din pager;
- scroll-ul foloseste indici care ajung la actiuni sau breakdown, nu la inceputul logurilor.

Surse: [BubblesScreen](../WearOS/app/src/main/java/com/intellidream/daily/wearos/presentation/bubbles/BubblesScreen.kt), [SmokesScreen](../WearOS/app/src/main/java/com/intellidream/daily/wearos/presentation/smokes/SmokesScreen.kt) si [DailyWearApp](../WearOS/app/src/main/java/com/intellidream/daily/wearos/presentation/DailyWearApp.kt).

Nu este lag, dar contribuie la impresia ca aplicatia nu raspunde.

## 15. De ce optimizarile anterioare nu au fost suficiente

[Documentatia modernizarii WearOS](./Features/WearOS-PixelWatch5-Modernization.md) descrie directii bune, dar unele concluzii sunt mai puternice decat demonstreaza implementarea:

| Afirmatie anterioara | Limita constatata |
|---|---|
| Hidratare de 0 ms la cold start | Exista deserializare sincrona in calea primului cadru |
| UI complet reactiv | Map-urile si bucket-urile mutabile nu notifica automat Compose |
| Single-flight | Un flag volatil nu garanteaza exclusivitatea |
| Offline reliability | Coada WearOS este numai in RAM |
| Eliminarea completa a GC prin memorarea orei | Este redusa o sursa de alocari, nu toate |
| Fluiditate demonstrata prin instalare si verificare vizuala | Screenshot-ul si layout-ul nu demonstreaza frame pacing de 60 FPS |

Optimizarile nu au fost inutile. Au eliminat probleme reale, dar au ramas goluri si au fost introduse alte compromisuri.

Documentatia existenta nu a fost modificata in cadrul acestei analize. Tabelul reprezinta observatiile de audit asupra afirmatiilor respective.

## 16. Prioritati recomandate

| Ordine | Interventie | Scop | Natura validarii |
|---|---|---|---|
| 1 | Baseline reproductibil pe ambele ceasuri; Debug / Release / R8 / profile | Separarea costului build-ului de costul aplicatiei | Benchmark si trace |
| 2 | Acceptare locala durabila a tap-urilor, outbox, upload independent de pagina | Interactiuni rapide indiferent de retea | Latenta tap, offline, process death, retry |
| 3 | Eliminarea hidratarii complete inainte de primul cadru; persistenta incrementala si retentie | Startup si utilizare indelungata | Startup, I/O, CPU, marimea cache-ului |
| 4 | Stare reactiva corecta, intervale absolute, reconciliere si fetch pe intervalul selectat | Eliminarea datelor blocate si loading-ului fara sfarsit | Teste de stare, istoric, schimbarea zilei |
| 5 | Exclusivitate reala pentru sync, succes/esec, prioritizare si retry | Trafic redus si date proaspete predictibil | Concurenta, request-uri, esec partial |
| 6 | Optimizari ghidate de trace: pager, colectori, layout, feedback | Reducerea jank-ului ramas | FrameTimeline, Main/RenderThread, alocari |
| 7 | Actualizare controlata a stack-ului Wear si integrarilor de sistem | Imbunatatiri moderne fara regresii | Comparatie inainte/dupa si teste de comportament |

### 16.1. Ce nu recomand ca punct de plecare

- Rescrierea in Views sau MAUI.
- Eliminarea graficelor.
- Eliminarea tuturor animatiilor.
- Pastrarea permanenta a tuturor paginilor.
- Websocket permanent numai pentru impresia de viteza.
- Schimbarea engine-ului HTTP fara dovada ca domina costul.
- Schimbari de Java target sau ABI prezentate drept solutie pentru FPS.
- Adaugarea de adnotari de stabilitate care nu corespund contractului modelelor.
- O migrare mare, simultana, a UI-ului si stratului de date, fara masuratori intermediare.

## 17. Protocol propus de masurare si validare

**Acest capitol defineste masuratori viitoare. Nu reprezinta rezultate deja obtinute.**

### 17.1. Conditii de test

Pe fiecare ceas:

- acelasi build identificabil;
- set de date cunoscut;
- stare de alimentare si power saver consemnata;
- temperatura controlata;
- debugger neatasat pentru concluziile finale de performanta;
- tipul conexiunii consemnat: Wi-Fi, Bluetooth proxy sau offline;
- rata reala de refresh verificata, nu presupusa din comentarii sau denumirea dispozitivului.

### 17.2. Scenarii

1. Cold start cu date locale existente.
2. Revenire din background.
3. Lansare din complication.
4. Swipe prin toate cele cinci pagini.
5. Scroll tactil si crown printr-o zi cu multe loguri.
6. Adaugari succesive, inclusiv pe conexiune slaba.
7. Navigare in zile si saptamani neaflate in cache.
8. Operare offline, terminare de proces si revenire.
9. Refresh concurent cu adaugare sau stergere.
10. Trecere peste miezul noptii si inceput de saptamana.

### 17.3. Indicatori si tinte initiale propuse

| Indicator | Tinta initiala propusa |
|---|---|
| Confirmare vizuala a tap-ului | Sub 100 ms, inclusiv offline |
| Navigare catre date deja locale | Fara asteptare dupa server |
| Cold start cu cache | Obiectiv initial p95 sub 1 s, rafinat dupa baseline |
| Revenire in aplicatie | Obiectiv initial p95 sub 250 ms |
| Scroll/swipe la 60 Hz | Buget de aproximativ 16,7 ms/cadru; tinta sub 1% cadre intarziate |
| Persistenta | Nicio operatie pierduta dupa terminarea procesului |
| Memorie/cache | Fara crestere continua cu zilele de utilizare |
| Date afisate | Niciun interval vechi prezentat ca intervalul nou selectat |

Tintele de startup sunt obiective de produs propuse, nu praguri garantate de platforma.

FPS-ul mediu nu este suficient. O medie buna poate ascunde blocaje de 100-300 ms, foarte vizibile pentru utilizator.

### 17.4. Instrumente

- Macrobenchmark pentru startup si interactiuni.
- Perfetto / System Trace pentru Main thread, RenderThread, scheduling, GC si I/O.
- FrameTimeline / JankStats pentru cadre intarziate.
- Verificarea aplicarii profilelor ART.
- Instrumentarea duratei si dimensiunii request-urilor, fara tokenuri sau date sensibile in log.
- Teste de stare si persistenta pentru concurenta, retry, zile goale si schimbarea intervalului.

### 17.5. Ordinea experimentelor

1. Identificarea precisa a build-ului instalat si capturarea baseline-ului.
2. Comparatia aceluiasi comportament pe build-uri de performanta corect configurate.
3. Eliminarea dependentei tap-urilor de retea si verificarea integritatii datelor.
4. Separarea costului de startup de incarcarea istoricului.
5. Repararea starii reactive si a istoricului.
6. Capturarea trace-urilor ramase si optimizarea punctuala a UI-ului.

Aceasta ordine permite atribuirea imbunatatirilor unor schimbari concrete, nu unui pachet mare de modificari imposibil de evaluat separat.

## 18. Verdict

Exista motive serioase sa ne asteptam la o imbunatatire substantiala fara saracirea suplimentara a interfetei. Nu exista insa o garantie de FPS sau de timp de raspuns fara validare pe dispozitive.

Trebuie rezolvate separat:

- build-ul neoptimizat;
- munca sincrona de la pornire;
- interactiunile dependente de retea;
- persistenta si propagarea starii;
- istoricul care nu poate fi incarcat corect.

**Prima etapa recomandata:** masurare pe Release optimizat, apoi tap-uri local-first cu persistenta reala si eliminarea cache-ului complet din calea primului cadru.

Defectele de istoric si de propagare a starii trebuie tratate ca buguri. Abia dupa aceste interventii trebuie decis, pe baza trace-urilor de pe ambele ceasuri, daca mai exista un cost UI care justifica schimbarea layout-ului sau a componentelor.

## 19. Referinte

### 19.1. Documentatie oficiala consultata

- [Performanta pe WearOS](https://developer.android.com/training/wearables/compose/performance).
- [Performanta Jetpack Compose](https://developer.android.com/develop/ui/compose/performance).
- [Baseline Profiles](https://developer.android.com/topic/performance/baselineprofiles/overview).
- [Compose pentru WearOS](https://developer.android.com/training/wearables/compose).
- [Wear Compose Pager](https://developer.android.com/reference/kotlin/androidx/wear/compose/foundation/pager/package-summary).
- [Strong skipping](https://developer.android.com/develop/ui/compose/performance/stability/strongskipping).
- [Stare in Compose](https://developer.android.com/develop/ui/compose/state).
- [SharedPreferences](https://developer.android.com/training/data-storage/shared-preferences).
- [Tiles pe WearOS](https://developer.android.com/training/wearables/tiles).

Versiunile si recomandarile din documentatia online pot evolua. Datele exacte raportate pentru APK se refera strict la artefactul local inspectat.

### 19.2. Documente existente in repository

- [Modernizarea WearOS pentru Pixel Watch 5](./Features/WearOS-PixelWatch5-Modernization.md).
- [Paritate WearOS / HarmonyOS / Orbit](./Features/WearOS-HarmonyOS-Orbit-Parity.md).
- [Arhitectura Android Habits: consistenta si performanta](./Features/Android_Habits_Consistency_and_Performance_Architecture.md).
- [Schema agregatelor zilnice](./Supabase_Schema_Summaries.sql).
- [RPC-uri pentru agregarea habits](../supabase/migrations/habits_rpc_functions.sql).
- [Protocolul de deployment](./Deployment_Protocol.md), consultat ca document de context; nu s-a executat deployment.
