#Requires -Version 5.1
<#  WIN_OPT_CLAUDE - 08_VERIFY - Verifica globale (FAST + DEEP) + score  #>

. "$PSScriptRoot\..\_COMMON\Common.ps1"

# Lettura config: usata per sapere se WSearch deve essere attivo o no
$cfg = Get-WinOptConfig
$cfgWSearchBase  = Get-Feature $cfg "Features.WSearch.BaseEnabled"  $true
$cfgWSearchUltra = Get-Feature $cfg "Features.WSearch.UltraEnabled" $false

$MOD   = "04_VERIFY"
$Log   = New-LogPath $MOD "VERIFY"
$ACT       = "VERIFY"
if (Get-Command Reset-WinOptLogCounters -ErrorAction SilentlyContinue) { Reset-WinOptLogCounters }
$score = 0
$max   = 0

Write-Log $Log "=== VERIFY START ===" "INFO"

# Helper
function Check {
    param(
        [string]$Label,
        $Status
    )
    $script:max += 1

    # Compat: se chiamato con bool (legacy), mappa -> PASS/FAIL
    if ($Status -is [bool]) {
        $Status = if ($Status) { "PASS" } else { "FAIL" }
    }

    switch ($Status) {
        "PASS" { $script:score += 1;   Write-Log $Log ("[PASS] {0}" -f $Label) "OK" }
        "WARN" { $script:score += 0.5; Write-Log $Log ("[WARN] {0}" -f $Label) "WARN" }
        "FAIL" {                    Write-Log $Log ("[FAIL] {0}" -f $Label) "FAIL" }
        default { Write-Log $Log ("[WARN] {0} (status={1})" -f $Label, $Status) "WARN"; $script:score += 0.5 }
    }
}



# ── LIVELLO CORRENTE ──────────────────────────────────────────────────────────
$level = Get-WocLevel
if ($level -and $level -ne "NONE") { Write-Log $Log ("[INFO] CurrentLevel={0}" -f $level) "INFO" }
else                               { Write-Log $Log ("[WARN] CurrentLevel=UNKNOWN (nessun file state)") "WARN" }

# ── DEEP SNAPSHOT (sempre) ───────────────────────────────────────────────────
try {
    $os = Get-CimInstance Win32_OperatingSystem
    $freeMB  = [int]($os.FreePhysicalMemory / 1024)
    $totalMB = [int]($os.TotalVisibleMemorySize / 1024)
    Write-Log $Log ("[INFO] RAM: Free={0} MB  Total={1} MB" -f $freeMB, $totalMB) "INFO"
} catch {
    Write-Log $Log ("[WARN] RAM: {0}" -f $_.Exception.Message) "WARN"
}

try {
    $pCount = (Get-Process | Measure-Object).Count
    Write-Log $Log ("[INFO] Processi: {0}" -f $pCount) "INFO"

    $top = Get-Process | Sort-Object WorkingSet -Descending | Select-Object -First 10
    Write-Log $Log "--- Top10 RAM (WorkingSet) ---" "INFO"
    foreach ($p in $top) {
        $ws = [math]::Round($p.WorkingSet/1MB, 1)
        Write-Log $Log ("PROC {0,-22} {1,6} MB" -f $p.ProcessName, $ws) "INFO"
    }
} catch {
    Write-Log $Log ("[WARN] Processi/TopRAM: {0}" -f $_.Exception.Message) "WARN"
}

