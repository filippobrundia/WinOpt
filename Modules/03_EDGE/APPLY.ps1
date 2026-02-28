#Requires -Version 5.1
<# WinOpt 2.5.7 - EDGE APPLY (ADMIN)
   Policy HKLM + Preferences utente in un unico script.
   Deterministico: backup prima, applica, ripristinabile.

   PERFORMANCE
   - StartupBoost + Background: OFF
   - SleepingTabs: ON

   NOISE / CONSUMER OFF
   - Shopping assistant, Rewards, Recommendations, Spotlight: OFF
   - Promozioni, Feedback utente: OFF
   - HubsSidebar (Copilot sidebar): OFF
   - NewTabPageContentEnabled: OFF  (rimuove feed MSN dalla NTP)

   PRIVACY
   - PersonalizationReporting, DiagnosticData: OFF
   - ConfigureDoNotTrack: ON
   - SpotlightExperiences: OFF

   UI
   - HideFirstRunExperience: ON
   - DefaultBrowserSettingEnabled (nag): OFF
   - ShowHomeButton: ON => Google
   - HomepageLocation: https://www.google.com
     NOTA: HomepageLocation viene ignorata da Edge 145+ consumer (senza MDM/Intune).
           Impostare manualmente da edge://settings/startHomeNTP se necessario.
   - FavoritesBarEnabled: OFF
   - NewTabPageQuickLinksEnabled: OFF
   - NewTabPageHideDefaultTopSites: ON
   - NewTabPagePrerenderEnabled: OFF
   NOTA: NewTabPageLocation non viene impostata - Edge 145 consumer la ignora.
         La NTP rimane la pagina Microsoft ma senza feed, quick links e top sites.

   ESTENSIONI
   - uBlock Origin: installazione forzata da Edge Add-ons store

   PREFERENCES UTENTE (applicati in coda, su tutti i profili)
   - Welcome page: marcata come vista
   - Barra preferiti: OFF
   - Raggruppamento schede: OFF
   - Toolbar configurata (ON: Schermo diviso, Cronologia, App, Download, Screenshot)

   NON tocca: WebView2, login/account, sync, password manager, Edge Update.
#>

. "$PSScriptRoot\..\_COMMON\Common.ps1"
# Elevation is handled by LAUNCHER.cmd (single UAC).
# Assert-Admin below is a safety net for direct execution outside the launcher.
& "$PSScriptRoot\..\_COMMON\Preflight.ps1"
if ($LASTEXITCODE -ne 0) {
    Write-Host "  Preflight fallito. Operazione annullata." -ForegroundColor Red
    exit 1
}

$MOD = "03_EDGE"
$Log = New-LogPath $MOD "APPLY"
$ACT = "APPLY"
if (Get-Command Reset-WinOptLogCounters -ErrorAction SilentlyContinue) { Reset-WinOptLogCounters }

$BackupDir = Join-Path $script:WOC_BACKUP_ROOT $MOD
Ensure-Dir $BackupDir
$BackupReg = Join-Path $BackupDir "reg.jsonl"
Remove-Item -LiteralPath $BackupReg -ErrorAction SilentlyContinue

Write-Log $Log "=== EDGE APPLY START ===" "INFO"
Assert-Admin $Log

Write-Log $Log "Chiusura processi msedge..." "INFO"
Get-Process msedge -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 800

$kEdge  = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
$kForce = Join-Path $kEdge "ExtensionInstallForcelist"

$policyList = @(
    "StartupBoostEnabled",
    "BackgroundModeEnabled",
    "SleepingTabsEnabled",
    "ShowRecommendationsEnabled",
    "EdgeShoppingAssistantEnabled",
    "HubsSidebarEnabled",
    "ShowMicrosoftRewards",
    "UserFeedbackAllowed",
    "PromotionalTabsEnabled",
    "NewTabPageContentEnabled",
    "HideFirstRunExperience",
    "DefaultBrowserSettingEnabled",
    "PersonalizationReportingEnabled",
    "DiagnosticData",
    "ConfigureDoNotTrack",
    "SpotlightExperiencesAndRecommendationsEnabled",
    "ShowHomeButton",
    "HomepageIsNewTabPage",
    "HomepageLocation",
    "NewTabPageQuickLinksEnabled",
    "NewTabPageHideDefaultTopSites",
    "NewTabPagePrerenderEnabled",
    "FavoritesBarEnabled"
)

