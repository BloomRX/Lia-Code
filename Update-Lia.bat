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
if not defined TEST_MODE set "TEST_MODE=tts-runtime-preflight"
if /i "%TEST_MODE%"=="tts-runtime-preflight" set "PS_SCRIPT=%~dp0benchmark\run-tts-runtime-preflight.ps1"
if /i "%TEST_MODE%"=="tts-preflight" set "PS_SCRIPT=%~dp0benchmark\run-tts-preflight.ps1"
if /i "%TEST_MODE%"=="llm-baseline" (
  set "PS_SCRIPT=%~dp0benchmark\run-llm-comparison.ps1"
  set "PS_ARGS=-BaselineOnly"
)
if /i "%TEST_MODE%"=="llm-comparison" set "PS_SCRIPT=%~dp0benchmark\run-llm-comparison.ps1"
if /i "%TEST_MODE%"=="omni-preflight" set "PS_SCRIPT=%~dp0benchmark\run-benchmark.ps1"
if /i "%TEST_MODE%"=="quality-both" set "PS_SCRIPT=%~dp0benchmark\run-quality-evaluation.ps1"
if /i "%TEST_MODE%"=="quality" set "PS_SCRIPT=%~dp0benchmark\run-quality-evaluation.ps1"
if /i "%TEST_MODE%"=="personality" (
  set "PS_SCRIPT=%~dp0benchmark\run-quality-evaluation.ps1"
  set "PS_ARGS=-Suite personality"
)
if /i "%TEST_MODE%"=="quality-8b" (
  set "PS_SCRIPT=%~dp0benchmark\run-quality-evaluation.ps1"
  set "PS_ARGS=-ModelVariant 8B"
)
if /i "%TEST_MODE%"=="speed" set "PS_SCRIPT=%~dp0benchmark\run-inference-benchmark.ps1"
if not defined PS_SCRIPT (
echo Uso: Update-Lia.bat [tts-runtime-preflight^|tts-preflight^|llm-baseline^|llm-comparison^|omni-preflight^|quality-both^|quality^|quality-8b^|personality^|speed]
echo Sem argumento, detecta runtimes neural TTS ja presentes, sem download, instalacao ou atualizacao.
echo Use quality-both para repetir a comparacao textual 4B/8B; personalidade fica pausada.
  pause
  exit /b 2
)

if /i "%TEST_MODE%"=="quality-both" goto run_both

echo Iniciando teste %TEST_MODE%...
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" %PS_ARGS%
set "RESULT=%ERRORLEVEL%"
goto finish

:run_both
echo Comparacao dos modelos: controle Qwen3-4B e candidato Qwen3-8B.
echo Os dois relatorios serao salvos e enviados automaticamente.
tasklist /fi "imagename eq chrome.exe" /nh 2>nul | find /i "chrome.exe" >nul
if not errorlevel 1 (
  echo.
  echo AVISO: Chrome esta aberto. Na RX 580 com 8 GB, ele pode ocupar VRAM e atrapalhar o teste 8B.
  choice /c SRC /n /m "Feche o Chrome e pressione S para seguir; R roda mesmo assim; C cancela: "
  if errorlevel 3 (
    echo Teste cancelado. Nenhum modelo foi executado.
    set "RESULT=3"
    goto finish
  )
  if errorlevel 2 echo Voce escolheu continuar com o Chrome aberto; o teste 8B pode falhar por falta de VRAM.
)
echo.
echo ===== MODELO DE CONTROLE: QWEN3-4B =====
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%"
set "RESULT4=%ERRORLEVEL%"
echo.
echo ===== MODELO CANDIDATO: QWEN3-8B =====
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -ModelVariant 8B
set "RESULT8=%ERRORLEVEL%"
set "RESULT=1"
if "!RESULT4!"=="0" if "!RESULT8!"=="0" set "RESULT=0"
if not "!RESULT4!"=="0" echo O teste 4B terminou com erro. Confira o relatorio local.
if not "!RESULT8!"=="0" echo O teste 8B terminou com erro. Confira o relatorio local.

goto finish

:finish
echo.
if not "%RESULT%"=="0" echo A rotina terminou com codigo %RESULT%. Consulte benchmark-results.
pause
exit /b %RESULT%
