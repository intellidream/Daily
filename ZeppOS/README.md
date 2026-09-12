# DayOne Orbit - Zepp OS (Amazfit)

Aplicația DayOne Orbit companion pentru ceasurile inteligente Amazfit (Amazfit Balance, Amazfit Active 2 etc.), dezvoltată pe Zepp OS 3.0 cu `@zeppos/zml`.

---

## Ghid Detaliat de Livrare și Instalare pe Ceas

Pentru ghidul complet pas-cu-pas de configurare a mașinii de la zero, activare Developer Mode în aplicația Zepp de pe telefon și instalare prin QR code, consultă:
➡️ **[`Docs/Features/ZeppOS-Amazfit-Deployment-Guide.md`](../Docs/Features/ZeppOS-Amazfit-Deployment-Guide.md)**

---

## Comenzi Rapide (Quick Start)

### 1. Instalare Dependențe (după clone sau reset mașină)
```bash
npm install
```

### 2. Livrare Directă pe Ceas (Preview & Live Debug)
```bash
npx zeus preview
```
1. La promptul interactiv din terminal, **nu alege din "Suggested"**, ci derulează în catalogul complet până la modelul ceasului tău (`Amazfit Balance` sau `Amazfit Active 2`).
2. În aplicația **Zepp** de pe telefon (pe același Wi-Fi cu Mac-ul): **Profile** -> **Developer options** -> Scanează codul QR din consolă.
3. Aplicația se instalează și pornește automat pe ceas.

### 3. Compilare Pachet `.zab` de Producție
```bash
npm run build
# Pachetul este generat în folderul dist/
```
