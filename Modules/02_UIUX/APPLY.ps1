#Requires -Version 5.1
<#  WIN_OPT_CLAUDE - 02_UIUX - APPLY (utente corrente, no admin richiesto)
    v1.3.1 - TaskbarDa HKCU rimosso: chiave owned da TrustedInstaller, scrittura
             negata anche da admin. I widget taskbar sono già bloccati dalla policy
             HKLM Dsh\AllowNewsAndInterests=0 impostata da 01_BASELINE.
#>

. "$PSScriptRoot\..\_COMMON\Common.ps1"

$MOD       = "02_UIUX"
$Log       = New-LogPath $MOD "APPLY"
$ACT       = "APPLY"
if (Get-Command Reset-WinOptLogCounters -ErrorAction SilentlyContinue) { Reset-WinOptLogCounters }
$BackupDir = Join-Path $script:WOC_BACKUP_ROOT $MOD
Ensure-Dir $BackupDir
$BackupReg = Join-Path $BackupDir "reg.jsonl"
Remove-Item -LiteralPath $BackupReg -ErrorAction SilentlyContinue

Write-Log $Log "=== UIUX APPLY START ===" "INFO"

$kExp  = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
$kCDM  = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
$kBAA  = "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications"
$kGCS  = "HKCU:\System\GameConfigStore"
$kGDV  = "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR"
$kAdv  = "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo"
$kPriv = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy"
$kPers = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
$kExpR = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer"
$kDesk = "HKCU:\Control Panel\Desktop"
$kCMenu = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"

# ── BACKUP ──────────────────────────────────────────────────────────────────
foreach ($k in @($kExp,$kCDM,$kBAA,$kGCS,$kGDV)) {
    try {
        $item = Get-ItemProperty -Path $k -ErrorAction Stop
        $item.PSObject.Properties | Where-Object { $_.Name -notlike "PS*" } | ForEach-Object {
            Backup-RegValue $BackupReg $k $_.Name
        }
    } catch { }
}
Backup-RegValue $BackupReg $kPers  "AppsUseLightTheme"
Backup-RegValue $BackupReg $kPers  "SystemUsesLightTheme"
Backup-RegValue $BackupReg $kExpR  "ShowRecent"
Backup-RegValue $BackupReg $kExpR  "ShowFrequent"
Backup-RegValue $BackupReg $kAdv   "Enabled"
Backup-RegValue $BackupReg $kPriv  "TailoredExperiencesWithDiagnosticDataEnabled"
Write-Log $Log "Backup registro -> $BackupReg"

# ── STOP EXPLORER (forza ricaricamento impostazioni Explorer al riavvio) ──────
Write-Log $Log "Stop Explorer (forza ricaricamento impostazioni HKCU al riavvio)..."
try {
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 600
    Write-Log $Log "Explorer stoppato." "OK"
} catch {
    Write-Log $Log ("Explorer stop SKIP: {0}" -f $_.Exception.Message) "WARN"
}

# ── DARK MODE ────────────────────────────────────────────────────────────────
Set-RegDword $Log $kPers "AppsUseLightTheme"    0
Set-RegDword $Log $kPers "SystemUsesLightTheme" 0

# ── EXPLORER ─────────────────────────────────────────────────────────────────
Set-RegDword $Log $kExp "HideFileExt"          0
Set-RegDword $Log $kExp "Hidden"               2
Set-RegDword $Log $kExp "ShowSuperHidden"      0
Set-RegDword $Log $kExp "TaskbarAl"            1
Set-RegDword $Log $kExp "SearchboxTaskbarMode" 1
# TaskbarDa HKCU: owned TrustedInstaller, scrittura negata a tutti (incluso admin).
# Widget taskbar bloccati da HKLM Dsh\AllowNewsAndInterests=0 (impostato da 01_BASELINE).
Write-Log $Log "TaskbarDa HKCU: SKIP (TrustedInstaller ACL). Widget gia' bloccati via HKLM Dsh policy." "SKIP"
Set-RegDword $Log $kExp "TaskbarMn"            0
Set-RegDword $Log $kExp "LaunchTo"             1
Set-RegDword $Log $kExp "Start_TrackDocs"      0
Set-RegDword $Log $kExp "Start_TrackProgs"     0
Set-RegDword $Log $kExpR "ShowRecent"          0
Set-RegDword $Log $kExpR "ShowFrequent"        0

# ── CONTENT DELIVERY MANAGER + SPOTLIGHT HKCU ───────────────────────────────
Write-Log $Log "--- ContentDeliveryManager + Spotlight HKCU ---"
Set-RegDword $Log $kCDM "SoftLandingEnabled"                  0
Set-RegDword $Log $kCDM "SilentInstalledAppsEnabled"          0
Set-RegDword $Log $kCDM "SystemPaneSuggestionsEnabled"        0
Set-RegDword $Log $kCDM "SubscribedContent-310093Enabled"     0
Set-RegDword $Log $kCDM "SubscribedContent-338388Enabled"     0
Set-RegDword $Log $kCDM "RotatingLockScreenEnabled"           0
Set-RegDword $Log $kCDM "SubscribedContent-338387Enabled"     0
Set-RegDword $Log $kCDM "SubscribedContent-338389Enabled"     0
Set-RegDword $Log $kCDM "SubscribedContent-353698Enabled"     0

