$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding

$root = Split-Path -Parent $PSScriptRoot
$resultsDir = Join-Path $root 'benchmark-results'
$cacheRoot = Join-Path $env:LOCALAPPDATA 'Lia-Code\benchmark-cache'
$modelCache = Join-Path $cacheRoot 'models'
$runtimeDir = Join-Path $cacheRoot 'llama-b11249-vulkan'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$jsonPath = Join-Path $resultsDir "lia-llm-comparison-$stamp.json"
$logPath = Join-Path $resultsDir "lia-llm-comparison-$stamp.log"
$issues = [System.Collections.Generic.List[string]]::new()
$report = [ordered]@{
    schemaVersion = 1
    evaluation = 'cached-cross-family-llm-comparison'
    createdAt = (Get-Date).ToString('o')
    policy = 'Use cached models only; no download or installation is performed.'
    machine = [ordered]@{}
    runtime = [ordered]@{}
    candidates = @()
    notes = @(
        'This is a text-only screening. Human review is required; the script does not choose a winner automatically.',
        'Model files are selected by filename from the Lia-Code cache. No files are removed or modified.',
        'GPU device enumeration and startup logs are evidence, not a measurement of peak VRAM under inference.'
    )
}
New-Item -ItemType Directory -Force -Path $resultsDir | Out-Null
$logLines = [System.Collections.Generic.List[string]]::new()
function Write-RunLog([string]$Message) {
    $safe = $Message
    if ($env:USERPROFILE) { $safe = [regex]::Replace($safe, [regex]::Escape($env:USERPROFILE), '%USERPROFILE%', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase) }
    $logLines.Add($safe)
    Write-Host $safe
}
function Invoke-NativeCapture([string]$Executable, [string[]]$Arguments) {
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& $Executable @Arguments 2>&1 | ForEach-Object { [string]$_ })
        $exitCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = $oldPreference }
    [pscustomobject]@{ ExitCode = $exitCode; Output = $output }
}
function Get-FreePort {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $port = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
    $listener.Stop()
    return $port
}
function Protect-Text([string]$Text) {
    if ($env:USERPROFILE) { return [regex]::Replace($Text, [regex]::Escape($env:USERPROFILE), '%USERPROFILE%', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase) }
    return $Text
}

$cases = @(
    [ordered]@{
        id = 'portugues-natural'
        system = 'Responda em português brasileiro, naturalmente e sem inventar fatos. Seja direta.'
        user = 'Explique em exatamente três frases a diferença entre memória RAM e VRAM, usando uma analogia simples.'
        check = 'Revisão humana: naturalidade em português, precisão e exatamente três frases.'
    },
    [ordered]@{
        id = 'planejamento-com-restricoes'
        system = 'Siga todos os requisitos e responda em português brasileiro.'
        user = 'Distribua 90 minutos entre: responder um e-mail urgente, revisar um pull request importante, começar um relatório que vence hoje e fazer uma pausa/transição. Responda em exatamente quatro linhas numeradas no formato “N min — tarefa — justificativa”; N deve ser um número inteiro de minutos, sem usar horários ou intervalos. Os quatro números precisam somar exatamente 90.'
        check = 'Automático: quatro durações em minutos somando 90. Humano: prioridades e justificativas sensatas.'
    },
    [ordered]@{
        id = 'codigo-python'
        system = 'Responda em português brasileiro. Produza código correto e conciso.'
        user = 'Escreva somar_pares(valores: list[int]) -> int em Python 3 para somar apenas números pares. Inclua três asserts cobrindo lista vazia, valores mistos e números negativos.'
        check = 'Humano: correção, assinatura e cobertura dos três casos.'
    },
    [ordered]@{
        id = 'json-exato'
        system = 'Retorne somente JSON válido, sem markdown nem texto extra.'
        user = 'Retorne um objeto JSON com exatamente estas chaves: "prioridade", "proxima_acao", "risco". Use strings curtas em português. Situação: ainda precisamos comparar a qualidade e o uso de memória de vários LLMs locais.'
        check = 'Automático: JSON válido, chaves exatas e todos os valores string.'
    },
    [ordered]@{
        id = 'nao-inventar-contexto'
        system = 'Se a informação não estiver na conversa, diga claramente que não foi informada. Responda em português brasileiro.'
        user = 'Qual é o nome do meu cachorro e em que cidade ele nasceu?'
        check = 'Humano: não inventar nome, cidade ou lembrança.'
    }
)

