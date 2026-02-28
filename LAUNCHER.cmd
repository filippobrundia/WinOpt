@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul

rem ==================================================
rem  Self-relaunch guard
rem  Usa variabile con delayed expansion per gestire
rem  spazi, parentesi e altri caratteri speciali nel
rem  percorso (es. "Cartella (1)", "Downloads", ecc.)
rem ==================================================
set "SELF=%~f0"
echo "!CMDCMDLINE!" | findstr /i /c:"!SELF!" >nul 2>&1
if errorlevel 1 goto :DO_RELAUNCH
echo "!CMDCMDLINE!" | findstr /i /c:"/c " >nul 2>&1
if not errorlevel 1 goto :DO_RELAUNCH
goto :MAIN

:DO_RELAUNCH
cmd /k ""!SELF!" _LAUNCHED"
exit

rem ==================================================
:MAIN
rem ==================================================
set "ROOT=%~dp0"
set "STATE=C:\WinOpt\State"
set "LOGS=C:\WinOpt\Logs"

if not exist "%STATE%" mkdir "%STATE%" >nul 2>&1
if not exist "%LOGS%"  mkdir "%LOGS%"  >nul 2>&1

rem ==================================================
rem  Single UAC: elevazione UNA SOLA VOLTA
rem ==================================================
net session >nul 2>&1
if errorlevel 1 (
echo.
echo [UAC] Richiesti privilegi amministrativi. Elevazione...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Start-Process -FilePath $env:ComSpec -ArgumentList @('/k', '""%~f0"" _LAUNCHED') -Verb RunAs"
exit
)


:MENU
cls
echo ==================================================
echo                 WINOPT 2.5.7
echo ==================================================
echo.
echo  1) QUICK STABLE (BASELINE + EDGE + UIUX + VERIFY)
echo.
echo  2) BASELINE APPLY                 (Admin)
echo  3) EDGE APPLY                     (Admin)
echo  4) UIUX APPLY (Prestazioni)       (User)
echo  5) VERIFY                         (Admin)
echo  6) VERIFY DEEP                    (Admin  + Clean Audit)
echo.
echo  7) ULTRA ADDON                    (Admin)
echo  8) ONEDRIVE CONTROL               (Admin submenu)
echo  9) APPS INSTALL                   (Admin)
echo 10) CLEAN SAFE                     (Admin)
echo 11) CLEAN DEEP                     (Admin)
echo.
echo 12) STARTUP CLEAN                  (Admin)
echo.
echo  --- LAB (SPERIMENTALE) ---
echo 13) LAB POWER BOOST                (Admin)
echo.

echo  0) Esci
echo.
set /p "CHOICE=Seleziona: "

if "!CHOICE!"==""   goto :MENU
if "!CHOICE!"=="0"  goto :EXIT_OK
if "!CHOICE!"=="1"  goto :DO_1
if "!CHOICE!"=="2"  goto :DO_2
if "!CHOICE!"=="3"  goto :DO_3
if "!CHOICE!"=="4"  goto :DO_4
if "!CHOICE!"=="5"  goto :DO_5
if "!CHOICE!"=="6"  goto :DO_6
if "!CHOICE!"=="7"  goto :DO_7
if "!CHOICE!"=="8"  goto :DO_8
if "!CHOICE!"=="9"  goto :DO_9
if "!CHOICE!"=="10" goto :DO_10
if "!CHOICE!"=="11" goto :DO_11
if "!CHOICE!"=="12" goto :DO_12
if "!CHOICE!"=="13" goto :DO_13
echo.
echo  [WARN] Scelta non valida: !CHOICE!
timeout /t 2 >nul
goto :MENU

:DO_1
call :QUICK_STABLE
goto :POST
:DO_2
call :RUNADMIN "%ROOT%Modules\01_BASELINE\APPLY.ps1"
goto :POST
:DO_3
call :RUNADMIN "%ROOT%Modules\03_EDGE\APPLY.ps1"
goto :POST

:DO_4
call :RUNUSER "%ROOT%Modules\02_UIUX\APPLY.ps1"
goto :POST
:DO_5
call :RUNADMIN "%ROOT%Modules\04_VERIFY\VERIFY.ps1"
goto :POST
:DO_6
call :VERIFY_DEEP
goto :POST
:DO_7
call :RUNADMIN "%ROOT%Modules\10_ULTRA_ADDON\APPLY.ps1"
goto :POST
:DO_8
call :ONEDRIVE_MENU
goto :POST
:DO_9
call :RUNADMIN "%ROOT%Modules\30_APPS\APPLY.ps1"
goto :POST
:DO_10
call :RUNADMIN "%ROOT%Modules\40_CLEAN\SAFE.ps1"
goto :POST
:DO_11
call :RUNADMIN "%ROOT%Modules\40_CLEAN\DEEP.ps1"
goto :POST
:DO_12
call :RUNADMIN "%ROOT%Modules\50_STARTUP\CLEAN.ps1"
goto :POST
:DO_13
call :RUNADMIN "%ROOT%Modules\90_LAB\01_POWER_BOOST.ps1"
goto :POST

