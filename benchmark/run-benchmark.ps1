$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

$root = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $root 'benchmark-results'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logPath = Join-Path $outDir "lia-benchmark-$stamp.log"
$reportPath = Join-Path $outDir "lia-benchmark-$stamp.json"
$issues = [System.Collections.Generic.List[string]]::new()
$report = [ordered]@{
    schemaVersion = 1
    evaluation = 'omni-runtime-preflight'
    createdAt = (Get-Date).ToString('o')
    machine = [ordered]@{}
    software = [ordered]@{}
    accelerators = @()
    runtimes = [ordered]@{}
    omniReadiness = [ordered]@{
        stage = 'preflight-only; no model downloaded or executed'
        referenceCandidate = 'Qwen2.5-Omni-3B (not selected)'
        declaredInputs = @('text', 'image', 'audio', 'video')
        declaredOutputs = @('text', 'speech')
        officialBf16MinimumVramGiBFor15SecondVideo = 18.38
        statedActualUsageMultiplierAtLeast = 1.2
        memoryReferenceSource = 'https://github.com/QwenLM/Qwen2.5-Omni#minimum-gpu-memory-requirements'
        targetGpuVramGiB = 8
        quantizedRuntimeVerified = $false
        modelSpecificMultimodalSupportVerified = $false
        cachedOmniAssets = @()
    }
    notes = @()
}

