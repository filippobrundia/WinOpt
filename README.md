# WinOpt

> **Windows 11 the way it should be** — privacy, performance and zero bloat, reproducible on every reinstall.

![Windows 11](https://img.shields.io/badge/Windows-11-0078D4?logo=windows11)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell)
![Version](https://img.shields.io/badge/version-2.5.8-brightgreen)
![License](https://img.shields.io/badge/license-MIT-blue)

---

> ⚠️ **This tool is designed for personal devices only.**
> Do not run on corporate, managed, or MDM/Intune-enrolled machines.
> If you are a sysadmin looking for enterprise hardening, use CIS Baselines or Microsoft Security Baselines instead.

---

## The problem it solves

Windows 11 ships with active telemetry, Copilot, OneDrive, dozens of useless services and preinstalled apps you never asked for. You can disable them one by one — but after the next reinstall, it all starts over.

WinOpt is a suite of scripts you run **once** after a clean Windows 11 installation and get a quiet, private and fast machine. The experience of running Windows LTSC, without buying a volume license or giving up the Store and security updates.

**Who it's for**

- People who reinstall Windows often and want to automate optimizations
- People managing multiple PCs who want reproducible configurations
- Power users, privacy-focused users, gamers who want to reduce background noise
- People who want to understand what is being changed (everything is documented and logged)

**Who it's NOT for**

- People who actively use OneDrive, Teams consumer, Copilot or Windows Recall
- Corporate environments managed by MDM/Intune
- People who prefer to keep Windows in the default Microsoft configuration

---

## What it does

### Privacy
- Disables telemetry, diagnostics, CEIP and advertising ID
- Disables Cortana, Bing in search, Copilot and Windows Recall
- Blocks Activity History, cross-device sync, Find My Device
- Blocks automatic driver installation via Windows Update
- DNS over HTTPS — Cloudflare 1.1.1.1 with fallback to local router DNS

### Performance
- Disables non-essential services: Xbox Live, DiagTrack, WerSvc, SysMain (on SSD)
- Optimizes CPU parameters: NetworkThrottlingIndex, SystemResponsiveness
- Fixed pagefile on SSD (eliminates fragmentation from dynamic resizing)
- NTFS: disables 8.3 name generation and LastAccessTime update
- Ultimate Performance power plan on desktops, High Performance on laptops

### UI/UX
- System dark mode, visible file extensions, Explorer opens "This PC"
- Classic Windows 10 context menu (no "Show more options" click)
- MenuShowDelay 20ms (from 400ms), WaitToKillAppTimeout 3000ms
- Removes Game DVR and background app throttling

### Edge
- No auto-start, no background mode when closed
- No shopping assistant, sidebar, Microsoft Rewards, Spotlight
- uBlock Origin force-installed via policy
- Do Not Track enabled, diagnostic data disabled

### Debloat
Removes ~30 preinstalled apps: Xbox, Teams consumer, Widgets, Clipchamp, BingNews, Cortana, OneDrive (optional), Office Hub, LinkedIn, WhatsApp Desktop and others.

Intentionally kept: Store, Calculator, Photos, Notepad, Paint, Snipping Tool, Clock.

### Included tools
| Module | Function |
|---|---|
| ULTRA ADDON | Advanced optimizations: WSearch off, SysMain off, transparency disabled |
| ONEDRIVE | Reversible on/off toggle with full registry and services backup |
| APPS INSTALL | Silent installation via winget from a customizable JSON list |
| CLEAN SAFE | Temp, browser cache, WER, thumbnail cache, Recycle Bin cleanup |
| CLEAN DEEP | SAFE + Windows Update cache + DISM ComponentCleanup |
| STARTUP CLEAN | Removal of bloatware autostart entries from Run keys |
| VERIFY | Post-apply check with numeric score, detects drift after updates |
| POWER BOOST | Optimal power plan with laptop/desktop detection |

---

## How to use

**Requirements**: Windows 11 (22H2, 23H2, 24H2 or 25H2) — PowerShell 5.1+ — Administrator account

```
1. Download WinOpt_2.5.8.zip from the Releases page
2. Extract to a folder of your choice (e.g. C:\WinOpt-setup\)
3. Right-click LAUNCHER.cmd → "Run as administrator"
4. From the menu select → Q (QUICK STABLE)
5. Read the on-screen summary when done
6. Restart Windows
```

**QUICK STABLE** applies in the recommended order: BASELINE → EDGE → UIUX → VERIFY.
This is the safe sequence for a complete first-time setup.

All logs are saved to `C:\WinOpt\Logs\` with the name `MODULE_ACTION_DATE.log`.

---

## Reversibility

Before every change, a **system Restore Point** is automatically created.
If something goes wrong: Start → type `rstrui` → Enter → follow the wizard.

Original registry values, services and tasks are saved to `C:\WinOpt\State\Backup\`
before every run. The OneDrive module uses these backups for full restoration.

---

## Project structure

```
WinOpt/
├── LAUNCHER.cmd                     ← Entry point — UAC elevation once only
├── MANIFEST_SHA256.txt              ← SHA256 hash of all files for integrity verification
├── Modules/
│   ├── _COMMON/
│   │   ├── Common.ps1               ← Shared functions (logging, registry, backup)
│   │   └── Preflight.ps1            ← Pre-execution checks (PS version, space, admin)
│   ├── Config/
│   │   └── WinOpt.config.psd1       ← Configuration (profile, WSearch, DoH)
│   ├── 01_BASELINE/                 ← Telemetry, services, tasks, debloat, DNS, pagefile
│   ├── 02_UIUX/                     ← Dark mode, Explorer, context menu, animations
│   ├── 03_EDGE/                     ← Edge policies + user preferences + uBlock
│   ├── 04_VERIFY/                   ← System state check with score
│   ├── 10_ULTRA_ADDON/              ← Advanced optimizations (run after BASELINE)
│   ├── 20_ONEDRIVE/                 ← OneDrive management: OFF / ON / STATUS
│   ├── 30_APPS/                     ← App installation via winget + JSON policy
│   ├── 40_CLEAN/                    ← Disk cleanup: SAFE / DEEP / AUDIT
│   ├── 50_STARTUP/                  ← Autostart entries cleanup
│   └── 90_LAB/                      ← Power Boost (power plan)
└── Docs/
    ├── ARCHITECTURE.md              ← Internal architecture description
    └── WinOpt_Complete_Guide_v2.5.8.docx  ← Full guide with explanation of every setting
```

---

## Technical documentation

The file `TECHNICAL_GUIDE.md` in the root contains the complete developer documentation:
architecture, every modified registry key, logic of each module and design decisions.

The file `Docs/WinOpt_Complete_Guide_v2.5.8.docx` contains a detailed explanation of every single setting — what it does, why it is applied, and what value it is set to.

---

## Security

- Never disables Windows Defender
- Does not touch system drivers or kernel components
- Every change has automatic backup before execution
- System Restore Point created before every run
- File integrity verification via `MANIFEST_SHA256.txt`

To report vulnerabilities or security issues see [SECURITY.md](SECURITY.md).

---

## Contributing

Pull requests welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

---

## Disclaimer

> ⚠️ This suite modifies Windows services, registry and configurations.
> The author is not responsible for any damage resulting from its use.
> **Always use on a system with a recent backup.**
> **For personal devices only — not intended for corporate or managed environments.**
> Not affiliated with Microsoft.

---

## License

[MIT](LICENSE) — © 2025 WinOpt Contributors
