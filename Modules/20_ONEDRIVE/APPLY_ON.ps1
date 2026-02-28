#Requires -Version 5.1
<#  WIN_OPT_CLAUDE - 20_ONEDRIVE - APPLY_ON (ADMIN)
    Riabilita OneDrive: rimuove policy HKLM, riavvia servizio e task schedulati.
    Ripristina lo stato precedente a APPLY_OFF se esiste il backup.
#>

. "$PSScriptRoot\..\_COMMON\Common.ps1"
# Elevation is handled by LAUNCHER.cmd (single UAC).
# Assert-Admin below is a safety net for direct execution outside the launcher.
$MOD = "20_ONEDRIVE"
$Log = New-LogPath $MOD "ON"
$ACT = "ON"
if (Get-Command Reset-WinOptLogCounters -ErrorAction SilentlyContinue) { Reset-WinOptLogCounters }
$BackupDir = Join-Path $script:WOC_BACKUP_ROOT $MOD
Ensure-Dir $BackupDir

Write-Log $Log "=== ONEDRIVE ON START ===" "INFO"
Assert-Admin $Log

# ── Ripristina da backup se disponibile ───────────────────────────────────────
$BackupReg  = Join-Path $BackupDir "reg_off.jsonl"
$BackupSvc  = Join-Path $BackupDir "services_off.txt"
$BackupTask = Join-Path $BackupDir "tasks_off.txt"

if (Test-Path -LiteralPath $BackupReg) {
    Write-Log $Log "--- Ripristino registro da backup ---"
    Restore-RegBackup $Log $BackupReg
} else {
    # Nessun backup: rimuove la policy disabilitante
    Write-Log $Log "--- Nessun backup: rimozione policy DisableFileSyncNGSC ---"
    $kOD = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"
    Remove-RegValue $Log $kOD "DisableFileSyncNGSC"
}

# ── Servizi ──────────────────────────────────────────────────────────────────
Write-Log $Log "--- Servizi ---"
if (Test-Path -LiteralPath $BackupSvc) {
    Restore-ServiceBackup $Log $BackupSvc
} else {
    Set-ServiceStart $Log "OneSyncSvc"    "Automatic"
    Set-ServiceStart $Log "FileSyncHelper" "Manual"
}
Start-ServiceSafe $Log "OneSyncSvc"

# ── Task schedulati ───────────────────────────────────────────────────────────
Write-Log $Log "--- Task schedulati ---"
if (Test-Path -LiteralPath $BackupTask) {
    Restore-TaskBackup $Log $BackupTask
} else {
    $taskList = @(Find-OneDriveTasks)
    if ($taskList.Count -gt 0) {
        foreach ($t in $taskList) { Enable-Task $Log $t }
    } else {
        Write-Log $Log "Nessun task OneDrive trovato" "SKIP"
    }
}

# ── Avvia OneDrive.exe utente corrente ────────────────────────────────────────
Write-Log $Log "--- Avvio OneDrive.exe ---"
$odExe = "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe"
if (Test-Path -LiteralPath $odExe) {
    try {
        Start-Process -FilePath $odExe -ArgumentList "/background" -ErrorAction Stop
        Write-Log $Log "OneDrive.exe avviato in background" "OK"
    } catch {
        Write-Log $Log "Avvio OneDrive.exe: $($_.Exception.Message)" "WARN"
    }
} else {
    Write-Log $Log "OneDrive.exe non trovato in: $odExe" "WARN"
    Write-Log $Log "Potrebbe essere necessario reinstallarlo da: https://www.microsoft.com/en-us/microsoft-365/onedrive/download" "INFO"
}

Write-Log $Log "=== ONEDRIVE ON END ===" "INFO"
Save-WocModuleState "20_ONEDRIVE_ON" @{ Policy="restored" }
if (Get-Command Write-WinOptFooter -ErrorAction SilentlyContinue) { Write-WinOptFooter $Log $MOD $ACT }
if (Get-Command Pause-WinOptIfInteractive -ErrorAction SilentlyContinue) { Pause-WinOptIfInteractive }