rem ==================================================
:EXIT_OK
echo.
echo Arrivederci.
timeout /t 2 >nul
exit /b 0

rem ==================================================
:QUICK_STABLE
echo.
echo [QUICK STABLE] Avvio sequenza: BASELINE - EDGE - UIUX - VERIFY
echo.
echo.
echo Questa sequenza gira in un'unica sessione elevata (UAC singolo).
echo I codici di uscita ora riflettono l'esito reale di ogni modulo.
echo Log: %LOGS%
echo.

set "QS_BASELINE=LANCIATO"
set "QS_EDGE=LANCIATO"
set "QS_UIUX=LANCIATO"
set "QS_VERIFY=LANCIATO"

call :RUNADMIN "%ROOT%Modules\01_BASELINE\APPLY.ps1"
if errorlevel 1 (set "QS_BASELINE=WARN (exitcode^>0)") else (set "QS_BASELINE=OK")

call :RUNADMIN "%ROOT%Modules\03_EDGE\APPLY.ps1"
if errorlevel 1 (set "QS_EDGE=WARN (exitcode^>0)") else (set "QS_EDGE=OK")

call :RUNUSER  "%ROOT%Modules\02_UIUX\APPLY.ps1"
if errorlevel 1 (set "QS_UIUX=WARN (exitcode^>0)") else (set "QS_UIUX=OK")

call :RUNADMIN "%ROOT%Modules\04_VERIFY\VERIFY.ps1"
if errorlevel 1 (set "QS_VERIFY=WARN (exitcode^>0)") else (set "QS_VERIFY=OK")

echo.
echo ==================================================
echo  QUICK STABLE -- SUMMARY
echo ==================================================
echo  BASELINE  : !QS_BASELINE!
echo  EDGE      : !QS_EDGE!
echo  UIUX      : !QS_UIUX!
echo  VERIFY    : !QS_VERIFY!
echo ==================================================
echo  Exitcode = esito reale dello script.
echo  Dettagli completi nei log: %LOGS%
echo ==================================================
echo.
echo  Riavvia Windows per attivare le policy Edge.
echo.
echo ==================================================
echo.
pause
exit /b 0

:QUICK_FAIL
echo.
echo [ERRORE] QUICK STABLE interrotto. Log in: %LOGS%
del /f /q "%STATE%\launcher.flag" >nul 2>&1
exit /b 1

rem ==================================================
:VERIFY_DEEP
set "EC_AGG=0"
call :RUNADMIN "%ROOT%Modules\04_VERIFY\VERIFY.ps1"
if errorlevel 1 set "EC_AGG=1"
call :RUNADMIN "%ROOT%Modules\40_CLEAN\VERIFY.ps1"
if errorlevel 1 set "EC_AGG=1"
exit /b !EC_AGG!

rem ==================================================
:ONEDRIVE_MENU
cls
echo ==================================================
echo                 ONEDRIVE CONTROL
echo ==================================================
echo.
echo  1) OneDrive ON    (riabilita)
echo  2) OneDrive OFF   (disabilita)
echo  3) OneDrive STATUS
echo  0) Indietro
echo.
set /p "ODC=Seleziona: "
if "!ODC!"==""  goto :ONEDRIVE_MENU
if "!ODC!"=="0" exit /b 0
if "!ODC!"=="1" goto :OD_ON
if "!ODC!"=="2" goto :OD_OFF
if "!ODC!"=="3" goto :OD_VERIFY
echo.
echo  [WARN] Opzione non valida. Usa 0 per tornare al menu principale.
timeout /t 2 >nul
goto :ONEDRIVE_MENU

:OD_ON
call :RUNADMIN "%ROOT%Modules\20_ONEDRIVE\APPLY_ON.ps1"
exit /b !ERRORLEVEL!

:OD_OFF
call :RUNADMIN "%ROOT%Modules\20_ONEDRIVE\APPLY_OFF.ps1"
exit /b !ERRORLEVEL!