# Pulizia chiavi legacy che causano conflitti o warning in edge://policy
Write-Log $Log "--- Pulizia chiavi legacy ---" "INFO"
@(
    "NewTabPageLocation",       # ignorato da Edge 145 consumer, conflittava con HomepageLocation
    "EdgeCopilotEnabled",       # non esiste in Edge 145
    "EdgeFollowEnabled",        # non esiste in Edge 145
    "MetricsReportingEnabled"   # non esiste in Edge 145
) | ForEach-Object { Remove-RegValue $Log $kEdge $_ }

Write-Log $Log "--- Backup policy Edge -> $BackupReg ---" "INFO"
New-Item -Path $kEdge -Force | Out-Null
foreach ($p in $policyList) { Backup-RegValue $BackupReg $kEdge $p }
Backup-RegValue $BackupReg $kForce "1"

Write-Log $Log "--- Applicazione policy Edge ---" "INFO"

# Performance
Set-RegDword $Log $kEdge "StartupBoostEnabled"   0
Set-RegDword $Log $kEdge "BackgroundModeEnabled" 0
Set-RegDword $Log $kEdge "SleepingTabsEnabled"   1

# Noise / consumer
Set-RegDword $Log $kEdge "ShowRecommendationsEnabled"   0
Set-RegDword $Log $kEdge "EdgeShoppingAssistantEnabled" 0
Set-RegDword $Log $kEdge "ShowMicrosoftRewards"         0
Set-RegDword $Log $kEdge "UserFeedbackAllowed"          0
Set-RegDword $Log $kEdge "PromotionalTabsEnabled"       0
Set-RegDword $Log $kEdge "HubsSidebarEnabled"           0
Set-RegDword $Log $kEdge "NewTabPageContentEnabled"     0   # feed MSN OFF

# Privacy
Set-RegDword $Log $kEdge "PersonalizationReportingEnabled"               0
Set-RegDword $Log $kEdge "DiagnosticData"                                0
Set-RegDword $Log $kEdge "ConfigureDoNotTrack"                           1
Set-RegDword $Log $kEdge "SpotlightExperiencesAndRecommendationsEnabled" 0

# UI / Onboarding
Set-RegDword  $Log $kEdge "HideFirstRunExperience"        1
Set-RegDword  $Log $kEdge "DefaultBrowserSettingEnabled"  0
Set-RegDword  $Log $kEdge "ShowHomeButton"                1
Set-RegDword  $Log $kEdge "HomepageIsNewTabPage"          0
Set-RegString $Log $kEdge "HomepageLocation"              "https://www.google.com"
Set-RegDword  $Log $kEdge "NewTabPageQuickLinksEnabled"   0
Set-RegDword  $Log $kEdge "NewTabPageHideDefaultTopSites" 1
Set-RegDword  $Log $kEdge "NewTabPagePrerenderEnabled"    0
Set-RegDword  $Log $kEdge "FavoritesBarEnabled"           0

# Estensioni: uBlock Origin installazione forzata
Ensure-Dir $kForce
Set-RegString $Log $kForce "1" "odfafepnkmbhccpbejgmiehpchacaeak;https://edge.microsoft.com/extensionwebstorebase/v1/crx"

Write-Log $Log "NOTA: Login/sync/WebView2/password manager/Edge Update non toccati." "INFO"
Save-WocModuleState "EDGE" @{ Policies = $policyList + @("ExtensionInstallForcelist\1"); KeyPath = $kEdge }
Write-Log $Log "=== EDGE APPLY (registry) END ===" "INFO"

# ══════════════════════════════════════════════════════════════════════════════
# PREFERENCES UTENTE
# Scritto direttamente qui - non serve un secondo script o un secondo riavvio.
# $env:LOCALAPPDATA punta al profilo dell'utente reale anche sotto UAC.
# ══════════════════════════════════════════════════════════════════════════════

function Ensure-Obj {
    param([object]$root, [string]$name)
    if ($null -eq $root.PSObject.Properties[$name] -or $null -eq $root.PSObject.Properties[$name].Value) {
        $root | Add-Member -NotePropertyName $name -NotePropertyValue ([PSCustomObject]@{}) -Force
    }
}
function Set-Prop {
    param([object]$obj, [string]$name, $value)
    $obj | Add-Member -NotePropertyName $name -NotePropertyValue $value -Force
}

