# WinOpt

> **Windows 11 come dovrebbe essere** — privacy, prestazioni e zero bloat, riproducibile ad ogni reinstallazione.

![Windows 11](https://img.shields.io/badge/Windows-11-0078D4?logo=windows11)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell)
![Versione](https://img.shields.io/badge/versione-2.5.7-brightgreen)
![Licenza](https://img.shields.io/badge/licenza-MIT-blue)

---

## Il problema che risolve

Windows 11 esce dalla fabbrica con telemetria attiva, Copilot, OneDrive, decine di servizi inutili e app preinstallate che non hai chiesto. Puoi disabilitarli uno a uno — ma alla prossima reinstallazione ricomincia tutto da capo.

WinOpt è una suite di script che esegui **una volta** dopo una installazione pulita di Windows 11 e ottieni una macchina silenziosa, privata e veloce. L'esperienza di chi usa Windows LTSC, senza dover comprare una licenza volume o rinunciare allo Store e agli aggiornamenti di sicurezza.

**Per chi è pensato**

- Chi reinstalla Windows spesso e vuole automatizzare le ottimizzazioni
- Chi gestisce più PC e vuole configurazioni riproducibili
- Power user, orientati alla privacy, gamer che vogliono ridurre il rumore in background
- Chi vuole capire cosa viene modificato (tutto è documentato e loggato)

**Non è pensato per**

- Chi usa attivamente OneDrive, Teams consumer, Copilot o Windows Recall
- Ambienti aziendali gestiti da MDM/Intune
- Chi preferisce mantenere Windows nella configurazione predefinita Microsoft

---

## Cosa fa

### Privacy
- Disabilita telemetria, diagnostica, CEIP e advertising ID
- Disabilita Cortana, Bing nella ricerca, Copilot e Windows Recall
- Blocca Activity History, sincronizzazione cross-device, Find My Device
- Blocca installazione automatica driver via Windows Update
- DNS over HTTPS — Cloudflare 1.1.1.1 con fallback al DNS del router locale

### Performance
- Disabilita servizi non essenziali: Xbox Live, DiagTrack, WerSvc, SysMain (su SSD)
- Ottimizza parametri CPU: NetworkThrottlingIndex, SystemResponsiveness
- Pagefile fisso su SSD (elimina frammentazione da ridimensionamento dinamico)
- NTFS: disabilita generazione nomi 8.3 e aggiornamento LastAccessTime
- Piano alimentazione Ultimate Performance su desktop, High Performance su laptop

### UI/UX
- Dark mode di sistema, estensioni file visibili, Explorer apre "Questo PC"
- Menu contestuale classico Windows 10 (niente "Mostra altre opzioni")
- MenuShowDelay 20ms (da 400ms), WaitToKillAppTimeout 3000ms
- Rimuove Game DVR e limitazione app in background

### Edge
- Nessun avvio automatico, nessun background mode quando chiuso
- Nessun shopping assistant, sidebar, Microsoft Rewards, Spotlight
- uBlock Origin installato forzatamente via policy
- Do Not Track attivo, dati diagnostici disabilitati

### Debloat
Rimuove ~30 app preinstallate: Xbox, Teams consumer, Widgets, Clipchamp, BingNews, Cortana, OneDrive (opzionale), Office Hub, LinkedIn, WhatsApp Desktop e altre.

Conserva intenzionalmente: Store, Calcolatrice, Foto, Blocco note, Paint, Snipping Tool, Clock.

### Strumenti inclusi
| Modulo | Funzione |
|---|---|
| ULTRA ADDON | Ottimizzazioni avanzate: WSearch off, SysMain off, trasparenze disabilitate |
| ONEDRIVE | Toggle on/off reversibile con backup completo di registro e servizi |
| APPS INSTALL | Installazione silenziosa via winget da lista JSON personalizzabile |
| CLEAN SAFE | Pulizia temp, cache browser, WER, thumbnail cache, Cestino |
| CLEAN DEEP | SAFE + cache Windows Update + DISM ComponentCleanup |
| STARTUP CLEAN | Rimozione voci avvio automatico bloatware dalle Run key |
| VERIFY | Check post-apply con score numerico, rileva drift dopo aggiornamenti |
| POWER BOOST | Piano alimentazione ottimale con rilevamento laptop/desktop |

---

## Come si usa

**Requisiti**: Windows 11 (22H2, 23H2 o 24H2) — PowerShell 5.1+ — Account amministratore

```
1. Scarica WinOpt_2.5.7.zip dalla pagina Releases
2. Decomprimi in una cartella a scelta (es. C:\WinOpt-setup\)
3. Tasto destro su LAUNCHER.cmd → "Esegui come amministratore"
4. Dal menu scegli  →  Q  (QUICK STABLE)
5. Leggi il summary a schermo al termine
6. Riavvia Windows
```

**QUICK STABLE** applica nell'ordine consigliato: BASELINE → EDGE → UIUX → VERIFY.
È la sequenza sicura per un primo setup completo.

Tutti i log vengono salvati in `C:\WinOpt\Logs\` con nome `MODULO_AZIONE_DATA.log`.

---

## Reversibilità

Prima di ogni modifica viene creato automaticamente un **Restore Point di sistema**.
In caso di problemi: Start → digita `rstrui` → Invio → segui la procedura guidata.

I valori originali di registro, servizi e task vengono salvati in `C:\WinOpt\State\Backup\`
prima di ogni run. Il modulo OneDrive usa questi backup per il ripristino completo.

---

## Struttura del progetto

```
WinOpt/
├── LAUNCHER.cmd                     ← Punto di ingresso — UAC una sola volta
├── MANIFEST_SHA256.txt              ← Hash SHA256 di tutti i file per verifica integrità
├── Modules/
│   ├── _COMMON/
│   │   ├── Common.ps1               ← Funzioni condivise (logging, registry, backup)
│   │   └── Preflight.ps1            ← Check pre-esecuzione (PS version, spazio, admin)
│   ├── Config/
│   │   └── WinOpt.config.psd1       ← Configurazione (profilo, WSearch, DoH)
│   ├── 01_BASELINE/                 ← Telemetria, servizi, task, debloat, DNS, pagefile
│   ├── 02_UIUX/                     ← Dark mode, Explorer, menu contestuale, animazioni
│   ├── 03_EDGE/                     ← Policy Edge + preferenze utente + uBlock
│   ├── 04_VERIFY/                   ← Verifica stato sistema con score
│   ├── 10_ULTRA_ADDON/              ← Ottimizzazioni avanzate (da usare dopo BASELINE)
│   ├── 20_ONEDRIVE/                 ← Gestione OneDrive: OFF / ON / STATUS
│   ├── 30_APPS/                     ← Installazione app via winget + policy JSON
│   ├── 40_CLEAN/                    ← Pulizia disco: SAFE / DEEP / AUDIT
│   ├── 50_STARTUP/                  ← Pulizia voci avvio automatico
│   └── 90_LAB/                      ← Power Boost (piano alimentazione)
└── Docs/
    └── ARCHITECTURE.md              ← Descrizione architettura interna
```

---

## Documentazione tecnica

Il file `TECHNICAL_GUIDE.md` nella root contiene la documentazione completa per sviluppatori:
architettura, ogni chiave di registro modificata, logica di ogni modulo e decisioni di design.

---

## Sicurezza

- Non disabilita mai Windows Defender
- Non tocca driver di sistema o componenti kernel
- Ogni modifica ha backup automatico prima dell'esecuzione
- Restore Point di sistema creato prima di ogni run
- Verifica integrità file tramite `MANIFEST_SHA256.txt`

Per segnalare vulnerabilità o problemi di sicurezza vedi [SECURITY.md](SECURITY.md).

---

## Contribuire

Pull request benvenute. Vedi [CONTRIBUTING.md](CONTRIBUTING.md) per le linee guida.

---

## Disclaimer

> ⚠️ Questa suite modifica servizi, registro di sistema e configurazioni Windows.
> L'autore non è responsabile per eventuali danni derivanti dall'utilizzo.
> **Usare sempre su sistema con backup recente.**
> Non affiliata con Microsoft.

---

## Licenza

[MIT](LICENSE) — © 2025 WinOpt Contributors