$rawLogPath = Join-Path $env:TEMP "lia-benchmark-raw-$stamp.log"
Start-Transcript -Path $rawLogPath -Force | Out-Null
try {
    Write-Host 'Lia-Code - preflight de viabilidade Omni' -ForegroundColor Cyan
    Write-Host 'Nenhum modelo será baixado, instalado ou executado nesta etapa.'
    Write-Host 'Coletando hardware, runtimes, dispositivos enumerados e modelos Omni já existentes...'

    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1
    $computer = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    $report.machine = [ordered]@{
        os = $os.Caption
        osVersion = $os.Version
        osBuild = $os.BuildNumber
        architecture = $env:PROCESSOR_ARCHITECTURE
        cpu = $cpu.Name.Trim()
        cpuCores = $cpu.NumberOfCores
        cpuLogicalProcessors = $cpu.NumberOfLogicalProcessors
        installedRamGiB = [math]::Round($computer.TotalPhysicalMemory / 1GB, 2)
        freeRamGiBAtStart = [math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1MB, 2)
    }

    $gpus = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue)
    foreach ($gpu in $gpus) {
        $vram = $null
        if ($gpu.AdapterRAM -and $gpu.AdapterRAM -gt 0) { $vram = [math]::Round($gpu.AdapterRAM / 1GB, 2) }
        $report.accelerators += [ordered]@{
            name = $gpu.Name
            driverVersion = $gpu.DriverVersion
            driverDate = $gpu.DriverDate
            reportedVramGiB = $vram
            videoProcessor = $gpu.VideoProcessor
        }
    }

    $python = Get-Command python -ErrorAction SilentlyContinue
    $git = Get-Command git -ErrorAction SilentlyContinue
    $ollama = Get-Command ollama -ErrorAction SilentlyContinue
    $report.software = [ordered]@{
        powershell = $PSVersionTable.PSVersion.ToString()
        pythonDetected = [bool]$python
        gitDetected = [bool]$git
        ollamaDetected = [bool]$ollama
        dxdiag = Test-Path "$env:WINDIR\System32\dxdiag.exe"
    }

    Write-Host "`nSistema: $($report.machine.os) (build $($report.machine.osBuild))"
    Write-Host "CPU: $($report.machine.cpu) | RAM: $($report.machine.installedRamGiB) GiB"
    if ($gpus.Count -eq 0) { $issues.Add('Nenhum adaptador gráfico foi encontrado via WMI.') }
    foreach ($gpu in $report.accelerators) {
        Write-Host "GPU: $($gpu.name) | Driver: $($gpu.driverVersion) | VRAM reportada: $($gpu.reportedVramGiB) GiB"
    }

    if ($ollama) {
        Write-Host "`nOllama detectado. Consultando modelos já instalados (sem baixar nada)..."
        $ollamaList = (& ollama list 2>&1 | Out-String).Trim()
        Write-Host $ollamaList
        $report.runtimes.ollama = [ordered]@{ detected = $true; localModels = $ollamaList }
    } else {
        $report.runtimes.ollama = [ordered]@{ detected = $false; localModels = $null }
        Write-Host "`nOllama não encontrado. Nenhum runtime será instalado nesta etapa."
    }

    $llamaCommands = @('llama-cli', 'llama-bench', 'llama-server')
    $foundLlama = @{}
    foreach ($name in $llamaCommands) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        $foundLlama[$name] = [bool]$cmd
    }
    $cacheRoot = Join-Path $env:LOCALAPPDATA 'Lia-Code\benchmark-cache'
    $cachedRuntime = Join-Path $cacheRoot 'llama-b11249-vulkan'
    $modelCache = Join-Path $cacheRoot 'models'
    $cachedCli = $null
    if (Test-Path -LiteralPath $cachedRuntime) {
        $cachedCli = Get-ChildItem -LiteralPath $cachedRuntime -Filter 'llama-cli.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    $cliCommand = Get-Command 'llama-cli' -ErrorAction SilentlyContinue
    $cliPath = if ($cachedCli) { $cachedCli.FullName } elseif ($cliCommand) { $cliCommand.Source } else { $null }
    $versionOutput = @()
    $versionExit = $null
    $deviceOutput = @()
    $deviceExit = $null
    if ($cliPath) {
        Write-Host "`nEnumerando os dispositivos vistos pelo llama.cpp (sem carregar modelo)..."
        $versionOutput = @(& $cliPath --version 2>&1 | ForEach-Object { [string]$_ })
        $versionExit = $LASTEXITCODE
        $deviceOutput = @(& $cliPath --list-devices 2>&1 | ForEach-Object { [string]$_ })
        $deviceExit = $LASTEXITCODE
        $deviceOutput | ForEach-Object { Write-Host $_ }
    }
    $deviceText = $deviceOutput -join [Environment]::NewLine
    $report.runtimes.llamaCpp = [ordered]@{
        commandsOnPath = $foundLlama
        cachedVulkanRuntimeFound = [bool]$cachedCli
        cliExecutableFound = [bool]$cliPath
        versionExitCode = $versionExit
        versionOutput = $versionOutput
        listDevicesExitCode = $deviceExit
        listDevicesOutput = $deviceOutput
        vulkanDeviceListed = [bool]($deviceText -match '(?i)Vulkan')
    }
    if (-not $cliPath) {
        $report.notes += 'llama-cli não foi encontrado nem no cache Lia-Code nem no PATH; dispositivos Vulkan não puderam ser enumerados.'
    } elseif ($deviceExit -ne 0) {
        $report.notes += 'llama-cli --list-devices falhou; o preflight não confirma backends Vulkan.'
    } else {
        $report.notes += 'A enumeração lista dispositivos disponíveis; não comprova que um modelo multimodal específico seja suportado ou caiba na VRAM.'
    }

    $cachedOmniAssets = @()
    if (Test-Path -LiteralPath $modelCache) {
        $cachedOmniAssets = @(Get-ChildItem -LiteralPath $modelCache -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '(?i)omni' } |
            Select-Object @{Name='fileName';Expression={$_.Name}}, @{Name='sizeGiB';Expression={[math]::Round($_.Length / 1GB, 2)}})
    }
    $report.omniReadiness.cachedOmniAssets = $cachedOmniAssets
    try {
        $cacheDrive = [System.IO.DriveInfo]::new([System.IO.Path]::GetPathRoot($cacheRoot))
        $report.omniReadiness.cacheFreeSpaceGiB = [math]::Round($cacheDrive.AvailableFreeSpace / 1GB, 2)
    } catch { $report.omniReadiness.cacheFreeSpaceGiB = $null }
    $report.omniReadiness.runtimeDeviceEnumeration = $deviceOutput
    $report.omniReadiness.vulkanDeviceListed = [bool]($deviceText -match '(?i)Vulkan')

    if ($ollama -and $ollamaList) {
        $ollamaOmni = @($ollamaList -split '[\r\n]+' | Where-Object { $_ -match '(?i)omni' })
        if ($ollamaOmni.Count -gt 0) { $report.omniReadiness.cachedOmniAssets += @($ollamaOmni) }
    }
    $report.notes += 'VRAM via WMI pode estar ausente ou incorreta; a enumeração Vulkan informa dispositivos, não memória livre nem offload real.'
    $report.notes += 'Este preflight não baixa nem executa modelos e não verifica processamento de imagem, áudio, vídeo ou geração de voz.'

    $json = $report | ConvertTo-Json -Depth 8
    Set-Content -LiteralPath $reportPath -Value $json -Encoding UTF8
    Write-Host "`nConcluído. Arquivos gerados:" -ForegroundColor Green
    Write-Host "  Log:     $logPath"
    Write-Host "  Relatório: $reportPath"
    Write-Host 'Envie os dois arquivos para investigarmos o próximo passo.'
} catch {
    $issues.Add($_.Exception.Message)
    Write-Host "ERRO: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace
} finally {
    if ($issues.Count -gt 0) {
        try {
            $report.notes += @($issues | ForEach-Object { "ERRO: $_" })
            $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8
        } catch {}
    }
    Stop-Transcript | Out-Null
    try {
        $safeLog = Get-Content -LiteralPath $rawLogPath -Raw
        if ($env:USERPROFILE) { $safeLog = [regex]::Replace($safeLog, [regex]::Escape($env:USERPROFILE), '%USERPROFILE%', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase) }
        if ($env:COMPUTERNAME) { $safeLog = [regex]::Replace($safeLog, [regex]::Escape($env:COMPUTERNAME), '[redacted-host]', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase) }
        $safeLog = [regex]::Replace($safeLog, '(?m)^(Nome de Usuário|Executar como Usuário):.*$', '$1: [redacted]')
        $safeLog = [regex]::Replace($safeLog, '(?m)^Computador:.*$', 'Computador: [redacted]')
        Set-Content -LiteralPath $logPath -Value $safeLog -Encoding UTF8
    } finally { Remove-Item -LiteralPath $rawLogPath -Force -ErrorAction SilentlyContinue }
}