# ── ADVERTISING ID (HKCU) ────────────────────────────────────────────────────
Write-Log $Log "--- Advertising ID HKCU ---"
Set-RegDword $Log $kAdv "Enabled" 0

# ── TAILORED EXPERIENCES (HKCU) ──────────────────────────────────────────────
Write-Log $Log "--- Tailored Experiences HKCU ---"
Set-RegDword $Log $kPriv "TailoredExperiencesWithDiagnosticDataEnabled" 0

# ── BACKGROUND APPS ──────────────────────────────────────────────────────────
Set-RegDword $Log $kBAA "GlobalUserDisabled" 1

# ── GAMEDVR ──────────────────────────────────────────────────────────────────
Set-RegDword $Log $kGCS "GameDVR_Enabled"   0
Set-RegDword $Log $kGDV "AppCaptureEnabled" 0

# ── TASKBAR AUTO-HIDE OFF ─────────────────────────────────────────────────────
try {
    $kSR = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3"
    $cur = (Get-ItemProperty -Path $kSR -Name "Settings" -ErrorAction Stop).Settings
    if ($cur -and $cur.Length -ge 9) {
        $new = [byte[]]$cur.Clone()
        $new[8] = ($new[8] -band 0xFD)
        Set-ItemProperty -Path $kSR -Name "Settings" -Type Binary -Value $new -ErrorAction Stop
        Write-Log $Log "Taskbar: auto-hide OFF (StuckRects3)" "OK"
    }
} catch {
    Write-Log $Log ("Taskbar: auto-hide OFF skip - {0}" -f $_.Exception.Message) "WARN"
}

# ── RIAVVIO EXPLORER ─────────────────────────────────────────────────────────
Write-Log $Log "Riavvio Explorer..."
try {
    Start-Process explorer.exe
    Write-Log $Log "Explorer riavviato." "OK"
} catch {
    Write-Log $Log ("Explorer restart SKIP: {0}" -f $_.Exception.Message) "WARN"
}




# ===================== VISUAL EFFECTS (BEST PERFORMANCE + FONT SMOOTHING) =====================
try {
  Write-Log $Log "UIUX: Imposto effetti visivi su 'Prestazioni migliori' (con Smussatura caratteri attiva)..." "INFO"

  New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Force | Out-Null
  Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name "VisualFXSetting" -Type DWord -Value 2 -ErrorAction Stop

  # Font smoothing ON
  Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "FontSmoothing" -Type String -Value "2" -ErrorAction SilentlyContinue
  Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "FontSmoothingType" -Type DWord -Value 2 -ErrorAction SilentlyContinue
  Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "FontSmoothingGamma" -Type DWord -Value 1500 -ErrorAction SilentlyContinue

  # Reduce animations explicitly
  Set-ItemProperty -Path "HKCU:\Control Panel\Desktop\WindowMetrics" -Name "MinAnimate" -Type String -Value "0" -ErrorAction SilentlyContinue
  Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarAnimations" -Type DWord -Value 0 -ErrorAction SilentlyContinue
  Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ListviewAlphaSelect" -Type DWord -Value 0 -ErrorAction SilentlyContinue
  Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ListviewShadow" -Type DWord -Value 0 -ErrorAction SilentlyContinue

  Write-Log $Log "UIUX: Effetti visivi impostati. Nota: alcune modifiche richiedono logout/login per effetto completo." "INFO"
} catch {
  Write-Log $Log ("UIUX: Errore impostando effetti visivi: {0}" -f $_.Exception.Message) "WARN"
}


# ── CONTEXT MENU: ripristino menu classico Win10 (rimuove lag Win11) ─────────
Write-Log $Log "--- Context menu classico (Win10 style) ---"
try {
    # Creare la chiave con valore Default vuoto e' sufficiente per ripristinare
    # il menu contestuale completo di Win10. Compatibile con tutte le app.
    $cmPath = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"
    if (-not (Test-Path -LiteralPath $cmPath)) {
        New-Item -Path $cmPath -Force | Out-Null
    }
    Set-ItemProperty -Path $cmPath -Name "(Default)" -Value "" -Type String -Force
    Write-Log $Log "Context menu classico attivato (richiede riavvio Explorer)." "OK"
} catch {
    Write-Log $Log ("Context menu classico: {0}" -f $_.Exception.Message) "WARN"
}

# ── MENU SPEED: riduzione ritardo apertura menu 400ms -> 20ms ────────────────
Write-Log $Log "--- Menu speed: ritardo 20ms ---"
Set-RegString $Log $kDesk "MenuShowDelay" "20"

# ── SHUTDOWN SPEED: app kill timeout ridotto a 2s (default 5s) ──────────────
Write-Log $Log "--- Shutdown speed: WaitToKillAppTimeout 3000ms ---"
# 3000ms: buon compromesso tra reattivita' allo spegnimento e chiusura pulita delle app.
Set-RegString $Log $kDesk "WaitToKillAppTimeout" "3000"

Write-Log $Log "=== UIUX APPLY END ===" "INFO"
Save-WocModuleState "UIUX" @{ Scope = "HKCU"; AppliedFor = $env:USERNAME }
Write-Host ""
Write-Host "  Log salvato: $Log" -ForegroundColor Cyan
Write-Host ""
if (Get-Command Write-WinOptFooter -ErrorAction SilentlyContinue) { Write-WinOptFooter $Log $MOD $ACT }
if (Get-Command Pause-WinOptIfInteractive -ErrorAction SilentlyContinue) { Pause-WinOptIfInteractive }