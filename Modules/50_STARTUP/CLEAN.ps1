#Requires -Version 5.1
<#  WIN_OPT_CLAUDE - 50_STARTUP - CLEAN (ADMIN)
    v1.0
    Gestisce le voci di avvio automatico (Run keys + Startup folder).
    Logica:
      - Lista TUTTO quello che parte all'avvio (Run HKCU, HKLM, Startup folders)
      - Disabilita le voci note come non essenziali / bloatware
      - Conserva le voci di sistema, AV, driver essenziali
      - Backup completo prima di qualsiasi modifica
      - NON tocca: Task Scheduler, servizi (già gestiti da BASELINE/ULTRA)
#>

. "$PSScriptRoot\..\_COMMON\Common.ps1"
# Elevation is handled by LAUNCHER.cmd (single UAC).
# Assert-Admin below is a safety net for direct execution outside the launcher.
$MOD = "50_STARTUP"
$Log = New-LogPath $MOD "CLEAN"
$ACT = "CLEAN"
if (Get-Command Reset-WinOptLogCounters -ErrorAction SilentlyContinue) { Reset-WinOptLogCounters }
$BackupDir = Join-Path $script:WOC_BACKUP_ROOT $MOD
Ensure-Dir $BackupDir
$BackupFile = Join-Path $BackupDir "startup_backup.jsonl"
Remove-Item -LiteralPath $BackupFile -ErrorAction SilentlyContinue

Write-Log $Log "=== STARTUP CLEAN START ===" "INFO"
Assert-Admin $Log

# ═══════════════════════════════════════════════════════════════════
# Pattern da DISABILITARE (case-insensitive match sul nome o sul path)
# Categorizzati per chiarezza. Aggiungi pure voci specifiche del tuo env.
# ═══════════════════════════════════════════════════════════════════
$removePatterns = @(
    # ── Microsoft bloatware ──────────────────────────────────────────
    @{P="OneDrive";         R="OneDrive autorun (gestito da 20_ONEDRIVE)"},
    @{P="OneDriveSetup";    R="OneDrive Setup"},
    @{P="MicrosoftEdgeAutoLaunch"; R="Edge auto-launch"},
    @{P="EdgeUpdate";       R="Edge Update helper"},
    @{P="Teams";            R="Microsoft Teams consumer"},
    @{P="com.squirrel.Teams"; R="Teams Squirrel updater"},
    @{P="Skype";            R="Skype autorun"},

    # ── Adobe ────────────────────────────────────────────────────────
    @{P="AdobeAAMUpdater";  R="Adobe AAM Updater"},
    @{P="Adobe Acrobat";    R="Adobe Acrobat autorun"},
    @{P="AdobeGCInvoker";   R="Adobe GC Invoker"},
    @{P="com.adobe";        R="Adobe helper"},

    # ── Comunicazione / Social ───────────────────────────────────────
    @{P="Discord";          R="Discord autostart"},
    @{P="Spotify";          R="Spotify autostart"},
    @{P="Steam";            R="Steam client autostart (non necessario all'avvio)"},
    @{P="EpicGamesLauncher"; R="Epic Games Launcher"},
    @{P="WhatsApp";         R="WhatsApp desktop autorun"},
    @{P="Telegram";         R="Telegram autorun"},
    @{P="Slack";            R="Slack autorun"},
    @{P="Zoom";             R="Zoom autorun"},

    # ── Produttività / Office ────────────────────────────────────────
    @{P="com.squirrel.Slack"; R="Slack Squirrel updater"},
    @{P="GoogleDriveSync";  R="Google Drive Sync"},
    @{P="Dropbox";          R="Dropbox autorun"},
    @{P="Box";              R="Box Sync autorun"},

    # ── Updater / helper commerciali ────────────────────────────────
    @{P="NortonSecurity";   R="Norton helper"},
    @{P="McAfee";           R="McAfee helper"},
    @{P="Avast";            R="Avast autorun"},
    @{P="AVG";              R="AVG autorun"},
    @{P="Bitdefender";      R="Bitdefender tray"},
    @{P="CCleaner";         R="CCleaner monitoring (scam optimizer)"},
    @{P="IObit";            R="IObit helper (scam optimizer)"},
    @{P="Driver Booster";   R="Driver Booster (scam optimizer)"},

    # ── Produttori hardware ──────────────────────────────────────────
    @{P="CorsairHID";       R="Corsair HID helper"},
    @{P="RAZERSynapse";     R="Razer Synapse"},
    @{P="ICUE";             R="Corsair iCUE"},
    @{P="LogiOptions";      R="Logitech Options"},
    @{P="LogiTray";         R="Logitech tray"},
    @{P="NahimicSvc";       R="Nahimic audio"},
    @{P="ArmouryCrate";     R="ASUS Armory Crate"},
    @{P="MSI Center";       R="MSI Center"},
    @{P="SteelSeriesGG";    R="SteelSeries GG"},

    # ── Varie ────────────────────────────────────────────────────────
    @{P="WinZip";           R="WinZip autorun"},
    @{P="qbittorrent";      R="qBittorrent autorun"},
    @{P="uTorrent";         R="uTorrent autorun"},
    @{P="VirtualBox";       R="VirtualBox tray"}
)

