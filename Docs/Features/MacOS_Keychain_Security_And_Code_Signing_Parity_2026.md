# macOS Keychain Security Architecture & Apple Developer Signing Parity (2026)

**Data:** 30 Octombrie 2026  
**Componente:** `DailyCore` (`KeychainManager.swift`), `MacOS/Daily` (`Daily.entitlements`, `project.pbxproj`), `SupabaseService.swift`  
**Platformă:** macOS 15.0+ (Apple Silicon arm64)

---

## 1. Context & Diagnoză

### Simptomul raportat
Aplicația Daily pe macOS solicita periodic dialogul nativ de sistem SecurityAgent:
> *"Daily wants to use confidential information stored in 'com.intellidream.daily' in your keychain. To allow this, enter the 'login' keychain password."*

Dialogul apărea de câteva ori pe zi, în special după sesiuni de dezvoltare / recompilare sau la intervale regulate de ~50 de minute în timp ce aplicația rula permanent în fundal în `MenuBarExtra`.

### Cauza Fundamentală (Root Cause Analysis)

1. **Autentificarea recentă în Supabase:**  
   Până în 29 Octombrie, ora 21:41 UTC, sesiunea activă Supabase nu fusese inițializată pe Mac. Odată autentificat, SDK-ul Supabase a început să stocheze și să actualizeze periodic token-ul de sesiune (`sb-akkfouifxztnfwwiclwg-auth-token`) sub serviciul `com.intellidream.daily`.

2. **Ciclul distructiv în `KeychainManager.save()`:**  
   Implementarea inițială apela necondiționat:
   ```swift
   delete(key: key)
   SecItemAdd(query, nil)
   ```
   Supabase Auth are activat `autoRefreshToken: true`, reîmprospătând JWT-ul înainte de expirare (la fiecare ~50 de minute). La fiecare refresh, `delete()` ștergea complet intrarea din `login.keychain-db` împreună cu lista sa de control al accesului (ACL) și permisiunea „Always Allow” acordată anterior de utilizator. Următorul apel `SecItemAdd` crea un element complet nou cu ACL resetat, forțând macOS să ceară din nou parola.

3. **Semnătura ad-hoc cauzată de un Entitlement nefolosit:**  
   În `MacOS/Daily/Daily.entitlements` fusese copiat din iOS entitlement-ul `com.apple.developer.applesignin`. Întrucât pe macOS este folosit flow-ul OAuth PKCE / Supabase (fără Sign in with Apple nativ pe Mac) și Mac-ul nu avea un profil de provisioning special pentru acea capabilitate pe desktop, Xcode a refuzat semnarea automată cu certificatul de dezvoltator și a făcut fallback silențios la **semnătură ad-hoc** (`Signature=adhoc`). La fiecare recompilare, CDHash-ul executabilului se schimba, invalidând dreptul de acces la elementele create de build-ul anterior.

---

## 2. Modificări Implementate

### A. Non-Destructive In-Place Update (`KeychainManager.swift`)
Înlocuirea ștergerii urmate de recreere cu actualizare in-place via `SecItemUpdate`:
```swift
// 1. Attempt non-destructive in-place update first to preserve Keychain ACL and user permissions
var status = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)

// 2. If item does not exist yet (errSecItemNotFound / -25300), create it fresh with SecItemAdd
if status == errSecItemNotFound {
    var addQuery = query
    addQuery[kSecValueData as String] = data
    addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
    
    status = SecItemAdd(addQuery as CFDictionary, nil)
    
    // Fallback without access group if access group is not entitled on the current host
    if status != errSecSuccess && accessGroup != nil {
        addQuery.removeValue(forKey: kSecAttrAccessGroup as String)
        status = SecItemAdd(addQuery as CFDictionary, nil)
    }
}
```
* **Efect:** Token-urile de sesiune Supabase se actualizează direct în payload-ul criptat existent. Elementul Keychain rămâne neschimbat, iar ACL-ul și permisiunile de acces sunt păstrate permanent.

