@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul
cd /d "%~dp0.."
title Lia-Code - Atualizar e testar

set "EXPECTED_BRANCH=arena/01a0ec89-lia-code"
for /f "delims=" %%B in ('git branch --show-current 2^>nul') do set "CURRENT_BRANCH=%%B"
if not "%CURRENT_BRANCH%"=="%EXPECTED_BRANCH%" (
  echo ERRO: branch atual "%CURRENT_BRANCH%"; esperada "%EXPECTED_BRANCH%".
  echo Clone correto: git clone -b %EXPECTED_BRANCH% https://github.com/BloomRX/Lia-Code.git
  pause
  exit /b 1
)

rem Generated benchmark reports can be modified locally after auto-commit.
rem Back them up outside the repo, restore report files only, and keep source changes untouched.
git diff --quiet -- benchmark-results
if errorlevel 1 (
  set "BACKUP_DIR=%LOCALAPPDATA%\Lia-Code\report-backups\pull-%RANDOM%-%RANDOM%"
  echo Relatorios locais alterados detectados. Fazendo backup em "!BACKUP_DIR!"...
  if not exist "!BACKUP_DIR!" mkdir "!BACKUP_DIR!"
  xcopy "benchmark-results\*" "!BACKUP_DIR!\" /e /i /h /y >nul
  if errorlevel 1 (
    echo ERRO: nao foi possivel fazer backup dos relatorios. Nada sera descartado.
    pause
    exit /b 1
  )
  git restore --worktree -- benchmark-results
  if errorlevel 1 (
    echo ERRO: nao foi possivel limpar somente os relatorios gerados.
    pause
    exit /b 1
  )
)

echo Atualizando a branch %EXPECTED_BRANCH%...
git pull --ff-only origin %EXPECTED_BRANCH%
if errorlevel 1 (
  echo ERRO: pull falhou. Nenhum arquivo local foi sobrescrito. Verifique suas alteracoes ou a conexao.
  pause
  exit /b 1
)

echo Iniciando benchmark de inferencia...
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0run-inference-benchmark.ps1"
set "RESULT=%ERRORLEVEL%"
echo.
if not "%RESULT%"=="0" echo Benchmark terminou com erro. Veja benchmark-results e o log para detalhes.
pause
exit /b %RESULT%
