#Requires -Version 5.1
<#  WIN_OPT_CLAUDE - 01_BASELINE - APPLY (ADMIN)
    v1.5 - nuove sezioni:
      + Bing nella ricerca Start disabilitato
      + Windows Recall/AI disabilitato (build 24H2+)
      + Input Personalization / ink & typing off
      + Copilot policy off
      + Cross-device clipboard, Lock screen camera, SettingSync, Location scripting
      + Pagefile fisso su SSD (riduce write, libera spazio)
#>

. "$PSScriptRoot\..\_COMMON\Common.ps1"
# Elevation is handled by LAUNCHER.cmd (single UAC).
# Assert-Admin below is a safety net for direct execution outside the launcher.
$MOD       = "01_BASELINE"
$Log       = New-LogPath $MOD "APPLY"
Assert-Admin $Log
$cfg       = Get-WinOptConfig
$ACT       = "APPLY"
if (Get-Command Reset-WinOptLogCounters -ErrorAction SilentlyContinue) { Reset-WinOptLogCounters }
$BackupDir = Join-Path $script:WOC_BACKUP_ROOT $MOD
Ensure-Dir $BackupDir

$BackupReg  = Join-Path $BackupDir "reg.jsonl"
$BackupSvc  = Join-Path $BackupDir "services.txt"
$BackupTask = Join-Path $BackupDir "tasks.txt"

Write-Log $Log "=== BASELINE APPLY START ===" "INFO"
# ── PREFLIGHT (restore point + space check) ───────────────────────────────────
& "$PSScriptRoot\..\_COMMON\Preflight.ps1"
if ($LASTEXITCODE -ne 0) {
    Write-Host "  Preflight fallito. Operazione annullata." -ForegroundColor Red
    exit 1
}
# Admin check: in condizioni normali è già elevato dal LAUNCHER.cmd.
# Manteniamo un controllo leggero per evitare "ghost" se qualcuno lancia lo script a mano.
try {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
              ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
} catch { $isAdmin = $false }

if (-not $isAdmin) {
    Write-Log $Log "Privilegi amministrativi richiesti. Avvia LAUNCHER.cmd come amministratore (UAC singolo) e rilancia." "FAIL"
    Write-Host "ERRORE: Privilegi amministrativi richiesti. Avvia LAUNCHER.cmd come amministratore." -ForegroundColor Red
    exit 1
}

# ── Windows Search (WSearch) ────────────────────────────────────────────────
$baseWSearchEnabled  = Get-Feature $cfg "Features.WSearch.BaseEnabled"      $true
$cfgDoHTemplates     = Get-Feature $cfg "Features.DoH.EnableTemplates"       $true
$cfgEnforceAdapterDns = Get-Feature $cfg "Features.DoH.EnforceAdapterDns"   $false
if ($baseWSearchEnabled) {
    Set-ServiceStart $Log "WSearch" "Automatic"; Start-ServiceSafe $Log "WSearch"
    Write-Log $Log "BASE: WSearch attivo (default). Disabilitalo solo se sai cosa perdi (Start/Explorer/Outlook search)." "INFO"
} else {
    Write-Log $Log "BASE: WSearch disabilitato via config. Nota: ricerca Start/Explorer può diventare più lenta." "WARN"
    Set-ServiceStart $Log "WSearch" "Disabled"; Stop-ServiceSafe $Log "WSearch"
}

Remove-Item -LiteralPath $BackupReg  -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $BackupSvc  -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $BackupTask -ErrorAction SilentlyContinue

# ── PATH REGISTRY ─────────────────────────────────────────────────────────────
$kDC    = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
$kDC2   = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection"
$kCC    = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
$kWER   = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting"
$kDO    = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization"
$kSQM   = "HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows"
$kADV   = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo"
$kDsh   = "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"
$kSrch  = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"
$kInp   = "HKLM:\SOFTWARE\Policies\Microsoft\InputPersonalization"
$kCop   = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"
$kAI    = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"
$kAct   = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
$kFMD   = "HKLM:\SOFTWARE\Policies\Microsoft\FindMyDevice"
$kSync  = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync"
$kLoc   = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors"
$kPerso = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization"

