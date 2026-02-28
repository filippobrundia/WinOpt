# WinOpt 2.5.7 — Guida Tecnica

Documentazione per sviluppatori e utenti avanzati. Descrive l'architettura, la logica di ogni modulo, le chiavi di registro modificate e le decisioni di design.

---

## Architettura generale

### Flusso di esecuzione

```
LAUNCHER.cmd  (UAC elevazione — UNA SOLA VOLTA all'avvio)
  └─ :RUNSCRIPT ADMIN / USER
       └─ powershell -File Modules\XX\APPLY.ps1
            ├─ . Modules\_COMMON\Common.ps1    (dot-source funzioni)
            ├─ & Modules\_COMMON\Preflight.ps1 (PS version, spazio, restore point)
            ├─ Assert-Admin $Log               (safety net se lanciato direttamente)
            ├─ Backup registro + servizi (JSONL)
            ├─ Modifiche sistema
            └─ Write-WinOptFooter              (summary OK/WARN/FAIL/SKIP)
```

### Gestione elevazione UAC (2.5.7)

Il launcher (`LAUNCHER.cmd`) verifica i privilegi admin **una sola volta** all'avvio tramite `net session`. Se non è elevato, rilancia se stesso con `Start-Process RunAs` e termina. Da quel momento, tutti i moduli girano nella sessione elevata senza ulteriori prompt UAC.

Ogni script APPLY contiene `Assert-Admin $Log` come **safety net**: se lo script viene lanciato direttamente (doppio clic, senza passare dal launcher), mostra un messaggio chiaro con suggerimento e termina con `exit 1`. Con il launcher elevato, questa chiamata passa senza effetti.

