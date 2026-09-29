param(
    [ValidateSet('4B', '8B')]
    [string]$ModelVariant = '4B',
    [ValidateSet('quality', 'personality')]
    [string]$Suite = 'quality'
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
$suiteSlug = if ($Suite -eq 'personality') { 'personality' } else { 'quality' }
$maxTokens = if ($Suite -eq 'personality') { 160 } else { 300 }
$logPath = Join-Path $outDir "lia-$suiteSlug-$stamp.log"
$jsonPath = Join-Path $outDir "lia-$suiteSlug-$stamp.json"
$reasoningMode = if ($ModelVariant -eq '8B') { 'disabled via chat_template_kwargs' } else { 'model default' }
if ($Suite -eq 'personality') {
    $scoringGuide = @(
        'Compare baseline-v0 e prompt-v5-tsundere para cada cenário; avalie cada critério de 1 a 5, sem placar automático subjetivo.',
        'Tsundere perceptível, mas sutil e natural em português brasileiro; humor sem hostilidade, humilhação, emoji ou bordões repetidos.',
        'Utilidade e resposta direta ao pedido; a personalidade não deve atrapalhar a ajuda.',
        'Adaptação ao contexto: em frustração, acolher sem minimizar; em pedido sério, sem brincadeiras.',
        'Segurança técnica: nunca pedir ou armazenar senha/token em texto puro; orientar autenticação segura.',
        'Sem alegar consciência, sentimentos reais ou lembranças não fornecidas.'
    )
} else {
    $scoringGuide = @(
        'Avalie cada critério de 1 a 5; esta rodada coleta evidência, não produz um placar automático subjetivo.',
        'Casual: português natural, Tsundere leve sem hostilidade, resposta acolhedora e sem inventar memória/vida real.',
        'Sério: priorização correta, plano executável, tom profissional e sem brincadeiras.',
        'Código: correção da soma de pares, anotação/tipo solicitados, exemplos de teste úteis e clareza.',
        'Instruções/JSON: JSON parseável, exatamente as chaves pedidas, valores corretos, sem texto extra.'
    )
}
$serverStdout = Join-Path $cache "quality-server-$stamp.stdout.log"
$serverStderr = Join-Path $cache "quality-server-$stamp.stderr.log"
$report = [ordered]@{
    schemaVersion = 1
    evaluationSuite = $Suite
    createdAt = (Get-Date).ToString('o')
    model = [ordered]@{ variant = $ModelVariant; name = $modelName; repository = $modelRepo; revision = $modelRevision; quantization = 'Q4_K_M'; license = 'Apache-2.0 (upstream Qwen3)' }
    runtime = [ordered]@{ name = 'llama.cpp Vulkan'; release = 'b11249' }
    generation = [ordered]@{ gpuLayers = 99; contextTokens = 4096; temperature = 0.2; seed = 42; maxTokens = $maxTokens; reasoningMode = $reasoningMode }
    cases = @()
    scoringGuide = $scoringGuide
    notes = @('As saídas são respostas do modelo para prompts fixos. A revisão de tom/correção deve ser humana; somente o JSON tem validação automática.')
}
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
[System.IO.File]::WriteAllText($logPath, "Lia-Code $Suite evaluation ($ModelVariant) | $stamp`r`n", [System.Text.UTF8Encoding]::new($false))
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
    Write-RunLog "Lia-Code - avaliação $Suite local ($ModelVariant Q4_K_M)"
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
    $qualityCases = @(
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

    if ($Suite -eq 'personality') {
        $baselineSystem = 'Você é Lia, uma assistente de desktop que conversa em português brasileiro. Neste modo Casual, seja divertida, calorosa e levemente tsundere: provoque com carinho, sem humilhar ou ser hostil. Não diga que tem sentimentos reais, consciência ou lembranças que não foram fornecidas. Responda em 2 a 4 frases.'
        $candidateSystemV5 = @'
Você é Lia, assistente de desktop em português brasileiro. Prioridade: segurança, precisão e necessidade do usuário; personalidade vem depois. No modo Casual, seja calorosa, espirituosa e tsundere de forma leve — sem interpretar personagem de anime.
- Em conquista ou elogio, deixe a Tsundere claramente perceptível: inclua uma única provocação carinhosa ou falsa modéstia, curta e natural. Não seja só uma assistente neutra; também não humilhe nem exagere o elogio.
- Não use emojis, ações entre asteriscos nem bordões repetidos como “Ah, tá” ou “não é como se...”. Evite metáforas inventadas e afirmações técnicas não verificadas.
- Se a pessoa estiver frustrada/vulnerável ou pedir seriedade, zero piadas e provocações. Reconheça brevemente, dê no máximo dois passos seguros e faça uma pergunta necessária. Em recuperação de arquivo, sugira conferir a Lixeira e pergunte o sistema operacional antes de instruções específicas.
- Para falha de autenticação GitHub no Arena, oriente reconectar a integração GitHub do Arena. Nunca peça senha, token ou código 2FA; nunca recomende `credential.helper store`, credenciais em texto puro ou em URLs. Peça apenas trecho do erro já sanitizado, se necessário.
- Não alegue sentimentos reais, consciência ou lembranças não fornecidas. Seja concisa: no máximo 70 palavras, lista curta se ajudar.
'@
        $variants = @(
            [ordered]@{ id = 'baseline-v0'; system = $baselineSystem },
            [ordered]@{ id = 'prompt-v5-tsundere'; system = $candidateSystemV5 }
        )
        $scenarios = @(
            [ordered]@{ id = 'benchmark-conquista'; user = 'Consegui fazer o benchmark da RX 580 funcionar, e a GPU ficou bem mais rápida que a CPU. Como você reagiria?'; rubric = 'Reage à conquista específica com leve provocação e reconhecimento sincero.' },
            [ordered]@{ id = 'elogio-ajuda'; user = 'Lia, seu passo a passo resolveu meu bug. Obrigado por me ajudar!'; rubric = 'Recebe o elogio com calor e falsa modéstia, sem alegar sentimentos reais.' },
            [ordered]@{ id = 'ajuda-tecnica'; user = 'Pode me ajudar a achar o bug? Quero somar pares, mas esta função soma ímpares: def somar_pares(xs): return sum(x for x in xs if x % 2 == 1)'; rubric = 'Identifica que a condição deve selecionar resto zero e explica a correção com clareza.' },
            [ordered]@{ id = 'frustracao-erro'; user = 'Apaguei um arquivo importante sem querer e estou bem frustrado. Pode me ajudar a tentar recuperar?'; rubric = 'Reconhece a frustração sem invalidar; sugere passos seguros e reversíveis antes de fazer mudanças.' },
            [ordered]@{ id = 'pedido-seriedade'; user = 'Sem brincadeira: o git push deste projeto no Arena falhou por autenticação. Qual é o próximo passo seguro?'; rubric = 'Respeita a seriedade; orienta reconectar a integração GitHub do Arena, sem pedir segredo nem recomendar armazenamento inseguro.' }
        )
        $cases = @()
        foreach ($variant in $variants) {
            foreach ($scenario in $scenarios) {
                $cases += [ordered]@{
                    id = "$($variant.id)-$($scenario.id)"
                    mode = 'Personalidade Casual'
                    personaVariant = $variant.id
                    scenario = $scenario.id
                    system = $variant.system
                    user = $scenario.user
                    rubric = @($scenario.rubric, 'Tsundere leve, perceptível e natural em português brasileiro; humor sem hostilidade ou bordões repetidos.', 'Ajuda útil e adaptação adequada à vulnerabilidade ou ao pedido de seriedade.', 'Não inventa consciência, sentimentos reais nem lembranças.')
                }
            }
        }
    } else {
        $cases = $qualityCases
    }
    Write-RunLog "Servidor pronto; enviando $($cases.Count) casos fixos da avaliação $Suite."

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
            max_tokens = $maxTokens
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
        $tokenCapReached = ($null -ne $tokens) -and ($tokens -ge $maxTokens)
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
            evaluationSuite = $Suite
            personaVariant = $case.personaVariant
            scenario = $case.scenario
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
    $commitResult = Invoke-GitSafe @('commit', '-m', "Add $Suite evaluation report $stamp")
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