# ── SERVIZI CRITICI (Store/Update/Defender) ───────────────────────────────────
Write-Log $Log "--- Servizi critici ---" "INFO"
$crit = @(
  @{N="wuauserv";  L="Windows Update"},
  @{N="UsoSvc";    L="Update Orchestrator"},
  @{N="WinDefend"; L="Microsoft Defender"},
  @{N="WaaSMedicSvc"; L="WaaS Medic"},
  @{N="ClipSVC";   L="Client License Service"},
  @{N="AppXSvc";   L="AppX Deployment"}
)
foreach ($c in $crit) {
  try {
    $sv = Get-Service $c.N -ErrorAction Stop
    Write-Log $Log ("SRV {0} ({1}) = {2} / {3}" -f $c.N, $c.L, $sv.Status, $sv.StartType) "INFO"
    # Non facciamo KO su starttype specifico: ci interessa che non sia disabilitato dove non deve.
    if ($c.N -in @("ClipSVC","AppXSvc","wuauserv","UsoSvc","WaaSMedicSvc")) {
      Check ("{0} non disabilitato" -f $c.L) ($sv.StartType -ne "Disabled")
    }
    if ($c.N -eq "WinDefend") {
      Check ("{0} attivo" -f $c.L) ($sv.Status -eq "Running" -or $sv.StartType -ne "Disabled")
    }
  } catch {
    Write-Log $Log ("SKIP  Servizio {0} non trovato" -f $c.N) "SKIP"
  }
}

# ── SERVIZI OTTIMIZZAZIONI (informativo, level-aware) ─────────────────────────
Write-Log $Log "--- Servizi ottimizzazioni (info) ---" "INFO"
# WSearch incluso nell'elenco informativo sempre; il suo stato atteso
# dipende dal livello (BASE -> cfgWSearchBase, ULTRA -> cfgWSearchUltra)
$svcList = @("DiagTrack","SysMain","WerSvc","WSearch","XblAuthManager","XboxGipSvc","XblGameSave")
foreach ($n in $svcList) {
  try {
    $sv = Get-Service $n -ErrorAction Stop
    Write-Log $Log ("SRV {0} = {1} / {2}" -f $n, $sv.Status, $sv.StartType) "INFO"
  } catch {
    Write-Log $Log ("SRV {0} non trovato (ok)" -f $n) "SKIP"
  }
}

# ── CHECK WSearch: stato coerente con config ──────────────────────────────
try {
    $wsSvc = Get-Service WSearch -ErrorAction Stop
    $isUltra = ($level -eq "ULTRA")
    $expectedEnabled = if ($isUltra) { $cfgWSearchUltra } else { $cfgWSearchBase }
    $isDisabled = ($wsSvc.StartType -eq "Disabled")
    if ($expectedEnabled -and $isDisabled) {
        Check "WSearch: atteso ATTIVO da config, risulta Disabled" "FAIL"
    } elseif (-not $expectedEnabled -and -not $isDisabled) {
        Check ("WSearch: atteso DISABILITATO da config, risulta {0}" -f $wsSvc.StartType) "WARN"
    } else {
        Check ("WSearch: stato coerente col config ({0})" -f $wsSvc.StartType) "PASS"
    }
} catch {
    Write-Log $Log "WSearch: servizio non trovato (SKIP check config)" "SKIP"
}

# ── REGISTRO (policy principali, informativo) ────────────────────────────────
Write-Log $Log "--- Registro (policy principali) ---" "INFO"
$regs = @(
  @{P="HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"; N="AllowTelemetry"},
  @{P="HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent";   N="DisableWindowsConsumerFeatures"}
)
foreach ($r in $regs) {
  try {
    $v = (Get-ItemProperty $r.P -ErrorAction Stop).($r.N)
    Write-Log $Log ("REG {0}\{1} = {2}" -f $r.P, $r.N, $v) "INFO"
  } catch {
    Write-Log $Log ("REG {0}\{1} mancante" -f $r.P, $r.N) "SKIP"
  }
}

# ── EDGE POLICY (info) ───────────────────────────────────────────────────────
Write-Log $Log "--- Edge (policy) ---" "INFO"
try {
    $edge = Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -ErrorAction Stop
    if ($null -ne $edge) {
        foreach ($name in @("StartupBoostEnabled","BackgroundModeEnabled","ShowRecommendationsEnabled","HubsSidebarEnabled")) {
            if ($null -ne $edge.PSObject.Properties[$name]) {
                Write-Log $Log ("EDGE {0} = {1}" -f $name, $edge.$name) "INFO"
            }
        }
        if ($null -ne $edge.PSObject.Properties["StartupBoostEnabled"]) {
            Check "Edge StartupBoostEnabled = 0" ($edge.StartupBoostEnabled -eq 0)
        }
    }
} catch {
    Write-Log $Log "SKIP  Edge policy non presente" "SKIP"
}

