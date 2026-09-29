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
$modelName = 'Qwen_Qwen3-4B-Instruct-2507-Q4_K_M.gguf'
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
[System.IO.File]::WriteAllText($logPath, "Lia-Code inference benchmark | $stamp`r`n", [System.Text.UTF8Encoding]::new($false))
function Protect-String([string]$Text) {
    if ($env:USERPROFILE) { $Text = [regex]::Replace($Text, [regex]::Escape($env:USERPROFILE), '%USERPROFILE%', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase) }
    return $Text
}
function Write-RunLog([string]$Message) {
    $safe = Protect-String $Message
    Write-Host $safe
    Add-Content -LiteralPath $logPath -Value $safe -Encoding UTF8
}
function Invoke-GitSafe([string[]]$GitArgs) {
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $lines = @(& git @GitArgs 2>&1 | ForEach-Object { [string]$_ })
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previousPreference }
    [pscustomobject]@{ ExitCode = $code; Output = $lines }
}
$failed = $false
try {
    Write-RunLog 'Lia-Code - benchmark local de inferência'
    Write-RunLog 'Vai baixar um runtime Vulkan e um modelo GGUF (~2,5 GB para o modelo).'
    Write-RunLog "Cache: $cache"
    $answer = Read-Host 'Digite S para continuar; qualquer outra resposta cancela'
    if ($answer -notmatch '^(s|sim|y|yes)$') { throw 'Execução cancelada pelo usuário antes de baixar os arquivos.' }

    $drive = [System.IO.DriveInfo]::new([System.IO.Path]::GetPathRoot($cache))
    Write-RunLog ("Espaço livre no drive do cache: {0:N1} GB" -f ($drive.AvailableFreeSpace / 1GB))
    if ($drive.AvailableFreeSpace -lt 5GB) { throw 'Menos de 5 GB livres no drive do cache. Libere espaço e tente novamente.' }

    if (-not (Test-Path $runtimeDir)) {
        Write-RunLog "Baixando llama.cpp $runtimeTag (Vulkan)..."
        Invoke-WebRequest -Uri $releaseUrl -OutFile $runtimeZip -UseBasicParsing
        Expand-Archive -LiteralPath $runtimeZip -DestinationPath $runtimeDir -Force
        Remove-Item -LiteralPath $runtimeZip -Force
    } else { Write-RunLog 'Runtime em cache reutilizado.' }
    $bench = Get-ChildItem -LiteralPath $runtimeDir -Filter 'llama-bench.exe' -Recurse | Select-Object -First 1
    $cli = Get-ChildItem -LiteralPath $runtimeDir -Filter 'llama-cli.exe' -Recurse | Select-Object -First 1
    if (-not $bench) { throw 'llama-bench.exe não apareceu no pacote baixado.' }
    if (-not $cli) { throw 'llama-cli.exe não apareceu no pacote baixado.' }

    if ((Test-Path $modelPath) -and ((Get-Item -LiteralPath $modelPath).Length -lt 2.2GB)) {
        Remove-Item -LiteralPath $modelPath -Force
        Write-RunLog 'Removido arquivo parcial de modelo da tentativa anterior.'
    }
    if (-not (Test-Path $modelPath)) {
        Write-RunLog 'Baixando modelo Qwen3-4B-Instruct-2507 Q4_K_M (~2,5 GB)...'
        Invoke-WebRequest -Uri $modelUrl -OutFile $modelPath -UseBasicParsing
    } else { Write-RunLog 'Modelo em cache reutilizado.' }
    if ((Get-Item -LiteralPath $modelPath).Length -lt 2.2GB) { throw 'O modelo tem menos de 2,2 GiB; download incompleto ou página de erro salva como arquivo. Apague o arquivo incompleto no cache e tente novamente.' }

    Write-RunLog "`nDispositivos reportados pelo llama.cpp:"
    $devices = @(& $cli.Source '--list-devices' 2>&1 | ForEach-Object { [string]$_ })
    $devices | ForEach-Object { Write-RunLog $_ }
    $report.deviceEnumeration = $devices
    $vulkanGpuFound = (($devices -join "`n") -match '(?i)Vulkan') -and (($devices -join "`n") -match '(?i)AMD|Radeon|RX 580')

    function Invoke-BenchCase([string]$Name, [int]$GpuLayers) {
        Write-RunLog "`n=== $Name (GPU layers: $GpuLayers) ==="
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $benchArgs = @('-m', $modelPath, '-p', '256', '-n', '64', '-t', '6', '-r', '2', '-ngl', "$GpuLayers")
        $output = @(& $bench.Source @benchArgs 2>&1 | ForEach-Object { $line = [string]$_; Write-RunLog $line; Protect-String $line })
        $exit = $LASTEXITCODE
        $sw.Stop()
        $report.tests += [ordered]@{ name = $Name; gpuLayers = $GpuLayers; exitCode = $exit; wallTimeSeconds = [math]::Round($sw.Elapsed.TotalSeconds, 2); rawOutput = $output }
        if ($exit -ne 0) { Write-RunLog "Teste '$Name' terminou com código $exit; detalhes estão no log." }
    }

    Invoke-BenchCase 'CPU baseline' 0
    if ($vulkanGpuFound) {
        Invoke-BenchCase 'Vulkan GPU offload' 99
    } else {
        $report.notes += 'Não foi identificado dispositivo AMD via Vulkan na enumeração do llama.cpp; teste de offload pulado. O teste CPU ainda foi executado.'
        Write-RunLog 'Não foi detectado dispositivo AMD Vulkan; pulando offload e preservando o diagnóstico.'
    }
    $report.notes += 'Cada caso usa 256 tokens de prompt, até 64 tokens de geração, 6 threads e 2 repetições, via llama-bench.'
} catch {
    $failed = $true
    $report.notes += "ERROR: $($_.Exception.Message)"
    Write-RunLog "ERRO: $($_.Exception.Message)"
} finally {
    try { $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding UTF8 } catch { $failed = $true; Write-RunLog "Falha ao gravar JSON: $($_.Exception.Message)" }
}

