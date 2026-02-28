#Requires -Version 5.1
<#  WIN_OPT_CLAUDE - 07_APPS - APPLY (ADMIN)  #>

. "$PSScriptRoot\..\_COMMON\Common.ps1"
# Elevation is handled by LAUNCHER.cmd (single UAC).
# Assert-Admin below is a safety net for direct execution outside the launcher.
$MOD = "07_APPS"
$Log = New-LogPath $MOD "APPLY"
$ACT       = "APPLY"
if (Get-Command Reset-WinOptLogCounters -ErrorAction SilentlyContinue) { Reset-WinOptLogCounters }
Write-Log $Log "=== APPS APPLY START ===" "INFO"
Assert-Admin $Log

$wg = Get-WingetPath
if (-not $wg) { Write-Log $Log "winget non trovato." "FAIL"; exit 1 }

$policyPath = Join-Path $PSScriptRoot "AppsPolicy.json"
if (-not (Test-Path -LiteralPath $policyPath)) { Write-Log $Log "AppsPolicy.json non trovato." "FAIL"; exit 1 }
$P    = Get-Content -LiteralPath $policyPath -Raw | ConvertFrom-Json
$apps = @($P.Apps)
if (-not $apps -or $apps.Count -eq 0) { Write-Log $Log "Nessuna app nella policy." "WARN"; exit 0 }

# Aggiorna sorgenti winget
Write-Log $Log "Aggiornamento sorgenti winget..."
$ec = Invoke-Winget $Log "source update --name winget" 60000
if ($ec -ne 0) {
    Write-Log $Log "Source update (winget) fallito: continuo comunque." "WARN"
}

$installed = 0; $skipped = 0; $failed = 0
$i = 0
foreach ($a in $apps) {
    $i++
    $id   = [string]$a.Id
    $name = [string]$a.Name
    if ([string]::IsNullOrWhiteSpace($id)) { continue }
    Write-Progress -Activity "APPS APPLY" -Status $name -PercentComplete ([math]::Round($i / $apps.Count * 100))

    if (Test-WingetInstalled $id) {
        Write-Log $Log ("SKIP  gia installato: {0} ({1})" -f $name, $id) "SKIP"
        $skipped++
        continue
    }

    Write-Log $Log ("INSTALL: {0} ({1})" -f $name, $id)
    $args = "install --id $id -e --source winget --silent --accept-source-agreements --accept-package-agreements"
    $ec   = Invoke-Winget $Log $args 600000

    if ($ec -eq 0 -and (Test-WingetInstalled $id)) {
        Write-Log $Log ("OK: installato {0}" -f $name) "OK"
        $installed++
    } else {
        Write-Log $Log ("FAIL: {0} (exit={1})" -f $name, $ec) "FAIL"
        $failed++
    }
}
Write-Progress -Activity "APPS APPLY" -Completed

Write-Log $Log ("SOMMARIO: Installati={0}  Saltati={1}  Falliti={2}" -f $installed, $skipped, $failed)
Write-Log $Log "=== APPS APPLY END ===" "INFO"
Write-Host ""
Write-Host "  Log salvato: $Log" -ForegroundColor Cyan
Write-Host ""
if (Get-Command Write-WinOptFooter -ErrorAction SilentlyContinue) { Write-WinOptFooter $Log $MOD $ACT }
if (Get-Command Pause-WinOptIfInteractive -ErrorAction SilentlyContinue) { Pause-WinOptIfInteractive }