function Apply-EdgePreferences {
    param([string]$PrefPath, [string]$ProfileName)
    Write-Log $Log ("--- Preferences profilo: {0} ---" -f $ProfileName) "INFO"

    if (!(Test-Path $PrefPath)) {
        New-Item -ItemType Directory -Path (Split-Path $PrefPath) -Force | Out-Null
        "{}" | Out-File -Encoding UTF8 $PrefPath -Force
        Write-Log $Log ("[$ProfileName] Preferences creato vuoto") "INFO"
    }

    try {
        $j = Get-Content $PrefPath -Raw -Encoding UTF8 | ConvertFrom-Json
        Write-Log $Log ("[$ProfileName] Preferences caricato OK") "INFO"
    } catch {
        $bak = "{0}.bak_{1:yyyyMMdd_HHmmss}" -f $PrefPath, (Get-Date)
        Copy-Item $PrefPath $bak -Force
        Write-Log $Log ("[$ProfileName] Preferences corrotto - backup: {0}" -f $bak) "WARN"
        $j = [PSCustomObject]@{}
    }

    Ensure-Obj $j "browser"
    Set-Prop $j.browser "has_seen_welcome_page"            $true
    Set-Prop $j.browser "enable_tab_groups"                $false
    Set-Prop $j.browser "tab_groups_collapse_freezing"     $false
    Set-Prop $j.browser "show_toolbar_apps_button"              $true
    Set-Prop $j.browser "show_toolbar_bookmarks_button"         $false
    Set-Prop $j.browser "show_toolbar_downloads_button"         $true
    Set-Prop $j.browser "show_toolbar_history_button"           $true
    Set-Prop $j.browser "show_toolbar_performance_center_button" 0
    Set-Prop $j.browser "show_toolbar_share_button"             $false
    Set-Prop $j.browser "show_toolbar_web_capture_button"       $true
    Set-Prop $j.browser "show_edge_split_window_toolbar_button" $true

    Ensure-Obj $j "bookmark_bar"
    Set-Prop $j.bookmark_bar "show_on_all_tabs" $false

    Ensure-Obj $j "edge"
    Ensure-Obj $j.edge "toolbar"
    Set-Prop $j.edge.toolbar "show_favorites_button"   $false
    Set-Prop $j.edge.toolbar "show_collections_button" $false
    Set-Prop $j.edge.toolbar "show_split_screen"       $true
    Set-Prop $j.edge.toolbar "show_history_button"     $true
    Set-Prop $j.edge.toolbar "show_apps_button"        $true
    Set-Prop $j.edge.toolbar "show_downloads_button"   $true
    Set-Prop $j.edge.toolbar "show_performance_button" $false
    Set-Prop $j.edge.toolbar "show_vpn_button"         $false
    Set-Prop $j.edge.toolbar "show_drop_button"        $false
    Set-Prop $j.edge.toolbar "show_web_capture"        $true
    Set-Prop $j.edge.toolbar "show_share_button"       $false
    Set-Prop $j.edge.toolbar "show_feedback_button"    $false

    ($j | ConvertTo-Json -Depth 50) | Out-File -Encoding UTF8 $PrefPath -Force
    Write-Log $Log ("[$ProfileName] Preferences scritto") "OK"
}

$userDataPath = Join-Path $env:LOCALAPPDATA "Microsoft\Edge\User Data"

if (!(Test-Path $userDataPath)) {
    Write-Log $Log "Edge User Data non trovata - Edge non ancora avviato su questo utente." "WARN"
    Write-Host "  [WARN] Preferences non scritte: avvia Edge una volta, poi rilancia APPLY." -ForegroundColor Yellow
} else {
    $profileDirs = @()
    $defPath = Join-Path $userDataPath "Default"
    if (Test-Path $defPath) { $profileDirs += $defPath }
    Get-ChildItem -Path $userDataPath -Directory |
        Where-Object { $_.Name -match "^Profile \d+$" } |
        ForEach-Object { $profileDirs += $_.FullName }

    if ($profileDirs.Count -eq 0) {
        Write-Log $Log "Nessun profilo trovato - aprire Edge almeno una volta." "WARN"
    } else {
        Write-Log $Log ("Profili trovati: {0}" -f $profileDirs.Count) "INFO"
        foreach ($dir in $profileDirs) {
            Apply-EdgePreferences -PrefPath (Join-Path $dir "Preferences") -ProfileName (Split-Path $dir -Leaf)
        }
    }
}

Write-Log $Log "=== EDGE APPLY END ===" "INFO"

Write-Host ""
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "  EDGE APPLY OK." -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Riavvia Windows per attivare le policy." -ForegroundColor Yellow
Write-Host ""
Write-Host ("  Log: {0}" -f $Log) -ForegroundColor DarkGray
Write-Host ""
if (Get-Command Write-WinOptFooter -ErrorAction SilentlyContinue) { Write-WinOptFooter $Log $MOD $ACT }
if (Get-Command Pause-WinOptIfInteractive -ErrorAction SilentlyContinue) { Pause-WinOptIfInteractive } else { Read-Host "  Premi INVIO per chiudere" }