$gitSummary = @()
$locationPushed = $false
try {
    Push-Location $root
    $locationPushed = $true
    $branchResult = Invoke-GitSafe @('branch', '--show-current')
    $branch = ($branchResult.Output -join '').Trim()
    if ($branchResult.ExitCode -ne 0) { throw 'Não foi possível identificar a branch atual.' }
    if ($branch -ne 'arena/01a0ec89-lia-code') { throw "Branch '$branch' inesperada; esperado arena/01a0ec89-lia-code." }
    $staged = Invoke-GitSafe @('diff', '--cached', '--quiet')
    if ($staged.ExitCode -ne 0) { throw 'Há alterações staged; recusando commit automático para proteger outros arquivos.' }
    $relLog = "benchmark-results/$(Split-Path -Leaf $logPath)"
    $relJson = "benchmark-results/$(Split-Path -Leaf $jsonPath)"
    $addResult = Invoke-GitSafe @('add', '-f', '--', $relLog, $relJson)
    $gitSummary += $addResult.Output
    if ($addResult.ExitCode -ne 0) { throw 'git add dos relatórios falhou.' }
    $commitResult = Invoke-GitSafe @('commit', '-m', "Add inference benchmark report $stamp")
    $gitSummary += $commitResult.Output
    if ($commitResult.ExitCode -ne 0) { throw 'git commit falhou.' }
    $pushResult = Invoke-GitSafe @('push', 'origin', 'arena/01a0ec89-lia-code')
    $gitSummary += $pushResult.Output
    if ($pushResult.ExitCode -ne 0) { throw 'git push falhou; relatórios continuam salvos localmente.' }
    $gitSummary += 'Benchmark report commitado e enviado para origin/arena/01a0ec89-lia-code.'
} catch { $gitSummary += "Commit/push automático não concluído: $($_.Exception.Message)" }
finally { if ($locationPushed) { Pop-Location } }
Add-Content -LiteralPath $logPath -Value ($gitSummary -join [Environment]::NewLine) -Encoding UTF8
Write-Host "`nRelatório: $jsonPath`nLog: $logPath`n$($gitSummary -join [Environment]::NewLine)"
if ($failed) { exit 1 }
exit 0
