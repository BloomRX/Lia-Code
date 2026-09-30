$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding

$root = Split-Path -Parent $PSScriptRoot
$resultsDir = Join-Path $root 'benchmark-results'
$resourceRoot = Join-Path $env:LOCALAPPDATA 'Lia-Code\tts\piper-directml-eval'
$modelsDir = Join-Path $resourceRoot 'models\faber-medium'
$cpuEnv = Join-Path $resourceRoot 'env-cpu'
$dmlEnv = Join-Path $resourceRoot 'env-directml'
$pipCache = Join-Path $resourceRoot 'pip-cache'
$audioDir = Join-Path $resourceRoot 'audio'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$jsonPath = Join-Path $resultsDir "lia-piper-latency-$stamp.json"
$logPath = Join-Path $resultsDir "lia-piper-latency-$stamp.log"
$logLines = [System.Collections.Generic.List[string]]::new()
$issues = [System.Collections.Generic.List[string]]::new()
$report = [ordered]@{
    schemaVersion = 1
    evaluation = 'piper-faber-cpu-vs-directml-latency'
    createdAt = (Get-Date).ToString('o')
    machine = [ordered]@{}
    policy = 'Create two removable environments outside the repository; CPU environment reuses the existing CPU ONNX Runtime through system-site-packages. Download pinned Piper Faber weights and package wheels; do not change system Python or install globally.'
    resourceRoot = '%LOCALAPPDATA%\Lia-Code\tts\piper-directml-eval'
    resources = [ordered]@{}
    cpu = [ordered]@{ setup = 'not-started'; result = $null }
    directml = [ordered]@{ setup = 'not-started'; result = $null }
    issues = @()
}
function Protect-Text([string]$Text) {
    if ($env:USERPROFILE) { return [regex]::Replace($Text, [regex]::Escape($env:USERPROFILE), '%USERPROFILE%', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase) }
    return $Text
}
function Write-RunLog([string]$Message) {
    $safe = Protect-Text $Message
    $logLines.Add($safe)
    Write-Host $safe
}
function Invoke-Native([string]$File, [string[]]$Arguments, [switch]$AllowFailure) {
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& $File @Arguments 2>&1 | ForEach-Object { [string]$_ })
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $oldPreference }
    foreach ($line in $output) { Write-RunLog $line }
    if ($code -ne 0 -and -not $AllowFailure) { throw "Command failed ($code): $File $($Arguments -join ' ')" }
    return [ordered]@{ exitCode = $code; output = @($output) }
}
function Download-File([string]$Url, [string]$Path, [string]$ExpectedSha256) {
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-RunLog "Baixando: $Url"
        try { Invoke-WebRequest -Uri $Url -OutFile $Path -UseBasicParsing -ErrorAction Stop | Out-Null }
        catch { if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }; throw }
    }
    $hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($ExpectedSha256 -and $hash -ne $ExpectedSha256.ToLowerInvariant()) {
        throw "SHA-256 inesperado para $(Split-Path -Leaf $Path): $hash"
    }
    return $hash
}
function Ensure-Venv([string]$BasePython, [string]$Path, [switch]$SystemSitePackages) {
    $pythonExe = Join-Path $Path 'Scripts\python.exe'
    if (-not (Test-Path -LiteralPath $pythonExe)) {
        $args = @('-m', 'venv')
        if ($SystemSitePackages) { $args += '--system-site-packages' }
        $args += $Path
        Invoke-Native $BasePython $args | Out-Null
    }
    if (-not (Test-Path -LiteralPath $pythonExe)) { throw "venv creation failed: $Path" }
    return $pythonExe
}

