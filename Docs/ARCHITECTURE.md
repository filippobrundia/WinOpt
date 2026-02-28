# WinOpt 2.5.7 RELEASE

## Architettura generale

Il launcher (`LAUNCHER.cmd`) gestisce **un'unica elevazione UAC** all'avvio.
Tutti i moduli Admin girano nella stessa sessione elevata: nessun auto-relaunch,
ExitCode propagati correttamente al launcher.

## QUICK STABLE
Sequenza automatica:
1. BASELINE (Admin)
2. EDGE (Admin) — policy di sistema; su Edge consumer alcune vengono ignorate (expected)
3. UIUX (User/HKCU) — non richiede admin
4. VERIFY (Admin)

## Moduli disponibili
| # | Modulo | Privilegi |
|---|--------|-----------|
| 01 | BASELINE — ottimizzazioni OS, servizi, telemetria | Admin |
| 02 | UIUX — prestazioni visive, HKCU | User |
| 03 | EDGE — policy privacy/performance browser | Admin |
| 04 | VERIFY — controllo stato suite con score | Admin |
| 10 | ULTRA ADDON — ottimizzazioni aggiuntive | Admin |
| 20 | ONEDRIVE ON/OFF — abilita o disabilita OneDrive | Admin |
| 30 | APPS — installazione app via winget | Admin |
| 40 | CLEAN SAFE/DEEP — pulizia disco | Admin |
| 50 | STARTUP CLEAN — ottimizzazione avvio | Admin |
| 90 | LAB / POWER BOOST — sperimentale | Admin |

## Struttura file
```
LAUNCHER.cmd                  — entry point, elevazione UAC, menu
Modules/
  _COMMON/Common.ps1          — funzioni condivise (unica source of truth)
  _COMMON/Preflight.ps1       — controlli pre-volo (admin, spazio disco, restore point)
  Config/WinOpt.config.psd1   — configurazione suite
  01_BASELINE/APPLY.ps1
  01_BASELINE/VERIFY.ps1
  ... (ogni modulo: APPLY + VERIFY dove applicabile)
Docs/
```

## Log e stato
- Log: `C:\WinOpt\Logs\`
- Stato moduli: `C:\WinOpt\State\`
- Flag launcher: `C:\WinOpt\State\launcher.flag`
- Backup registro/servizi: `C:\WinOpt\State\Backup\`

## Note operative
- `Assert-Admin` in ogni modulo Admin è un **safety net** per lancio diretto
  fuori dal launcher: esce con `exit 1` e messaggio chiaro.
- Con il launcher elevato, `Assert-Admin` passa sempre senza effetti collaterali.
- VERIFY_DEEP aggrega gli exitcode di entrambi gli step: se uno fallisce → exitcode 1.
