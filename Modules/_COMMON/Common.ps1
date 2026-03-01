#Requires -Version 5.1
<#
  WIN_OPT_CLAUDE - _COMMON\Common.ps1
  v1.3 - Clean-Folder riporta file bloccati/in uso
#>

$script:WOC_LOG_ROOT    = "C:\WinOpt\Logs"
$script:WOC_BACKUP_ROOT = "C:\WinOpt\State\Backup"

$script:WOC_OK_COUNT   = 0
$script:WOC_WARN_COUNT = 0
$script:WOC_FAIL_COUNT = 0

function Reset-WinOptLogCounters {
    $script:WOC_OK_COUNT   = 0
    $script:WOC_WARN_COUNT = 0
    $script:WOC_FAIL_COUNT = 0
}

function Ensure-Dir {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Get-WinOptConfig {
    param([string]$Path)
    try {
        if (-not $Path) {
            # Common.ps1 è in Modules\_COMMON, Config è in Modules\Config
            $Path = Join-Path (Split-Path $PSScriptRoot -Parent) "Config\WinOpt.config.psd1"
        }
        if (Test-Path -LiteralPath $Path) {
            return Import-PowerShellDataFile -Path $Path
        }
    } catch { }
    return @{ Profile="BASE"; Features=@{} }
}

function Get-Feature {
    param($Config, [string]$Path, $Default=$null)
    try {
        $cur = $Config
        foreach ($k in $Path -split '\.') {
            if ($cur -is [hashtable] -and $cur.ContainsKey($k)) {
                $cur = $cur[$k]
            } else {
                return $Default
            }
        }
        return $cur
    } catch {
        return $Default
    }
}

function Start-ServiceSafe {
    param([string]$Log, [string]$Name)
    try {
        $svc = Get-Service -Name $Name -ErrorAction Stop
        if ($svc.Status -ne "Running") {
            Start-Service -Name $Name -ErrorAction Stop
            $deadline = (Get-Date).AddSeconds(15)
            do {
                Start-Sleep -Milliseconds 400
                $svc.Refresh()
            } while ($svc.Status -ne "Running" -and (Get-Date) -lt $deadline)
            if ($svc.Status -eq "Running") {
                Write-Log $Log ("SERVICE START {0} OK" -f $Name) "OK"
            } else {
                Write-Log $Log ("SERVICE START {0} WARN (stato finale: {1})" -f $Name, $svc.Status) "WARN"
            }
        } else {
            Write-Log $Log ("SERVICE START SKIP {0} already Running" -f $Name) "SKIP"
        }
    } catch {
        Write-Log $Log ("SERVICE START WARN {0} ({1})" -f $Name, $_.Exception.Message) "WARN"
    }
}

function New-LogPath {
    param([string]$ModuleName, [string]$Action)
    Ensure-Dir $script:WOC_LOG_ROOT
    $ts = Get-Date -Format "yyyyMMdd_HHmmss"
    return Join-Path $script:WOC_LOG_ROOT ("{0}_{1}_{2}.log" -f $ModuleName, $Action, $ts)
}

function Write-Log {
    param([string]$Log, [string]$Msg, [string]$Level = "INFO")
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Msg
    Add-Content -Path $Log -Value $line -Encoding UTF8
    switch ($Level) {
        "OK"   { $script:WOC_OK_COUNT++;   Write-Host $line -ForegroundColor Green }
        "FAIL" { $script:WOC_FAIL_COUNT++; Write-Host $line -ForegroundColor Red }
        "WARN" { $script:WOC_WARN_COUNT++; Write-Host $line -ForegroundColor Yellow }
        "SKIP" { Write-Host $line -ForegroundColor DarkGray }
        default { Write-Host $line }
    }
}

function Assert-Admin {
    param([string]$Log)

    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
               ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if ($Log) { Write-Log $Log ("IsAdmin={0}" -f $isAdmin) }

    if (-not $isAdmin) {
        if ($Log) { Write-Log $Log "ERRORE: questo script richiede privilegi Administrator." "FAIL" }
        Write-Host ""
        Write-Host "ERRORE: questo script richiede privilegi Administrator." -ForegroundColor Red
        Write-Host "Suggerimento: avvia LAUNCHER.cmd (tasto destro -> Esegui come amministratore)." -ForegroundColor Yellow
        exit 1
    }
}

function Backup-RegValue {
    param([string]$BackupFile, [string]$KeyPath, [string]$ValueName)
    Ensure-Dir (Split-Path -Parent $BackupFile)
    $obj = [ordered]@{ Key=$KeyPath; Name=$ValueName; Exists=$false; Type=$null; Value=$null }
    try {
        $item = Get-ItemProperty -Path $KeyPath -ErrorAction Stop
        if ($null -ne $item.PSObject.Properties[$ValueName]) {
            $obj.Exists = $true
            $obj.Value  = $item.$ValueName
            $q = & reg.exe query $KeyPath /v $ValueName 2>$null
            if ($LASTEXITCODE -eq 0 -and $q) {
                $m = ($q | Select-String -Pattern ("^\s*{0}\s+(\S+)\s+(.+)$" -f [regex]::Escape($ValueName))).Matches
                if ($m.Count -gt 0) { $obj.Type = $m[0].Groups[1].Value }
            }
        }
    } catch { }
    ($obj | ConvertTo-Json -Depth 6 -Compress) | Add-Content -Path $BackupFile -Encoding UTF8
}

function Set-RegDword {
    param([string]$Log, [string]$KeyPath, [string]$Name, [int]$Value)

    try {
        if (-not (Test-Path -LiteralPath $KeyPath)) { New-Item -Path $KeyPath -Force | Out-Null }

        $curExists = $false
        $curVal = $null
        try {
            $item = Get-ItemProperty -Path $KeyPath -ErrorAction Stop
            if ($null -ne $item.PSObject.Properties[$Name]) {
                $curExists = $true
                $curVal = [int]$item.$Name
            }
        } catch { }

        if ($curExists -and $curVal -eq $Value) {
            Write-Log $Log ("REG SKIP {0}\{1} already = {2}" -f $KeyPath, $Name, $Value) "SKIP"
            return
        }

        if ($curExists) {
            Set-ItemProperty -Path $KeyPath -Name $Name -Type DWord -Value $Value -Force -ErrorAction Stop | Out-Null
        } else {
            New-ItemProperty -Path $KeyPath -Name $Name -PropertyType DWord -Value $Value -Force -ErrorAction Stop | Out-Null
        }
        Write-Log $Log ("REG SET  {0}\{1} = {2}" -f $KeyPath, $Name, $Value) "OK"
    } catch {
        Write-Log $Log ("REG SET  WARN {0}\{1} ({2})" -f $KeyPath, $Name, $_.Exception.Message) "WARN"
    }
}

function Set-RegString {
    param([string]$Log, [string]$KeyPath, [string]$Name, [string]$Value)
    try {
        if (-not (Test-Path -LiteralPath $KeyPath)) { New-Item -Path $KeyPath -Force | Out-Null }

        $curExists = $false
        $curVal = $null
        try {
            $item = Get-ItemProperty -Path $KeyPath -ErrorAction Stop
            if ($null -ne $item.PSObject.Properties[$Name]) {
                $curExists = $true
                $curVal = [string]$item.$Name
            }
        } catch { }

        if ($curExists -and $curVal -eq $Value) {
            Write-Log $Log ("REG SKIP {0}\{1} already = {2}" -f $KeyPath, $Name, $Value) "SKIP"
            return
        }

        if ($curExists) {
            Set-ItemProperty -Path $KeyPath -Name $Name -Value $Value -Force -ErrorAction Stop | Out-Null
        } else {
            New-ItemProperty -Path $KeyPath -Name $Name -PropertyType String -Value $Value -Force -ErrorAction Stop | Out-Null
        }
        Write-Log $Log ("REG SET  {0}\{1} = {2}" -f $KeyPath, $Name, $Value) "OK"
    } catch {
        Write-Log $Log ("REG SET  WARN {0}\{1} ({2})" -f $KeyPath, $Name, $_.Exception.Message) "WARN"
    }
}

function Remove-RegValue {
    param([string]$Log, [string]$KeyPath, [string]$Name)
    try {
        Remove-ItemProperty -Path $KeyPath -Name $Name -ErrorAction Stop
        Write-Log $Log ("REG DEL  {0}\{1}" -f $KeyPath, $Name) "OK"
    } catch {
        Write-Log $Log ("REG DEL  SKIP {0}\{1}" -f $KeyPath, $Name) "SKIP"
    }
}

function Restore-RegBackup {
    param([string]$Log, [string]$BackupFile)
    if (-not (Test-Path -LiteralPath $BackupFile)) {
        Write-Log $Log "Nessun backup registro trovato: $BackupFile" "WARN"
        return
    }
    Get-Content -LiteralPath $BackupFile -Encoding UTF8 | ForEach-Object {
        $line = $_.Trim()
        if ([string]::IsNullOrWhiteSpace($line)) { return }
        try {
            $o = $line | ConvertFrom-Json -ErrorAction Stop
            if ($o.Exists -eq $true) {
                if (-not (Test-Path $o.Key)) { New-Item -Path $o.Key -Force | Out-Null }
                if ($o.Type -eq "REG_DWORD" -or $o.Value -is [int]) {
                    Set-ItemProperty -Path $o.Key -Name $o.Name -Type DWord -Value ([int]$o.Value) -Force
                } else {
                    Set-ItemProperty -Path $o.Key -Name $o.Name -Value $o.Value -Force
                }
                Write-Log $Log ("REG RESTORE {0}\{1} = {2}" -f $o.Key, $o.Name, $o.Value) "OK"
            } else {
                Write-Log $Log ("REG RESTORE DEL {0}\{1} (non esisteva prima)" -f $o.Key, $o.Name) "OK"
                Remove-RegValue $Log $o.Key $o.Name
            }
        } catch {
            Write-Log $Log ("REG RESTORE FAIL: {0}" -f $_.Exception.Message) "WARN"
        }
    }
}

function Set-ServiceStart {
    param([string]$Log, [string]$Name, [ValidateSet("Automatic","Manual","Disabled")][string]$StartType)
    try {
        Set-Service -Name $Name -StartupType $StartType -ErrorAction Stop
        Write-Log $Log ("SERVICE  {0} => {1}" -f $Name, $StartType) "OK"
    } catch {
        Write-Log $Log ("SERVICE  SKIP {0} ({1})" -f $Name, $_.Exception.Message) "WARN"
    }
}

# v1.8: Stop-ServiceSafe senza -NoWait: attende effettivo arresto (max 15s)
function Stop-ServiceSafe {
    param([string]$Log, [string]$Name)
    try {
        $svc = Get-Service -Name $Name -ErrorAction Stop
        if ($svc.Status -eq "Running") {
            Stop-Service -Name $Name -Force -ErrorAction Stop
            # Attendi che il servizio si fermi davvero (max 15s)
            $deadline = (Get-Date).AddSeconds(15)
            do {
                Start-Sleep -Milliseconds 400
                $svc.Refresh()
            } while ($svc.Status -ne "Stopped" -and (Get-Date) -lt $deadline)

            if ($svc.Status -eq "Stopped") {
                Write-Log $Log ("SERVICE  STOP {0}" -f $Name) "OK"
            } else {
                Write-Log $Log ("SERVICE  STOP WARN {0} (non fermato dopo 15s, stato corrente: {1})" -f $Name, $svc.Status) "WARN"
            }
        } else {
            Write-Log $Log ("SERVICE  STOP SKIP {0} (gia' fermo: {1})" -f $Name, $svc.Status) "SKIP"
        }
    } catch {
        Write-Log $Log ("SERVICE  STOP SKIP {0} ({1})" -f $Name, $_.Exception.Message) "WARN"
    }
}

function Backup-ServiceStart {
    param([string]$BackupFile, [string[]]$ServiceNames)
    Ensure-Dir (Split-Path -Parent $BackupFile)
    Remove-Item -LiteralPath $BackupFile -ErrorAction SilentlyContinue
    foreach ($s in $ServiceNames) {
        try {
            $gs = Get-Service -Name $s -ErrorAction Stop
            "{0}|{1}" -f $gs.Name, $gs.StartType | Add-Content -Path $BackupFile -Encoding UTF8
        } catch { }
    }
}

function Restore-ServiceBackup {
    param([string]$Log, [string]$BackupFile)
    if (-not (Test-Path -LiteralPath $BackupFile)) {
        Write-Log $Log "Nessun backup servizi trovato: $BackupFile" "WARN"
        return
    }
    Get-Content -LiteralPath $BackupFile -Encoding UTF8 | ForEach-Object {
        $parts = $_ -split "\|", 2
        if ($parts.Count -eq 2 -and $parts[1] -in @("Automatic","Manual","Disabled")) {
            Set-ServiceStart $Log $parts[0] $parts[1]
        }
    }
}

function Disable-Task {
    param([string]$Log, [string]$TaskPath)
    try {
        # LastIndexOf usato al posto di Split-Path: i percorsi Task Scheduler
        # NON sono percorsi file system. Split-Path su "\TaskName" darebbe tp="\\"
        # causando errore "sintassi non corretta" su task root (es. OneDrive con SID).
        $last = $TaskPath.LastIndexOf("\")
        $tp   = if ($last -le 0) { "\" } else { $TaskPath.Substring(0, $last + 1) }
        $tn   = $TaskPath.Substring($last + 1)
        Disable-ScheduledTask -TaskPath $tp -TaskName $tn -ErrorAction Stop | Out-Null
        Write-Log $Log ("TASK     DISABLED {0}" -f $TaskPath) "OK"
    } catch {
        Write-Log $Log ("TASK     SKIP {0} ({1})" -f $TaskPath, $_.Exception.Message) "WARN"
    }
}

function Enable-Task {
    param([string]$Log, [string]$TaskPath)
    try {
        $last = $TaskPath.LastIndexOf("\")
        $tp   = if ($last -le 0) { "\" } else { $TaskPath.Substring(0, $last + 1) }
        $tn   = $TaskPath.Substring($last + 1)
        Enable-ScheduledTask -TaskPath $tp -TaskName $tn -ErrorAction Stop | Out-Null
        Write-Log $Log ("TASK     ENABLED {0}" -f $TaskPath) "OK"
    } catch {
        Write-Log $Log ("TASK     SKIP {0} ({1})" -f $TaskPath, $_.Exception.Message) "WARN"
    }
}

function Find-OneDriveTasks {
    <#
      Ritorna lista di task OneDrive in formato completo: \Path\TaskName
      Cerca in:
        \Microsoft\OneDrive\
        \Microsoft\Windows\OneDrive\
      e fallback: qualunque task con nome che inizia per OneDrive
    #>
    $results = New-Object System.Collections.Generic.List[string]
    $paths = @("\Microsoft\OneDrive\","\Microsoft\Windows\OneDrive\")
    foreach ($p in $paths) {
        try {
            $ts = Get-ScheduledTask -TaskPath $p -ErrorAction SilentlyContinue
            foreach ($t in $ts) {
                if ($t.TaskName -like "OneDrive*") { $results.Add($p + $t.TaskName) }
            }
        } catch { }
    }
    if ($results.Count -eq 0) {
        try {
            $all = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like "OneDrive*" }
            foreach ($t in $all) { $results.Add(($t.TaskPath) + ($t.TaskName)) }
        } catch { }
    }
    return @($results | Select-Object -Unique)
}

function Backup-TaskState {
    param([string]$BackupFile, [string[]]$TaskPaths)
    Ensure-Dir (Split-Path -Parent $BackupFile)
    Remove-Item -LiteralPath $BackupFile -ErrorAction SilentlyContinue
    foreach ($t in $TaskPaths) {
        try {
            $last = $t.LastIndexOf("\")
            $tp   = if ($last -le 0) { "\" } else { $t.Substring(0, $last + 1) }
            $tn   = $t.Substring($last + 1)
            $st = Get-ScheduledTask -TaskPath $tp -TaskName $tn -ErrorAction Stop
            "{0}|{1}" -f $t, $st.State | Add-Content -Path $BackupFile -Encoding UTF8
        } catch { }
    }
}

function Restore-TaskBackup {
    param([string]$Log, [string]$BackupFile)
    if (-not (Test-Path -LiteralPath $BackupFile)) {
        Write-Log $Log "Nessun backup task trovato: $BackupFile" "WARN"
        return
    }
    Get-Content -LiteralPath $BackupFile -Encoding UTF8 | ForEach-Object {
        $parts = $_ -split "\|", 2
        if ($parts.Count -eq 2) {
            if ($parts[1] -eq "Disabled") { Disable-Task $Log $parts[0] }
            else                          { Enable-Task  $Log $parts[0] }
        }
    }
}

function Remove-AppxSafe {
    param([string]$Log, [string]$Pattern, [switch]$Provisioned)
    try {
        $pkgs = Get-AppxPackage -AllUsers | Where-Object { $_.Name -like $Pattern -or $_.PackageFullName -like $Pattern }
        foreach ($p in $pkgs) {
            try {
                Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction Stop
                Write-Log $Log ("APPX     REMOVED {0}" -f $p.PackageFullName) "OK"
            } catch {
                Write-Log $Log ("APPX     SKIP {0} ({1})" -f $p.PackageFullName, $_.Exception.Message) "WARN"
            }
        }
    } catch {
        Write-Log $Log ("APPX     QUERY FAIL {0}" -f $Pattern) "WARN"
    }
    if ($Provisioned) {
        try {
            $prov = Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like $Pattern -or $_.PackageName -like $Pattern }
            foreach ($pp in $prov) {
                try {
                    Remove-AppxProvisionedPackage -Online -PackageName $pp.PackageName -ErrorAction Stop | Out-Null
                    Write-Log $Log ("PROV     REMOVED {0}" -f $pp.PackageName) "OK"
                } catch {
                    Write-Log $Log ("PROV     SKIP {0} ({1})" -f $pp.PackageName, $_.Exception.Message) "WARN"
                }
            }
        } catch {
            Write-Log $Log ("PROV     QUERY FAIL {0}" -f $Pattern) "WARN"
        }
    }
}

function Get-FolderSizeMB {
    param([string]$Path)
    try {
        if (-not (Test-Path -LiteralPath $Path -ErrorAction SilentlyContinue)) { return 0 }
        $sum = 0
        Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { -not $_.PSIsContainer } |
            ForEach-Object { $sum += $_.Length }
        return [math]::Round($sum / 1MB, 2)
    } catch { return 0 }
}

# FIX v1.3: Clean-Folder distingue file eliminati / bloccati / già liberi
function Clean-Folder {
    param([string]$Log, [string]$Path, [string]$Label = "")
    $lbl = if ($Label) { $Label } else { $Path }
    if (-not (Test-Path -LiteralPath $Path -ErrorAction SilentlyContinue)) {
        Write-Log $Log ("CLEAN    SKIP (non trovata) {0}" -f $lbl) "SKIP"
        return 0
    }
    $before  = Get-FolderSizeMB $Path
    $deleted = 0
    $locked  = 0
    try {
        Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop
                $deleted++
            } catch {
                $locked++
            }
        }
    } catch { }
    $after = Get-FolderSizeMB $Path
    $freed = [math]::Round([math]::Max(0, $before - $after), 2)

    if ($locked -gt 0) {
        Write-Log $Log ("CLEAN    {0}  prima={1}MB  liberati={2}MB  eliminati={3}  bloccati(in uso)={4}" -f $lbl, $before, $freed, $deleted, $locked) "WARN"
    } else {
        Write-Log $Log ("CLEAN    {0}  prima={1}MB  liberati={2}MB  eliminati={3}" -f $lbl, $before, $freed, $deleted) "OK"
    }
    return $freed
}

$script:WOC_STATE_ROOT = "C:\WinOpt\State"

function Get-WocLevel {
    $f = Join-Path $script:WOC_STATE_ROOT "current_level.txt"
    if (Test-Path -LiteralPath $f) {
        return (Get-Content -LiteralPath $f -Raw -Encoding UTF8).Trim()
    }
    return "NONE"
}

function Set-WocLevel {
    param([string]$Level)
    Ensure-Dir $script:WOC_STATE_ROOT
    $Level | Set-Content -Path (Join-Path $script:WOC_STATE_ROOT "current_level.txt") -Encoding UTF8 -NoNewline
}

function Clear-WocLevel {
    $f = Join-Path $script:WOC_STATE_ROOT "current_level.txt"
    Remove-Item -LiteralPath $f -ErrorAction SilentlyContinue
}

function Save-WocModuleState {
    param([string]$Module, [hashtable]$Info = @{})
    Ensure-Dir $script:WOC_STATE_ROOT
    $state = [ordered]@{
        Module      = $Module
        AppliedAt   = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        MachineName = $env:COMPUTERNAME
        UserName    = $env:USERNAME
    }
    foreach ($k in $Info.Keys) { $state[$k] = $Info[$k] }
    $state | ConvertTo-Json -Depth 10 |
        Set-Content -Path (Join-Path $script:WOC_STATE_ROOT "$Module.json") -Encoding UTF8
}

function Clear-WocModuleState {
    param([string]$Module)
    Remove-Item -LiteralPath (Join-Path $script:WOC_STATE_ROOT "$Module.json") -ErrorAction SilentlyContinue
}

function Get-WingetPath {
    $wg = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($wg) { return $wg.Source }
    return $null
}

function Invoke-Winget {
    param([string]$Log, [string]$Arguments, [int]$TimeoutMs = 600000)
    Write-Log $Log ("WINGET   {0}" -f $Arguments)
    $tmpOut = [System.IO.Path]::GetTempFileName()
    $tmpErr = [System.IO.Path]::GetTempFileName()
    try {
        $p = Start-Process -FilePath "winget.exe" `
                           -ArgumentList $Arguments `
                           -NoNewWindow -PassThru `
                           -RedirectStandardOutput $tmpOut `
                           -RedirectStandardError  $tmpErr
        if (-not $p.WaitForExit($TimeoutMs)) {
            try { $p.Kill() } catch { }
            Write-Log $Log ("WINGET   TIMEOUT dopo {0} min" -f [math]::Round($TimeoutMs/60000,1)) "WARN"
            return 1460
        }
        $p.WaitForExit()
        $ec  = $p.ExitCode
        if ($null -eq $ec) { $ec = 0 }
        $out = (Get-Content -LiteralPath $tmpOut -Raw -Encoding UTF8 -ErrorAction SilentlyContinue) + ""
        $err = (Get-Content -LiteralPath $tmpErr -Raw -Encoding UTF8 -ErrorAction SilentlyContinue) + ""
        $filterSpinner = { ($_ -split "`r?`n" | Where-Object { $_ -notmatch '^\s*[-\|/\s]+$' -and $_.Trim() }) -join "`n" }
        $cleanOut = & $filterSpinner $out
        $cleanErr = & $filterSpinner $err
        if ($cleanOut.Trim()) { Write-Log $Log $cleanOut.Trim() }
        if ($cleanErr.Trim()) { Write-Log $Log $cleanErr.Trim() "WARN" }
        return $ec
    } finally {
        Remove-Item -LiteralPath $tmpOut -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tmpErr -ErrorAction SilentlyContinue
    }
}

function Test-WingetInstalled {
    param([string]$Id)
    $tmpOut = [System.IO.Path]::GetTempFileName()
    $tmpErr = [System.IO.Path]::GetTempFileName()
    try {
        $p = Start-Process -FilePath "winget.exe" `
                           -ArgumentList "list --id $Id -e --accept-source-agreements" `
                           -NoNewWindow -PassThru `
                           -RedirectStandardOutput $tmpOut `
                           -RedirectStandardError  $tmpErr
        if (-not $p.WaitForExit(30000)) {
            try { $p.Kill() } catch { }
            return $false
        }
        $p.WaitForExit()
        $out = (Get-Content -LiteralPath $tmpOut -Raw -Encoding UTF8 -ErrorAction SilentlyContinue) + ""
        if ($out -match "Nessun pacchetto installato trovato" -or
            $out -match "No installed package found") { return $false }
        return ($out -imatch [regex]::Escape($Id))
    } catch {
        return $false
    } finally {
        Remove-Item -LiteralPath $tmpOut -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tmpErr -ErrorAction SilentlyContinue
    }
}

function Write-WinOptFooter {
    param(
        [string]$Log,
        [string]$ModuleName,
        [string]$Action
    )
    try {
        $warn = [int]$script:WOC_WARN_COUNT
        $fail = [int]$script:WOC_FAIL_COUNT
        $ok   = [int]$script:WOC_OK_COUNT
        $status = if ($fail -gt 0) { "FAIL" } elseif ($warn -gt 0) { "WARN" } else { "OK" }
        $msg = "SUMMARY {0} {1}: Status={2} OK={3} WARN={4} FAIL={5} Log={6}" -f $ModuleName, $Action, $status, $ok, $warn, $fail, $Log
        Write-Log $Log $msg $status
        Write-Host ""
        Write-Host $msg -ForegroundColor Cyan
        Write-Host ""
    } catch { }
}

function Pause-WinOptIfInteractive {
    <#
      Keeps the PowerShell window open only when launched outside the launcher.
      - Launcher sets env WINOPT_FROM_LAUNCHER=1 E scrive un flag file in WOC_STATE_ROOT.
        Il flag file sopravvive all'elevazione UAC (il processo elevato non eredita l'env
        of CMD parent, but can read the file from disk).
      - Double-click / manual run => pauses to allow reading output.
      - Can be forced off with $env:WINOPT_NO_PAUSE=1
    #>
    try {
        if ($env:WINOPT_NO_PAUSE -eq '1') { return }
        if ($env:WINOPT_FROM_LAUNCHER -eq '1') { return }
        # FIX v1.8: controlla anche il flag file (UAC-safe)
        $flagFile = Join-Path $script:WOC_STATE_ROOT "launcher.flag"
        if (Test-Path -LiteralPath $flagFile -ErrorAction SilentlyContinue) { return }
        # Pause only for interactive console host (avoid scheduled tasks / non-interactive)
        if ($Host -and $Host.Name -eq 'ConsoleHost') {
            Write-Host ''
            Write-Host 'Premi INVIO per chiudere...' -ForegroundColor Yellow
            [void](Read-Host)
        }
    } catch { }
}