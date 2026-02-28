#Requires -Version 5.1
<#  WIN_OPT_CLAUDE - 20_ONEDRIVE - APPLY_OFF (ADMIN)
    Disabilita OneDrive: policy HKLM, servizio, task schedulati.
    Non disinstalla OneDrive (reversibile con APPLY_ON.ps1).
#>

. "$PSScriptRoot\..\_COMMON\Common.ps1"
# Elevation is handled by LAUNCHER.cmd (single UAC).
# Assert-Admin below is a safety net for direct execution outside the launcher.
$MOD = "20_ONEDRIVE"
$Log = New-LogPath $MOD "OFF"
$ACT = "OFF"
if (Get-Command Reset-WinOptLogCounters -ErrorAction SilentlyContinue) { Reset-WinOptLogCounters }
$BackupDir = Join-Path $script:WOC_BACKUP_ROOT $MOD
Ensure-Dir $BackupDir

Write-Log $Log "=== ONEDRIVE OFF START ===" "INFO"
Assert-Admin $Log

# ── Backup ───────────────────────────────────────────────────────────────────
$BackupReg  = Join-Path $BackupDir "reg_off.jsonl"
$BackupSvc  = Join-Path $BackupDir "services_off.txt"
$BackupTask = Join-Path $BackupDir "tasks_off.txt"
Remove-Item -LiteralPath $BackupReg  -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $BackupSvc  -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $BackupTask -ErrorAction SilentlyContinue

$kOD = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"
Backup-RegValue $BackupReg $kOD "DisableFileSyncNGSC"
Write-Log $Log "Backup registro -> $BackupReg"

$svcList = @("OneSyncSvc","OneSyncSvc_*","FileSyncHelper")
Backup-ServiceStart $BackupSvc @("OneSyncSvc")
Write-Log $Log "Backup servizi -> $BackupSvc"

$taskList = @(Find-OneDriveTasks)
if ($taskList.Count -gt 0) {
    Backup-TaskState $BackupTask $taskList
    Write-Log $Log "Backup task -> $BackupTask ($($taskList.Count) trovati)"
} else {
    Write-Log $Log "Nessun task OneDrive trovato da backuppare" "SKIP"
}

# ── Policy HKLM ──────────────────────────────────────────────────────────────
Write-Log $Log "--- Policy HKLM ---"
Set-RegDword $Log $kOD "DisableFileSyncNGSC" 1

# ── Servizi ──────────────────────────────────────────────────────────────────
Write-Log $Log "--- Servizi ---"
Set-ServiceStart $Log "OneSyncSvc"    "Disabled"
Stop-ServiceSafe $Log "OneSyncSvc"
Set-ServiceStart $Log "FileSyncHelper" "Disabled"
Stop-ServiceSafe $Log "FileSyncHelper"

# Termina processo OneDrive.exe se attivo
try {
    $procs = Get-Process -Name "OneDrive" -ErrorAction SilentlyContinue
    foreach ($p in $procs) {
        $p.Kill()
        Write-Log $Log "Processo OneDrive.exe terminato (PID $($p.Id))" "OK"
    }
    if (-not $procs) { Write-Log $Log "Processo OneDrive.exe non attivo" "SKIP" }
} catch {
    Write-Log $Log "Kill OneDrive.exe: $($_.Exception.Message)" "WARN"
}

# ── Task schedulati ───────────────────────────────────────────────────────────
Write-Log $Log "--- Task schedulati ---"
if ($taskList.Count -gt 0) {
    foreach ($t in $taskList) { Disable-Task $Log $t }
} else {
    Write-Log $Log "Nessun task OneDrive da disabilitare" "SKIP"
}

Write-Log $Log "=== ONEDRIVE OFF END ===" "INFO"
Save-WocModuleState "20_ONEDRIVE_OFF" @{ Policy="DisableFileSyncNGSC=1" }
if (Get-Command Write-WinOptFooter -ErrorAction SilentlyContinue) { Write-WinOptFooter $Log $MOD $ACT }
if (Get-Command Pause-WinOptIfInteractive -ErrorAction SilentlyContinue) { Pause-WinOptIfInteractive }