# ── BACKUP ──────────────────────────────────────────────────────────────────
foreach ($kv in @(
    @($kDC,   "AllowTelemetry"),
    @($kDC,   "DoNotShowFeedbackNotifications"),
    @($kDC,   "LimitEnhancedDiagnosticDataWindowsAnalytics"),
    @($kDC,   "AllowDeviceNameInTelemetry"),
    @($kDC2,  "AllowTelemetry"),
    @($kSQM,  "CEIPEnable"),
    @($kCC,   "DisableWindowsConsumerFeatures"),
    @($kCC,   "DisableCloudOptimizedContent"),
    @($kCC,   "DisableLockScreenAppNotifications"),
    @($kCC,   "DisableWindowsSpotlightFeatures"),
    @($kCC,   "DisableWindowsSpotlightOnActionCenter"),
    @($kCC,   "DisableWindowsSpotlightOnSettings"),
    @($kCC,   "DisableTailoredExperiencesWithDiagnosticData"),
    @($kWER,  "Disabled"),
    @($kDO,   "DODownloadMode"),
    @($kADV,  "DisabledByGroupPolicy"),
    @($kDsh,  "AllowNewsAndInterests"),
    @($kSrch, "DisableWebSearch"),
    @($kSrch, "ConnectedSearchUseWeb"),
    @($kSrch, "AllowCortana"),
    @($kSrch, "BingSearchEnabled"),
    @($kInp,  "AllowInputPersonalization"),
    @($kInp,  "RestrictImplicitInkCollection"),
    @($kInp,  "RestrictImplicitTextCollection"),
    @($kCop,  "TurnOffWindowsCopilot"),
    @($kAI,   "DisableAIDataAnalysis"),
    @($kAI,   "AllowRecallEnablement"),
    @($kAct,  "EnableActivityFeed"),
    @($kAct,  "PublishUserActivities"),
    @($kAct,  "UploadUserActivities"),
    @($kFMD,  "AllowFindMyDevice"),
    @($kSync, "DisableSettingSync"),
    @($kSync, "DisableSettingsSyncUserOverride"),
    @($kLoc,  "DisableLocationScripting"),
    @($kPerso,"NoLockScreenCamera"),
    @($kWU,   "ExcludeWUDriversInQualityUpdate"),
    @($kSysP, "NetworkThrottlingIndex"),
    @($kSysP, "SystemResponsiveness"),
    @("HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters", "EnableAutoDoh")
)) { Backup-RegValue $BackupReg $kv[0] $kv[1] }
Write-Log $Log "Backup registro -> $BackupReg"

$svcList = @("DiagTrack","dmwappushservice","SysMain","WerSvc","XblAuthManager","XblGameSave","XboxGipSvc","XboxNetApiSvc","MapsBroker","RemoteRegistry")
Backup-ServiceStart $BackupSvc $svcList
Write-Log $Log "Backup servizi -> $BackupSvc"

$taskList = @(
    "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser",
    "\Microsoft\Windows\Application Experience\ProgramDataUpdater",
    "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator",
    "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip",
    "\Microsoft\Windows\Customer Experience Improvement Program\KernelCeipTask",
    "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector",
    "\Microsoft\Windows\Windows Error Reporting\QueueReporting"
)
Backup-TaskState $BackupTask $taskList
Write-Log $Log "Backup task -> $BackupTask"

# ── SERVIZI ──────────────────────────────────────────────────────────────────
Write-Log $Log "--- Configurazione servizi ---"
Set-ServiceStart $Log "DiagTrack"         "Disabled";  Stop-ServiceSafe $Log "DiagTrack"
Set-ServiceStart $Log "dmwappushservice"  "Disabled";  Stop-ServiceSafe $Log "dmwappushservice"
Set-ServiceStart $Log "SysMain"           "Automatic"
Set-ServiceStart $Log "WerSvc"            "Disabled";  Stop-ServiceSafe $Log "WerSvc"
Set-ServiceStart $Log "XblAuthManager"    "Disabled";  Stop-ServiceSafe $Log "XblAuthManager"
Set-ServiceStart $Log "XblGameSave"       "Disabled";  Stop-ServiceSafe $Log "XblGameSave"
Set-ServiceStart $Log "XboxGipSvc"        "Disabled";  Stop-ServiceSafe $Log "XboxGipSvc"
Set-ServiceStart $Log "XboxNetApiSvc"     "Disabled";  Stop-ServiceSafe $Log "XboxNetApiSvc"
Set-ServiceStart $Log "MapsBroker"        "Manual"
Set-ServiceStart $Log "RemoteRegistry"    "Manual";    Stop-ServiceSafe $Log "RemoteRegistry"

