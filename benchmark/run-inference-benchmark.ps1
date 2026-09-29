$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding
$root = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $root 'benchmark-results'
$cache = Join-Path $env:LOCALAPPDATA 'Lia-Code\benchmark-cache'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logPath = Join-Path $outDir "lia-inference-$stamp.log"
$jsonPath = Join-Path $outDir "lia-inference-$stamp.json"
$runtimeTag = 'b11249'
$runtimeZip = Join-Path $cache "llama-$runtimeTag-vulkan.zip"
$runtimeDir = Join-Path $cache "llama-$runtimeTag-vulkan"
$modelName = 'Qwen3-4B-Instruct-2507-Q4_K_M.gguf'
$modelPath = Join-Path (Join-Path $cache 'models') $modelName
$releaseUrl = "https://github.com/ggml-org/llama.cpp/releases/download/$runtimeTag/llama-$runtimeTag-bin-win-vulkan-x64.zip"
$modelUrl = "https://huggingface.co/bartowski/Qwen_Qwen3-4B-Instruct-2507-GGUF/resolve/main/$modelName?download=true"
$report = [ordered]@{
    schemaVersion = 1
    createdAt = (Get-Date).ToString('o')
    model = [ordered]@{ name = $modelName; repository = 'bartowski/Qwen_Qwen3-4B-Instruct-2507-GGUF'; quantization = 'Q4_K_M'; sourceLicense = 'Apache-2.0 (upstream Qwen model; verify repository notices)' }
    runtime = [ordered]@{ name = 'llama.cpp Vulkan'; release = $runtimeTag }
    deviceEnumeration = @()
    tests = @()
    notes = @('Initial local inference benchmark; measures throughput only, not answer quality.', 'The model and runtime are downloaded to the user LocalAppData cache, not into the Git repository.')
}
New-Item -ItemType Directory -Force -Path $outDir, $cache, (Split-Path -Parent $modelPath) | Out-Null
Start-Transcript -Path $logPath -Force | Out-Null
$failed = $false
try {
    Write-Host 'Lia-Code - benchmark local de inferência' -ForegroundColor Cyan
    Write-Host 'Vai baixar um runtime Vulkan e um modelo GGUF (~2,5 GB para o modelo).'
    Write-Host "Cache: $cache"
    $answer = Read-Host 'Digite S para continuar; qualquer outra resposta cancela'
    if ($answer -notmatch '^(s|sim|y|yes)$') { throw 'Execução cancelada pelo usuário antes de baixar os arquivos.' }

    $drive = [System.IO.DriveInfo]::new([System.IO.Path]::GetPathRoot($cache))
    Write-Host ("Espaço livre no drive do cache: {0:N1} GB" -f ($drive.AvailableFreeSpace / 1GB))
    if ($drive.AvailableFreeSpace -lt 5GB) { throw 'Menos de 5 GB livres no drive do cache. Libere espaço e tente novamente.' }

    if (-not (Test-Path $runtimeDir)) {
        Write-Host "Baixando llama.cpp $runtimeTag (Vulkan)..."
        Invoke-WebRequest -Uri $releaseUrl -OutFile $runtimeZip -UseBasicParsing
        Expand-Archive -LiteralPath $runtimeZip -DestinationPath $runtimeDir -Force
        Remove-Item -LiteralPath $runtimeZip -Force
    } else { Write-Host "Runtime em cache: $runtimeDir" }
    $bench = Get-ChildItem -LiteralPath $runtimeDir -Filter 'llama-bench.exe' -Recurse | Select-Object -First 1
    $cli = Get-ChildItem -LiteralPath $runtimeDir -Filter 'llama-cli.exe' -Recurse | Select-Object -First 1
    if (-not $bench) { throw 'llama-bench.exe não apareceu no pacote baixado.' }
    if (-not $cli) { throw 'llama-cli.exe não apareceu no pacote baixado.' }

    if (-not (Test-Path $modelPath)) {
        Write-Host 'Baixando modelo Qwen3-4B-Instruct-2507 Q4_K_M (~2,5 GB)...'
        Invoke-WebRequest -Uri $modelUrl -OutFile $modelPath -UseBasicParsing
    } else { Write-Host "Modelo em cache: $modelPath" }
    if ((Get-Item -LiteralPath $modelPath).Length -lt 2.2GB) { throw 'O modelo tem menos de 2,2 GiB; download incompleto ou página de erro salva como arquivo. Apague o arquivo incompleto no cache e tente novamente.' }

    Write-Host "`nDispositivos reportados pelo llama.cpp:"
    $devices = @(& $cli.Source '--list-devices' 2>&1 | ForEach-Object { [string]$_ })
    $devices | ForEach-Object { Write-Host $_ }
    $report.deviceEnumeration = $devices
    $vulkanGpuFound = (($devices -join "`n") -match '(?i)Vulkan') -and (($devices -join "`n") -match '(?i)AMD|Radeon|RX 580')

    function Invoke-BenchCase([string]$Name, [int]$GpuLayers) {
        Write-Host "`n=== $Name (GPU layers: $GpuLayers) ===" -ForegroundColor Yellow
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $benchArgs = @('-m', $modelPath, '-p', '256', '-n', '64', '-t', '6', '-r', '2', '-ngl', "$GpuLayers")
        $output = @(& $bench.Source @benchArgs 2>&1 | ForEach-Object { $line = [string]$_; Add-Content -LiteralPath $logPath -Value $line; Write-Host $line; $line })
        $exit = $LASTEXITCODE
        $sw.Stop()
        $report.tests += [ordered]@{ name = $Name; gpuLayers = $GpuLayers; exitCode = $exit; wallTimeSeconds = [math]::Round($sw.Elapsed.TotalSeconds, 2); rawOutput = $output }
        if ($exit -ne 0) { Write-Host "Teste '$Name' terminou com código $exit; detalhes estão no log." -ForegroundColor Red }
    }

    Invoke-BenchCase 'CPU baseline' 0
    if ($vulkanGpuFound) {
        Invoke-BenchCase 'Vulkan GPU offload' 99
    } else {
        $report.notes += 'Não foi identificado dispositivo AMD via Vulkan na enumeração do llama.cpp; teste de offload pulado. O teste CPU ainda foi executado.'
        Write-Host 'Não foi detectado dispositivo AMD Vulkan; pulando offload e preservando o diagnóstico.' -ForegroundColor Yellow
    }
    $report.notes += 'Cada caso usa 256 tokens de prompt, até 64 tokens de geração, 6 threads e 2 repetições, via llama-bench.'
} catch {
    $failed = $true
    $report.notes += "ERROR: $($_.Exception.Message)"
    Write-Host "ERRO: $($_.Exception.Message)" -ForegroundColor Red
} finally {
    try { $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding UTF8 } catch { $failed = $true; Write-Host "Falha ao gravar JSON: $($_.Exception.Message)" -ForegroundColor Red }
    Stop-Transcript | Out-Null
}

