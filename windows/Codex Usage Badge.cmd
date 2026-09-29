@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "BADGE_MANAGER=%~dp0manage-windows.ps1"
set "BADGE_LOG=%~dp0Codex Usage Badge.log"
if not exist "%BADGE_MANAGER%" (
  call :Log "package incomplete"
  echo This package is incomplete. Extract the ZIP completely and try again.
  pause
  exit /b 1
)
call :Log "event=menu-opened"

:Menu
cls
echo ========================================
echo          Codex Usage Badge
echo ========================================
echo.
echo  1. Install or update
echo  2. Restart Codex with Badge
echo  3. Check status
echo  4. Uninstall
echo  5. Exit
echo.
set "BADGE_MENU="
set /p "BADGE_MENU=Choose an option [1-5]: "
if "%BADGE_MENU%"=="1" goto Install
if "%BADGE_MENU%"=="2" goto Restart
if "%BADGE_MENU%"=="3" goto Status
if "%BADGE_MENU%"=="4" goto Uninstall
if "%BADGE_MENU%"=="5" (
  call :Log "event=menu-exited"
  exit /b 0
)
call :Log "event=menu-selection result=invalid"
echo Invalid option. Choose a number from 1 to 5.
pause
goto Menu

:Install
call :RunAction Install
if errorlevel 1 goto Menu
echo.
echo Save your Codex work before restarting.
:RestartPrompt
set "BADGE_RESTART="
set /p "BADGE_RESTART=Type C to continue or N to return to the menu: "
if /I "%BADGE_RESTART%"=="C" (
  call :Log "event=restart-confirmation result=continue"
  goto Restart
)
if /I "%BADGE_RESTART%"=="N" (
  call :Log "event=restart-confirmation result=cancel"
  goto Menu
)
call :Log "event=restart-confirmation result=invalid"
echo Please type C or N.
goto RestartPrompt

:Restart
call :RunAction Launch
pause
goto Menu

:Status
call :RunAction Status
pause
goto Menu

:Uninstall
call :RunAction Uninstall
pause
goto Menu

:RunAction
call :Log "event=action-start action=%~1"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%BADGE_MANAGER%" -Action %~1
set "BADGE_EXIT=%ERRORLEVEL%"
if "%BADGE_EXIT%"=="0" (call :Log "event=action-finish action=%~1 result=success") else (call :Log "event=action-finish action=%~1 result=failed exitCode=%BADGE_EXIT%")
exit /b %BADGE_EXIT%

:Log
>> "%BADGE_LOG%" echo [%date% %time%] %~1
exit /b 0