# ── TASK ─────────────────────────────────────────────────────────────────────
Write-Log $Log "--- Disabilitazione task ---"
foreach ($t in $taskList) { Disable-Task $Log $t }

# ── REGISTRO: TELEMETRIA ─────────────────────────────────────────────────────
Write-Log $Log "--- Registro: Telemetria ---"
Set-RegDword $Log $kDC  "AllowTelemetry"                              0
Set-RegDword $Log $kDC  "DoNotShowFeedbackNotifications"              1
Set-RegDword $Log $kDC  "LimitEnhancedDiagnosticDataWindowsAnalytics" 0
Set-RegDword $Log $kDC  "AllowDeviceNameInTelemetry"                  0
Set-RegDword $Log $kDC2 "AllowTelemetry"                              0
Set-RegDword $Log $kWER "Disabled"                                    1
Set-RegDword $Log $kDO  "DODownloadMode"                              0

# ── REGISTRO: CEIP ───────────────────────────────────────────────────────────
Write-Log $Log "--- Registro: CEIP ---"
Set-RegDword $Log $kSQM "CEIPEnable" 0

# ── REGISTRO: CLOUDCONTENT / SPOTLIGHT / LOCK SCREEN ────────────────────────
Write-Log $Log "--- Registro: CloudContent / Spotlight / Lock screen ---"
Set-RegDword $Log $kCC "DisableWindowsConsumerFeatures"               1
Set-RegDword $Log $kCC "DisableCloudOptimizedContent"                 1
Set-RegDword $Log $kCC "DisableLockScreenAppNotifications"            1
Set-RegDword $Log $kCC "DisableWindowsSpotlightFeatures"              1
Set-RegDword $Log $kCC "DisableWindowsSpotlightOnActionCenter"        1
Set-RegDword $Log $kCC "DisableWindowsSpotlightOnSettings"            1
Set-RegDword $Log $kCC "DisableTailoredExperiencesWithDiagnosticData" 1


# ── REGISTRO: CONTENTDELIVERYMANAGER (SUGGERIMENTI) ──────────────────────────
Write-Log $Log "--- Registro: ContentDeliveryManager (suggerimenti Start/Store) ---"
$kCDM  = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
$kWU   = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
$kSysP = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
Set-RegDword $Log $kCDM "SilentInstalledAppsEnabled"  0
Set-RegDword $Log $kCDM "SystemPaneSuggestionsEnabled" 0
Set-RegDword $Log $kCDM "PreInstalledAppsEnabled"     0
Set-RegDword $Log $kCDM "OemPreInstalledAppsEnabled"  0

# ── REGISTRO: ADVERTISING ID ─────────────────────────────────────────────────
Write-Log $Log "--- Registro: Advertising ID ---"
Set-RegDword $Log $kADV "DisabledByGroupPolicy" 1

# ── REGISTRO: WIDGET TASKBAR ─────────────────────────────────────────────────
Write-Log $Log "--- Registro: Widget taskbar (HKLM Dsh) ---"
Set-RegDword $Log $kDsh "AllowNewsAndInterests" 0

# ── REGISTRO: BING / RICERCA START ───────────────────────────────────────────
Write-Log $Log "--- Registro: Bing / ricerca Start ---"
Set-RegDword $Log $kSrch "DisableWebSearch"     1
Set-RegDword $Log $kSrch "ConnectedSearchUseWeb" 0
Set-RegDword $Log $kSrch "AllowCortana"          0
Set-RegDword $Log $kSrch "BingSearchEnabled"     0

# ── REGISTRO: INPUT PERSONALIZATION ──────────────────────────────────────────
Write-Log $Log "--- Registro: Input personalization / ink & typing ---"
Set-RegDword $Log $kInp "AllowInputPersonalization"       0
Set-RegDword $Log $kInp "RestrictImplicitInkCollection"   1
Set-RegDword $Log $kInp "RestrictImplicitTextCollection"  1

# ── REGISTRO: COPILOT ────────────────────────────────────────────────────────
Write-Log $Log "--- Registro: Copilot policy ---"
Set-RegDword $Log $kCop "TurnOffWindowsCopilot" 1

# ── REGISTRO: WINDOWS RECALL / AI ────────────────────────────────────────────
Write-Log $Log "--- Registro: Windows Recall / AI (24H2+) ---"
Set-RegDword $Log $kAI "DisableAIDataAnalysis"  1
Set-RegDword $Log $kAI "AllowRecallEnablement"  0

