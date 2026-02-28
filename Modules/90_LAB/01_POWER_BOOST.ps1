#Requires -Version 5.1
<#  WIN_OPT_CLAUDE - 12_POWER - APPLY (ADMIN)
    Rileva automaticamente se siamo su laptop o desktop:
    - LAPTOP  -> Balanced (risparmia batteria, non penalizza le prestazioni)
    - DESKTOP -> High Performance (nessuna batteria, massime prestazioni)
    Backup del piano corrente per REVERT esatto.
#>

. "$PSScriptRoot\..\_COMMON\Common.ps1"
# Elevation is handled by LAUNCHER.cmd (single UAC).
# Assert-Admin below is a safety net for direct execution outside the launcher.
$MOD       = "12_POWER"
$Log       = New-LogPath $MOD "APPLY"
$ACT       = "APPLY"
if (Get-Command Reset-WinOptLogCounters -ErrorAction SilentlyContinue) { Reset-WinOptLogCounters }
$BackupDir = Join-Path $script:WOC_BACKUP_ROOT $MOD
Ensure-Dir $BackupDir
$BackupFile = Join-Path $BackupDir "power.json"

Write-Log $Log "=== POWER APPLY START ===" "INFO"
# ── PREFLIGHT (restore point + space check) ───────────────────────────────────
& "$PSScriptRoot\..\_COMMON\Preflight.ps1"
if ($LASTEXITCODE -ne 0) {
    Write-Host "  Preflight fallito. Operazione annullata." -ForegroundColor Red
    exit 1
}
Assert-Admin $Log

# ── RILEVAMENTO TIPO MACCHINA ─────────────────────────────────────────────────
# ChassisTypes: 8,9,10,11,14 = notebook/laptop/tablet
# 3,4,5,6,7 = desktop/tower/mini-tower
# Se la batteria e' presente, e' quasi certamente un laptop.
$isLaptop = $false
try {
    $bat = Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue
    if ($bat) {
        $isLaptop = $true
        Write-Log $Log "Rilevato: LAPTOP (batteria presente)" "INFO"
    } else {
        $chassis = Get-CimInstance -ClassName Win32_SystemEnclosure -ErrorAction SilentlyContinue
        $laptopTypes = @(8,9,10,11,14,30,31,32)
        if ($chassis -and ($chassis.ChassisTypes | Where-Object { $_ -in $laptopTypes })) {
            $isLaptop = $true
            Write-Log $Log ("Rilevato: LAPTOP (ChassisType={0})" -f ($chassis.ChassisTypes -join ",")) "INFO"
        } else {
            Write-Log $Log ("Rilevato: DESKTOP (ChassisType={0})" -f ($chassis.ChassisTypes -join ",")) "INFO"
        }
    }
} catch {
    Write-Log $Log "Rilevamento tipo macchina fallito. Default: DESKTOP." "WARN"
}

# ── BACKUP PIANO CORRENTE ─────────────────────────────────────────────────────
$currentGuid = $null
try {
    $activeLine = & powercfg /getactivescheme 2>$null
    if ($activeLine -match "([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})") {
        $currentGuid = $Matches[1]
        Write-Log $Log ("Piano corrente: {0}" -f $currentGuid) "INFO"
    }
} catch { }

$bak = [ordered]@{ OriginalGuid=$currentGuid; IsLaptop=$isLaptop; AppliedAt=(Get-Date -Format "o") }
$bak | ConvertTo-Json | Set-Content -Path $BackupFile -Encoding UTF8
Write-Log $Log "Backup piano -> $BackupFile"

# ── GUID PIANI STANDARD ───────────────────────────────────────────────────────
$GUID_BALANCED      = "381b4222-f694-41f0-9685-ff5bb260df2e"
$GUID_HIGH_PERF     = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
$GUID_POWER_SAVER   = "a1841308-3541-4fab-bc81-f71556f20b4a"
$GUID_ULTIMATE      = "e9a42b02-d5df-448d-aa00-03f14749eb61"  # presente solo su alcune build

# ── SELEZIONE E APPLICAZIONE ──────────────────────────────────────────────────
if ($isLaptop) {
    $targetGuid = $GUID_BALANCED
    $targetName = "Balanced"
    Write-Log $Log "LAPTOP rilevato -> piano Balanced (preserva batteria)" "INFO"
} else {
    # Desktop: prova Ultimate Performance, fallback High Performance
    $ultimateExists = & powercfg /list 2>$null | Select-String -Pattern $GUID_ULTIMATE
    if ($ultimateExists) {
        $targetGuid = $GUID_ULTIMATE
        $targetName = "Ultimate Performance"
        Write-Log $Log "DESKTOP: Ultimate Performance disponibile -> selezionato." "INFO"
    } else {
        $targetGuid = $GUID_HIGH_PERF
        $targetName = "High Performance"
        Write-Log $Log "DESKTOP: Ultimate Performance non presente -> High Performance." "INFO"
        # Prova ad abilitare Ultimate Performance (richiede feature abilitata)
        try {
            & powercfg /duplicatescheme $GUID_ULTIMATE 2>$null | Out-Null
            Start-Sleep -Milliseconds 500
            $ultimateExists2 = & powercfg /list 2>$null | Select-String -Pattern $GUID_ULTIMATE
            if ($ultimateExists2) {
                $targetGuid = $GUID_ULTIMATE
                $targetName = "Ultimate Performance"
                Write-Log $Log "Ultimate Performance abilitato con successo." "OK"
            }
        } catch { }
    }
}

try {
    & powercfg /setactive $targetGuid 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Log $Log ("Piano energetico impostato: {0} ({1})" -f $targetName, $targetGuid) "OK"
    } else {
        Write-Log $Log ("powercfg /setactive fallito (ExitCode={0})" -f $LASTEXITCODE) "WARN"
    }
} catch {
    Write-Log $Log ("Errore applicazione piano: {0}" -f $_.Exception.Message) "WARN"
}

# ── IMPOSTAZIONI AGGIUNTIVE (coerenti con il piano) ──────────────────────────
Write-Log $Log "--- Impostazioni aggiuntive ---"
$kPwr = "HKLM:\SYSTEM\CurrentControlSet\Control\Power"
Backup-RegValue (Join-Path $BackupDir "reg.jsonl") $kPwr "HibernateEnabled"
Backup-RegValue (Join-Path $BackupDir "reg.jsonl") $kPwr "HibernateEnabledDefault"

if ($isLaptop) {
    # Laptop: ibernazione utile per batteria scarica
    Write-Log $Log "LAPTOP: ibernazione mantenuta attiva." "INFO"
} else {
    # Desktop: ibernazione spreca spazio su SSD, disabilitata
    try {
        & powercfg /hibernate off 2>$null | Out-Null
        Write-Log $Log "DESKTOP: ibernazione disabilitata (libera spazio hiberfil.sys)." "OK"
    } catch {
        Write-Log $Log ("Hibernate off SKIP: {0}" -f $_.Exception.Message) "WARN"
    }
}

Write-Log $Log "=== POWER APPLY END ===" "INFO"
Write-Host ""; Write-Host "  Log salvato: $Log" -ForegroundColor Cyan
if (Get-Command Write-WinOptFooter -ErrorAction SilentlyContinue) { Write-WinOptFooter $Log $MOD $ACT }
if (Get-Command Pause-WinOptIfInteractive -ErrorAction SilentlyContinue) { Pause-WinOptIfInteractive }
