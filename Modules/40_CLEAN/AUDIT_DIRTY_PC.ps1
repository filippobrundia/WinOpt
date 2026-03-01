#Requires -Version 5.1
<#  WIN_OPT_CLAUDE - 06_CLEAN - AUDIT_DIRTY_PC
    Audit a zero modifiche: scansiona il PC per bloatware, AV truffaldini,
    optimizer scam, remote access agents, startup anomali, proxy/DNS/hosts alterati.
    NON rimuove nulla. Solo report.
#>

. "$PSScriptRoot\..\_COMMON\Common.ps1"

$MOD = "06_CLEAN"
$Log = New-LogPath $MOD "AUDIT_DIRTY_PC"
$ACT       = "AUDIT_DIRTY_PC"
if (Get-Command Reset-WinOptLogCounters -ErrorAction SilentlyContinue) { Reset-WinOptLogCounters }
Write-Log $Log "=== AUDIT DIRTY PC START ===" "INFO"
Write-Log $Log "NOTA: questo script e' SOLO lettura. Nessuna modifica al sistema." "INFO"

# ── Pattern sospetti ─────────────────────────────────────────────────────────
$suspiciousPatterns = @(
    # Optimizer/Cleaner truffaldini
    "CCleaner","Advanced SystemCare","PC Optimizer","Registry Cleaner","WinOptimizer",
    "System Mechanic","SlimCleaner","PC Speed Maximizer","Wise Care","Wise Registry",
    "Driver Booster","Driver Easy","Driver Talent","Snappy Driver","IObit",
    "Auslogics","Glary Utilities","Restoro","Reimage","PC Reviver",
    # Adware / PUP noti
    "OpenCandy","MyWebSearch","Conduit","Ask Toolbar","SearchProtect",
    "Babylon","Delta Toolbar","Snap.do","eSafe","SpeedBit",
    # Remote access legit ma spesso installati senza consenso
    "AnyDesk","TeamViewer","LogMeIn","RemotePC","ScreenConnect",
    "ConnectWise","Splashtop","Ammyy Admin","RemoteUtilities",
    # AV truffaldini / scareware
    "MacKeeper","SpyHunter","MalwareFox","Reimage Repair","PC Tools",
    "Total AV","Adaware","Comodo","ZoneAlarm"
)

# ── Programmi installati ──────────────────────────────────────────────────────
Write-Log $Log "--- Programmi installati (check pattern sospetti) ---"
$installedApps = @()
$regPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
)
foreach ($rp in $regPaths) {
    try {
        Get-ItemProperty $rp -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName } |
        Select-Object DisplayName, Publisher, DisplayVersion, InstallDate |
        ForEach-Object { $installedApps += $_ }
    } catch { }
}

$foundSuspicious = @()
foreach ($app in ($installedApps | Sort-Object DisplayName -Unique)) {
    foreach ($pat in $suspiciousPatterns) {
        if ($app.DisplayName -ilike "*$pat*") {
            $msg = ("[SOSPETTO] {0,-40} Publisher={1}" -f $app.DisplayName, $app.Publisher)
            Write-Log $Log $msg "WARN"
            $foundSuspicious += $app.DisplayName
            break
        }
    }
}
if ($foundSuspicious.Count -eq 0) {
    Write-Log $Log "Nessun programma sospetto nei pattern comuni." "OK"
}

# ── Startup anomali (Run keys) ────────────────────────────────────────────────
Write-Log $Log "--- Startup entries (Run keys) ---"
$runKeys = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"
)
foreach ($k in $runKeys) {
    try {
        $props = Get-ItemProperty -Path $k -ErrorAction Stop
        $props.PSObject.Properties | Where-Object { $_.Name -notlike "PS*" } | ForEach-Object {
            $val = [string]$_.Value
            # Segnala se punta a path non standard
            $suspicious = $val -match "(?i)(temp|appdata\\roaming|downloads|users\\public|programdata\\(?!microsoft))"
            $level = if ($suspicious) {"WARN"} else {"INFO"}
            Write-Log $Log ("[RUNKEY][{0}] {1,-25} -> {2}" -f (Split-Path $k -Leaf), $_.Name, $val) $level
        }
    } catch { }
}

# Startup folder
Write-Log $Log "--- Startup folder items ---"
$startFolders = @(
    "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup",
    "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp"
)
foreach ($sf in $startFolders) {
    if (Test-Path -LiteralPath $sf) {
        $items = Get-ChildItem -LiteralPath $sf -ErrorAction SilentlyContinue
        if ($items) {
            $items | ForEach-Object { Write-Log $Log ("[STARTUP_FOLDER] {0}" -f $_.FullName) "WARN" }
        } else {
            Write-Log $Log ("[STARTUP_FOLDER] {0}: vuota" -f $sf) "OK"
        }
    }
}

