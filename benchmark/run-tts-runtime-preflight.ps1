$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding

$root = Split-Path -Parent $PSScriptRoot
$resultsDir = Join-Path $root 'benchmark-results'
$cacheRoot = Join-Path $env:LOCALAPPDATA 'Lia-Code\benchmark-cache'
$modelCache = Join-Path $cacheRoot 'models'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$jsonPath = Join-Path $resultsDir "lia-tts-runtime-preflight-$stamp.json"
$logPath = Join-Path $resultsDir "lia-tts-runtime-preflight-$stamp.log"
$issues = [System.Collections.Generic.List[string]]::new()
$logLines = [System.Collections.Generic.List[string]]::new()
$report = [ordered]@{
    schemaVersion = 1
    evaluation = 'neural-tts-runtime-availability-preflight'
    createdAt = (Get-Date).ToString('o')
    policy = 'Inventory already-present Python/ONNX/PyTorch/eSpeak components and matching local model files only. No network access, weight download, package installation, runtime update, or synthesis.'
    machine = [ordered]@{}
    commands = [ordered]@{}
    python = [ordered]@{
        executableAvailable = $false
        version = $null
        probeExitCode = $null
        modules = [ordered]@{}
        onnxRuntimeVersion = $null
        onnxExecutionProviders = @()
        probeError = $null
    }
    modelCache = [ordered]@{
        piperFaberOnnxFiles = @()
        kokoroLikelyFiles = @()
        scannedOutsideRepository = $true
    }
    routeAssessment = [ordered]@{}
    notes = @(
        'The rejected Microsoft Maria SAPI sample is not treated as the neural TTS candidate.',
        'Availability is detected without importing PyTorch, downloading models, contacting package indexes, or installing/updating software.',
        'A detected runtime or file is not proof of successful inference, quality, or a valid license; a later explicit test is still required.'
    )
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
function Get-CommandRecord([string]$Name) {
    $found = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { return [ordered]@{ available = $true; commandType = [string]$found.CommandType } }
    return [ordered]@{ available = $false; commandType = $null }
}

New-Item -ItemType Directory -Force -Path $resultsDir | Out-Null
Write-RunLog 'Lia-Code — diagnóstico de runtimes TTS neurais já presentes; sem downloads nem instalações.'
try {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $report.machine = [ordered]@{
        os = $os.Caption
        osBuild = $os.BuildNumber
        powershellVersion = $PSVersionTable.PSVersion.ToString()
        systemCulture = [System.Globalization.CultureInfo]::CurrentCulture.Name
    }
    foreach ($name in @('python.exe', 'py.exe', 'espeak-ng.exe', 'espeak.exe')) {
        $report.commands[$name] = Get-CommandRecord $name
        Write-RunLog ("Comando {0}: {1}" -f $name, $report.commands[$name].available)
    }

    $pythonCommand = Get-Command 'python.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    $pythonLauncher = Get-Command 'py.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pythonCommand -and ($pythonCommand.Source -like '*\WindowsApps\python.exe' -or $pythonCommand.Source -like '*\WindowsApps\python3.exe')) {
        $report.python.probeError = 'python.exe is a Microsoft Store execution alias; skipped without opening the Store.'
        $pythonCommand = $null
    }
    $probeCode = @'
import importlib.util, json, sys
names = ["onnxruntime", "kokoro", "torch", "transformers", "piper", "numpy", "soundfile", "huggingface_hub"]
modules = {name: importlib.util.find_spec(name) is not None for name in names}
result = {"version": sys.version.split()[0], "modules": modules, "onnxRuntimeVersion": None, "onnxExecutionProviders": [], "probeError": None}
if modules["onnxruntime"]:
    try:
        import onnxruntime as ort
        result["onnxRuntimeVersion"] = ort.__version__
        result["onnxExecutionProviders"] = ort.get_available_providers()
    except Exception as exc:
        result["probeError"] = "onnxruntime provider query failed: " + type(exc).__name__
print(json.dumps(result, ensure_ascii=False))
'@
    # Windows PowerShell 5.1 strips embedded quotes from native -c arguments.
    # Pass the probe as base64 and use a quote-free Python bootstrap instead.
    $encodedProbe = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($probeCode))
    $pythonRunner = 'exec(__import__(chr(98)+chr(97)+chr(115)+chr(101)+chr(54)+chr(52)).b64decode(__import__(chr(115)+chr(121)+chr(115)).argv[1]))'
    $nativeOutput = @()
    $nativeExitCode = $null
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        if ($pythonCommand) {
            $report.python.executableAvailable = $true
            $nativeOutput = @(& $pythonCommand.Source -B -c $pythonRunner $encodedProbe 2>&1 | ForEach-Object { [string]$_ })
            $nativeExitCode = $LASTEXITCODE
        } elseif ($pythonLauncher) {
            $report.python.executableAvailable = $true
            $nativeOutput = @(& $pythonLauncher.Source -3 -B -c $pythonRunner $encodedProbe 2>&1 | ForEach-Object { [string]$_ })
            $nativeExitCode = $LASTEXITCODE
        }
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    $report.python.probeExitCode = $nativeExitCode
    if ($report.python.executableAvailable -and $nativeExitCode -eq 0) {
        $jsonLine = $nativeOutput | Where-Object { $_.Trim().StartsWith('{') } | Select-Object -Last 1
        if ($jsonLine) {
            $pythonResult = ConvertFrom-Json -InputObject $jsonLine -ErrorAction Stop
            $report.python.version = [string]$pythonResult.version
            foreach ($key in $pythonResult.modules.PSObject.Properties.Name) { $report.python.modules[$key] = [bool]$pythonResult.modules.$key }
            $report.python.onnxRuntimeVersion = $pythonResult.onnxRuntimeVersion
            $report.python.onnxExecutionProviders = @($pythonResult.onnxExecutionProviders)
            $report.python.probeError = $pythonResult.probeError
            Write-RunLog "Python: $($report.python.version)"
            foreach ($key in $report.python.modules.Keys) { Write-RunLog ("Python module {0}: {1}" -f $key, $report.python.modules[$key]) }
            if ($report.python.onnxRuntimeVersion) { Write-RunLog "ONNX Runtime: $($report.python.onnxRuntimeVersion) | providers: $($report.python.onnxExecutionProviders -join ', ')" }
        } else {
            $report.python.probeError = Protect-Text (($nativeOutput -join ' ') -replace '\s+', ' ')
            Write-RunLog "Python probe returned no JSON result (exit $nativeExitCode)."
        }
    } elseif ($report.python.executableAvailable) {
        $report.python.probeError = Protect-Text (($nativeOutput -join ' ') -replace '\s+', ' ')
        Write-RunLog "Python probe failed (exit $nativeExitCode); no change was attempted."
    } else {
        Write-RunLog 'Python/py launcher not found on PATH.'
    }

    if (Test-Path -LiteralPath $modelCache) {
        $report.modelCache.piperFaberOnnxFiles = @(
            Get-ChildItem -LiteralPath $modelCache -Filter '*.onnx' -File -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match '(?i)faber|pt.?br' } |
                Select-Object -First 10 | ForEach-Object { Protect-Text $_.FullName }
        )
        $report.modelCache.kokoroLikelyFiles = @(
            Get-ChildItem -LiteralPath $modelCache -File -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match '(?i)kokoro|pf_dora|pm_alex|pm_santa' } |
                Select-Object -First 10 | ForEach-Object { Protect-Text $_.FullName }
        )
    }
    $hasCpuProvider = @($report.python.onnxExecutionProviders | Where-Object { $_ -eq 'CPUExecutionProvider' }).Count -gt 0
    $hasDirectMlProvider = @($report.python.onnxExecutionProviders | Where-Object { $_ -eq 'DmlExecutionProvider' }).Count -gt 0
    $hasEspeak = [bool]($report.commands['espeak-ng.exe'].available -or $report.commands['espeak.exe'].available)
    $report.routeAssessment = [ordered]@{
        piperDirectOnnx = [ordered]@{
            python = [bool]$report.python.executableAvailable
            onnxRuntime = [bool]$report.python.modules['onnxruntime']
            cpuProvider = $hasCpuProvider
            directMlProvider = $hasDirectMlProvider
            espeakCommand = $hasEspeak
            matchingFaberModelCached = ($report.modelCache.piperFaberOnnxFiles.Count -gt 0)
            readyToAttemptInference = ([bool]$report.python.executableAvailable -and [bool]$report.python.modules['onnxruntime'] -and $hasCpuProvider -and $hasEspeak -and $report.modelCache.piperFaberOnnxFiles.Count -gt 0)
            note = 'Readiness is a prerequisite heuristic only; no model was loaded and license/provenance still require review.'
        }
        kokoroPython = [ordered]@{
            python = [bool]$report.python.executableAvailable
            kokoro = [bool]$report.python.modules['kokoro']
            torch = [bool]$report.python.modules['torch']
            transformers = [bool]$report.python.modules['transformers']
            espeakCommand = $hasEspeak
            likelyModelOrVoiceFileCached = ($report.modelCache.kokoroLikelyFiles.Count -gt 0)
            readyToAttemptInference = ([bool]$report.python.executableAvailable -and [bool]$report.python.modules['kokoro'] -and [bool]$report.python.modules['torch'] -and [bool]$report.python.modules['transformers'] -and $hasEspeak -and $report.modelCache.kokoroLikelyFiles.Count -gt 0)
            note = 'Readiness is a prerequisite heuristic only; no model was loaded and license/provenance still require review.'
        }
    }
    Write-RunLog "Cache model Faber encontrado: $($report.modelCache.piperFaberOnnxFiles.Count -gt 0)"
    Write-RunLog "Cache provável Kokoro encontrado: $($report.modelCache.kokoroLikelyFiles.Count -gt 0)"
} catch {
    $issues.Add((Protect-Text ([string]$_.Exception.Message)))
    Write-RunLog "Erro no diagnóstico: $($_.Exception.Message)"
}

