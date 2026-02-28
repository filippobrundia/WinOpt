#Requires -Version 5.1
<#  WIN_OPT_CLAUDE - 02_UIUX - AUDIT (utente corrente, no admin)
    v1.3 - TaskbarDa aggiunto con atteso=0
#>

. "$PSScriptRoot\..\_COMMON\Common.ps1"

$MOD = "02_UIUX"
$Log = New-LogPath $MOD "AUDIT"
$ACT       = "AUDIT"
if (Get-Command Reset-WinOptLogCounters -ErrorAction SilentlyContinue) { Reset-WinOptLogCounters }
Write-Log $Log "=== UIUX AUDIT START ===" "INFO"

$checks = @(
    @{P="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; N="TaskbarAl";             E=1; D="Taskbar align (1=centro)"},
    @{P="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; N="SearchboxTaskbarMode";  E=1; D="Search taskbar (1=icona)"},
    @{P="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; N="TaskbarDa";             E=0; D="Widget taskbar (0=off)"},
    @{P="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; N="HideFileExt";           E=0; D="Nascondi estensioni (0=mostra)"},
    @{P="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; N="TaskbarMn";             E=0; D="Teams Chat (0=off)"},
    @{P="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; N="Start_TrackDocs";       E=0; D="Track docs (0=off)"},
    @{P="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; N="SystemPaneSuggestionsEnabled";         E=0; D="Suggerimenti Start"},
    @{P="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; N="SilentInstalledAppsEnabled";           E=0; D="App installazione silenziosa"},
    @{P="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; N="SubscribedContent-310093Enabled";      E=0; D="Consigli Impostazioni"},
    @{P="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; N="RotatingLockScreenEnabled";            E=0; D="Spotlight lock screen"},
    @{P="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; N="SubscribedContent-338387Enabled";      E=0; D="Spotlight lock screen sub"},
    @{P="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; N="SubscribedContent-338389Enabled";      E=0; D="Spotlight taskbar info"},
    @{P="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; N="SubscribedContent-353698Enabled";      E=0; D="Timeline suggestions"},
    @{P="HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications"; N="GlobalUserDisabled"; E=1; D="App sfondo (1=off)"},
    @{P="HKCU:\System\GameConfigStore";                                               N="GameDVR_Enabled";     E=0; D="GameDVR (0=off)"},
    @{P="HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR";                    N="AppCaptureEnabled";   E=0; D="App capture (0=off)"},
    @{P="HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo";            N="Enabled";             E=0; D="Advertising ID HKCU (0=off)"},
    @{P="HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy";                    N="TailoredExperiencesWithDiagnosticDataEnabled"; E=0; D="Tailored Experiences HKCU"},
    @{P="HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize";         N="AppsUseLightTheme";   E=0; D="App dark mode (0=dark)"},
    @{P="HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize";         N="SystemUsesLightTheme";E=0; D="Sistema dark mode (0=dark)"}
)

foreach ($c in $checks) {
    try {
        $v  = (Get-ItemProperty -Path $c.P -ErrorAction Stop).($c.N)
        $ok = if ($v -eq $c.E) { "OK" } else { "WARN" }
        Write-Log $Log ("{0,-45} = {1,-5}  [atteso={2}] {3}" -f $c.N, $v, $c.E, $c.D) $ok
    } catch {
        Write-Log $Log ("{0,-45}   MANCANTE  [atteso={1}] {2}" -f $c.N, $c.E, $c.D) "SKIP"
    }
}

Write-Log $Log "=== UIUX AUDIT END ===" "INFO"
Write-Host ""
Write-Host "  Log salvato: $Log" -ForegroundColor Cyan
Write-Host ""
if (Get-Command Write-WinOptFooter -ErrorAction SilentlyContinue) { Write-WinOptFooter $Log $MOD $ACT }
if (Get-Command Pause-WinOptIfInteractive -ErrorAction SilentlyContinue) { Pause-WinOptIfInteractive }
