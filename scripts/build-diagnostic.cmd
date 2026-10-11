@echo off
setlocal
rem Compile only the original diagnostic service. No image or device writes.
rem Usage: build-diagnostic.cmd C:\QNX\SDP805 [C:\QNXCONFIG]
if "%~1"=="" (
  echo Usage: build-diagnostic.cmd SDK_DIRECTORY [CONFIG_DIRECTORY]
  exit /b 2
)
set "SDK=%~f1"
set "PROJECT=%~dp0.."
if not exist "%SDK%\qnxsdp-env.bat" exit /b 2
call "%SDK%\qnxsdp-env.bat"
if errorlevel 1 exit /b 1
@echo off
if not "%~2"=="" (
  set "QNX_CONFIGURATION=%~f2"
  set "QNX_CONFIGURATION_EXCLUSIVE=%~f2"
)
if not exist "%PROJECT%\output" mkdir "%PROJECT%\output"
if not exist "%PROJECT%\build\tmp" mkdir "%PROJECT%\build\tmp"
set "TEMP=%PROJECT%\build\tmp"
set "TMP=%TEMP%"
set "TMPDIR=%TEMP%"
qcc -Vgcc_ntox86_64 -std=c11 -D_QNX_SOURCE -Wall -Wextra -Werror -O2 -o "%PROJECT%\output\m6-diag" "%PROJECT%\src\diagnostic-server.c" -lsocket
exit /b %ERRORLEVEL%