# Submit only these generated report files, and only from the session's designated branch.
# Refuse to commit if the user already has staged changes, so unrelated work is never included.
$gitSummary = @()
$gitCommand = Get-Command git -ErrorAction SilentlyContinue
if ($gitCommand) {
    Push-Location $root
    try {
        $branch = (& git branch --show-current 2>&1 | Out-String).Trim()
        if ($branch -ne 'arena/01a0ec89-lia-code') {
            $gitSummary += "AUTO-PUSH ignorado: branch atual '$branch' não é arena/01a0ec89-lia-code."
        } else {
            & git diff --cached --quiet
            if ($LASTEXITCODE -ne 0) {
                $gitSummary += 'AUTO-PUSH ignorado: há alterações já staged no repositório; faça submit manual para evitar incluir arquivos alheios.'
            } else {
                & git add -f -- $logPath $reportPath 2>&1 | ForEach-Object { $gitSummary += [string]$_ }
                if ($LASTEXITCODE -ne 0) { throw 'git add falhou.' }
                & git commit -m "Add local benchmark report $stamp" 2>&1 | ForEach-Object { $gitSummary += [string]$_ }
                if ($LASTEXITCODE -ne 0) { throw 'git commit falhou.' }
                & git push origin arena/01a0ec89-lia-code 2>&1 | ForEach-Object { $gitSummary += [string]$_ }
                if ($LASTEXITCODE -ne 0) { throw 'git push falhou. Os relatórios continuam salvos localmente.' }
                $gitSummary += 'Relatórios commitados e enviados para origin/arena/01a0ec89-lia-code.'
            }
        }
    } catch {
        $gitSummary += "AUTO-PUSH falhou: $($_.Exception.Message)"
    } finally {
        Pop-Location
    }
} else {
    $gitSummary += 'AUTO-PUSH indisponível: Git não está instalado ou não está no PATH.'
}

Add-Content -LiteralPath $logPath -Value ($gitSummary -join [Environment]::NewLine)
Write-Host "`n$($gitSummary -join [Environment]::NewLine)"

if ($issues.Count -gt 0) {
    Write-Host "`nOcorreu um problema. O log foi salvo em: $logPath" -ForegroundColor Yellow
    exit 1
}
exit 0