### B. Configurarea Identității Apple Developer (`MacOS/Daily.xcodeproj`)
Setarea explicită a identității de dezvoltare și a Team ID-ului utilizatorului:
* `CODE_SIGN_IDENTITY = "Apple Development";`
* `DEVELOPMENT_TEAM = 7LZ9ZT2Z5B;`
* `CODE_SIGN_STYLE = Automatic;`
* **Efect:** Binarul este semnat permanent cu certificatul:
  `Apple Development: MIHAI IONESCU (46P99RQF56)` cu `TeamIdentifier=7LZ9ZT2Z5B`. Sistemul de securitate macOS recunoaște binarul după identitatea stabilă a echipei de dezvoltare, nu după hash-ul volatil al fișierului compilat.

### C. Curățarea Entitlements-urilor (`MacOS/Daily/Daily.entitlements`)
Eliminarea cheii `com.apple.developer.applesignin` din entitlement-ul de macOS.
* **Efect:** Permite compilarea și semnarea automată fără blocaje de provisioning profile.

### D. Eliminarea Intrării Stale din Keychain
Ștergerea vechii chei corupte din `login.keychain-db` creată de build-urile ad-hoc anterioare:
```bash
security delete-generic-password -s "com.intellidream.daily"
```

---

## 3. Verificare și Validare

1. **Teste Unitare DailyCore:**  
   Toate cele 56 de teste din `DailyCore` (8 suite de testare) trec cu 0 erori:
   ```bash
   swift test --package-path DailyCore
   # Test run with 56 tests in 8 suites passed after 0.097 seconds.
   ```
2. **Validare Semnătură Digitală:**  
   Verificare prin `codesign -dvvv`:
   * `Authority=Apple Development: MIHAI IONESCU (46P99RQF56)`
   * `Authority=Apple Worldwide Developer Relations Certification Authority`
   * `Authority=Apple Root CA`
   * `TeamIdentifier=7LZ9ZT2Z5B`
   * `Signature size=4783`
3. **Execuție Live pe macOS:**  
   Aplicația Daily rulează în fundal ca `MenuBarExtra`, salvând și reîmprospătând token-urile de autentificare în Keychain fără a mai declanșa niciun dialog de sistem.

---

## 4. Incidentul din 1 Noiembrie 2026: Diagnosticare Extensie Widgets, dyld Crash & Soluția Definitivă Zero-Prompt

### Simptome Raportate
1. Aplicația macOS a încetat să mai pornească (`dyld` crash la inițializare).
2. Sistemul afișa din nou dialoguri repetitive `SecurityAgent`:
   > *"DayOne wants to access key 'com.intellidream.daily' in your keychain. To allow this, enter the 'login' keychain password."*

### Cauze Fundamentale (Root Causes)

1. **Entitlement App Group Fără Prefix de Team ID în macOS App Sandbox:**
   * La adăugarea țintei `DailyWidgets` (`DailyWidgetsExtension.appex`), în fișierele `Daily.entitlements` și `DailyWidgets.entitlements` a fost inclus șirul:
     `<string>group.com.intellidream.daily</string>` alături de cel prefixat `<string>7LZ9ZT2Z5B.group.com.intellidream.daily</string>`.
   * În macOS App Sandbox, un grup neprefixat este considerat de Apple un grup universal administrat prin profiluri de provisioning. Ca urmare, comanda `xcodebuild` din CLI a început să eșueze cu:
     `error: No profiles for 'com.intellidream.daily.macos' were found: Xcode couldn't find any Mac App Development provisioning profiles matching...`.
   * Când s-a încercat `-allowProvisioningUpdates`, serverul Apple a refuzat generarea profilului deoarece Mac-ul fizic (`HAWKEYE`) nu este înregistrat sub rubrica macOS Devices din contul de developer.