# ── REGISTRO: ACTIVITY HISTORY ─────────────────────────────────────────────
Write-Log $Log "--- Registro: Activity History ---"
Set-RegDword $Log $kAct "EnableActivityFeed"    0
Set-RegDword $Log $kAct "PublishUserActivities"  0
Set-RegDword $Log $kAct "UploadUserActivities"   0

# ── REGISTRO: FIND MY DEVICE ────────────────────────────────────────────────
Write-Log $Log "--- Registro: Find My Device ---"
Set-RegDword $Log $kFMD "AllowFindMyDevice" 0

# ── REGISTRO: CROSS-DEVICE CLIPBOARD ────────────────────────────────────────
Write-Log $Log "--- Registro: Cross-device clipboard ---"
Set-RegDword $Log $kAct "AllowCrossDeviceClipboard" 0

# ── REGISTRO: LOCK SCREEN CAMERA ─────────────────────────────────────────────
Write-Log $Log "--- Registro: Lock screen camera ---"
Set-RegDword $Log $kPerso "NoLockScreenCamera" 1

# ── REGISTRO: SETTINGS SYNC (cloud) ─────────────────────────────────────────
Write-Log $Log "--- Registro: Settings Sync cloud ---"
Set-RegDword $Log $kSync "DisableSettingSync"              2
Set-RegDword $Log $kSync "DisableSettingsSyncUserOverride" 1

# ── REGISTRO: LOCATION SCRIPTING ────────────────────────────────────────────
# DisableLocationScripting=1: blocca accesso location tramite API/script.
# NON disabilita il GPS fisico o le app che l'utente ha autorizzato esplicitamente.
Write-Log $Log "--- Registro: Location scripting ---"
Set-RegDword $Log $kLoc "DisableLocationScripting" 1

# ── DEBLOAT APPX ─────────────────────────────────────────────────────────────
Write-Log $Log "--- Debloat Appx ---"
function Remove-AppxAndProv {
    param([string]$Label, [string[]]$NamePatterns)
    try {
        $found = @()
        foreach ($pat in $NamePatterns) {
            $found += Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { $_.Name -like $pat }
        }
        $found = $found | Sort-Object PackageFullName -Unique
        if (-not $found -or $found.Count -eq 0) {
            Write-Log $Log ("Appx: {0} -> NONE" -f $Label) "INFO"
        } else {
            foreach ($p in $found) {
                try { Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction Stop; Write-Log $Log ("OK Appx: {0}" -f $p.Name) "OK" }
                catch { Write-Log $Log ("FAIL Appx: {0} ({1})" -f $p.Name, $_.Exception.Message) "WARN" }
            }
        }
        $prov = @()
        foreach ($pat in $NamePatterns) {
            $prov += Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like $pat }
        }
        $prov = $prov | Sort-Object PackageName -Unique
        if (-not $prov -or $prov.Count -eq 0) {
            Write-Log $Log ("Prov: {0} -> NONE" -f $Label) "INFO"
        } else {
            foreach ($pp in $prov) {
                try { Remove-AppxProvisionedPackage -Online -PackageName $pp.PackageName -ErrorAction Stop | Out-Null; Write-Log $Log ("OK Prov: {0}" -f $pp.DisplayName) "OK" }
                catch { Write-Log $Log ("FAIL Prov: {0} ({1})" -f $pp.DisplayName, $_.Exception.Message) "WARN" }
            }
        }
    } catch { Write-Log $Log ("Debloat {0}: errore {1}" -f $Label, $_.Exception.Message) "WARN" }
}

