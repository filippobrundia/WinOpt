#Requires -Version 5.1
<#  WIN_OPT_CLAUDE - _COMMON\Preflight.ps1
    Controlli pre-volo: PS version, admin, spazio disco, punto di ripristino.
    Chiamata dagli script APPLY come:
        & "$PSScriptRoot\..\\_COMMON\\Preflight.ps1"
        if ($LASTEXITCODE -ne 0) { exit 1 }
    Exit 0 = OK, Exit 1 = FAIL (blocca l'APPLY)
#>
param(
    [bool]$RequireAdmin       = $true,
    [int]$MinFreeGB           = 5,
    [bool]$CreateRestorePoint = $true
)

. "$PSScriptRoot\Common.ps1"

$ok = $true

# ── PS Version ────────────────────────────────────────────────────────────────
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Host "  [PREFLIGHT] FAIL - PowerShell 5.1+ richiesto. Versione: $($PSVersionTable.PSVersion)" -ForegroundColor Red
    $ok = $false
} else {
    Write-Host "  [PREFLIGHT] PS $($PSVersionTable.PSVersion) OK" -ForegroundColor Green
}

# ── Admin ─────────────────────────────────────────────────────────────────────
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($RequireAdmin -and -not $isAdmin) {
    Write-Host "  [PREFLIGHT] FAIL - Richiesti privilegi Administrator." -ForegroundColor Red
    $ok = $false
} else {
    Write-Host "  [PREFLIGHT] Admin: $isAdmin" -ForegroundColor Green
}

# ── Spazio disco C: ───────────────────────────────────────────────────────────
try {
    $drv    = Get-PSDrive C -ErrorAction Stop
    $freeGB = [math]::Round($drv.Free / 1GB, 2)
    if ($freeGB -lt $MinFreeGB) {
        Write-Host "  [PREFLIGHT] FAIL - Disco C: ${freeGB}GB liberi (minimo ${MinFreeGB}GB)" -ForegroundColor Red
        $ok = $false
    } else {
        Write-Host "  [PREFLIGHT] Disco C: ${freeGB}GB liberi - OK" -ForegroundColor Green
    }
} catch {
    Write-Host "  [PREFLIGHT] WARN - Impossibile verificare disco: $($_.Exception.Message)" -ForegroundColor Yellow
}

if (-not $ok) { exit 1 }

# ── Restore Point ─────────────────────────────────────────────────────────────
if ($CreateRestorePoint -and $isAdmin) {
    Write-Host "  [PREFLIGHT] Creazione punto di ripristino..." -ForegroundColor Cyan
    try {
        Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
        Checkpoint-Computer `
            -Description "WIN_OPT_CLAUDE $(Get-Date -Format 'yyyyMMdd_HHmmss')" `
            -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Write-Host "  [PREFLIGHT] Punto di ripristino creato." -ForegroundColor Green
    } catch {
        # Non blocca: il restore point fallisce su sistemi con WMI instabile
        Write-Host "  [PREFLIGHT] Restore point SKIP (non critico): $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

exit 0