$gitSummary = @()
try {
    Push-Location $root
    $branch = (& git branch --show-current 2>&1 | Out-String).Trim()
    if ($branch -ne 'arena/01a0ec89-lia-code') { throw "Branch '$branch' inesperada; esperado arena/01a0ec89-lia-code." }
    & git diff --cached --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Há alterações staged; recusando commit automático para proteger outros arquivos.' }
    $relLog = "benchmark-results/$(Split-Path -Leaf $logPath)"
    $relJson = "benchmark-results/$(Split-Path -Leaf $jsonPath)"
    & git add -f -- $relLog $relJson 2>&1 | ForEach-Object { $gitSummary += [string]$_ }
    if ($LASTEXITCODE -ne 0) { throw 'git add dos relatórios falhou.' }
    & git commit -m "Add inference benchmark report $stamp" 2>&1 | ForEach-Object { $gitSummary += [string]$_ }
    if ($LASTEXITCODE -ne 0) { throw 'git commit falhou.' }
    & git push origin arena/01a0ec89-lia-code 2>&1 | ForEach-Object { $gitSummary += [string]$_ }
    if ($LASTEXITCODE -ne 0) { throw 'git push falhou; relatórios continuam salvos localmente.' }
    $gitSummary += 'Benchmark report commitado e enviado para origin/arena/01a0ec89-lia-code.'
} catch { $gitSummary += "Commit/push automático não concluído: $($_.Exception.Message)" }
finally { if ((Get-Location).Path -eq $root) { Pop-Location } }
Add-Content -LiteralPath $logPath -Value ($gitSummary -join [Environment]::NewLine)
Write-Host "`nRelatório: $jsonPath`nLog: $logPath`n$($gitSummary -join [Environment]::NewLine)"
if ($failed) { exit 1 }
exit 0