Remove-AppxAndProv "Xbox App"                @("Microsoft.XboxApp*")
Remove-AppxAndProv "Gaming App"              @("Microsoft.GamingApp*")
Remove-AppxAndProv "Xbox Game Bar Overlay"   @("Microsoft.XboxGamingOverlay*")
Remove-AppxAndProv "Xbox Game Overlay"       @("Microsoft.XboxGameOverlay*")
Remove-AppxAndProv "Xbox Speech Overlay"     @("Microsoft.XboxSpeechToTextOverlay*")
Remove-AppxAndProv "WebExperience / Widgets" @("MicrosoftWindows.Client.WebExperience*","Microsoft.WindowsWidgets*")
Remove-AppxAndProv "Copilot"                 @("Microsoft.Copilot*")
Remove-AppxAndProv "Office Hub (Microsoft 365)" @("Microsoft.MicrosoftOfficeHub*")
Remove-AppxAndProv "Teams (consumer)"        @("MicrosoftTeams*","MSTeams*")
Remove-AppxAndProv "Phone Link"              @("Microsoft.YourPhone*")
Remove-AppxAndProv "Get Help"                @("Microsoft.GetHelp*")
Remove-AppxAndProv "Get Started"             @("Microsoft.Getstarted*")
Remove-AppxAndProv "Feedback Hub"            @("Microsoft.WindowsFeedbackHub*")
Remove-AppxAndProv "People"                  @("Microsoft.People*")
Remove-AppxAndProv "Solitaire"               @("Microsoft.MicrosoftSolitaireCollection*")
Remove-AppxAndProv "Groove Music"            @("Microsoft.ZuneMusic*")
Remove-AppxAndProv "Movies & TV"             @("Microsoft.ZuneVideo*")
Remove-AppxAndProv "Clipchamp"               @("Clipchamp.Clipchamp*")
Remove-AppxAndProv "Bing News"               @("Microsoft.BingNews*")
Remove-AppxAndProv "Bing Weather"            @("Microsoft.BingWeather*")
Remove-AppxAndProv "Maps"                    @("Microsoft.WindowsMaps*")
Remove-AppxAndProv "Outlook (New)"           @("Microsoft.OutlookForWindows*","Microsoft.Office.Outlook*")
Remove-AppxAndProv "Power Automate"          @("*PowerAutomate*","Microsoft.PowerAutomate*")
Remove-AppxAndProv "Bing Search"             @("Microsoft.BingSearch*")
Remove-AppxAndProv "Bing Apps (altri)"       @("Microsoft.Bing*")
Remove-AppxAndProv "Microsoft Family"        @("*MicrosoftFamily*","*FamilySafety*","MicrosoftCorporationII.MicrosoftFamily*")
Remove-AppxAndProv "LinkedIn"                @("*LinkedIn*","7EE7776C.LinkedIn*")
Remove-AppxAndProv "WhatsApp"                @("*WhatsApp*","5319275A.WhatsAppDesktop*")
Remove-AppxAndProv "Dev Home"                @("Microsoft.Windows.DevHome*")
Remove-AppxAndProv "QuickAssist"             @("MicrosoftCorporationII.QuickAssist*")
Remove-AppxAndProv "CrossDevice"             @("MicrosoftWindows.CrossDevice*")
Remove-AppxAndProv "Sticky Notes"            @("Microsoft.MicrosoftStickyNotes*")

Write-Log $Log "NOTA: rimozioni Appx non ripristinate automaticamente." "WARN"
Write-Log $Log "NOTA: WindowsStore, Defender, GamingServices NON toccati." "INFO"



# ── FILE SYSTEM: 8.3 + LAST ACCESS ──────────────────────────────────────────
Write-Log $Log "--- File System: disabilita nomi 8.3 e last-access timestamp ---"
try {
    $r = & fsutil behavior set disable8dot3 1 2>&1
    Write-Log $Log ("fsutil disable8dot3 = 1 | {0}" -f ($r -join " ")) "OK"
} catch {
    Write-Log $Log ("fsutil disable8dot3: {0}" -f $_.Exception.Message) "WARN"
}
try {
    $r = & fsutil behavior set disablelastaccess 1 2>&1
    Write-Log $Log ("fsutil disablelastaccess = 1 | {0}" -f ($r -join " ")) "OK"
} catch {
    Write-Log $Log ("fsutil disablelastaccess: {0}" -f $_.Exception.Message) "WARN"
}

# ── WINDOWS UPDATE: escludi driver automatici ────────────────────────────────
Write-Log $Log "--- Windows Update: blocco driver automatici ---"
Set-RegDword $Log $kWU "ExcludeWUDriversInQualityUpdate" 1

# ── MULTIMEDIA PROFILE: network throttling + system responsiveness ───────────
Write-Log $Log "--- Multimedia SystemProfile: network throttling + responsiveness ---"
# NetworkThrottlingIndex = 0xFFFFFFFF disabilita il throttling QoS sul traffico
# non-multimediale. Priorita' massima a tutti i dati di rete.
Set-RegDword $Log $kSysP "NetworkThrottlingIndex" 0xFFFFFFFF
# SystemResponsiveness = 0 -> priorita' massima al processo in foreground.
Set-RegDword $Log $kSysP "SystemResponsiveness" 0