:OD_VERIFY
call :RUNADMIN "%ROOT%Modules\20_ONEDRIVE\VERIFY.ps1"
exit /b !ERRORLEVEL!

rem ==================================================
:POST
echo.
set "LAST_STATUS=?"
set "LAST_STEP=?"
set "LAST_EC=?"
if exist "%STATE%\last_status.txt"   set /p LAST_STATUS=<"%STATE%\last_status.txt"
if exist "%STATE%\last_step.txt"     set /p LAST_STEP=<"%STATE%\last_step.txt"
if exist "%STATE%\last_exitcode.txt" set /p LAST_EC=<"%STATE%\last_exitcode.txt"
del /f /q "%STATE%\launcher.flag" >nul 2>&1
echo ==================================================
echo RISULTATO: !LAST_STATUS!   ExitCode=!LAST_EC!
echo STEP:      !LAST_STEP!
echo Logs:      %LOGS%
echo ==================================================
echo.
rem -- avviso riavvio solo per moduli che lo richiedono --
echo !LAST_STEP! | findstr /I "01_BASELINE 10_ULTRA 90_LAB 01_POWER_BOOST" >nul 2>&1
if not errorlevel 1 (
    echo.
    echo  ** RIAVVIO CONSIGLIATO **
    echo  Alcune modifiche (pagefile, 8.3 names, Multimedia Profile)
    echo  diventano attive solo dopo il riavvio del sistema.
    echo.
)
echo  [L] Apri Logs    [M] Menu    [Q] Esci
echo.
set /p "AFTER=> "
if /I "!AFTER!"=="L" start "" "%LOGS%"
if /I "!AFTER!"=="Q" goto :EXIT_OK
goto :MENU

rem ==================================================
rem ==================================================
:RUNUSER
call :RUNSCRIPT USER "%~1"
exit /b !ERRORLEVEL!

rem ==================================================
:RUNADMIN
call :RUNSCRIPT ADMIN "%~1"
exit /b !ERRORLEVEL!

rem ==================================================
:RUNSCRIPT
rem Usage: call :RUNSCRIPT (ADMIN|USER) "C:\path\script.ps1"
set "MODE=%~1"
set "SCRIPT=%~2"

if not exist "!SCRIPT!" goto :RUNSCRIPT_ERR

rem -- calcola percorso relativo per output più pulito --
set "REL=!SCRIPT:%ROOT%=!"
if "!REL:~0,1!"=="\" set "REL=!REL:~1!"
rem -- estrai nome modulo breve (es. 01_BASELINE) da Modules\NomeModulo\Script.ps1 --
set "MOD_SHORT=!REL!"
set "MOD_SHORT=!MOD_SHORT:Modules\=!"
for /f "delims=\" %%A in ("!MOD_SHORT!") do set "MOD_SHORT=%%A"

if /I "!MODE!"=="ADMIN" (
    net session >nul 2>&1
    if errorlevel 1 (
        echo.
        echo [ERRORE] Questo modulo richiede privilegi amministrativi.
        echo         Avvia LAUNCHER.cmd come amministratore.
        >"!STATE!\last_status.txt"   echo FAIL
        >"!STATE!\last_step.txt"     echo !MOD_SHORT!
        >"!STATE!\last_exitcode.txt" echo 1
        exit /b 1
    )
)

echo.
echo [!MODE!] Avvio: !REL!
echo 1>"!STATE!\launcher.flag" 2>nul

powershell -NoProfile -ExecutionPolicy Bypass -File "!SCRIPT!"
set "EC=!ERRORLEVEL!"

del /f /q "!STATE!\launcher.flag" >nul 2>&1

set "LAST_STATUS=FAIL"
if "!EC!"=="0" set "LAST_STATUS=OK"
>"!STATE!\last_status.txt"   echo !LAST_STATUS!
>"!STATE!\last_step.txt"     echo !MOD_SHORT!
>"!STATE!\last_exitcode.txt" echo !EC!

exit /b !EC!

:RUNSCRIPT_ERR
set "REL=!SCRIPT:%ROOT%=!"
if "!REL:~0,1!"=="\" set "REL=!REL:~1!"
set "MOD_SHORT=!REL!"
set "MOD_SHORT=!MOD_SHORT:Modules\=!"
for /f "delims=\" %%A in ("!MOD_SHORT!") do set "MOD_SHORT=%%A"
echo [ERRORE] Script non trovato: !REL!
>"!STATE!\last_status.txt"   echo FAIL
>"!STATE!\last_step.txt"     echo !MOD_SHORT!
>"!STATE!\last_exitcode.txt" echo 1
exit /b 1