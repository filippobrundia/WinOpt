#Requires -Version 5.1
<#  WIN_OPT_CLAUDE - 07_APPS - AUDIT  #>

. "$PSScriptRoot\..\_COMMON\Common.ps1"

$MOD = "07_APPS"
$Log = New-LogPath $MOD "AUDIT"
$ACT       = "AUDIT"
if (Get-Command Reset-WinOptLogCounters -ErrorAction SilentlyContinue) { Reset-WinOptLogCounters }
Write-Log $Log "=== APPS AUDIT START ===" "INFO"

$wg = Get-WingetPath
if (-not $wg) {
    Write-Log $Log "winget non trovato. Installa/ripara 'App Installer' dallo Store." "FAIL"
    exit 1
}
Write-Log $Log ("winget trovato: {0}" -f $wg) "OK"

$policyPath = Join-Path $PSScriptRoot "AppsPolicy.json"
if (-not (Test-Path -LiteralPath $policyPath)) {
    Write-Log $Log "AppsPolicy.json non trovato in $policyPath" "FAIL"
    exit 1
}
$P    = Get-Content -LiteralPath $policyPath -Raw | ConvertFrom-Json
$apps = @($P.Apps)

if (-not $apps -or $apps.Count -eq 0) {
    Write-Log $Log "Nessuna app nella policy." "WARN"
    exit 0
}

$present = @()
$missing  = @()
foreach ($a in $apps) {
    $id = [string]$a.Id
    if ([string]::IsNullOrWhiteSpace($id)) { continue }
    if (Test-WingetInstalled $id) {
        $present += $a
        Write-Log $Log ("[OK]      {0,-30} ({1})" -f $a.Name, $id) "OK"
    } else {
        $missing += $a
        Write-Log $Log ("[MANCANTE] {0,-30} ({1})" -f $a.Name, $id) "WARN"
    }
}

Write-Log $Log ("Policy: {0} app  |  Installate: {1}  |  Mancanti: {2}" -f $apps.Count, $present.Count, $missing.Count)
Write-Log $Log "=== APPS AUDIT END ===" "INFO"
Write-Host ""
Write-Host "  Log salvato: $Log" -ForegroundColor Cyan
Write-Host ""
if (Get-Command Write-WinOptFooter -ErrorAction SilentlyContinue) { Write-WinOptFooter $Log $MOD $ACT }
if (Get-Command Pause-WinOptIfInteractive -ErrorAction SilentlyContinue) { Pause-WinOptIfInteractive }
