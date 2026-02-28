#Requires -Version 5.1
<#  WIN_OPT_CLAUDE - 06_CLEAN - SAFE
    Pulizia sicura: temp, WER, DO cache, browser cache, cestino, thumbnail.
    NON tocca cookie, sessioni, password, WU download cache.
    Non richiede admin (alcune cartelle protette vengono saltate silenziosamente).
#>

. "$PSScriptRoot\..\_COMMON\Common.ps1"

$MOD = "06_CLEAN"
$Log = New-LogPath $MOD "SAFE"
$ACT       = "SAFE"
if (Get-Command Reset-WinOptLogCounters -ErrorAction SilentlyContinue) { Reset-WinOptLogCounters }
Write-Log $Log "=== CLEAN SAFE START ===" "INFO"

$targets = @(
    @{L="Windows Temp";          P="C:\Windows\Temp"},
    @{L="User Temp";             P=$env:TEMP},
    @{L="LocalAppData Temp";     P=(Join-Path $env:LOCALAPPDATA "Temp")},
    @{L="DO Cache";              P="C:\Windows\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache"},
    @{L="WER";                   P="C:\ProgramData\Microsoft\Windows\WER"},
    @{L="Thumbnail Cache";       P=(Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Explorer")},
    @{L="Edge Cache";            P=(Join-Path $env:LOCALAPPDATA "Microsoft\Edge\User Data\Default\Cache")},
    @{L="Chrome Cache";          P=(Join-Path $env:LOCALAPPDATA "Google\Chrome\User Data\Default\Cache")}
)

# FIX v1.8: avviso se i browser risultano aperti (cache locked -> MB liberati azzerati)
$browserProcs = @("msedge","chrome","firefox","brave","opera")
$openBrowsers = @()
foreach ($b in $browserProcs) {
    if (Get-Process -Name $b -ErrorAction SilentlyContinue) { $openBrowsers += $b }
}
if ($openBrowsers.Count -gt 0) {
    Write-Log $Log ("ATTENZIONE: browser aperti rilevati: {0}" -f ($openBrowsers -join ", ")) "WARN"
    Write-Log $Log "I file di cache del browser sono bloccati. Chiudere i browser prima di eseguire CLEAN SAFE" "WARN"
    Write-Log $Log "per massimizzare lo spazio recuperato. La pulizia continua ma molti file potrebbero risultare bloccati." "WARN"
}

$totale = 0
$i = 0
foreach ($t in $targets) {
    $i++
    Write-Progress -Activity "CLEAN SAFE" -Status $t.L -PercentComplete ([math]::Round($i / $targets.Count * 100))
    # Clean-Folder ritorna i MB liberati (numero). Somma al totale.
    $totale += (Clean-Folder $Log $t.P $t.L)
}

# Firefox cache2 tutti i profili
$ffRoot = Join-Path $env:APPDATA "Mozilla\Firefox\Profiles"
if (Test-Path -LiteralPath $ffRoot) {
    Get-ChildItem -LiteralPath $ffRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $cache2 = Join-Path $_.FullName "cache2"
        $totale += (Clean-Folder $Log $cache2 ("Firefox cache2 [{0}]" -f $_.Name))
    }
} else {
    Write-Log $Log "Firefox: nessun profilo trovato." "SKIP"
}

Write-Progress -Activity "CLEAN SAFE" -Completed

# Cestino
try {
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    Write-Log $Log "Cestino svuotato." "OK"
} catch {
    Write-Log $Log "Cestino: impossibile svuotare." "WARN"
}

Write-Log $Log ("Totale liberato: ~{0:N1} MB" -f $totale)
Write-Log $Log "=== CLEAN SAFE END ===" "INFO"
Write-Host ""
Write-Host "  Log salvato: $Log" -ForegroundColor Cyan
Write-Host ""
# FIX v1.8: esponi il totale a DEEP.ps1 tramite env var (usato per somma cumulativa)
$env:WOC_SAFE_FREED_MB = [string]$totale
if (Get-Command Write-WinOptFooter -ErrorAction SilentlyContinue) { Write-WinOptFooter $Log $MOD $ACT }
if (Get-Command Pause-WinOptIfInteractive -ErrorAction SilentlyContinue) { Pause-WinOptIfInteractive }
