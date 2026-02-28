#Requires -Version 5.1
<#  WIN_OPT_CLAUDE - 06_CLEAN - AUDIT  #>

. "$PSScriptRoot\..\_COMMON\Common.ps1"

$MOD = "06_CLEAN"
$Log = New-LogPath $MOD "AUDIT"
$ACT       = "AUDIT"
if (Get-Command Reset-WinOptLogCounters -ErrorAction SilentlyContinue) { Reset-WinOptLogCounters }
Write-Log $Log "=== CLEAN AUDIT START ===" "INFO"

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Write-Log $Log ("Admin = {0}" -f $isAdmin)

# Richiede privilegi amministrativi. Avvia LAUNCHER.cmd come amministratore.
if (-not $isAdmin) {
    Write-Log $Log "CLEAN AUDIT richiede privilegi amministrativi: esecuzione annullata." "ERROR"
    Write-Host "CLEAN AUDIT richiede privilegi amministrativi. Avvia il launcher come amministratore." -ForegroundColor Red
    exit 1
}

$targets = @(
    @{L="Windows Temp";          P="C:\Windows\Temp"},
    @{L="User Temp";             P=$env:TEMP},
    @{L="LocalAppData Temp";     P=(Join-Path $env:LOCALAPPDATA "Temp")},
    @{L="DO Cache";              P="C:\Windows\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache"},
    @{L="WER";                   P="C:\ProgramData\Microsoft\Windows\WER"},
    @{L="WU Download Cache";     P="C:\Windows\SoftwareDistribution\Download"},
    @{L="Edge Cache";            P=(Join-Path $env:LOCALAPPDATA "Microsoft\Edge\User Data\Default\Cache")},
    @{L="Chrome Cache";          P=(Join-Path $env:LOCALAPPDATA "Google\Chrome\User Data\Default\Cache")},
    @{L="CBS Logs";              P="C:\Windows\Logs\CBS"}
)

# Firefox: somma tutti i profili
$ffTotal = 0
$ffRoot  = Join-Path $env:APPDATA "Mozilla\Firefox\Profiles"
if (Test-Path -LiteralPath $ffRoot) {
    Get-ChildItem -LiteralPath $ffRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $cache2 = Join-Path $_.FullName "cache2"
        $ffTotal += Get-FolderSizeMB $cache2
    }
}

$rows   = @()
$totale = 0
foreach ($t in $targets) {
    $mb = Get-FolderSizeMB $t.P
    $totale += $mb
    $rows += [pscustomobject]@{Cartella=$t.L; MB=$mb; Percorso=$t.P}
}
if ($ffTotal -gt 0) {
    $totale += $ffTotal
    $rows += [pscustomobject]@{Cartella="Firefox Cache2 (tutti profili)"; MB=$ffTotal; Percorso=$ffRoot}
}

$rows | Sort-Object MB -Descending | ForEach-Object {
    $color = if ($_.MB -gt 500) { "FAIL" } elseif ($_.MB -gt 100) { "WARN" } else { "OK" }
    Write-Log $Log ("{0,-35} {1,8:N1} MB   {2}" -f $_.Cartella, $_.MB, $_.Percorso) $color
}

Write-Log $Log ("Totale recuperabile stimato: {0:N1} MB" -f $totale)

# DISM analyze
if ($isAdmin) {
    Write-Log $Log "DISM AnalyzeComponentStore in corso (attendere)..."
    try {
        $txt = & dism.exe /Online /Cleanup-Image /AnalyzeComponentStore 2>&1 | Out-String
        if ($txt -match "Component Store Cleanup Recommended\s*:\s*(Yes|No)") {
            Write-Log $Log ("DISM Cleanup Recommended = {0}" -f $Matches[1]) $(if ($Matches[1] -eq "Yes") {"WARN"} else {"OK"})
        }
        if ($txt -match "Windows Explorer Reported Size of Component Store\s*:\s*(.+)") {
            Write-Log $Log ("DISM Store Size = {0}" -f $Matches[1].Trim())
        }
    } catch {
        Write-Log $Log ("DISM FAIL: {0}" -f $_.Exception.Message) "WARN"
    }
} else {
    Write-Log $Log "DISM Analyze: SALTATO (richiede Admin)" "SKIP"
}

Write-Log $Log "=== CLEAN AUDIT END ===" "INFO"
Write-Host ""
Write-Host "  Log salvato: $Log" -ForegroundColor Cyan
Write-Host ""
if (Get-Command Write-WinOptFooter -ErrorAction SilentlyContinue) { Write-WinOptFooter $Log $MOD $ACT }
if (Get-Command Pause-WinOptIfInteractive -ErrorAction SilentlyContinue) { Pause-WinOptIfInteractive }
