param(
    [ValidateSet('4B', '8B')]
    [string]$ModelVariant = '4B'
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding
$root = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $root 'benchmark-results'
$cache = Join-Path $env:LOCALAPPDATA 'Lia-Code\benchmark-cache'
if ($ModelVariant -eq '8B') {
    $modelName = 'Qwen_Qwen3-8B-Q4_K_M.gguf'
    $modelRepo = 'bartowski/Qwen_Qwen3-8B-GGUF'
    $modelRevision = '9338057cea2b55fad29c435822e9f1a45482ef04'
    $minimumModelBytes = [long](4.5 * 1GB)
    $minimumFreeBytes = 7GB
    $modelUrl = 'https://huggingface.co/bartowski/Qwen_Qwen3-8B-GGUF/resolve/{0}/{1}?download=true' -f $modelRevision, $modelName
} else {
    $modelName = 'Qwen_Qwen3-4B-Instruct-2507-Q4_K_M.gguf'
    $modelRepo = 'bartowski/Qwen_Qwen3-4B-Instruct-2507-GGUF'
    $modelRevision = '5ba9dff45461e5bab86959be7d585609fe9e6bc3'
    $minimumModelBytes = 2.2GB
    $minimumFreeBytes = 5GB
    $modelUrl = 'https://huggingface.co/bartowski/Qwen_Qwen3-4B-Instruct-2507-GGUF/resolve/{0}/{1}?download=true' -f $modelRevision, $modelName
}
$modelPath = Join-Path (Join-Path $cache 'models') $modelName
$runtimeDir = Join-Path $cache 'llama-b11249-vulkan'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logPath = Join-Path $outDir "lia-quality-$stamp.log"
$jsonPath = Join-Path $outDir "lia-quality-$stamp.json"
$reasoningMode = if ($ModelVariant -eq '8B') { 'disabled via chat_template_kwargs' } else { 'model default' }
$serverStdout = Join-Path $cache "quality-server-$stamp.stdout.log"
$serverStderr = Join-Path $cache "quality-server-$stamp.stderr.log"
$report = [ordered]@{
    schemaVersion = 1
    createdAt = (Get-Date).ToString('o')
    model = [ordered]@{ variant = $ModelVariant; name = $modelName; repository = $modelRepo; revision = $modelRevision; quantization = 'Q4_K_M'; license = 'Apache-2.0 (upstream Qwen3)' }
    runtime = [ordered]@{ name = 'llama.cpp Vulkan'; release = 'b11249' }
    generation = [ordered]@{ gpuLayers = 99; contextTokens = 4096; temperature = 0.2; seed = 42; maxTokens = 300; reasoningMode = $reasoningMode }
    cases = @()
    scoringGuide = @(
        'Avalie cada critério de 1 a 5; esta rodada coleta evidência, não produz um placar automático subjetivo.',
        'Casual: português natural, Tsundere leve sem hostilidade, resposta acolhedora e sem inventar memória/vida real.',
        'Sério: priorização correta, plano executável, tom profissional e sem brincadeiras.',
        'Código: correção da soma de pares, anotação/tipo solicitados, exemplos de teste úteis e clareza.',
        'Instruções/JSON: JSON parseável, exatamente as chaves pedidas, valores corretos, sem texto extra.'
    )
    notes = @('As saídas são respostas do modelo para prompts fixos. A revisão de tom/correção deve ser humana; somente o JSON tem validação automática.')
}
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
[System.IO.File]::WriteAllText($logPath, "Lia-Code quality evaluation | $stamp`r`n", [System.Text.UTF8Encoding]::new($false))
function Protect-String([string]$Text) {
    if ($env:USERPROFILE) { $Text = [regex]::Replace($Text, [regex]::Escape($env:USERPROFILE), '%USERPROFILE%', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase) }
    return $Text
}
function Write-RunLog([string]$Message) {
    $safe = Protect-String $Message
    Write-Host $safe
    Add-Content -LiteralPath $logPath -Value $safe -Encoding UTF8
}
function Invoke-NativeCapture([string]$Executable, [string[]]$Arguments) {
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $lines = @(& $Executable @Arguments 2>&1 | ForEach-Object { [string]$_ })
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previousPreference }
    [pscustomobject]@{ ExitCode = $code; Output = $lines }
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
$serverProc = $null
$failed = $false
$stage = 'preflight'
try {
    Write-RunLog "Lia-Code - avaliação qualitativa local ($ModelVariant Q4_K_M)"
    if ((Test-Path $modelPath) -and ((Get-Item -LiteralPath $modelPath).Length -lt $minimumModelBytes)) {
        Remove-Item -LiteralPath $modelPath -Force
        Write-RunLog 'Removido download parcial do modelo da tentativa anterior.'
    }
    if (-not (Test-Path $modelPath)) {
        if ($ModelVariant -eq '4B') { throw 'Modelo Q4_K_M de 4B não encontrado no cache. Rode Update-Lia.bat speed primeiro.' }
        $drive = [System.IO.DriveInfo]::new([System.IO.Path]::GetPathRoot($cache))
        if ($drive.AvailableFreeSpace -lt $minimumFreeBytes) { throw 'São necessários pelo menos 7 GiB livres para baixar o modelo 8B.' }
        $answer = Read-Host 'O modelo 8B ocupa cerca de 5,03 GB. Digite S para baixar; outra resposta cancela'
        if ($answer -notmatch '^(s|sim|y|yes)$') { throw 'Download do candidato 8B cancelado pelo usuário.' }
        $stage = 'download candidate 8B from Hugging Face'
        Write-RunLog "Baixando $modelName de $modelRepo (revisão fixada)..."
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $modelPath) | Out-Null
        Invoke-WebRequest -Uri $modelUrl -OutFile $modelPath -UseBasicParsing
    }
    if ((Get-Item -LiteralPath $modelPath).Length -lt $minimumModelBytes) { throw "Arquivo do modelo menor que o limite esperado ($minimumModelBytes bytes); possível download incompleto." }
    $serverExe = Get-ChildItem -LiteralPath $runtimeDir -Filter 'llama-server.exe' -Recurse | Select-Object -First 1
    if (-not $serverExe) { throw 'llama-server.exe não encontrado no runtime em cache.' }

    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $port = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
    $listener.Stop()
    $serverArgs = "-m `"$modelPath`" -ngl 99 --ctx-size 4096 --parallel 1 --host 127.0.0.1 --port $port --no-webui"
    Write-RunLog "Iniciando servidor local apenas em 127.0.0.1:$port com offload Vulkan."
    $serverProc = Start-Process -FilePath $serverExe.FullName -ArgumentList $serverArgs -WorkingDirectory $serverExe.DirectoryName -PassThru -WindowStyle Hidden -RedirectStandardOutput $serverStdout -RedirectStandardError $serverStderr

    $stage = 'wait for local model server'
    $ready = $false
    for ($i = 0; $i -lt 240; $i++) {
        if ($serverProc.HasExited) { throw "llama-server encerrou cedo (código $($serverProc.ExitCode))." }
        try {
            $health = Invoke-RestMethod -Uri "http://127.0.0.1:$port/health" -Method Get -TimeoutSec 2
            $ready = $true
            break
        } catch { Start-Sleep -Seconds 1 }
    }
    if (-not $ready) { throw 'llama-server não ficou pronto em 240 segundos.' }
    Write-RunLog 'Servidor pronto; enviando quatro casos fixos de avaliação.'

    $cases = @(
        [ordered]@{
            id = 'casual-tsundere'
            mode = 'Casual'
            system = 'Você é Lia, uma assistente de desktop que conversa em português brasileiro. Neste modo Casual, seja divertida, calorosa e levemente tsundere: provoque com carinho, sem humilhar ou ser hostil. Não diga que tem sentimentos reais, consciência ou lembranças que não foram fornecidas. Responda em 2 a 4 frases.'
            user = 'Consegui fazer o primeiro benchmark da minha RX 580 funcionar, e a GPU ficou bem mais rápida que a CPU. Como você reagiria?'
            rubric = @('Tom casual brasileiro e personalidade perceptível, sem exagerar.', 'Reage ao resultado específico sem afirmar que lembra de conversas passadas.', 'Resposta breve, útil e sem grosseria.')
        },
        [ordered]@{
            id = 'serio-priorizacao'
            mode = 'Sério'
            system = 'Você é Lia no Modo Sério. Responda em português brasileiro, de forma profissional, objetiva e sem piadas ou flerte. Não invente fatos. Responda em até 90 palavras.'
            user = 'Tenho 90 minutos. Faça um plano em exatamente quatro linhas numeradas que some 90 minutos: responder e-mail urgente, revisar pull request importante, começar relatório que vence hoje e reservar uma pequena pausa/transição. Para cada linha, dê o tempo e uma justificativa curta.'
            rubric = @('Prioriza o item urgente e/ou o prazo mais próximo de forma sensata.', 'Plano cabe em 90 minutos e reserva algum tempo para transições.', 'Tom sério, claro e sem brincadeira.')
        },
        [ordered]@{
            id = 'codigo-python'
            mode = 'Trabalho / programação'
            system = 'Você é uma assistente técnica. Responda em português brasileiro. Seja precisa e não inclua dependências desnecessárias.'
            user = 'Escreva uma função Python 3 chamada somar_pares(valores: list[int]) -> int que some apenas os números pares. Inclua três asserts que cubram lista vazia, valores mistos e números negativos. Mostre código executável.'
            rubric = @('A função soma apenas inteiros pares e retorna zero para lista vazia.', 'Anotação de tipo e nome pedidos estão corretos.', 'Três asserts cobrem os casos pedidos; verificar manualmente se passam.')
        },
        [ordered]@{
            id = 'json-instructions'
            mode = 'Seguimento de instruções'
            system = 'Siga exatamente o formato pedido pelo usuário. Não inclua markdown, comentários ou texto antes/depois do JSON.'
            user = 'Retorne exatamente um objeto JSON válido com somente estas três chaves: "prioridade", "proxima_acao" e "risco". Use valores string curtos em português. Situação: o benchmark já confirmou que a RX 580 acelera geração local, mas a qualidade das respostas ainda não foi avaliada.'
            rubric = @('O conteúdo precisa ser JSON válido sem prefixo/sufixo.', 'As únicas chaves devem ser prioridade, proxima_acao e risco.', 'Os valores devem refletir corretamente a situação dada.')
        }
    )

    foreach ($case in $cases) {
        $stage = "quality case $($case.id)"
        Write-RunLog "`n=== Caso: $($case.id) | modo: $($case.mode) ==="
        $payload = @{
            model = 'local-qwen3-4b'
            messages = @(
                @{ role = 'system'; content = $case.system },
                @{ role = 'user'; content = $case.user }
            )
            temperature = 0.2
            seed = 42
            max_tokens = 300
            stream = $false
        }
        if ($ModelVariant -eq '8B') { $payload['chat_template_kwargs'] = @{ enable_thinking = $false } }
        $payloadJson = $payload | ConvertTo-Json -Depth 8 -Compress
        $body = [System.Text.Encoding]::UTF8.GetBytes($payloadJson)
        $timer = [System.Diagnostics.Stopwatch]::StartNew()
        $response = Invoke-RestMethod -Uri "http://127.0.0.1:$port/v1/chat/completions" -Method Post -Body $body -ContentType 'application/json; charset=utf-8' -TimeoutSec 180
        $timer.Stop()
        $text = [string]$response.choices[0].message.content
        $finishReason = [string]$response.choices[0].finish_reason
        $thinkingContentPresent = $false
        try { $thinkingContentPresent = -not [string]::IsNullOrWhiteSpace([string]$response.choices[0].message.reasoning_content) } catch {}
        $tokens = $null
        try { $tokens = [int]$response.usage.completion_tokens } catch {}
        $tokenCapReached = ($null -ne $tokens) -and ($tokens -ge 300)
        $autoCheck = [ordered]@{ jsonValid = $null; exactExpectedKeys = $null; allValuesStrings = $null; scheduleLineCount = $null; scheduleDurationsMinutes = $null; scheduleTotals90 = $null }
        if ($case.id -eq 'serio-priorizacao') {
            $durationMatches = [regex]::Matches($text, '(?im)^\s*(?:\*\*)?\d+[.)][^\r\n]*?(\d+)\s*(?:minutos?|min)\b')
            $durations = @($durationMatches | ForEach-Object { [int]$_.Groups[1].Value })
            $sum = 0
            if ($durations.Count -gt 0) { $sum = ($durations | Measure-Object -Sum).Sum }
            $autoCheck.scheduleLineCount = $durationMatches.Count
            $autoCheck.scheduleDurationsMinutes = $durations
            $autoCheck.scheduleTotals90 = ($durationMatches.Count -eq 4 -and $sum -eq 90)
        }
        if ($case.id -eq 'json-instructions') {
            try {
                $parsed = ConvertFrom-Json -InputObject $text -ErrorAction Stop
                $keys = @($parsed.PSObject.Properties.Name | Sort-Object)
                $expected = @('prioridade', 'proxima_acao', 'risco')
                $expected = @($expected | Sort-Object)
                $autoCheck.jsonValid = $true
                $autoCheck.exactExpectedKeys = (($keys -join '|') -eq ($expected -join '|'))
                $autoCheck.allValuesStrings = $true
                foreach ($key in $expected) { if ($parsed.$key -isnot [string]) { $autoCheck.allValuesStrings = $false } }
            } catch { $autoCheck.jsonValid = $false; $autoCheck.exactExpectedKeys = $false; $autoCheck.allValuesStrings = $false }
        }
        $item = [ordered]@{
            id = $case.id
            mode = $case.mode
            systemPrompt = $case.system
            userPrompt = $case.user
            response = Protect-String $text
            elapsedSeconds = [math]::Round($timer.Elapsed.TotalSeconds, 2)
            completionTokens = $tokens
            finishReason = $finishReason
            tokenCapReached = $tokenCapReached
            emptyResponse = [string]::IsNullOrWhiteSpace($text)
            reasoningContentPresent = $thinkingContentPresent
            automaticChecks = $autoCheck
            rubric = $case.rubric
            humanScore = $null
        }
        $report.cases += $item
        Write-RunLog ("Tempo: {0:N2}s | tokens reportados: {1} | finish: {2} | limite atingido: {3} | resposta vazia: {4} | canal de raciocínio presente: {5}" -f $item.elapsedSeconds, $tokens, $finishReason, $tokenCapReached, $item.emptyResponse, $thinkingContentPresent)
        Write-RunLog 'Resposta:'
        Write-RunLog $text
        if ($case.id -eq 'serio-priorizacao') { Write-RunLog "Linhas de agenda com minutos: $($autoCheck.scheduleLineCount); durações: $($autoCheck.scheduleDurationsMinutes -join ', '); soma 90: $($autoCheck.scheduleTotals90)" }
        if ($case.id -eq 'json-instructions') { Write-RunLog "JSON parseável: $($autoCheck.jsonValid); chaves exatas: $($autoCheck.exactExpectedKeys); valores string: $($autoCheck.allValuesStrings)" }
    }
    $report.notes += 'Servidor parado ao final; API ficou vinculada somente ao loopback 127.0.0.1.'
} catch {
    $failed = $true
    $detail = $_.Exception.Message
    $report.notes += "ERROR during ${stage}: $detail"
    Write-RunLog "ERRO durante ${stage}: $detail"
    foreach ($diagnostic in @($serverStdout, $serverStderr)) {
        if (Test-Path $diagnostic) {
            Write-RunLog "Detalhes do servidor ($([IO.Path]::GetFileName($diagnostic))):"
            Get-Content -LiteralPath $diagnostic -Tail 30 -ErrorAction SilentlyContinue | ForEach-Object { Write-RunLog $_ }
        }
    }
} finally {
    if ($serverProc) {
        try {
            $serverProc.Refresh()
            if (-not $serverProc.HasExited) { Stop-Process -Id $serverProc.Id -Force -ErrorAction SilentlyContinue; [void]$serverProc.WaitForExit(5000) }
        } catch {}
    }
    $startupEvidence = @()
    foreach ($diagnostic in @($serverStdout, $serverStderr)) {
        try {
            if (Test-Path $diagnostic) {
                $startupEvidence += @(Get-Content -LiteralPath $diagnostic -ErrorAction SilentlyContinue | Where-Object { $_ -match '(?i)Vulkan|offload|device|GPU|layer' } | ForEach-Object { Protect-String ([string]$_) })
            }
        } catch {}
    }
    $report.serverStartupEvidence = $startupEvidence
    $startupEvidence | ForEach-Object { Write-RunLog $_ }
    try { $report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonPath -Encoding UTF8 } catch { $failed = $true; Write-RunLog "Falha ao gravar JSON: $($_.Exception.Message)" }
}