New-Item -ItemType Directory -Force -Path $resultsDir,$modelsDir,$pipCache,$audioDir | Out-Null
Write-RunLog 'Lia-Code — teste Piper Faber: CPU existente versus ambiente DirectML isolado.'
Write-RunLog 'Nenhum pacote será instalado no Python global; tudo baixado/instalado fica sob o diretório TTS externo e removível.'
try {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $report.machine = [ordered]@{
        os = $os.Caption; osBuild = $os.BuildNumber
        powershellVersion = $PSVersionTable.PSVersion.ToString()
        culture = [System.Globalization.CultureInfo]::CurrentCulture.Name
    }
    $pythonCommand = Get-Command python.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $pythonCommand) { throw 'python.exe not found on PATH.' }
    $basePython = $pythonCommand.Source

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $modelName = 'pt_BR-faber-medium.onnx'
    $modelUrl = 'https://huggingface.co/rhasspy/piper-voices/resolve/2f8dbe0bb0dde986411632bf014a13cdbe6596e7/pt/pt_BR/faber/medium/pt_BR-faber-medium.onnx?download=true'
    $configUrl = 'https://huggingface.co/rhasspy/piper-voices/resolve/2f8dbe0bb0dde986411632bf014a13cdbe6596e7/pt/pt_BR/faber/medium/pt_BR-faber-medium.onnx.json?download=true'
    $modelPath = Join-Path $modelsDir $modelName
    $configPath = "$modelPath.json"
    $modelSha = Download-File $modelUrl $modelPath '858555e3a064209c57088fe6bd70c4c3dc54d03eaa00c45d5ecaf43a33f95aa7'
    $configSha = Download-File $configUrl $configPath $null

    $piperWheelName = 'piper_tts-1.8.0-cp39-abi3-win_amd64.whl'
    $piperWheel = Join-Path $resourceRoot $piperWheelName
    $piperUrl = 'https://files.pythonhosted.org/packages/12/9c/c736d1961cf9ce0655278731b9430df41892ca2ded7b09dabcb340612158/piper_tts-1.8.0-cp39-abi3-win_amd64.whl'
    $piperSha = Download-File $piperUrl $piperWheel '5da9bfdb05dfe15da3536859d422e605483ffa6d2b3ec2c5b9593bae6b5aa6a4'
    $dmlWheelName = 'onnxruntime_directml-1.24.4-cp314-cp314-win_amd64.whl'
    $dmlWheel = Join-Path $resourceRoot $dmlWheelName
    $dmlUrl = 'https://files.pythonhosted.org/packages/b7/04/816932a3ade867a687e406716ca76e0774c6b921545b45818e3ebfcc54ce/onnxruntime_directml-1.24.4-cp314-cp314-win_amd64.whl'
    # Pin and verify against PyPI's published SHA-256 for the CPython 3.14 Windows wheel.
    $dmlSha = Download-File $dmlUrl $dmlWheel '51d86bb949488e572b00422f344990a4a81d982416d73b6c0e4ced2bcd423d19'

    $report.resources = [ordered]@{
        voiceModel = [ordered]@{
            path = '%LOCALAPPDATA%\Lia-Code\tts\piper-directml-eval\models\faber-medium\pt_BR-faber-medium.onnx'
            origin = $modelUrl; repositoryRevision = '2f8dbe0bb0dde986411632bf014a13cdbe6596e7'
            sha256 = $modelSha; sizeBytes = (Get-Item $modelPath).Length
            license = 'Upstream model card attributes CC0 to the dataset but does not clearly state a separate license for this exact weight. Local evaluation only; do not redistribute pending clarification.'
        }
        voiceConfig = [ordered]@{ origin = $configUrl; sha256 = $configSha; sizeBytes = (Get-Item $configPath).Length }
        piperWheel = [ordered]@{
            path = "%LOCALAPPDATA%\Lia-Code\tts\piper-directml-eval\$piperWheelName"
            origin = $piperUrl; version = '1.8.0'; sha256 = $piperSha; license = 'GPL-3.0-or-later; wheel includes Piper/eSpeak phonemization components.'
        }
        directmlWheel = [ordered]@{
            path = "%LOCALAPPDATA%\Lia-Code\tts\piper-directml-eval\$dmlWheelName"
            origin = $dmlUrl; version = '1.24.4'; sha256 = $dmlSha; license = 'MIT'
        }
        deletion = 'Delete %LOCALAPPDATA%\Lia-Code\tts\piper-directml-eval to remove both venvs, model, downloaded wheels, pip cache, profiles and WAV outputs. The system Python/CPU ONNX Runtime is not modified.'
    }

    $cpuPython = Ensure-Venv $basePython $cpuEnv -SystemSitePackages
    $dmlPython = Ensure-Venv $basePython $dmlEnv
    Invoke-Native $cpuPython @('-m','pip','--cache-dir',$pipCache,'install','--no-deps',$piperWheel) | Out-Null
    Invoke-Native $dmlPython @('-m','pip','--cache-dir',$pipCache,'install',$dmlWheel) | Out-Null
    Invoke-Native $dmlPython @('-m','pip','--cache-dir',$pipCache,'install','--no-deps',$piperWheel) | Out-Null

    $inventoryProbe = Join-Path $PSScriptRoot 'write-python-package-inventory.py'
    $cpuInventoryPath = Join-Path $resourceRoot 'cpu-package-inventory.json'
    $dmlInventoryPath = Join-Path $resourceRoot 'directml-package-inventory.json'
    Invoke-Native $cpuPython @('-B',$inventoryProbe,'--output',$cpuInventoryPath) | Out-Null
    Invoke-Native $dmlPython @('-B',$inventoryProbe,'--output',$dmlInventoryPath) | Out-Null
    $report.resources.packageInventories = @('cpu-package-inventory.json','directml-package-inventory.json')

    $probe = Join-Path $PSScriptRoot 'run-piper-latency-probe.py'
    $cpuOut = Join-Path $audioDir 'cpu'
    $dmlOut = Join-Path $audioDir 'directml'
    New-Item -ItemType Directory -Force -Path $cpuOut,$dmlOut | Out-Null
    Write-RunLog 'Executando benchmark CPU com ONNX Runtime preexistente...'
    $cpuRun = Invoke-Native $cpuPython @('-B',$probe,'--model',$modelPath,'--output-dir',$cpuOut,'--provider','cpu','--runs','4') -AllowFailure
    $report.cpu.setup = if ($cpuRun.exitCode -eq 0) { 'ok' } else { 'probe-failed' }
    if ($cpuRun.exitCode -eq 0) {
        $cpuJson = $cpuRun.output | Where-Object { $_.Trim().StartsWith('{') } | Select-Object -Last 1
        if ($cpuJson) { $report.cpu.result = ConvertFrom-Json -InputObject $cpuJson -ErrorAction Stop }
    } else { $issues.Add((Protect-Text "CPU probe failed: $($cpuRun.output -join ' ')")) }

    Write-RunLog 'Executando benchmark DirectML; exige confirmação de nós executados no provider DML...'
    $dmlRun = Invoke-Native $dmlPython @('-B',$probe,'--model',$modelPath,'--output-dir',$dmlOut,'--provider','directml','--runs','4') -AllowFailure
    $report.directml.setup = if ($dmlRun.exitCode -eq 0) { 'ok' } else { 'probe-failed' }
    if ($dmlRun.exitCode -eq 0) {
        $dmlJson = $dmlRun.output | Where-Object { $_.Trim().StartsWith('{') } | Select-Object -Last 1
        if ($dmlJson) { $report.directml.result = ConvertFrom-Json -InputObject $dmlJson -ErrorAction Stop }
    } else { $issues.Add((Protect-Text "DirectML probe failed: $($dmlRun.output -join ' ')")) }
} catch {
    $issues.Add((Protect-Text ([string]$_.Exception.Message)))
    Write-RunLog "Falha no benchmark: $($_.Exception.Message)"
}
$report.issues = @($issues)
try {
    $manifestPath = Join-Path $resourceRoot 'resource-manifest.json'
    $report.resources | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    $report | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
    $logLines | Set-Content -LiteralPath $logPath -Encoding UTF8
    Write-Host "Relatórios: $jsonPath`n$logPath"
} catch { Write-Host "ERRO ao salvar relatório: $($_.Exception.Message)"; exit 1 }