$definitions = @(
    [ordered]@{ family = 'Qwen3-4B'; pattern = '(?i)qwen3.*4b.*\.gguf$'; license = 'Apache-2.0'; repo = 'Qwen/Qwen3-4B'; role = 'baseline já testado anteriormente' },
    [ordered]@{ family = 'Qwen3-8B'; pattern = '(?i)qwen3.*8b.*\.gguf$'; license = 'Apache-2.0'; repo = 'Qwen/Qwen3-8B'; role = 'comparação de escala' },
    [ordered]@{ family = 'Phi-4-mini-instruct'; pattern = '(?i)phi[-_. ]?4[-_. ]?mini.*\.gguf$'; license = 'MIT'; repo = 'microsoft/Phi-4-mini-instruct'; role = 'alternativa de outra família, texto' },
    [ordered]@{ family = 'Granite-3.3-2B-Instruct'; pattern = '(?i)granite[-_. ]?3[._-]?3[-_. ]?2b.*\.gguf$'; license = 'Apache-2.0'; repo = 'ibm-granite/granite-3.3-2b-instruct'; role = 'alternativa compacta, texto' },
    [ordered]@{ family = 'Mistral-7B-Instruct-v0.3'; pattern = '(?i)mistral.*7b.*instruct.*\.gguf$'; license = 'Apache-2.0'; repo = 'mistralai/Mistral-7B-Instruct-v0.3'; role = 'alternativa maior, texto' }
)

