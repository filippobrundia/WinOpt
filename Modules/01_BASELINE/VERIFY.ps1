#Requires -Version 5.1
<#  WIN_OPT_CLAUDE - 01_BASELINE - AUDIT  v1.5 #>

. "$PSScriptRoot\..\_COMMON\Common.ps1"

$MOD = "01_BASELINE"
$Log = New-LogPath $MOD "AUDIT"
$ACT       = "AUDIT"
if (Get-Command Reset-WinOptLogCounters -ErrorAction SilentlyContinue) { Reset-WinOptLogCounters }
Write-Log $Log "=== BASELINE AUDIT START ===" "INFO"

# ── SERVIZI ──────────────────────────────────────────────────────────────────
$svcExpected = @{
    "DiagTrack"="Disabled"; "dmwappushservice"="Disabled"; "WerSvc"="Disabled"
    "XblAuthManager"="Disabled"; "XblGameSave"="Disabled"; "XboxGipSvc"="Disabled"; "XboxNetApiSvc"="Disabled"
    "MapsBroker"="Manual"; "RemoteRegistry"="Manual"; "SysMain"="Automatic"
}
foreach ($s in $svcExpected.Keys) {
    try {
        $sv = Get-Service -Name $s -ErrorAction Stop
        $expST = $svcExpected[$s]
        $okST  = $sv.StartType -eq $expST
        # Per Disabled, vogliamo anche Status=Stopped
        $okSts = if ($expST -eq "Disabled") { $sv.Status -eq "Stopped" } else { $true }
        $level = if ($okST -and $okSts) { "OK" } else { "WARN" }
        Write-Log $Log ("SVC   {0,-22} Status={1,-10} StartType={2,-12} [atteso={3}]" -f $sv.Name,$sv.Status,$sv.StartType,$expST) $level
    } catch { Write-Log $Log ("SVC   {0,-22} NON TROVATO" -f $s) "SKIP" }
}

# ── TASK ─────────────────────────────────────────────────────────────────────
$tasks = @(
    "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser",
    "\Microsoft\Windows\Application Experience\ProgramDataUpdater",
    "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator",
    "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip",
    "\Microsoft\Windows\Customer Experience Improvement Program\KernelCeipTask",
    "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector",
    "\Microsoft\Windows\Windows Error Reporting\QueueReporting"
)
foreach ($t in $tasks) {
    try {
        $tp = (Split-Path $t -Parent) + "\"; $tn = Split-Path $t -Leaf
        $st = Get-ScheduledTask -TaskPath $tp -TaskName $tn -ErrorAction Stop
        $ok = if ($st.State -eq "Disabled") { "OK" } else { "WARN" }
        Write-Log $Log ("TASK  {0,-60} State={1}" -f $t,$st.State) $ok
    } catch { Write-Log $Log ("TASK  {0,-60} NON TROVATO" -f $t) "SKIP" }
}

# ── REGISTRO ─────────────────────────────────────────────────────────────────
$regs = @(
    @{P="HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection";          N="AllowTelemetry";                              E=0; D="Telemetria"},
    @{P="HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection";          N="AllowDeviceNameInTelemetry";                  E=0; D="Nome device in telemetria"},
    @{P="HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection"; N="AllowTelemetry";                        E=0; D="Telemetria (path2)"},
    @{P="HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting"; N="Disabled";                                    E=1; D="WER"},
    @{P="HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows";               N="CEIPEnable";                                  E=0; D="CEIP"},
    @{P="HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent";            N="DisableWindowsConsumerFeatures";              E=1; D="Consumer features Start"},
    @{P="HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent";            N="DisableWindowsSpotlightFeatures";             E=1; D="Spotlight"},
    @{P="HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent";            N="DisableLockScreenAppNotifications";           E=1; D="Lock screen notifiche"},
    @{P="HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent";            N="DisableTailoredExperiencesWithDiagnosticData"; E=1; D="Tailored Experiences"},
    @{P="HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo";         N="DisabledByGroupPolicy";                       E=1; D="Advertising ID"},
    @{P="HKLM:\SOFTWARE\Policies\Microsoft\Dsh";                             N="AllowNewsAndInterests";                       E=0; D="Widget taskbar"},
    @{P="HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search";          N="DisableWebSearch";                            E=1; D="Bing Start (web)"},
    @{P="HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search";          N="ConnectedSearchUseWeb";                       E=0; D="Bing Start (connected)"},
    @{P="HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search";          N="BingSearchEnabled";                           E=0; D="Bing ricerca"},
    @{P="HKLM:\SOFTWARE\Policies\Microsoft\InputPersonalization";            N="AllowInputPersonalization";                   E=0; D="Input personalization"},
    @{P="HKLM:\SOFTWARE\Policies\Microsoft\InputPersonalization";            N="RestrictImplicitInkCollection";               E=1; D="Ink collection"},
    @{P="HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot";          N="TurnOffWindowsCopilot";                       E=1; D="Copilot"},
    @{P="HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI";              N="DisableAIDataAnalysis";                       E=1; D="Recall AI data analysis"},
    @{P="HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI";              N="AllowRecallEnablement";                       E=0; D="Recall enablement"},
    @{P="HKLM:\SOFTWARE\Policies\Microsoft\Windows\System";                 N="EnableActivityFeed";                          E=0; D="Activity History feed"},
    @{P="HKLM:\SOFTWARE\Policies\Microsoft\Windows\System";                 N="PublishUserActivities";                       E=0; D="Activity History publish"},
    @{P="HKLM:\SOFTWARE\Policies\Microsoft\Windows\System";                 N="UploadUserActivities";                        E=0; D="Activity History upload"},
    @{P="HKLM:\SOFTWARE\Policies\Microsoft\FindMyDevice";                    N="AllowFindMyDevice";                           E=0; D="Find My Device"},
    @{P="HKLM:\SOFTWARE\Policies\Microsoft\Windows\System";                  N="AllowCrossDeviceClipboard";                   E=0; D="Cross-device clipboard"},
    @{P="HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync";             N="DisableSettingSync";                          E=2; D="Settings Sync cloud"},
    @{P="HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors";      N="DisableLocationScripting";                    E=1; D="Location scripting"},
    @{P="HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization";         N="NoLockScreenCamera";                          E=1; D="Lock screen camera"}
)
foreach ($r in $regs) {
    try {
        $v  = (Get-ItemProperty -Path $r.P -ErrorAction Stop).($r.N)
        $ok = if ($v -eq $r.E) { "OK" } else { "WARN" }
        Write-Log $Log ("REG   {0,-50} = {1,-5}  [atteso={2}] {3}" -f $r.N,$v,$r.E,$r.D) $ok
    } catch {
        Write-Log $Log ("REG   {0,-50}   MANCANTE  [atteso={1}] {2}" -f $r.N,$r.E,$r.D) "SKIP"
    }
}

Write-Log $Log "=== BASELINE AUDIT END ===" "INFO"
Write-Host ""; Write-Host "  Log salvato: $Log" -ForegroundColor Cyan
if (Get-Command Write-WinOptFooter -ErrorAction SilentlyContinue) { Write-WinOptFooter $Log $MOD $ACT }
if (Get-Command Pause-WinOptIfInteractive -ErrorAction SilentlyContinue) { Pause-WinOptIfInteractive }
