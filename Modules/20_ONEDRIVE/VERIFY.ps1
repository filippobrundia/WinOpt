#Requires -Version 5.1
<#  WIN_OPT_CLAUDE - 03_ONEDRIVE - STATUS  #>

. "$PSScriptRoot\..\_COMMON\Common.ps1"

$MOD = "03_ONEDRIVE"
$Log = New-LogPath $MOD "STATUS"
$ACT       = "STATUS"
if (Get-Command Reset-WinOptLogCounters -ErrorAction SilentlyContinue) { Reset-WinOptLogCounters }
Write-Log $Log "=== ONEDRIVE STATUS START ===" "INFO"

# Policy HKLM
try {
    $v = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive" -ErrorAction Stop)."DisableFileSyncNGSC"
    $stato = if ($v -eq 1) { "DISABILITATO (policy)" } else { "ABILITATO (policy=$v)" }
    Write-Log $Log ("Policy  DisableFileSyncNGSC = {0}  => {1}" -f $v, $stato)
} catch {
    Write-Log $Log "Policy  DisableFileSyncNGSC  MANCANTE (OneDrive non bloccato da policy)" "SKIP"
}

# Autostart HKCU
try {
    $run = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -ErrorAction Stop)."OneDrive"
    Write-Log $Log ("Autorun  HKCU Run\OneDrive = {0}" -f $run)
} catch {
    Write-Log $Log "Autorun  HKCU Run\OneDrive  MANCANTE (autoavvio rimosso)" "SKIP"
}

# Processo in esecuzione
$proc = Get-Process OneDrive -ErrorAction SilentlyContinue
if ($proc) {
    Write-Log $Log ("Processo OneDrive IN ESECUZIONE  (PID={0})" -f $proc.Id) "WARN"
} else {
    Write-Log $Log "Processo OneDrive NON in esecuzione." "OK"
}

Write-Log $Log "=== ONEDRIVE STATUS END ===" "INFO"
Write-Host ""
Write-Host "  Log salvato: $Log" -ForegroundColor Cyan
Write-Host ""
if (Get-Command Write-WinOptFooter -ErrorAction SilentlyContinue) { Write-WinOptFooter $Log $MOD $ACT }
if (Get-Command Pause-WinOptIfInteractive -ErrorAction SilentlyContinue) { Pause-WinOptIfInteractive }