> **Differenza rispetto alle versioni precedenti (≤ 2.5.6):** nelle versioni precedenti ogni script si auto-elevava singolarmente con `Start-Process -Verb RunAs`. Questo causava un UAC per ogni modulo e rendeva gli ExitCode inaffidabili (il launcher vedeva l'esito del "wrapper", non dello script reale). Dalla 2.5.7 l'elevazione è centralizzata nel launcher e gli ExitCode sono deterministici.

### ExitCode affidabili

`:RUNSCRIPT` nel launcher cattura il `%ERRORLEVEL%` di `powershell -File` e lo scrive in `C:\WinOpt\State\last_exitcode.txt`. Il blocco `:POST` lo mostra a schermo. Il summary `OK/FAIL` è ora affidabile.

### Sistema di log

Tutti gli script scrivono in `C:\WinOpt\Logs\` con naming `MODULO_AZIONE_YYYYMMDD_HHMMSS.log`.

Formato entry:
```
[yyyy-MM-dd HH:mm:ss] [LEVEL] messaggio
```

Livelli: `OK` (verde) · `WARN` (giallo) · `FAIL` (rosso) · `SKIP` (grigio) · `INFO` (bianco)

Ogni script termina con un summary:
```
SUMMARY 01_BASELINE APPLY: Status=OK OK=47 WARN=2 FAIL=0 Log=C:\WinOpt\Logs\...
```

### Sistema di backup

Prima di qualsiasi modifica, ogni script APPLY salva in `C:\WinOpt\State\Backup\MODULO\`:

- `reg.jsonl` — ogni riga: `{"Key":"...","Name":"...","Exists":true,"Type":"REG_DWORD","Value":0}`
- `services.txt` — ogni riga: `NomeServizio|StartType`
- `tasks.txt` — ogni riga: `\Path\TaskName|State`

I backup vengono usati da `APPLY_ON.ps1` (modulo OneDrive) per il ripristino. Per gli altri moduli il metodo consigliato è il Restore Point automatico creato prima di ogni run.

### Source of truth unica

`Modules\_COMMON\Common.ps1` è l'unico file con le funzioni condivise. Non esistono copie in altri percorsi. Tutti gli script usano il dot-source relativo:
```powershell
. "$PSScriptRoot\..\\_COMMON\Common.ps1"
```

---

## Modulo Preflight

**File:** `Modules/_COMMON/Preflight.ps1`

Eseguito da ogni script APPLY prima di qualsiasi modifica.

| Controllo | Comportamento se fallisce |
|---|---|
| PowerShell ≥ 5.1 | Blocca (exit 1) |
| Privilegi Administrator | Blocca se `RequireAdmin = $true` |
| Spazio libero C: ≥ 5 GB | Blocca |
| Creazione Restore Point | Non blocca (WARN se fallisce) |

Il restore point viene creato con `Checkpoint-Computer -Description "WIN_OPT_CLAUDE YYYYMMDD_HHMMSS"`. Se VSS è disabilitato o WMI è instabile, il fallimento è loggato come WARN e l'esecuzione continua.

---

## Modulo 01_BASELINE

**File:** `Modules/01_BASELINE/APPLY.ps1`

Il modulo principale. Applica tutte le ottimizzazioni compatibili con qualsiasi uso del sistema.

### Servizi modificati

| Servizio | Stato | Motivo |
|---|---|---|
| DiagTrack | Disabled + Stop | Telemetria connessa Microsoft (Connected User Experiences) |
| dmwappushservice | Disabled + Stop | WAP Push Message Routing, usato dalla telemetria |
| WerSvc | Disabled + Stop | Windows Error Reporting — upload report a Microsoft |
| XblAuthManager | Disabled + Stop | Xbox Live autenticazione |
| XblGameSave | Disabled + Stop | Xbox Live salvataggi cloud |
| XboxGipSvc | Disabled + Stop | Protocollo Xbox accessori |
| XboxNetApiSvc | Disabled + Stop | Xbox Live networking API |
| MapsBroker | Manual | Download mappe offline — Manual evita avvio automatico |
| RemoteRegistry | Manual + Stop | Accesso remoto al registro — disabilitato in ULTRA |
| SysMain | Automatic | Prefetch/Superfetch — disabilitato in ULTRA su SSD |
| WSearch | Automatic + Start | Windows Search — controllato da config `WSearch.BaseEnabled` |

### Task schedulati disabilitati

| Task | Motivo |
|---|---|
| `\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser` | Scansiona app installate e invia dati a Microsoft |
| `\Microsoft\Windows\Application Experience\ProgramDataUpdater` | Aggiorna DB compatibilità applicazioni |
| `\Microsoft\Windows\Customer Experience Improvement Program\Consolidator` | Raccoglie dati CEIP e li invia a Microsoft |
| `\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip` | CEIP specifico per dispositivi USB |
| `\Microsoft\Windows\Customer Experience Improvement Program\KernelCeipTask` | CEIP a livello kernel |
| `\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector` | Raccoglie dati S.M.A.R.T. e li invia a Microsoft |
| `\Microsoft\Windows\Windows Error Reporting\QueueReporting` | Invia report errori in coda a Microsoft |

### Chiavi di registro — Telemetria

```
HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection
  AllowTelemetry                               = 0   (Security level — nessuna telemetria)
  DoNotShowFeedbackNotifications               = 1   (nessun popup "Invia feedback")
  LimitEnhancedDiagnosticDataWindowsAnalytics  = 0
  AllowDeviceNameInTelemetry                   = 0   (non inviare il nome del PC)

HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection
  AllowTelemetry                               = 0   (secondo percorso, per ridondanza)

HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting
  Disabled                                     = 1   (blocca WER lato policy)

HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization
  DODownloadMode                               = 0   (disabilita P2P update sharing)

HKLM\SOFTWARE\Policies\Microsoft\SQMClient\Windows
  CEIPEnable                                   = 0   (Customer Experience Improvement Program off)
```

### Chiavi di registro — Windows Spotlight e contenuti cloud

```
HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent
  DisableWindowsConsumerFeatures               = 1   (nessuna app suggerita nel menu Start)
  DisableCloudOptimizedContent                 = 1   (nessun contenuto personalizzato da cloud)
  DisableLockScreenAppNotifications            = 1   (nessuna notifica app nella lock screen)
  DisableWindowsSpotlightFeatures              = 1   (disabilita Spotlight completamente)
  DisableWindowsSpotlightOnActionCenter        = 1   (nessun suggerimento in Action Center)
  DisableWindowsSpotlightOnSettings            = 1   (nessun suggerimento in Impostazioni)
  DisableTailoredExperiencesWithDiagnosticData = 1   (nessuna esperienza personalizzata da dati diagnostici)

HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager
  SilentInstalledAppsEnabled                   = 0   (nessuna app installata silenziosamente)
  SystemPaneSuggestionsEnabled                 = 0   (nessun suggerimento nel pannello sistema)
  PreInstalledAppsEnabled                      = 0   (nessuna app preinstallata aggiuntiva)
  OemPreInstalledAppsEnabled                   = 0   (nessuna app OEM preinstallata)
```

### Chiavi di registro — Pubblicità e tracking

```
HKLM\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo
  DisabledByGroupPolicy                        = 1   (blocca Advertising ID di sistema)

HKCU\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo
  Enabled                                      = 0   (disabilita ID pubblicità per l'utente corrente)
```

### Chiavi di registro — Ricerca, Cortana, Copilot, AI

```
HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search
  DisableWebSearch                             = 1   (nessuna ricerca web dalla barra di ricerca Start)
  ConnectedSearchUseWeb                        = 0   (ricerca Start non usa internet)
  AllowCortana                                 = 0   (Cortana disabilitata)
  BingSearchEnabled                            = 0   (Bing nella ricerca Start disabilitato)

HKLM\SOFTWARE\Policies\Microsoft\InputPersonalization
  AllowInputPersonalization                    = 0   (no personalizzazione input — typing/ink)
  RestrictImplicitInkCollection                = 1   (no raccolta dati scrittura a mano)
  RestrictImplicitTextCollection               = 1   (no raccolta dati tastiera)

HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot
  TurnOffWindowsCopilot                        = 1   (Copilot completamente disabilitato)

HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsAI
  DisableAIDataAnalysis                        = 1   (Windows AI non analizza i dati utente)
  AllowRecallEnablement                        = 0   (Windows Recall non può essere abilitato — build 24H2+)

HKLM\SOFTWARE\Policies\Microsoft\Dsh
  AllowNewsAndInterests                        = 0   (widget News and Interests disabilitato)
```

### Chiavi di registro — Activity History e sincronizzazione

```
HKLM\SOFTWARE\Policies\Microsoft\Windows\System
  EnableActivityFeed                           = 0   (nessuna cronologia attività)
  PublishUserActivities                        = 0   (non pubblicare attività utente)
  UploadUserActivities                         = 0   (non caricare attività utente su cloud)
  AllowCrossDeviceClipboard                    = 0   (appunti non sincronizzati tra dispositivi)

HKLM\SOFTWARE\Policies\Microsoft\FindMyDevice
  AllowFindMyDevice                            = 0   (Trova il mio dispositivo disabilitato)

HKLM\SOFTWARE\Policies\Microsoft\Windows\Personalization
  NoLockScreenCamera                           = 1   (fotocamera nella lock screen disabilitata)

HKLM\SOFTWARE\Policies\Microsoft\Windows\SettingSync
  DisableSettingSync                           = 2   (sincronizzazione impostazioni disabilitata)
  DisableSettingsSyncUserOverride              = 1   (l'utente non può riabilitarla)

HKLM\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors
  DisableLocationScripting                     = 1   (script non possono accedere alla posizione)
```

### Chiavi di registro — Windows Update (driver)

```
HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate
  ExcludeWUDriversInQualityUpdate              = 1   (Windows Update non installa driver automaticamente)
```
Motivazione: i driver automatici da WU spesso installano versioni generiche o obsolete, sovrascrivendo driver OEM ottimizzati. Meglio gestire i driver manualmente o tramite il software del produttore hardware.

### Chiavi di registro — Performance CPU e rete

```
HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile
  NetworkThrottlingIndex                       = 0xFFFFFFFF   (throttling rete disabilitato)
  SystemResponsiveness                         = 0             (massima priorità foreground)
```

**NetworkThrottlingIndex = 0xFFFFFFFF**: Windows di default limita la banda dei processi non-multimediali per garantire smoothness audio/video in streaming. Con questo valore tutti i processi ricevono la stessa priorità di rete — benefico per gaming, sviluppo, trasferimenti file.

**SystemResponsiveness = 0**: il default Windows è 20, che riserva il 20% delle risorse CPU per i processi background. Con 0 il processo in foreground ottiene massima priorità. Benefico per workstation mono-applicazione; sconsigliato su sistemi con molti processi background critici.

### File system NTFS

```
fsutil behavior set disable8dot3 1
fsutil behavior set disablelastaccess 1
```

**disable8dot3 = 1**: NTFS smette di generare alias in formato 8.3 (`PROGRA~1`) per ogni file creato. Riduce l'overhead nelle scansioni di directory. Richiede riavvio per effetto completo. Non impatta applicazioni moderne; alcune applicazioni legacy 16-bit potrebbero non funzionare (praticamente inesistenti su Windows 11).

**disablelastaccess = 1**: NTFS non aggiorna il timestamp "LastAccessTime" a ogni lettura di file. Su SSD elimina write inutili che accelerano l'usura delle celle. Riduce anche la frammentazione della MFT. Le applicazioni di backup che usano LastAccessTime per il rilevamento modifiche potrebbero essere impattate (raro).

### Pagefile ottimizzato per SSD

Lo script usa WMI per:
1. Rilevare se C: è SSD tramite `Get-PhysicalDisk -MediaType SSD`
2. Calcolare: `min = min(RAM × 1.5, 4096 MB)` · `max = max(min, 2048 MB)` — cap a 4 GB
3. Disabilitare la gestione automatica Windows (`AutomaticManagedPagefile = $false`)
4. Rimuovere pagefile su altri drive
5. Impostare pagefile fisso su C: con le dimensioni calcolate

**Motivazione**: un pagefile fisso evita la frammentazione da ridimensionamento dinamico. Su SSD la dimensione moderata (max 4 GB) bilancia disponibilità di memoria virtuale e usura celle. Su HDD la sezione viene saltata — Windows gestisce meglio il pagefile dinamico su disco rotante.

### DNS over HTTPS (DoH)

1. `HKLM\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters\EnableAutoDoh = 2` — Windows usa DoH automaticamente quando il DNS primario è in whitelist built-in
2. Registrazione template DoH tramite `Add-DnsClientDohServerAddress` per: `1.1.1.1`, `1.0.0.1` (Cloudflare), `8.8.8.8`, `8.8.4.4` (Google)
3. Se `Features.DoH.EnforceAdapterDns = $true` (default): imposta `1.1.1.1` come DNS primario su tutti gli adapter attivi, conservando il DNS corrente come secondario (per risoluzione nomi locali: NAS, stampanti, `\\nomepc`)

**Perché Cloudflare 1.1.1.1**: è il resolver pubblico più veloce (media RTT ~14ms), con policy di privacy verificate (nessun log permanente), e supporta sia DoH che DoT. Il DNS del router come secondario garantisce la risoluzione dei nomi della rete locale che `1.1.1.1` non conosce.

### App rimosse (debloat)

Usa `Remove-AppxPackage -AllUsers` + `Remove-AppxProvisionedPackage -Online` per rimozione sia per l'utente corrente sia per i nuovi profili:

| Pacchetto rimosso | Categoria |
|---|---|
| Microsoft.XboxApp, XboxGamingOverlay, XboxGameOverlay, XboxSpeechToTextOverlay | Xbox — inutile su PC senza Xbox |
| Microsoft.GamingApp | Xbox Game Pass overlay |
| Microsoft.WebExperience (Widgets) | Widget panel — impatta telemetria |
| Microsoft.WindowsCopilot | Copilot — gestito anche via policy |
| Microsoft.MicrosoftOfficeHub | Office promotion app |
| MicrosoftTeams (consumer) | Teams versione consumer (non business) |
| Microsoft.YourPhone / Link to Windows | Phone Link |
| Microsoft.GetHelp, Microsoft.Getstarted | Onboarding apps |
| Microsoft.WindowsFeedbackHub | Feedback Hub |
| Microsoft.People | Rubrica integrata |
| Microsoft.MicrosoftSolitaireCollection | Solitaire |
| Microsoft.ZuneMusic (Groove), ZuneVideo | Media player deprecati |
| Clipchamp.Clipchamp | Editor video cloud |
| Microsoft.BingNews, BingWeather | Bing content apps |
| Microsoft.WindowsMaps | Mappe offline |
| Microsoft.OutlookForWindows | Nuova Outlook (app separata) |
| Microsoft.PowerAutomateDesktop | Power Automate |
| Microsoft.BingSearch | Ricerca Bing integrata |
| Microsoft.MicrosoftFamily | Family Safety |
| LinkedIn, WhatsApp Desktop | App social preinstallate |
| Microsoft.DevHome | Developer onboarding tool |
| Microsoft.QuickAssist | Remote assistance |
| MicrosoftCorporationII.MicrosoftFamily | Variante Family |
| Microsoft.Windows.CrossDevice | Cross-device continuity |
| Microsoft.MicrosoftStickyNotes | Sticky Notes (opzionale) |

**Non rimossi intenzionalmente**: Microsoft Store, Calcolatrice, Fotocamera, Foto, Blocco note, Snipping Tool, Paint, Clock — applicazioni con utilizzo reale.

---

## Modulo 02_UIUX

**File:** `Modules/02_UIUX/APPLY.ps1`

Modifica solo chiavi HKCU (utente corrente). Non richiede elevazione admin. La maggior parte delle modifiche è visibile immediatamente; alcune richiedono il riavvio di Explorer o della sessione.

### Chiavi di registro

```
HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize
  AppsUseLightTheme                            = 0   (dark mode per le app)
  SystemUsesLightTheme                         = 0   (dark mode per la shell di sistema)

HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced
  HideFileExt                                  = 0   (estensioni file visibili)
  Hidden                                       = 2   (file e cartelle nascosti visibili)
  ShowSuperHidden                              = 0   (file di sistema nascosti restano tali)
  TaskbarAl                                    = 1   (icone taskbar allineate al centro — default Win11)
  SearchboxTaskbarMode                         = 1   (barra ricerca → solo icona)
  TaskbarMn                                    = 0   (Chat/Meet Now rimosso dalla taskbar)
  LaunchTo                                     = 1   (Explorer si apre su "Questo PC" invece di "Accesso rapido")
  Start_TrackDocs                              = 0   (documenti recenti non tracciati)
  Start_TrackProgs                             = 0   (programmi usati di recente non tracciati)

HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer
  ShowRecent                                   = 0   (file recenti non mostrati in Start/Explorer)
  ShowFrequent                                 = 0   (cartelle frequenti non mostrate)
```

**Estensioni file visibili**: la scelta di nascondere le estensioni è storica e ha causato innumerevoli infezioni da malware (es. `documento.pdf.exe` appare come `documento.pdf`). Renderle visibili è una pratica di sicurezza standard.

**LaunchTo = Questo PC**: riduce la superficie di tracking (accesso rapido mostra file recenti e cartelle frequenti) e dà una vista immediata delle unità disponibili.

```
HKCU\System\GameConfigStore
  GameDVR_Enabled                              = 0   (Game DVR disabilitato)

HKCU\Software\Microsoft\Windows\CurrentVersion\GameDVR
  AppCaptureEnabled                            = 0   (registrazione app in background disabilitata)
```

**Game DVR**: il servizio Game DVR registra continuamente un buffer video in background per permettere il "replay" degli ultimi secondi di gioco. Consuma CPU, GPU e RAM anche quando non si gioca. Su sistemi non gaming è overhead puro.

```
HKCU\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications
  GlobalUserDisabled                           = 1   (app in background globalmente limitate)
```

```
HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects
  VisualFXSetting                              = 2   (bilanciato verso prestazioni)

HKCU\Control Panel\Desktop
  FontSmoothing                                = 2   (font smoothing attivo)
  FontSmoothingType                            = 2   (ClearType — ottimale per LCD)
  FontSmoothingGamma                           = 1500
  MenuShowDelay                                = 20  (ms — default 400ms, riduce latenza menu)
  WaitToKillAppTimeout                         = 3000 (ms — default 5000ms, shutdown più rapido)

HKCU\Control Panel\Desktop\WindowMetrics
  MinAnimate                                   = 0   (animazione minimizza/massimizza disabilitata)
```

**MenuShowDelay = 20ms**: riduce il ritardo prima che appaiano i sottomenu. Il default di 400ms era pensato per mouse meccanici lenti; su hardware moderno 20ms è impercettibile ma elimina la sensazione di "lag" nell'interfaccia.

**WaitToKillAppTimeout = 3000ms**: al momento dello spegnimento, Windows aspetta questo tempo prima di terminare forzatamente le app che non rispondono. Riduce i tempi di shutdown da ~10 a ~5 secondi mantenendo abbastanza tempo per chiusure pulite.

```
HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32
  (Default)                                    = ""  (menu contestuale classico Win10)
```

**Menu contestuale classico**: questa chiave forza Windows 11 a usare il menu contestuale completo "stile Windows 10", eliminando il submenu "Mostra altre opzioni" e il relativo ritardo (~400ms). Ripristina l'accesso diretto a tutte le voci (incluse quelle di app terze come 7-Zip, Git, ecc.) con un solo clic destro.

---

## Modulo 03_EDGE

**File:** `Modules/03_EDGE/APPLY.ps1`

Tutte le modifiche sono policy HKLM (`SOFTWARE\Policies\Microsoft\Edge`). Le policy HKLM sovrascrivono le impostazioni locali utente e sopravvivono agli aggiornamenti di Edge.

**Nota**: Su Edge in versione consumer (non gestito da MDM/Intune), alcune policy vengono silenziosamente ignorate da Edge stesso. Questo comportamento è documentato da Microsoft e non è aggirabile senza MDM.

### Chiavi di registro

```
HKLM\SOFTWARE\Policies\Microsoft\Edge
  StartupBoostEnabled           = 0   (Edge non si precarica all'avvio di Windows)
  BackgroundModeEnabled         = 0   (Edge non gira in background quando chiuso)
  SleepingTabsEnabled           = 1   (tab inattive sospese per ridurre RAM — da mantenere ON)
  ShowRecommendationsEnabled    = 0   (nessun contenuto promozionale dalla barra laterale)
  EdgeShoppingAssistantEnabled  = 0   (shopping assistant / price comparison disabilitato)
  HubsSidebarEnabled            = 0   (sidebar destra disabilitata)
  ShowMicrosoftRewards          = 0   (Microsoft Rewards non mostrato)
  HideFirstRunExperience        = 1   (nessun wizard benvenuto al primo avvio)
  PersonalizationReportingEnabled = 0 (nessuna segnalazione per personalizzazione)
  MetricsReportingEnabled       → RIMOSSA: chiave inesistente in Edge 145, causava warning in edge://policy
  DiagnosticData                = 0   (dati diagnostici Edge disabilitati)
  ConfigureDoNotTrack           = 1   (header Do Not Track inviato a ogni sito)
  SpotlightExperiencesAndRecommendationsEnabled = 0 (nessun contenuto Spotlight in Edge)
  ShowHomeButton                = 1   (pulsante Home visibile)
  HomepageIsNewTabPage          = 0   (homepage separata dalla nuova scheda)
  HomepageLocation              = https://www.google.com
                                  ⚠ Ignorata da Edge 145+ consumer (senza MDM/Intune)
                                  Impostare manualmente da edge://settings/startHomeNTP
  NewTabPageLocation            → RIMOSSA: ignorata da Edge 145 consumer (conflitto con HomepageLocation)
  FavoritesBarEnabled           = 0   (barra preferiti nascosta di default)
```

**StartupBoostEnabled = 0 + BackgroundModeEnabled = 0**: combinati, evitano che Edge consumi RAM e CPU anche quando non è in uso. Edge con startup boost rimane parzialmente in memoria dall'avvio di Windows. La disabilitazione riduce il footprint a regime di ~150-300 MB per sessione aperta.

---

## Modulo 10_ULTRA_ADDON

**File:** `Modules/10_ULTRA_ADDON/APPLY.ps1`

Da applicare **dopo** BASELINE. Ottimizzazioni più aggressive che disabilitano componenti utili ma non essenziali in scenari d'uso orientati alle prestazioni.

### Differenze rispetto a BASELINE

| Componente | BASELINE | ULTRA |
|---|---|---|
| WSearch (Windows Search) | Automatic | Disabled + Stop |
| SysMain (Superfetch) | Automatic | Disabled + Stop |
| MapsBroker | Manual | Disabled |
| RemoteRegistry | Manual | Disabled |
| WMPNetworkSvc | — | Disabled + Stop |
| RetailDemo | — | Disabled |
| Trasparenze UI | Invariate | Disabilitate |

**WSearch disabilitato**: su SSD NVMe moderni la ricerca diretta del filesystem (es. `Everything`) è spesso più veloce di WSearch. Se si usa la ricerca integrata di Windows frequentemente, lasciare BASELINE.

**SysMain (Superfetch) disabilitato**: su SSD il precaricamento in RAM non porta benefici significativi — i tempi di accesso SSD (~0.1ms) sono comparabili alla RAM per l'uso quotidiano. Su HDD è invece utile. Il modulo verifica il tipo di disco prima di disabilitare.

### App aggiuntive rimosse

`Microsoft.WindowsWidgets`, `Microsoft.YourPhone`, `Microsoft.Todos`, `Microsoft.MicrosoftOfficeHub`

---

## Modulo 04_VERIFY

**File:** `Modules/04_VERIFY/VERIFY.ps1`

Esegue check a runtime e produce un punteggio `score/max`. Legge `WinOpt.config.psd1` per sapere quale stato è atteso per WSearch in base al profilo corrente (`BASE` o `ULTRA`).

### Check effettuati

- Stato servizi: DiagTrack, SysMain, WerSvc, WSearch, tutti i servizi Xbox
- Chiavi telemetria: AllowTelemetry, CEIPEnable, DODownloadMode
- Chiavi ricerca: DisableWebSearch, AllowCortana, BingSearchEnabled
- Chiavi UIUX: tema scuro, estensioni file visibili, GameDVR
- Stato debloat: verifica che i pattern app principali non siano installati
- WSearch config-aware: confronta stato effettivo con valore atteso da config (BASE vs ULTRA)

---

## Modulo 20_ONEDRIVE

**File:** `Modules/20_ONEDRIVE/APPLY_OFF.ps1`, `APPLY_ON.ps1`, `VERIFY.ps1`

### OFF — Disabilita OneDrive

```
HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive
  DisableFileSyncNGSC                          = 1   (blocca sincronizzazione OneDrive via policy)

Servizi: OneSyncSvc → Disabled, FileSyncHelper → Disabled
Processo: OneDrive.exe terminato se in esecuzione
Task schedulati: tutti i task OneDrive trovati → Disabled
```

I task OneDrive hanno il SID utente nel nome (es. `OneDrive Standalone Update Task-S-1-5-21-...`). Il parsing usa `LastIndexOf('\')` invece di `Split-Path` per evitare il fallimento con path di Task Scheduler che non sono filesystem path.

Lo script esegue un backup completo di chiavi, servizi e task prima di qualsiasi modifica.

### ON — Riabilita OneDrive

Ripristina servizi e task dallo stato di backup (se disponibile) o dai valori default. Avvia `OneDrive.exe /background` per il riavvio del client. Non reinstalla OneDrive se era stato disinstallato manualmente.

---

## Modulo 40_CLEAN

**File:** `Modules/40_CLEAN/SAFE.ps1`, `DEEP.ps1`

### SAFE — Pulizia sicura

Elimina il contenuto di cartelle temporanee senza toccare file di sistema:
- `C:\Windows\Temp` e `%TEMP%` e `%LOCALAPPDATA%\Temp`
- Delivery Optimization cache (`C:\Windows\ServiceProfiles\NetworkService\...\DeliveryOptimization\Cache`)
- Windows Error Reporting cache (`C:\ProgramData\Microsoft\Windows\WER`)
- Thumbnail Cache Explorer (`%LOCALAPPDATA%\Microsoft\Windows\Explorer`)
- Cache Edge, Chrome, Firefox (tutti i profili trovati)
- Cestino (tramite `Clear-RecycleBin`)

La funzione `Clean-Folder` distingue tra file eliminati, file bloccati (in uso) e spazio liberato, loggando i dettagli.

### DEEP — Pulizia approfondita

Include tutto di SAFE più:
- Svuotamento cache Windows Update (`C:\Windows\SoftwareDistribution\Download`): ferma i servizi WU, svuota la cartella, riavvia i servizi.
- `DISM /Online /Cleanup-Image /StartComponentCleanup` — rimuove versioni obsolete di componenti Windows dal WinSxS store. Può liberare 1-5 GB. Richiede 10-30 minuti.

---

## Modulo 50_STARTUP

**File:** `Modules/50_STARTUP/CLEAN.ps1`

Scansiona le Run key del registro e rimuove le voci che corrispondono a pattern noti di bloatware/startup non necessario:

Chiavi scansionate:
- `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run`
- `HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run` (app 32-bit)
- `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`
- `HKCU\Software\Microsoft\Windows\CurrentVersion\RunOnce`

**Pattern rimossi**: OneDrive standalone updater, Steam (`steam.exe -silent`), Discord (`--start-minimized`), Spotify, Adobe Updater/ARM, McAfee updater, Skype for desktop, Teams consumer updater, Epic Games launcher, Ubisoft Connect.

**Pattern conservati sempre**: SecurityHealth, WindowsDefender, driver Intel/AMD/NVIDIA/Realtek, servizi Bluetooth, AutoHotkey, input tools Microsoft. Le cartelle Startup vengono solo auditate (log WARN) ma non modificate automaticamente.

---

## Modulo 90_LAB — Power Boost

**File:** `Modules/90_LAB/01_POWER_BOOST.ps1`

Attiva il piano di alimentazione **Ultimate Performance** (`{e9a42b02-d5df-448d-aa00-03f14749eb61}`) se disponibile (desktop/workstation), altrimenti **High Performance**. Su laptop viene usato **Bilanciato** per rispettare la batteria.

Su desktop, disabilita l'ibernazione (`powercfg /hibernate off`) per liberare spazio su disco equivalente alla dimensione della RAM (`hiberfil.sys` = dimensione RAM). Su un sistema con 32 GB di RAM libera 32 GB.

**Ultimate Performance** è un piano Microsoft introdotto in Windows 10 Pro for Workstations che elimina tutti i micro-delay del power management (nessun C-state CPU, nessun throttling GPU, latenza I/O minima). Non adatto a laptop per l'impatto sulla batteria e sul calore.

---

## File di configurazione

**File:** `Modules/Config/WinOpt.config.psd1`

```powershell
@{
  Profile = "BASE"   # BASE | ULTRA — influenza VERIFY (check WSearch)

  Features = @{
    WSearch = @{
      BaseEnabled  = $true    # WSearch attivo in modalità BASE
      UltraEnabled = $false   # WSearch disabilitato in ULTRA
    }
    DoH = @{
      EnableTemplates    = $true   # Registra server DoH Cloudflare/Google
      EnforceAdapterDns  = $true   # Cambia DNS adapter: 1.1.1.1 + router
    }
  }
}
```

La funzione `Get-WinOptConfig` in `Common.ps1` carica questo file con fallback ai valori default se mancante o malformato. Ogni script chiama `Get-Feature $cfg "Features.DoH.EnforceAdapterDns" $true` per leggere le singole voci in modo null-safe.

---

## Compatibilità periferiche

Nessuna modifica tocca i servizi: `Spooler` (stampanti), `PrintWorkflowUserSvc`, `bthserv`, `BthAvctpSvc`, `BluetoothUserService`. I pattern keeplist in `50_STARTUP/CLEAN.ps1` includono esplicitamente driver Realtek, Bluetooth e input tools.

Il menu contestuale classico (chiave CLSID in UIUX) agisce solo sull'interfaccia shell e non interferisce con driver o servizi.

---

## Versioning

| Versione | Principali cambiamenti |
|---|---|
| 2.0 | Prima versione pubblica, menu 13 opzioni, architettura modulare |
| 2.1 | Fix parsing task OneDrive (SID), STARTUP CLEAN nel menu |
| 2.2 | Fix RUNADMIN ExitCode, fix ONEDRIVE_MENU WARN spurio |
| 2.3 | Summary QUICK per moduli, fix dispatch menu |
| 2.4 | 8dot3/lastaccess, WU driver block, NetworkThrottlingIndex, SystemResponsiveness, menu contestuale classico, MenuShowDelay, WaitToKillAppTimeout |
| 2.5 | DNS DoH (EnableAutoDoh + template + adapter), VERIFY config-aware WSearch, pagefile deduplicato |
| 2.5.6 | Struttura modulare consolidata, logging centralizzato C:\WinOpt\, score VERIFY |
| 2.5.7 | UAC centralizzato nel launcher (single elevation), ExitCode deterministici, RUNSCRIPT unificato, Assert-Admin come safety net, CRCRLF corretti, MOD_SHORT nel POST, MANIFEST SHA256, documentazione allineata |
| 2.5.7-p1 | Fix ONEDRIVE_MENU: riscritto con label esplicite (:OD_ON, :OD_OFF, :OD_VERIFY) — il compound `(call & goto :EOF)` causava chiusura anticipata della finestra senza mostrare il risultato POST |