2. **Ocolirea Semnării Automate (`CODE_SIGNING_ALLOWED=NO`) și dyld Team ID Mismatch:**
   * Pentru a trece de eroarea de compilare, un script anterior a rulat `xcodebuild CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`, urmat de un script bash manual cu `codesign --force`.
   * În Xcode 16 / macOS 15 SDK, compilatorul generează dylib-uri dinamice de debug (`Daily.debug.dylib`, `__preview.dylib`, `DailyWidgetsExtension.debug.dylib`).
   * Semnarea manuală incompletă sau divergentă a lăsat dylib-urile cu semnături nepotrivite, ducând la oprirea forțată a aplicației la lansare de către subsistemul dinamic:
     `dyld: Library not loaded: @rpath/Daily.debug.dylib ... mapping process and mapped file (non-platform) have different Team IDs`.

3. **Limitarea Sandbox-ului pe Keychain-ul Tradițional (`login.keychain-db`):**
   * Pe macOS, un App Sandbox fără entitlement-ul restricționat `keychain-access-groups` (care impune profil de provisioning) nu are acces la Data Protection Keychain hardware (returnează `errSecMissingEntitlement` / -34018).
   * Astfel, `KeychainManager` făcea fallback pe `login.keychain-db` (keychain-ul pe fișier al utilizatorului).
   * În `login.keychain-db`, dacă aplicația recompilată nu se potrivește 100% cu cerința ACL anterioară (din cauza semnărilor manuale/ad-hoc), macOS SecurityAgent intervine de fiecare dată pentru a cere parola de login a utilizatorului.

### Soluția Arhitecturală Implementată

1. **Curățarea Entitlements-urilor pe macOS (`Daily.entitlements` & `DailyWidgets.entitlements`):**
   * S-a eliminat complet `group.com.intellidream.daily`, păstrând exclusiv `7LZ9ZT2Z5B.group.com.intellidream.daily`.
   * Întrucât grupul este prefixat strict cu Team ID-ul (`7LZ9ZT2Z5B`), macOS permite semnarea nativă automată `Apple Development` **fără niciun profil de provisioning**.
   * Xcode semnează automat, atomic și omogen aplicația principală, extensia de widgeturi și toate dylib-urile de debug (`Daily.debug.dylib`, `__preview.dylib`).

2. **Stocare Token Supabase în Containerul Sandboxed `GroupDefaults` (Zero-Prompt Parity):**
   * În `SupabaseService.swift`, clasa `SupabaseKeychainStorage` a fost adaptată pentru macOS:
     - Pe macOS, `store()`, `retrieve()` și `remove()` utilizează direct containerul comun `GroupDefaults.shared.userDefaults` (`7LZ9ZT2Z5B.group.com.intellidream.daily`).
     - Acest container este izolat sandbox, criptat la nivel de volum prin FileVault, partajat instant între aplicație și widgeturi și nu atinge niciodată `login.keychain-db`.
     - Pe iOS și watchOS, se păstrează stocarea hardware nativă din `KeychainManager`.
   * În `KeychainManager.swift`, metodele `save()`, `getData()` și `delete()` oferă mirroring și citire automată din `GroupDefaults` pe macOS pentru a garanta absența totală a oricărui dialog `SecurityAgent`.

3. **Validare Completă:**
   * `xcodebuild -project MacOS/Daily.xcodeproj -scheme Daily -configuration Debug -destination 'platform=macOS' build`: **BUILD SUCCEEDED** cu semnătura completă `Apple Development: MIHAI IONESCU (46P99RQF56)`.
   * `Daily.app` pornește instant, rulează în fundal fără nicio eroare de dyld.
   * `SecurityAgent` raportează `No SecurityAgent` (0 ferestre, 0 dialoguri de parolă).
   * Widgeturile desktop citesc datele din același container `7LZ9ZT2Z5B.group.com.intellidream.daily` fără fricțiune.
