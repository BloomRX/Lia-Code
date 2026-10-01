@echo off
setlocal
cd /d "%~dp0.."
title Lia-Code - Diagnostico de benchmark

where powershell.exe >nul 2>nul
if errorlevel 1 (
  echo ERRO: Windows PowerShell nao foi encontrado.
  echo Este teste requer Windows PowerShell 5.1 ou PowerShell 7.
  pause
  exit /b 1
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0run-benchmark.ps1"
set "RESULT=%ERRORLEVEL%"
echo.
if not "%RESULT%"=="0" echo O diagnostico terminou com erro. Consulte benchmark-results.
pause
exit /b %RESULT%