$serverProc = $null
try {
    Write-RunLog 'Lia-Code — comparação local de LLMs em cache; sem downloads/instalações.'
    if (-not (Test-Path -LiteralPath $modelCache)) { throw 'Cache de modelos Lia-Code não existe; encerrando sem baixar nada.' }
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1
    $computer = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    $report.machine = [ordered]@{
        os = $os.Caption
        osBuild = $os.BuildNumber
        cpu = $cpu.Name.Trim()
        installedRamGiB = [math]::Round($computer.TotalPhysicalMemory / 1GB, 2)
        freeRamGiBAtStart = [math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1MB, 2)
    }
    Write-RunLog "Sistema: $($report.machine.os) | CPU: $($report.machine.cpu) | RAM livre inicial: $($report.machine.freeRamGiBAtStart) GiB"

    $cli = $null
    if (Test-Path -LiteralPath $runtimeDir) {
        $cli = Get-ChildItem -LiteralPath $runtimeDir -Filter 'llama-cli.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    $serverExe = $null
    if (Test-Path -LiteralPath $runtimeDir) {
        $serverExe = Get-ChildItem -LiteralPath $runtimeDir -Filter 'llama-server.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    if (-not $serverExe) { throw 'llama-server não encontrado no runtime Vulkan em cache; encerrando sem instalar.' }
    $versionText = @()
    $deviceText = @()
    if ($cli) {
        $versionResult = Invoke-NativeCapture $cli.FullName @('--version')
        $deviceResult = Invoke-NativeCapture $cli.FullName @('--list-devices')
        $versionText = $versionResult.Output
        $deviceText = $deviceResult.Output
        Write-RunLog "Runtime: $($versionText -join ' | ')"
        $deviceText | ForEach-Object { Write-RunLog $_ }
    }
    $freeVramMiB = $null
    $deviceJoined = $deviceText -join [Environment]::NewLine
    if ($deviceJoined -match '(?i)\(([0-9,]+)\s*MiB,\s*([0-9,]+)\s*MiB\s*free\)') { $freeVramMiB = [int](($Matches[2] -replace ',', '')) }
    $chromeRunning = [bool](Get-Process -Name 'chrome' -ErrorAction SilentlyContinue | Select-Object -First 1)
    $report.runtime = [ordered]@{
        path = Protect-Text $serverExe.FullName
        versionOutput = $versionText
        deviceEnumeration = $deviceText
        reportedFreeVramMiBAtPreflight = $freeVramMiB
        chromeRunningAtPreflight = $chromeRunning
        deviceEnumerationOnly = $true
    }

    $allModels = @(Get-ChildItem -LiteralPath $modelCache -Filter '*.gguf' -File -Recurse -ErrorAction SilentlyContinue)
    foreach ($definition in $definitions) {
        $match = $allModels | Where-Object { $_.Name -match $definition.pattern } |
            Sort-Object @{ Expression = { if ($_.Name -match '(?i)Q4_K_M') { 0 } else { 1 } } }, @{ Expression = { $_.Length } } |
            Select-Object -First 1
        $cachedFileName = $null
        $cachedSizeGiB = $null
        $initialResult = 'not-cached; skipped without download'
        if ($match) {
            $cachedFileName = $match.Name
            $cachedSizeGiB = [math]::Round($match.Length / 1GB, 2)
            $initialResult = 'pending'
        }
        $candidate = [ordered]@{
            family = $definition.family
            repository = $definition.repo
            declaredLicense = $definition.license
            purpose = $definition.role
            cached = [bool]$match
            fileName = $cachedFileName
            sizeGiB = $cachedSizeGiB
            result = $initialResult
            memoryPreflight = $null
            cases = @()
            startupEvidence = @()
            error = $null
        }
        $report.candidates += $candidate
        if (-not $match) {
            Write-RunLog "SKIP $($definition.family): nenhum GGUF correspondente no cache; nada será baixado."
            continue
        }

        $estimatedFileMiB = [math]::Ceiling($match.Length / 1MB)
        $candidate.memoryPreflight = [ordered]@{
            modelFileMiB = $estimatedFileMiB
            reserveMiBForGpuContextAndOtherUse = 2560
            reportedFreeVramMiB = $freeVramMiB
            reserveMiBForSystemRam = 1024
            reportedFreeRamGiB = $report.machine.freeRamGiBAtStart
            chromeRunning = $chromeRunning
            note = 'Conservative screening heuristic only; actual model memory use is taken from runtime startup evidence, not inferred from file size.'
        }
        if ($null -ne $freeVramMiB -and ($estimatedFileMiB + 2560) -gt $freeVramMiB) {
            $candidate.result = 'skipped-memory-headroom'
            $candidate.error = 'Candidate file size plus the 2.5 GiB reserve exceeds the runtime-reported free VRAM; skipped to reduce OOM risk.'
            Write-RunLog "SKIP $($definition.family): arquivo + reserva conservadora excede a VRAM livre enumerada."
            continue
        }
        if ($null -eq $freeVramMiB -and $estimatedFileMiB -gt 3584) {
            $candidate.result = 'skipped-unknown-vram'
            $candidate.error = 'VRAM livre não foi reportada; candidate exceeds the 3.5 GiB conservative file-size limit.'
            Write-RunLog "SKIP $($definition.family): VRAM livre desconhecida e arquivo maior que 3,5 GiB."
            continue
        }
        $freeRamMiB = [math]::Floor($report.machine.freeRamGiBAtStart * 1024)
        if (($estimatedFileMiB + 1024) -gt $freeRamMiB) {
            $candidate.result = 'skipped-system-ram-headroom'
            $candidate.error = 'Candidate file size plus the 1 GiB system reserve exceeds free RAM; skipped to reduce memory pressure.'
            Write-RunLog "SKIP $($definition.family): arquivo + reserva conservadora excede RAM livre."
            continue
        }
        if ($chromeRunning -and $estimatedFileMiB -gt 3584) {
            $candidate.result = 'skipped-chrome-open'
            $candidate.error = 'Chrome is open and this larger candidate is skipped to preserve VRAM headroom.'
            Write-RunLog "SKIP $($definition.family): Chrome aberto e arquivo maior que 3,5 GiB."
            continue
        }
        Write-RunLog "`n===== $($definition.family) | $($match.Name) | $([math]::Round($match.Length / 1GB, 2)) GiB ====="
        $candidate.result = 'tested'
        $port = Get-FreePort
        $stdout = Join-Path $cacheRoot "llm-$($definition.family)-$stamp.stdout.log"
        $stderr = Join-Path $cacheRoot "llm-$($definition.family)-$stamp.stderr.log"
        try {
            $arguments = "-m `"$($match.FullName)`" -ngl 99 --ctx-size 4096 --parallel 1 --host 127.0.0.1 --port $port --no-webui"
            $serverProc = Start-Process -FilePath $serverExe.FullName -ArgumentList $arguments -WorkingDirectory $serverExe.DirectoryName -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
            $ready = $false
            for ($i = 0; $i -lt 180; $i++) {
                $serverProc.Refresh()
                if ($serverProc.HasExited) { throw "llama-server encerrou durante o carregamento (código $($serverProc.ExitCode))." }
                try { $null = Invoke-RestMethod -Uri "http://127.0.0.1:$port/health" -Method Get -TimeoutSec 2; $ready = $true; break }
                catch { Start-Sleep -Seconds 1 }
            }
            if (-not $ready) { throw 'Servidor local não ficou pronto em 180 segundos.' }

            foreach ($case in $cases) {
                $candidateResult = [ordered]@{
                    id = $case.id
                    prompt = $case.user
                    response = $null
                    elapsedSeconds = $null
                    completionTokens = $null
                    finishReason = $null
                    automaticChecks = [ordered]@{}
                    humanReviewGuide = $case.check
                    error = $null
                }
                try {
                    $payload = @{
                        model = $definition.family
                        messages = @(
                            @{ role = 'system'; content = $case.system },
                            @{ role = 'user'; content = $case.user }
                        )
                        temperature = 0.2
                        seed = 42
                        max_tokens = 220
                        stream = $false
                    }
                    if ($definition.family -like 'Qwen3-*') { $payload['chat_template_kwargs'] = @{ enable_thinking = $false } }
                    $body = [System.Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json -Depth 8 -Compress))
                    $timer = [System.Diagnostics.Stopwatch]::StartNew()
                    $response = Invoke-RestMethod -Uri "http://127.0.0.1:$port/v1/chat/completions" -Method Post -Body $body -ContentType 'application/json; charset=utf-8' -TimeoutSec 180
                    $timer.Stop()
                    $text = [string]$response.choices[0].message.content
                    $candidateResult.response = Protect-Text $text
                    $candidateResult.elapsedSeconds = [math]::Round($timer.Elapsed.TotalSeconds, 2)
                    $candidateResult.finishReason = [string]$response.choices[0].finish_reason
                    try { $candidateResult.completionTokens = [int]$response.usage.completion_tokens } catch {}
                    if ($case.id -eq 'planejamento-com-restricoes') {
                        $durations = @([regex]::Matches($text, '(?im)^\s*(?:\*\*)?\d+[.)][^\r\n]*?(\d+)\s*(?:minutos?|min)\b') | ForEach-Object { [int]$_.Groups[1].Value })
                        $sum = 0; if ($durations.Count -gt 0) { $sum = ($durations | Measure-Object -Sum).Sum }
                        $candidateResult.automaticChecks = [ordered]@{ durationCount = $durations.Count; durationsMinutes = $durations; totalIs90 = ($durations.Count -eq 4 -and $sum -eq 90) }
                    } elseif ($case.id -eq 'json-exato') {
                        try {
                            $parsed = ConvertFrom-Json -InputObject $text -ErrorAction Stop
                            $keys = @($parsed.PSObject.Properties.Name | Sort-Object)
                            $expected = @('prioridade', 'proxima_acao', 'risco')
                            $expected = @($expected | Sort-Object)
                            $allStrings = $true; foreach ($key in $expected) { if ($parsed.$key -isnot [string]) { $allStrings = $false } }
                            $candidateResult.automaticChecks = [ordered]@{ jsonValid = $true; exactKeys = (($keys -join '|') -eq ($expected -join '|')); valuesAreStrings = $allStrings }
                        } catch { $candidateResult.automaticChecks = [ordered]@{ jsonValid = $false; exactKeys = $false; valuesAreStrings = $false } }
                    }
                    Write-RunLog "$($case.id): $($candidateResult.elapsedSeconds)s; tokens=$($candidateResult.completionTokens); finish=$($candidateResult.finishReason)"
                    Write-RunLog (Protect-Text $text)
                    if ($case.id -in @('planejamento-com-restricoes','json-exato')) { Write-RunLog ("Checagens: " + ($candidateResult.automaticChecks | ConvertTo-Json -Compress)) }
                } catch {
                    $candidateResult.error = $_.Exception.Message
                    $candidate.result = 'partial-inference-error'
                    $issues.Add("$($definition.family)/$($case.id): $($_.Exception.Message)")
                    Write-RunLog "ERRO $($definition.family)/$($case.id): $($_.Exception.Message)"
                }
                $candidate.cases += $candidateResult
            }
        } catch {
            $candidate.result = 'load-or-inference-failed'
            $candidate.error = $_.Exception.Message
            $issues.Add("$($definition.family): $($_.Exception.Message)")
            Write-RunLog "ERRO $($definition.family): $($_.Exception.Message)"
        } finally {
            if ($serverProc) {
                try { $serverProc.Refresh(); if (-not $serverProc.HasExited) { Stop-Process -Id $serverProc.Id -Force -ErrorAction SilentlyContinue; [void]$serverProc.WaitForExit(5000) } } catch {}
                $serverProc = $null
            }
            foreach ($diagnostic in @($stdout, $stderr)) {
                try {
                    if ($diagnostic -and (Test-Path -LiteralPath $diagnostic)) {
                        $candidate.startupEvidence += @(Get-Content -LiteralPath $diagnostic -ErrorAction SilentlyContinue | Where-Object { $_ -match '(?i)Vulkan|offload|device|GPU|layer|buffer|memory|load|tensor|weight|model' } | ForEach-Object { Protect-Text ([string]$_) })
                    }
                } catch {}
            }
        }
    }
    $ran = @($report.candidates | Where-Object { $_.result -eq 'tested' -and $_.cases.Count -gt 0 }).Count
    if ($ran -eq 0) { $report.notes += 'Nenhum candidato em cache pôde ser avaliado. O relatório lista o que falta; não foi feito download.' }
    $report.notes += 'As medições de tempo são de ponta a ponta por prompt e variam com carga do sistema. Revisar manualmente todas as respostas antes de escolher o LLM-base.'
} catch {
    $issues.Add($_.Exception.Message)
    $report.notes += "Preflight/evaluation error: $($_.Exception.Message)"
    Write-RunLog "ERRO: $($_.Exception.Message)"
} finally {
    if ($serverProc) {
        try { $serverProc.Refresh(); if (-not $serverProc.HasExited) { Stop-Process -Id $serverProc.Id -Force -ErrorAction SilentlyContinue; [void]$serverProc.WaitForExit(5000) } } catch {}
    }
}

$report | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
$logLines | Set-Content -LiteralPath $logPath -Encoding UTF8
Write-Host "`nRelatórios locais: $jsonPath`n$logPath"

$gitSummary = [System.Collections.Generic.List[string]]::new()
$pushedLocation = $false
try {
    Push-Location $root
    $pushedLocation = $true
    $branch = (& git branch --show-current 2>$null).Trim()
    if ($branch -ne 'arena/01a0ec89-lia-code') { throw "Branch inválida para envio automático: '$branch'." }
    & git diff --cached --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Há alterações staged; recusando commit automático.' }
    & git add -f -- "benchmark-results/$(Split-Path -Leaf $jsonPath)" "benchmark-results/$(Split-Path -Leaf $logPath)"
    if ($LASTEXITCODE -ne 0) { throw 'git add dos relatórios falhou.' }
    & git commit -m "Add cross-family LLM comparison report $stamp"
    if ($LASTEXITCODE -ne 0) { throw 'git commit dos relatórios falhou.' }
    & git push origin arena/01a0ec89-lia-code
    if ($LASTEXITCODE -ne 0) { throw 'git push dos relatórios falhou; eles permanecem locais.' }
    $gitSummary.Add('Relatórios commitados e enviados para arena/01a0ec89-lia-code.')
} catch { $gitSummary.Add("Envio automático não concluído: $($_.Exception.Message)") }
finally { if ($pushedLocation) { Pop-Location } }
Write-Host ($gitSummary -join [Environment]::NewLine)
if ($issues.Count -gt 0 -or ($gitSummary -join ' ') -notmatch 'Relatórios commitados e enviados') { exit 1 }
exit 0
