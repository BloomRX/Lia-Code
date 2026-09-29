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
    createdAt = (Get-Date).ToString('o')
    machine = [ordered]@{}
    software = [ordered]@{}
    accelerators = @()
    runtimes = [ordered]@{}
    notes = @()
}

$rawLogPath = Join-Path $env:TEMP "lia-benchmark-raw-$stamp.log"
Start-Transcript -Path $rawLogPath -Force | Out-Null
try {
    Write-Host 'Lia-Code - diagnóstico inicial de benchmark' -ForegroundColor Cyan
    Write-Host 'Nenhum modelo será baixado ou instalado.'
    Write-Host 'Coletando informações do sistema...'

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
    $report.runtimes.llamaCpp = $foundLlama
    if (-not ($foundLlama.Values | Where-Object { $_ })) {
        $report.notes += 'llama.cpp não foi encontrado no PATH; o teste inicial apenas identifica hardware e software. Nenhum modelo foi executado.'
    }

    $report.notes += 'VRAM via WMI pode estar ausente ou incorreta; será validada com ferramentas do runtime escolhido.'
    $report.notes += 'Este é o benchmark de reconhecimento do ambiente (fase 0), não um teste comparativo de qualidade/velocidade de LLM.'

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