# ── Task schedulati sospetti ──────────────────────────────────────────────────
Write-Log $Log "--- Scheduled Tasks sospetti (non-Microsoft) ---"
try {
    $allTasks = Get-ScheduledTask -ErrorAction Stop |
                Where-Object { $_.TaskPath -notlike "\Microsoft\*" -and $_.State -ne "Disabled" }
    foreach ($t in $allTasks) {
        $action = ($t.Actions | Select-Object -First 1).Execute
        Write-Log $Log ("[TASK] {0}{1}  Action={2}" -f $t.TaskPath, $t.TaskName, $action) "WARN"
    }
    if (-not $allTasks) {
        Write-Log $Log "Nessun task non-Microsoft attivo trovato." "OK"
    }
} catch {
    Write-Log $Log ("Task schedulati: errore - {0}" -f $_.Exception.Message) "WARN"
}

# ── Proxy / DNS ───────────────────────────────────────────────────────────────
Write-Log $Log "--- Proxy / DNS ---"
# Proxy HKCU
try {
    $proxy = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -ErrorAction Stop
    $proxyEnabled = $proxy.ProxyEnable
    $proxyServer  = $proxy.ProxyServer
    if ($proxyEnabled -eq 1 -and $proxyServer) {
        Write-Log $Log ("[PROXY] ABILITATO: {0}" -f $proxyServer) "WARN"
    } else {
        Write-Log $Log "[PROXY] Disabilitato." "OK"
    }
} catch { }

# DNS
try {
    $adapters = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction Stop |
                Where-Object { $_.ServerAddresses -and $_.ServerAddresses.Count -gt 0 }
    foreach ($a in $adapters) {
        $dns = $a.ServerAddresses -join ", "
        # DNS non standard (non Google 8.8.8.8, Cloudflare 1.1.1.1, Microsoft, o vuoto)
        $knownDNS = @("8.8.8.8","8.8.4.4","1.1.1.1","1.0.0.1","9.9.9.9","4.2.2.1","4.2.2.2")
        $unknownDNS = $a.ServerAddresses | Where-Object {
            $ip = $_
            $ip -ne "" -and -not ($ip.StartsWith("192.168.")) -and
            -not ($ip.StartsWith("10.")) -and -not ($ip.StartsWith("172.")) -and
            $ip -notin $knownDNS
        }
        if ($unknownDNS) {
            Write-Log $Log ("[DNS] {0}: {1}  POTENZIALMENTE ANOMALO" -f $a.InterfaceAlias, $dns) "WARN"
        } else {
            Write-Log $Log ("[DNS] {0}: {1}" -f $a.InterfaceAlias, $dns) "OK"
        }
    }
} catch {
    Write-Log $Log ("DNS: {0}" -f $_.Exception.Message) "SKIP"
}

# ── Hosts file ───────────────────────────────────────────────────────────────
Write-Log $Log "--- Hosts file ---"
$hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
try {
    $hostsLines = Get-Content -LiteralPath $hostsPath -ErrorAction Stop |
                  Where-Object { $_ -notmatch "^\s*#" -and $_.Trim() -ne "" }
    if ($hostsLines.Count -gt 0) {
        Write-Log $Log ("[HOSTS] {0} entry personalizzate:" -f $hostsLines.Count) "WARN"
        $hostsLines | Select-Object -First 20 | ForEach-Object {
            Write-Log $Log ("  {0}" -f $_) "WARN"
        }
    } else {
        Write-Log $Log "[HOSTS] Pulito (solo commenti)" "OK"
    }
} catch {
    Write-Log $Log ("Hosts file: {0}" -f $_.Exception.Message) "WARN"
}

# ── AV/Security prodotti di terze parti ─────────────────────────────────────
Write-Log $Log "--- Prodotti AV/Security terze parti ---"
try {
    $avProducts = Get-CimInstance -Namespace root\SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction Stop
    foreach ($av in $avProducts) {
        $isMs = $av.displayName -imatch "Windows Defender|Microsoft"
        $level = if ($isMs) {"OK"} else {"WARN"}
        Write-Log $Log ("[AV] {0}  (productState={1})" -f $av.displayName, $av.productState) $level
    }
} catch {
    Write-Log $Log "SecurityCenter2: non disponibile." "SKIP"
}

# ── SOMMARIO ──────────────────────────────────────────────────────────────────
Write-Log $Log ""
Write-Log $Log "======= SOMMARIO AUDIT DIRTY PC ======="
Write-Log $Log ("Programmi sospetti trovati:  {0}" -f $foundSuspicious.Count) $(if ($foundSuspicious.Count -gt 0) {"WARN"} else {"OK"})
Write-Log $Log "Check [WARN] lines for everything that requires attention."
Write-Log $Log "======================================="

Write-Log $Log "=== AUDIT DIRTY PC END ===" "INFO"
Write-Host ""
Write-Host "  Log salvato: $Log" -ForegroundColor Cyan
Write-Host ""
if (Get-Command Write-WinOptFooter -ErrorAction SilentlyContinue) { Write-WinOptFooter $Log $MOD $ACT }
if (Get-Command Pause-WinOptIfInteractive -ErrorAction SilentlyContinue) { Pause-WinOptIfInteractive }
