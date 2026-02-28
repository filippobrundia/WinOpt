#Requires -Version 5.1
<#  WIN_OPT_CLAUDE - 05_ADDON_ULTRA - APPLY (ADMIN)
    v1.4 - aggiunto backup registry HKCU prima di scrivere
           cosi REVERT puo' ripristinare valori originali invece di hardcoded
#>

. "$PSScriptRoot\..\_COMMON\Common.ps1"
# Elevation is handled by LAUNCHER.cmd (single UAC).
# Assert-Admin below is a safety net for direct execution outside the launcher.
$MOD       = "05_ADDON_ULTRA"
$Log       = New-LogPath $MOD "APPLY"
$cfg       = Get-WinOptConfig
$ACT       = "APPLY"
if (Get-Command Reset-WinOptLogCounters -ErrorAction SilentlyContinue) { Reset-WinOptLogCounters }
$BackupDir = Join-Path $script:WOC_BACKUP_ROOT $MOD
Ensure-Dir $BackupDir

$BackupTask = Join-Path $BackupDir "tasks.txt"
$BackupReg  = Join-Path $BackupDir "reg.jsonl"
Remove-Item -LiteralPath $BackupTask -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $BackupReg  -ErrorAction SilentlyContinue

Write-Log $Log "=== ADDON ULTRA APPLY START ===" "INFO"
# ── PREFLIGHT (restore point + space check) ───────────────────────────────────
& "$PSScriptRoot\..\_COMMON\Preflight.ps1"
if ($LASTEXITCODE -ne 0) {
    Write-Host "  Preflight fallito. Operazione annullata." -ForegroundColor Red
    exit 1
}
Assert-Admin $Log

$level = Get-WocLevel
if ($level -ne "BASE" -and $level -ne "ULTRA") {
    Write-Log $Log ("ATTENZIONE: livello corrente = {0}. Consigliato eseguire prima 01_BASELINE." -f $level) "WARN"
}

# ── BACKUP REGISTRY HKCU (prima di scrivere) ─────────────────────────────────
$kPers = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
$kVFX  = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
$kDesk = "HKCU:\Control Panel\Desktop"
$kExp  = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"

Backup-RegValue $BackupReg $kPers "EnableTransparency"
Backup-RegValue $BackupReg $kVFX  "VisualFXSetting"
Backup-RegValue $BackupReg $kDesk "MinAnimate"
Backup-RegValue $BackupReg $kExp  "TaskbarAnimations"
Write-Log $Log "Backup registro HKCU -> $BackupReg"

# ── SERVIZI ──────────────────────────────────────────────────────────────────
# FIX v1.8: verifica SSD prima di disabilitare SysMain (Superfetch)
# Su HDD, SysMain migliora i tempi di caricamento — disabilitarlo peggiorerebbe le prestazioni.
$hasHDD = $false
try {
    $disks = Get-PhysicalDisk -ErrorAction Stop
    $hddDisks = @($disks | Where-Object { $_.MediaType -eq 'HDD' })
    if ($hddDisks.Count -gt 0) { $hasHDD = $true }
} catch {
    # Get-PhysicalDisk non disponibile (raro su W10+): comportamento conservativo
    Write-Log $Log "Rilevamento tipo disco non disponibile: SysMain disabilitato comunque (ULTRA)." "WARN"
}

if ($hasHDD) {
    Write-Log $Log "ATTENZIONE: disco HDD rilevato. SysMain (Superfetch) disabilitato come richiesto da ULTRA," "WARN"
    Write-Log $Log "            ma su HDD potrebbe rallentare i tempi di avvio delle applicazioni." "WARN"
    Write-Log $Log "            Valuta di mantenerlo abilitato se le prestazioni peggiorano." "WARN"
} else {
    Write-Log $Log "SSD rilevato: disabilitazione SysMain ottimale (riduce write non necessari)." "INFO"
}
Set-ServiceStart $Log "SysMain"        "Disabled"; Stop-ServiceSafe $Log "SysMain"

# FIX v1.8: WSearch - avviso esplicito prima di disabilitare
Write-Log $Log "ATTENZIONE: WSearch (Windows Search) sta per essere disabilitato." "WARN"
Write-Log $Log "Effetti: ricerca in Esplora File NON indicizzata (piu' lenta su cartelle grandi)," "WARN"
Write-Log $Log "         ricerca nel menu Start puo' perdere reattivita'." "WARN"
Write-Log $Log "         Per ripristinare: ULTRA REVERT oppure riabilita manualmente il servizio WSearch." "WARN"
$ultraWSearchEnabled = Get-Feature $cfg "Features.WSearch.UltraEnabled" $false
if (-not $ultraWSearchEnabled) {
    Set-ServiceStart $Log "WSearch" "Disabled"; Stop-ServiceSafe $Log "WSearch"
} else {
    Write-Log $Log "ULTRA: Config richiede WSearch attivo (utile per Start/Explorer/Outlook search)." "WARN"
    Set-ServiceStart $Log "WSearch" "Automatic"; Start-ServiceSafe $Log "WSearch"
}

Set-ServiceStart $Log "MapsBroker"     "Disabled"
Set-ServiceStart $Log "RemoteRegistry" "Disabled"; Stop-ServiceSafe $Log "RemoteRegistry"
Set-ServiceStart $Log "WMPNetworkSvc"  "Disabled"; Stop-ServiceSafe $Log "WMPNetworkSvc"
Set-ServiceStart $Log "RetailDemo"     "Disabled"

# ── TASK ─────────────────────────────────────────────────────────────────────
$taskList = @(
    "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser",
    "\Microsoft\Windows\Application Experience\ProgramDataUpdater",
    "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector"
)
Backup-TaskState $BackupTask $taskList
foreach ($t in $taskList) { Disable-Task $Log $t }

# ── APPX ─────────────────────────────────────────────────────────────────────
$patterns = @("Microsoft.WindowsWidgets*","Microsoft.YourPhone*","Microsoft.Todos*","Microsoft.MicrosoftOfficeHub*")
foreach ($p in $patterns) { Remove-AppxSafe $Log $p -Provisioned }

# ── UIUX PERFORMANCE (HKCU) ──────────────────────────────────────────────────
try {
    Write-Log $Log "UIUX ULTRA: trasparenze OFF, animazioni ridotte" "INFO"
    Set-RegDword  $Log $kPers "EnableTransparency" 0
    Set-RegDword  $Log $kVFX  "VisualFXSetting"    2
    Set-RegString $Log $kDesk "MinAnimate"          "0"
    Set-RegDword  $Log $kExp  "TaskbarAnimations"   0
} catch {
    Write-Log $Log ("UIUX ULTRA: errore ({0})" -f $_.Exception.Message) "WARN"
}

Write-Log $Log "NOTA: rimozioni Appx non ripristinate automaticamente." "WARN"
Write-Log $Log "=== ADDON ULTRA APPLY END ===" "INFO"
Set-WocLevel "ULTRA"
Write-Host ""
Write-Host "  Log salvato: $Log" -ForegroundColor Cyan
Write-Host ""
if (Get-Command Write-WinOptFooter -ErrorAction SilentlyContinue) { Write-WinOptFooter $Log $MOD $ACT }
if (Get-Command Pause-WinOptIfInteractive -ErrorAction SilentlyContinue) { Pause-WinOptIfInteractive }
