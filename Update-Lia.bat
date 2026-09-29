@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul
cd /d "%~dp0"
title Lia-Code - Atualizar e executar benchmark

set "EXPECTED_BRANCH=arena/01a0ec89-lia-code"
for /f "delims=" %%B in ('git branch --show-current 2^>nul') do set "CURRENT_BRANCH=%%B"
if not "%CURRENT_BRANCH%"=="%EXPECTED_BRANCH%" (
  echo ERRO: branch atual "%CURRENT_BRANCH%"; esperada "%EXPECTED_BRANCH%".
  echo Clone correto: git clone -b %EXPECTED_BRANCH% https://github.com/BloomRX/Lia-Code.git
  pause
  exit /b 1
)

rem Preserve locally changed generated reports outside the repository before pulling updates.
git diff --quiet -- benchmark-results
if errorlevel 1 (
  set "BACKUP_DIR=%LOCALAPPDATA%\Lia-Code\report-backups\pull-%RANDOM%-%RANDOM%"
  echo Relatorios locais alterados. Backup em "!BACKUP_DIR!"...
  if not exist "!BACKUP_DIR!" mkdir "!BACKUP_DIR!"
  xcopy "benchmark-results\*" "!BACKUP_DIR!\" /e /i /h /y >nul
  if errorlevel 1 (
    echo ERRO: nao foi possivel fazer backup dos relatorios. Nada sera descartado.
    pause
    exit /b 1
  )
  git restore --worktree -- benchmark-results
  if errorlevel 1 (
    echo ERRO: nao foi possivel restaurar os relatorios gerados.
    pause
    exit /b 1
  )
)

echo Atualizando a branch %EXPECTED_BRANCH%...
git pull --ff-only origin %EXPECTED_BRANCH%
set "PULL_RESULT=%ERRORLEVEL%"
if not "%PULL_RESULT%"=="0" (
  echo ERRO: git pull terminou com codigo %PULL_RESULT%. Nenhuma alteracao de codigo foi descartada.
  pause
  exit /b %PULL_RESULT%
)

set "TEST_MODE=%~1"
if not defined TEST_MODE set "TEST_MODE=quality"
if /i "%TEST_MODE%"=="quality" set "PS_SCRIPT=%~dp0benchmark\run-quality-evaluation.ps1"
if /i "%TEST_MODE%"=="speed" set "PS_SCRIPT=%~dp0benchmark\run-inference-benchmark.ps1"
if not defined PS_SCRIPT (
  echo Uso: Update-Lia.bat [quality^|speed]
  echo Sem argumento, executa a avaliacao de qualidade.
  pause
  exit /b 2
)

echo Iniciando teste %TEST_MODE%...
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%"
set "RESULT=%ERRORLEVEL%"
echo.
if not "%RESULT%"=="0" echo Teste terminou com erro. Consulte benchmark-results.
pause
exit /b %RESULT%