try {
    $report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
    $logLines | Set-Content -LiteralPath $logPath -Encoding UTF8
    Write-Host "Relatórios: $jsonPath`n$logPath"
} catch {
    Write-Host "ERRO ao salvar relatório: $($_.Exception.Message)"
    exit 1
}

$gitSummary = [System.Collections.Generic.List[string]]::new()
$pushedLocation = $false
try {
    Push-Location $root
    $pushedLocation = $true
    $branch = (& git branch --show-current 2>$null).Trim()
    if ($branch -ne 'arena/01a0ec89-lia-code') { throw "Branch inválida para envio: '$branch'." }
    & git diff --cached --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Há alterações staged; recusando commit automático.' }
    & git add -f -- "benchmark-results/$(Split-Path -Leaf $jsonPath)" "benchmark-results/$(Split-Path -Leaf $logPath)"
    if ($LASTEXITCODE -ne 0) { throw 'git add dos relatórios falhou.' }
    & git commit -m "Add neural TTS runtime preflight report $stamp"
    if ($LASTEXITCODE -ne 0) { throw 'git commit dos relatórios falhou.' }
    & git push origin arena/01a0ec89-lia-code
    if ($LASTEXITCODE -ne 0) { throw 'git push falhou; relatórios permanecem locais.' }
    $gitSummary.Add('Relatórios commitados e enviados para arena/01a0ec89-lia-code.')
} catch { $gitSummary.Add("Relatórios salvos; envio não concluído: $(Protect-Text ([string]$_.Exception.Message))") }
finally { if ($pushedLocation) { Pop-Location } }
Write-Host ($gitSummary -join [Environment]::NewLine)
if ($issues.Count -gt 0 -or ($gitSummary -join ' ') -notmatch 'Relatórios commitados e enviados') { exit 1 }
exit 0