$gitSummary = @()
$locationPushed = $false
try {
    Push-Location $root
    $locationPushed = $true
    $branchResult = Invoke-GitSafe @('branch', '--show-current')
    $branch = ($branchResult.Output -join '').Trim()
    if ($branchResult.ExitCode -ne 0 -or $branch -ne 'arena/01a0ec89-lia-code') { throw "Branch inválida para auto-submit: '$branch'." }
    $staged = Invoke-GitSafe @('diff', '--cached', '--quiet')
    if ($staged.ExitCode -ne 0) { throw 'Há alterações staged; recusando commit automático para proteger outros arquivos.' }
    $relLog = "benchmark-results/$(Split-Path -Leaf $logPath)"
    $relJson = "benchmark-results/$(Split-Path -Leaf $jsonPath)"
    $addResult = Invoke-GitSafe @('add', '-f', '--', $relLog, $relJson)
    $gitSummary += $addResult.Output
    if ($addResult.ExitCode -ne 0) { throw 'git add dos relatórios falhou.' }
    $commitResult = Invoke-GitSafe @('commit', '-m', "Add quality evaluation report $stamp")
    $gitSummary += $commitResult.Output
    if ($commitResult.ExitCode -ne 0) { throw 'git commit falhou.' }
    $pushResult = Invoke-GitSafe @('push', 'origin', 'arena/01a0ec89-lia-code')
    $gitSummary += $pushResult.Output
    if ($pushResult.ExitCode -ne 0) { throw 'git push falhou; relatórios continuam locais.' }
    $gitSummary += 'Relatório qualitativo commitado e enviado para origin/arena/01a0ec89-lia-code.'
} catch { $gitSummary += "Auto-submit não concluído: $($_.Exception.Message)" }
finally { if ($locationPushed) { Pop-Location } }
Add-Content -LiteralPath $logPath -Value ($gitSummary -join [Environment]::NewLine) -Encoding UTF8
Write-Host "`nJSON: $jsonPath`nLog: $logPath`n$($gitSummary -join [Environment]::NewLine)"
if ($failed) { exit 1 }
exit 0
