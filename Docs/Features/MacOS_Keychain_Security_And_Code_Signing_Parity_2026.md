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