# ═══════════════════════════════════════════════════════════════════
# Pattern da CONSERVARE sempre (override dei remove patterns)
# ═══════════════════════════════════════════════════════════════════
$keepPatterns = @(
    "SecurityHealth",     # Windows Security
    "WindowsDefender",    # Defender
    "MsMpEng",            # Defender engine
    "VBoxService",        # VirtualBox guest (macchina virtuale)
    "vmware",             # VMware tools
    "ctfmon",             # CTF Monitor (input methods)
    "igfxtray",           # Intel GPU tray (driver)
    "igfxhk",             # Intel GPU hotkey (driver)
    "nvtmru",             # NVIDIA tray (driver)
    "nvcplui",            # NVIDIA Control Panel
    "Realtek",            # Realtek audio
    "IntelliPoint",       # Microsoft mouse driver
    "IntelliType",        # Microsoft keyboard driver
    "BthUDTask",          # Bluetooth
    "BTTray",             # Bluetooth tray
    "hkcmd",              # Intel hotkey daemon
    "persistence",        # Intel GPU persistence
    "AutoHotkey",         # AHK scripts utente
    "PrintIsolationHost"  # Print spooler
)

# ═══════════════════════════════════════════════════════════════════
# Funzione: testa se un nome/path è nella keeplist
# ═══════════════════════════════════════════════════════════════════
function Should-Keep {
    param([string]$Name, [string]$Value)
    foreach ($k in $keepPatterns) {
        if ($Name -ilike "*$k*" -or $Value -ilike "*$k*") { return $true }
    }
    return $false
}

# ═══════════════════════════════════════════════════════════════════
# Raccolta e processo Run keys
# ═══════════════════════════════════════════════════════════════════
$runKeys = @(
    @{Hive="HKLM"; Key="HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"},
    @{Hive="HKLM"; Key="HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"},
    @{Hive="HKCU"; Key="HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"},
    @{Hive="HKCU"; Key="HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce"}
)

$disabled = 0; $kept = 0; $skipped = 0

foreach ($rk in $runKeys) {
    try {
        $props = Get-ItemProperty -Path $rk.Key -ErrorAction Stop
        $entries = $props.PSObject.Properties | Where-Object { $_.Name -notlike "PS*" }
        foreach ($e in $entries) {
            $name = $e.Name
            $val  = [string]$e.Value

            # Keep override
            if (Should-Keep $name $val) {
                Write-Log $Log ("[KEEP]   [{0}] {1,-30} -> {2}" -f $rk.Hive, $name, $val) "INFO"
                $kept++
                continue
            }

            # Check remove patterns
            $matched = $null
            foreach ($p in $removePatterns) {
                if ($name -ilike "*$($p.P)*" -or $val -ilike "*$($p.P)*") {
                    $matched = $p
                    break
                }
            }

            if ($matched) {
                # Backup
                @{ Key=$rk.Key; Name=$name; Value=$val; Reason=$matched.R } |
                    ConvertTo-Json -Compress | Add-Content -Path $BackupFile -Encoding UTF8
                # Remove
                try {
                    Remove-ItemProperty -Path $rk.Key -Name $name -ErrorAction Stop
                    Write-Log $Log ("[RIMOSSO] [{0}] {1,-30} ({2})" -f $rk.Hive, $name, $matched.R) "OK"
                    $disabled++
                } catch {
                    Write-Log $Log ("[FAIL]   [{0}] {1}: {2}" -f $rk.Hive, $name, $_.Exception.Message) "WARN"
                }
            } else {
                Write-Log $Log ("[INFO]   [{0}] {1,-30} -> {2}" -f $rk.Hive, $name, $val) "INFO"
                $skipped++
            }
        }
    } catch {
        Write-Log $Log ("Run key non trovata: {0}" -f $rk.Key) "SKIP"
    }
}

# ═══════════════════════════════════════════════════════════════════
# Startup folders (solo elenca, non rimuove — troppo vario)
# ═══════════════════════════════════════════════════════════════════
Write-Log $Log "--- Startup folders (solo audit) ---"
$startFolders = @(
    "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup",
    "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp"
)
foreach ($sf in $startFolders) {
    if (Test-Path -LiteralPath $sf) {
        $items = Get-ChildItem -LiteralPath $sf -ErrorAction SilentlyContinue
        if ($items) {
            foreach ($i in $items) {
                Write-Log $Log ("[STARTUP_FOLDER] {0}" -f $i.FullName) "WARN"
            }
        } else {
            Write-Log $Log ("[STARTUP_FOLDER] {0}: vuota." -f $sf) "OK"
        }
    }
}

# ═══════════════════════════════════════════════════════════════════
# Sommario
# ═══════════════════════════════════════════════════════════════════
Write-Log $Log "==="
Write-Log $Log ("SOMMARIO: Rimossi={0}  Conservati={1}  Non riconosciuti={2}" -f $disabled, $kept, $skipped) $(
    if ($disabled -gt 0) { "OK" } else { "INFO" }
)
Write-Log $Log ("Backup in: {0}" -f $BackupFile) "INFO"
Write-Log $Log "NOTA: le voci non riconosciute ([INFO]) richiedono valutazione manuale." "INFO"
Write-Log $Log "NOTA: le modifiche Run key sono immediate (no riavvio)." "INFO"
Write-Log $Log "NOTA: voci nelle Startup folders segnalate come [WARN] ma non rimosse." "INFO"
Write-Log $Log "==="
Write-Log $Log "=== STARTUP CLEAN END ===" "INFO"

Write-Host ""
Write-Host "  Log salvato: $Log" -ForegroundColor Cyan
Write-Host ""
if (Get-Command Write-WinOptFooter -ErrorAction SilentlyContinue) { Write-WinOptFooter $Log $MOD $ACT }
if (Get-Command Pause-WinOptIfInteractive -ErrorAction SilentlyContinue) { Pause-WinOptIfInteractive }