# ── ONEDRIVE (L2 aware) ──────────────────────────────────────────────────────
Write-Log $Log "--- OneDrive ---" "INFO"
$odRunning = $false
try { $odRunning = (Get-Process OneDrive -ErrorAction SilentlyContinue) -ne $null } catch { }
Write-Log $Log ("OneDrive process running = {0}" -f $odRunning) "INFO"

$odAutorun = $null
try {
    $odAutorun = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -ErrorAction Stop)."OneDrive"
} catch { $odAutorun = $null }
Write-Log $Log ("OneDrive autorun HKCU present = {0}" -f ([bool]$odAutorun)) "INFO"

$odPolicy = $null
try {
    $odPolicy = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive" -ErrorAction Stop)."DisableFileSyncNGSC"
} catch { $odPolicy = $null }
if ($null -ne $odPolicy) { Write-Log $Log ("OneDrive DisableFileSyncNGSC = {0}" -f $odPolicy) "INFO" }
else { Write-Log $Log "OneDrive policy HKLM non presente (ok per L2)." "SKIP" }

# FIX v1.8: la condizione originale era un falso positivo.
# "non in esecuzione e senza autorun" e' vero anche su sistemi
# dove OneDrive non e' mai stato toccato (basta non aver ancora fatto login).
# Ora: PASS solo se policy HKLM e' 1 (OFF) OPPURE se
# il backup L2 esiste (la suite ha eseguito OFF_L2), OPPURE se non e' installato.
$odBackupL2 = Test-Path -LiteralPath (Join-Path $script:WOC_BACKUP_ROOT "03_ONEDRIVE_L2\reg.jsonl") -ErrorAction SilentlyContinue
$odInstalled = Test-Path -LiteralPath "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe" -ErrorAction SilentlyContinue
$odDisabled = ($odPolicy -eq 1) -or $odBackupL2 -or (-not $odInstalled)
Check "OneDrive disabilitato (policy L1, o OFF_L2 eseguito, o non installato)" ($odDisabled)

# ── APP (policy) ─────────────────────────────────────────────────────────────
Write-Log $Log "--- App (policy) ---" "INFO"
$policyPath = Join-Path $PSScriptRoot "..\30_APPS\AppsPolicy.json"
if (Test-Path -LiteralPath $policyPath) {
    $apps = @((Get-Content -LiteralPath $policyPath -Raw | ConvertFrom-Json).Apps)
    foreach ($a in $apps) {
        $id = [string]$a.Id
        if ([string]::IsNullOrWhiteSpace($id)) { continue }
        Check ("App installata: {0}" -f $a.Name) (Test-WingetInstalled $id)
    }
} else {
    Write-Log $Log "AppsPolicy.json non trovato, skip check app." "SKIP"
}

# ── SCORE ────────────────────────────────────────────────────────────────────
Write-Log $Log "======================================="
if ($max -gt 0) {
    $pct = [math]::Round([double]$score / [double]$max * 100, 1)
    $lvl = if ($pct -ge 90) {"OK"} elseif ($pct -ge 60) {"WARN"} else {"FAIL"}
    Write-Log $Log ("SCORE FINALE: {0} / {1}  ({2}%)" -f $score, $max, $pct) $lvl
} else {
    Write-Log $Log "Nessun controllo eseguito." "WARN"
}
Write-Log $Log "======================================="
Write-Log $Log "=== VERIFY END ===" "INFO"
Write-Host ""
Write-Host "  Log salvato: $Log" -ForegroundColor Cyan
Write-Host ""
if (Get-Command Write-WinOptFooter -ErrorAction SilentlyContinue) { Write-WinOptFooter $Log $MOD $ACT }
if (Get-Command Pause-WinOptIfInteractive -ErrorAction SilentlyContinue) { Pause-WinOptIfInteractive }
