#Requires -Version 5.1
<# WinOpt 2.5.7 - EDGE POST (USER)
   Da lanciare dopo riavvio, con Edge chiuso.
   Lavora su TUTTI i profili in Edge\User Data\ (Default + Profile N).

   Applica a livello Preferences JSON:
   - Welcome page: marcata come vista (evita wizard onboarding)
   - Barra preferiti: OFF
   - Raggruppamento schede: OFF
   - Toolbar configurazione (Edge 145 usa due sezioni distinte):
       * edge.toolbar.*          per: favorites, collections, split, web_capture, drop, vpn...
       * browser.show_toolbar_*  per: apps, bookmarks, downloads, history, performance, share

   Configurazione toolbar target:
       ON  : Schermo diviso, Cronologia, App, Download, Screenshot
       OFF : Preferiti, Raccolte, Prestazioni, VPN, Drop, Condividi, Feedback
#>

. "$PSScriptRoot\..\_COMMON\Common.ps1"

$MOD = "03_EDGE"
$Log = New-LogPath $MOD "APPLY_USER"
if (Get-Command Reset-WinOptLogCounters -ErrorAction SilentlyContinue) { Reset-WinOptLogCounters }

Write-Log $Log "=== EDGE POST (USER) START ===" "INFO"
Write-Log $Log ("Utente: {0}" -f $env:USERNAME) "INFO"

Write-Log $Log "Chiusura processi msedge..." "INFO"
Get-Process msedge -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 1200

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

    Write-Log $Log ("--- Profilo: {0} ---" -f $ProfileName) "INFO"

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

    # Welcome visto
    Ensure-Obj $j "browser"
    Set-Prop $j.browser "has_seen_welcome_page" $true
    Write-Log $Log ("[$ProfileName] has_seen_welcome_page = true") "OK"

    # Barra preferiti OFF
    Ensure-Obj $j "bookmark_bar"
    Set-Prop $j.bookmark_bar "show_on_all_tabs" $false
    Write-Log $Log ("[$ProfileName] bookmark_bar OFF") "OK"

    # Raggruppamento schede OFF (chiavi confermate da dump Preferences Edge 145)
    Set-Prop $j.browser "enable_tab_groups"            $false
    Set-Prop $j.browser "tab_groups_collapse_freezing" $false
    Write-Log $Log ("[$ProfileName] tab groups OFF") "OK"

    # Toolbar - sezione edge.toolbar (confermate da dump Preferences Edge 145)
    Ensure-Obj $j "edge"
    Ensure-Obj $j.edge "toolbar"
    Set-Prop $j.edge.toolbar "show_favorites_button"   $false   # Preferiti    OFF
    Set-Prop $j.edge.toolbar "show_collections_button" $false   # Raccolte     OFF
    Set-Prop $j.edge.toolbar "show_split_screen"       $true    # Schermo div. ON
    Set-Prop $j.edge.toolbar "show_history_button"     $true    # Cronologia   ON
    Set-Prop $j.edge.toolbar "show_apps_button"        $true    # App          ON
    Set-Prop $j.edge.toolbar "show_downloads_button"   $true    # Download     ON
    Set-Prop $j.edge.toolbar "show_performance_button" $false   # Prestazioni  OFF
    Set-Prop $j.edge.toolbar "show_vpn_button"         $false   # VPN          OFF
    Set-Prop $j.edge.toolbar "show_drop_button"        $false   # Drop         OFF
    Set-Prop $j.edge.toolbar "show_web_capture"        $true    # Screenshot   ON
    Set-Prop $j.edge.toolbar "show_share_button"       $false   # Condividi    OFF
    Set-Prop $j.edge.toolbar "show_feedback_button"    $false   # Feedback     OFF
    Write-Log $Log ("[$ProfileName] edge.toolbar OK") "OK"

    # Toolbar - sezione browser.show_toolbar_* (confermate da dump Preferences Edge 145)
    Set-Prop $j.browser "show_toolbar_apps_button"               $true    # App          ON
    Set-Prop $j.browser "show_toolbar_bookmarks_button"          $false   # Preferiti    OFF
    Set-Prop $j.browser "show_toolbar_downloads_button"          $true    # Download     ON
    Set-Prop $j.browser "show_toolbar_history_button"            $true    # Cronologia   ON
    Set-Prop $j.browser "show_toolbar_performance_center_button" 0        # Prestazioni  OFF
    Set-Prop $j.browser "show_toolbar_share_button"              $false   # Condividi    OFF
    Set-Prop $j.browser "show_toolbar_web_capture_button"        $true    # Screenshot   ON
    Set-Prop $j.browser "show_edge_split_window_toolbar_button"  $true    # Schermo div. ON
    Write-Log $Log ("[$ProfileName] browser.show_toolbar_* OK") "OK"

    ($j | ConvertTo-Json -Depth 50) | Out-File -Encoding UTF8 $PrefPath -Force
    Write-Log $Log ("[$ProfileName] Preferences scritto") "OK"
}

$userDataPath = Join-Path $env:LOCALAPPDATA "Microsoft\Edge\User Data"

if (!(Test-Path $userDataPath)) {
    Write-Log $Log "Edge User Data non trovata - Edge mai avviato su questo utente?" "WARN"
    Write-Host "  [WARN] Avvia Edge almeno una volta, poi rilancia questo script." -ForegroundColor Yellow
} else {
    $profileDirs = @()
    $defaultPath = Join-Path $userDataPath "Default"
    if (Test-Path $defaultPath) { $profileDirs += $defaultPath }
    Get-ChildItem -Path $userDataPath -Directory |
        Where-Object { $_.Name -match "^Profile \d+$" } |
        ForEach-Object { $profileDirs += $_.FullName }

    if ($profileDirs.Count -eq 0) {
        Write-Log $Log "Nessun profilo trovato in $userDataPath" "WARN"
    } else {
        Write-Log $Log ("Profili trovati: {0}" -f $profileDirs.Count) "INFO"
        foreach ($dir in $profileDirs) {
            Apply-EdgePreferences -PrefPath (Join-Path $dir "Preferences") -ProfileName (Split-Path $dir -Leaf)
        }
    }
}

Write-Log $Log "=== EDGE POST (USER) END ===" "INFO"

Write-Host ""
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "  EDGE POST OK." -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "  Ora puoi aprire Edge." -ForegroundColor Yellow
Write-Host ""
Write-Host ("  Log: {0}" -f $Log) -ForegroundColor DarkGray
Write-Host ""
if (Get-Command Pause-WinOptIfInteractive -ErrorAction SilentlyContinue) { Pause-WinOptIfInteractive } else { Read-Host "  Premi INVIO per chiudere" }