$gitSummary = [System.Collections.Generic.List[string]]::new()
$pushedLocation = $false
try {
    Push-Location $root; $pushedLocation = $true
    $branch = (& git branch --show-current 2>$null).Trim()
    if ($branch -ne 'arena/01a0ec89-lia-code') { throw "Branch inválida para envio: '$branch'." }
    & git diff --cached --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Há alterações staged; recusando commit automático.' }
    & git add -f -- "benchmark-results/$(Split-Path -Leaf $jsonPath)" "benchmark-results/$(Split-Path -Leaf $logPath)"
    if ($LASTEXITCODE -ne 0) { throw 'git add dos relatórios falhou.' }
    & git commit -m "Add Piper Faber latency report $stamp"
    if ($LASTEXITCODE -ne 0) { throw 'git commit dos relatórios falhou.' }
    & git push origin arena/01a0ec89-lia-code
    if ($LASTEXITCODE -ne 0) { throw 'git push falhou; relatório permanece local.' }
    $gitSummary.Add('Relatório commitado e enviado para arena/01a0ec89-lia-code.')
} catch { $gitSummary.Add("Relatório salvo; envio não concluído: $(Protect-Text ([string]$_.Exception.Message))") }
finally { if ($pushedLocation) { Pop-Location } }
Write-Host ($gitSummary -join [Environment]::NewLine)
if ($issues.Count -gt 0 -or ($gitSummary -join ' ') -notmatch 'Relatório commitado e enviado') { exit 1 }
exit 0
