#Requires -Version 5.1
<#  WIN_OPT_CLAUDE - 06_CLEAN - DEEP (ADMIN)
    Deep: esegue prima SAFE, poi WU download cache + DISM StartComponentCleanup.
#>

. "$PSScriptRoot\..\_COMMON\Common.ps1"
# Elevation is handled by LAUNCHER.cmd (single UAC).
# Assert-Admin below is a safety net for direct execution outside the launcher.
$MOD = "06_CLEAN"
$Log = New-LogPath $MOD "DEEP"
$ACT       = "DEEP"
if (Get-Command Reset-WinOptLogCounters -ErrorAction SilentlyContinue) { Reset-WinOptLogCounters }
Write-Log $Log "=== CLEAN DEEP START ===" "INFO"
Assert-Admin $Log

# Prima esegui SAFE
$safeScript = Join-Path $PSScriptRoot "SAFE.ps1"
if (Test-Path -LiteralPath $safeScript) {
    Write-Log $Log "Esecuzione SAFE.ps1 prima di DEEP..."
    $env:WOC_SUBSCRIPT = "1"
    $env:WINOPT_NO_PAUSE = "1"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $safeScript
    $env:WOC_SUBSCRIPT = "0"
    $env:WINOPT_NO_PAUSE = "0"
    # FIX v1.8: leggi il totale SAFE per la somma cumulativa
    $safeFreedMB = 0
    try { $safeFreedMB = [double]$env:WOC_SAFE_FREED_MB } catch { }
    Write-Log $Log ("SAFE completato. Liberati da SAFE: ~{0:N1} MB" -f $safeFreedMB) "OK"
} else {
    $safeFreedMB = 0
    Write-Log $Log "SAFE.ps1 non trovato: $safeScript" "WARN"
}

# Stop servizi WU prima di svuotare download cache
$wuSvcs = @("wuauserv","bits","dosvc","cryptsvc")
Write-Log $Log "--- Stop servizi Windows Update ---"
foreach ($s in $wuSvcs) {
    try {
        $sv = Get-Service $s -ErrorAction Stop
        if ($sv.Status -eq "Running") {
            Stop-Service $s -Force -ErrorAction SilentlyContinue
            Write-Log $Log ("Servizio fermato: {0}" -f $s) "OK"
        }
    } catch { }
}

$wuCache = "C:\Windows\SoftwareDistribution\Download"
$freed = Clean-Folder $Log $wuCache "WU Download Cache"
Write-Log $Log ("WU Cache liberata: {0:N1} MB" -f $freed)

# Riavvia servizi WU
Write-Log $Log "--- Riavvio servizi Windows Update ---"
foreach ($s in $wuSvcs) {
    try { Start-Service $s -ErrorAction SilentlyContinue; Write-Log $Log ("Riavviato: {0}" -f $s) "OK" } catch { }
}

# DISM StartComponentCleanup
Write-Log $Log "--- DISM StartComponentCleanup (attendere, può richiedere minuti) ---"
try {
    $outFile = Join-Path $env:TEMP ("WOC_DISM_DEEP_{0}.txt" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
    $errFile = $outFile -replace "\.txt$", "_err.txt"
    $p = Start-Process -FilePath "dism.exe" `
         -ArgumentList "/Online", "/Cleanup-Image", "/StartComponentCleanup" `
         -PassThru -NoNewWindow `
         -RedirectStandardOutput $outFile -RedirectStandardError $errFile
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while (-not $p.HasExited) {
        Start-Sleep -Seconds 20
        Write-Log $Log ("DISM in corso... {0:mm\:ss} trascorsi" -f $sw.Elapsed)
    }
    $sw.Stop()
    $exitCode = $p.ExitCode
    if ($null -eq $exitCode) { $exitCode = $LASTEXITCODE }
    $out = Get-Content -LiteralPath $outFile -ErrorAction SilentlyContinue | Select-Object -Last 10
    if ($out) { $out | ForEach-Object { Write-Log $Log ("DISM: {0}" -f $_) } }
    if ($exitCode -eq 0) {
        Write-Log $Log ("DISM completato in {0:mm\:ss}" -f $sw.Elapsed) "OK"
    } else {
        Write-Log $Log ("DISM exit code {0} (non critico)" -f $exitCode) "WARN"
    }
    Remove-Item -LiteralPath $outFile -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $errFile -ErrorAction SilentlyContinue
} catch {
    Write-Log $Log ("DISM FAIL: {0}" -f $_.Exception.Message) "WARN"
}

Write-Log $Log "=== CLEAN DEEP END ===" "INFO"
# FIX v1.8: totale cumulativo SAFE + DEEP
$totalCumulative = $safeFreedMB + $freed
Write-Log $Log ("TOTALE CUMULATIVO (SAFE + DEEP): ~{0:N1} MB liberati" -f $totalCumulative) "OK"
Write-Host ""
Write-Host "  Log salvato: $Log" -ForegroundColor Cyan
Write-Host ""
if (Get-Command Write-WinOptFooter -ErrorAction SilentlyContinue) { Write-WinOptFooter $Log $MOD $ACT }
if (Get-Command Pause-WinOptIfInteractive -ErrorAction SilentlyContinue) { Pause-WinOptIfInteractive }