# ── DNS over HTTPS (DoH) ─────────────────────────────────────────────────────
Write-Log $Log "--- DNS over HTTPS (DoH) ---"
$kDnscache = "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters"

# 1. Abilita DoH automatico: Windows usa DoH se il DNS primario e' nella lista
#    built-in (Cloudflare 1.1.1.1/1.0.0.1, Google 8.8.8.8/8.8.4.4)
Set-RegDword $Log $kDnscache "EnableAutoDoh" 2

# 2. Registra template DoH per Cloudflare e Google
if ($cfgDoHTemplates) {
    $dohServers = @(
        @{IP="1.1.1.1";   Template="https://cloudflare-dns.com/dns-query"},
        @{IP="1.0.0.1";   Template="https://cloudflare-dns.com/dns-query"},
        @{IP="8.8.8.8";   Template="https://dns.google/dns-query"},
        @{IP="8.8.4.4";   Template="https://dns.google/dns-query"}
    )
    foreach ($s in $dohServers) {
        try {
            Add-DnsClientDohServerAddress -ServerAddress $s.IP -DohTemplate $s.Template `
                -AllowFallbackToUdp $true -AutoUpgrade $true -ErrorAction Stop
            Write-Log $Log ("DoH template registrato: {0} -> {1}" -f $s.IP, $s.Template) "OK"
        } catch {
            if ($_.Exception.Message -like "*already*" -or $_.Exception.Message -like "*gia*") {
                Write-Log $Log ("DoH template gia' presente: {0}" -f $s.IP) "SKIP"
            } else {
                Write-Log $Log ("DoH template {0}: {1}" -f $s.IP, $_.Exception.Message) "WARN"
            }
        }
    }
}

# 3. Imposta DNS adapter: 1.1.1.1 primario + router come secondario
#    Solo se EnforceAdapterDns = $true nel config (default false per sicurezza)
if ($cfgEnforceAdapterDns) {
    Write-Log $Log "EnforceAdapterDns = true: imposto 1.1.1.1 primario su adapter attivi..." "INFO"
    $dohCapable = @("1.1.1.1","1.0.0.1","8.8.8.8","8.8.4.4")
    try {
        $adapters = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction Stop |
                    Where-Object { $_.ServerAddresses.Count -gt 0 -and
                                   $_.InterfaceAlias -notlike "*Loopback*" }
        foreach ($a in $adapters) {
            $currentDNS = @($a.ServerAddresses)
            $primary     = $currentDNS[0]
            if ($primary -in $dohCapable) {
                Write-Log $Log ("Adapter '{0}': DNS gia' DoH-capable ({1}), skip." -f $a.InterfaceAlias, $primary) "SKIP"
                continue
            }
            # Backup
            "{0}|{1}" -f $a.InterfaceAlias, ($currentDNS -join ",") |
                Add-Content -Path (Join-Path $BackupDir "dns_backup.txt") -Encoding UTF8
            # 1.1.1.1 primario, router attuale come secondario (fallback nomi locali)
            $newDNS = @("1.1.1.1", $primary)
            Set-DnsClientServerAddress -InterfaceIndex $a.InterfaceIndex `
                -ServerAddresses $newDNS -ErrorAction Stop
            Write-Log $Log ("Adapter '{0}': DNS impostato 1.1.1.1 (primario) + {1} (secondario, router)" `
                -f $a.InterfaceAlias, $primary) "OK"
        }
        Write-Log $Log "DNS backup in: $(Join-Path $BackupDir 'dns_backup.txt')" "INFO"
    } catch {
        Write-Log $Log ("DNS adapter: {0}" -f $_.Exception.Message) "WARN"
    }
} else {
    Write-Log $Log "EnforceAdapterDns = false (config): DNS adapter non modificati. DoH attivo se gia' su 1.1.1.1." "INFO"
}


# ── PULIZIA TEMP ─────────────────────────────────────────────────────────────
Write-Log $Log "--- Pulizia cartelle temp ---"
$null = Clean-Folder $Log "C:\Windows\Temp"                                                          "Windows Temp"
$null = Clean-Folder $Log $env:TEMP                                                                   "User Temp"
$null = Clean-Folder $Log (Join-Path $env:LOCALAPPDATA "Temp")                                        "LocalAppData Temp"
$null = Clean-Folder $Log "C:\ProgramData\Microsoft\Windows\WER"                                     "WER"
$null = Clean-Folder $Log "C:\Windows\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache" "DO Cache"

# ── PAGEFILE (SSD: fisso per ridurre write e frammentazione) ──────────────────
Write-Log $Log "--- Pagefile ---"
try {
    $hasHDD = $false
    try {
        $disks = Get-PhysicalDisk -ErrorAction Stop
        if (@($disks | Where-Object { $_.MediaType -eq "HDD" }).Count -gt 0) { $hasHDD = $true }
    } catch {
        Write-Log $Log "Rilevamento tipo disco non disponibile: pagefile non modificato." "WARN"
        throw "skip"
    }

    $ramGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 0)

    if ($hasHDD) {
        Write-Log $Log ("HDD rilevato (RAM={0}GB): pagefile lasciato a gestione automatica Windows." -f $ramGB) "INFO"
    } else {
        # SSD: pagefile fisso. Min=1.5x RAM fino a 4GB, max=4GB, floor 2GB.
        $pfMin = [math]::Max(2048, [math]::Min(4096, [int]($ramGB * 1.5 * 1024)))
        $pfMax = 4096

        # Backup stato corrente
        $pfBak = Join-Path $BackupDir "pagefile.json"
        try {
            $curPF = Get-CimInstance -ClassName Win32_PageFileSetting -ErrorAction Stop
            @{ Path=$curPF.Name; InitialSize=$curPF.InitialSize; MaximumSize=$curPF.MaximumSize } |
                ConvertTo-Json | Set-Content -Path $pfBak -Encoding UTF8
            Write-Log $Log ("Backup pagefile -> {0}" -f $pfBak)
        } catch { Write-Log $Log "Backup pagefile: nessun setting esplicito trovato (era Auto)." "INFO" }

        # Disabilita gestione automatica, imposta C: fisso
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem
        if ($cs.AutomaticManagedPagefile) {
            $cs | Set-CimInstance -Property @{ AutomaticManagedPagefile = $false } -ErrorAction Stop
            Write-Log $Log "Pagefile: gestione automatica disabilitata." "INFO"
        }
        # Rimuovi eventuali pagefile NON su C:, poi imposta/aggiorna C:\pagefile.sys
        # Nota: CIM/WMI richiede tipi UInt32 per InitialSize/MaximumSize su alcune build.
        $targetName = "C:\\pagefile.sys"
        Get-CimInstance Win32_PageFileSetting -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne $targetName } |
            Remove-CimInstance -ErrorAction SilentlyContinue

        $pfProps = @{ Name = $targetName; InitialSize = [uint32]$pfMin; MaximumSize = [uint32]$pfMax }
        try {
            # Prova a creare ex-novo
            New-CimInstance -ClassName Win32_PageFileSetting -Property $pfProps -ErrorAction Stop | Out-Null
        } catch {
            # Se esiste già, aggiorna in-place
            $existing = Get-CimInstance Win32_PageFileSetting -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -eq $targetName } |
                        Select-Object -First 1
            if ($existing) {
                $existing | Set-CimInstance -Property @{ InitialSize = [uint32]$pfMin; MaximumSize = [uint32]$pfMax } -ErrorAction Stop | Out-Null
            } else {
                throw
            }
        }
        Write-Log $Log ("SSD (RAM={0}GB): pagefile fisso C: {1}MB-{2}MB (effettivo al prossimo riavvio)." -f $ramGB, $pfMin, $pfMax) "OK"
        Write-Log $Log "NOTA: la modifica al pagefile diventa effettiva al prossimo riavvio." "INFO"
    }
} catch {
    if ($_.Exception.Message -ne "skip") {
        Write-Log $Log ("Pagefile: errore - {0}" -f $_.Exception.Message) "WARN"
    }
}

Write-Log $Log "=== BASELINE APPLY END ===" "INFO"
Save-WocModuleState "BASE" @{ Services=$svcList; Tasks=$taskList }
Set-WocLevel "BASE"
Write-Host ""
Write-Host "  Log salvato: $Log" -ForegroundColor Cyan
Write-Host ""
if (Get-Command Write-WinOptFooter -ErrorAction SilentlyContinue) { Write-WinOptFooter $Log $MOD $ACT }
if (Get-Command Pause-WinOptIfInteractive -ErrorAction SilentlyContinue) { Pause-WinOptIfInteractive }
