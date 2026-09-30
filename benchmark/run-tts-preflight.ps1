$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding

$root = Split-Path -Parent $PSScriptRoot
$resultsDir = Join-Path $root 'benchmark-results'
$cacheRoot = Join-Path $env:LOCALAPPDATA 'Lia-Code\benchmark-cache'
$ttsCache = Join-Path $cacheRoot 'tts'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$jsonPath = Join-Path $resultsDir "lia-tts-preflight-$stamp.json"
$logPath = Join-Path $resultsDir "lia-tts-preflight-$stamp.log"
$samplePath = Join-Path $ttsCache "lia-sapi-ptbr-$stamp.wav"
$sampleText = 'Olá! Eu sou a Lia. Posso ajudar você a organizar suas tarefas, explicar uma ideia com clareza e responder em português brasileiro. Esta é uma frase de teste para avaliar ritmo, pronúncia e naturalidade.'
$logLines = [System.Collections.Generic.List[string]]::new()
$synth = $null
$report = [ordered]@{
    schemaVersion = 1
    evaluation = 'windows-sapi-tts-baseline-preflight'
    createdAt = (Get-Date).ToString('o')
    policy = 'Inspect and, only if already available, use the built-in Windows System.Speech/SAPI stack. No model weights, packages, runtimes, or software are downloaded, installed, or updated.'
    machine = [ordered]@{}
    provider = [ordered]@{
        name = 'Windows System.Speech / SAPI'
        assemblyAvailable = $false
        status = 'not-checked'
        voices = @()
        selectedVoice = $null
        sample = $null
        error = $null
    }
    notes = @(
        'This is only an installed-OS-voice baseline, not an evaluation or selection of neural TTS weights.',
        'The WAV is saved only in the external local cache and is not added to Git or uploaded.',
        'The script does not open a microphone, capture speech, or play audio automatically.',
        'If no pt-BR SAPI voice is present, report that fact without installing or downloading one.'
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

New-Item -ItemType Directory -Force -Path $resultsDir | Out-Null
Write-RunLog 'Lia-Code — preflight TTS de voz SAPI já instalada; sem downloads nem instalações.'
try {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $report.machine = [ordered]@{
        os = $os.Caption
        osBuild = $os.BuildNumber
        powershellVersion = $PSVersionTable.PSVersion.ToString()
        systemCulture = [System.Globalization.CultureInfo]::CurrentCulture.Name
    }
    Write-RunLog "Sistema: $($report.machine.os) | PowerShell: $($report.machine.powershellVersion)"
    try {
        Add-Type -AssemblyName System.Speech -ErrorAction Stop
        $report.provider.assemblyAvailable = $true
        $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
        $installed = @($synth.GetInstalledVoices())
        $voiceRows = @(
            foreach ($voice in $installed) {
                [ordered]@{
                    name = [string]$voice.VoiceInfo.Name
                    culture = [string]$voice.VoiceInfo.Culture.Name
                    gender = [string]$voice.VoiceInfo.Gender
                    age = [string]$voice.VoiceInfo.Age
                    enabled = [bool]$voice.Enabled
                }
            }
        )
        $report.provider.voices = $voiceRows
        Write-RunLog "Vozes SAPI disponíveis: $($voiceRows.Count)"
        foreach ($voice in $voiceRows) { Write-RunLog ("Voz: {0} | {1} | habilitada={2}" -f $voice.name, $voice.culture, $voice.enabled) }
        $ptBr = @($installed | Where-Object { $_.Enabled -and $_.VoiceInfo.Culture.Name -ieq 'pt-BR' })
        if ($ptBr.Count -eq 0) {
            $report.provider.status = 'no-installed-pt-BR-SAPI-voice'
            Write-RunLog 'Nenhuma voz SAPI pt-BR habilitada foi encontrada. Nenhuma voz será baixada ou instalada.'
        } else {
            $selected = $ptBr[0]
            $report.provider.status = 'synthesized-installed-pt-BR-voice'
            $report.provider.selectedVoice = [ordered]@{
                name = [string]$selected.VoiceInfo.Name
                culture = [string]$selected.VoiceInfo.Culture.Name
                gender = [string]$selected.VoiceInfo.Gender
                age = [string]$selected.VoiceInfo.Age
            }
            New-Item -ItemType Directory -Force -Path $ttsCache | Out-Null
            $synth.SelectVoice($selected.VoiceInfo.Name)
            $synth.SetOutputToWaveFile($samplePath)
            $synth.Speak($sampleText)
            $synth.SetOutputToNull()
            $item = Get-Item -LiteralPath $samplePath
            $hash = (Get-FileHash -LiteralPath $samplePath -Algorithm SHA256).Hash.ToLowerInvariant()
            $report.provider.sample = [ordered]@{
                text = $sampleText
                format = 'WAV (System.Speech default format)'
                path = "%LOCALAPPDATA%\Lia-Code\benchmark-cache\tts\$(Split-Path -Leaf $samplePath)"
                sizeBytes = $item.Length
                sha256 = $hash
                playback = 'not-played-automatically; listen locally'
                cleanup = 'Delete only this WAV after reviewing it; no package/model files were created.'
            }
            Write-RunLog "Áudio gerado localmente: %LOCALAPPDATA%\Lia-Code\benchmark-cache\tts\$(Split-Path -Leaf $samplePath) ($($item.Length) bytes)"
        }
    } catch {
        $report.provider.status = 'system-speech-unavailable-or-synthesis-failed'
        $report.provider.error = Protect-Text ([string]$_.Exception.Message)
        if (Test-Path -LiteralPath $samplePath) { Remove-Item -LiteralPath $samplePath -Force -ErrorAction SilentlyContinue }
        Write-RunLog "System.Speech indisponível ou síntese falhou: $($report.provider.error)"
    }
} catch {
    $report.provider.status = 'preflight-error'
    $report.provider.error = Protect-Text ([string]$_.Exception.Message)
    Write-RunLog "Erro de preflight: $($report.provider.error)"
} finally {
    if ($synth) { try { $synth.Dispose() } catch {} }
}

try {
    $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
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
    & git commit -m "Add installed Windows TTS preflight report $stamp"
    if ($LASTEXITCODE -ne 0) { throw 'git commit dos relatórios falhou.' }
    & git push origin arena/01a0ec89-lia-code
    if ($LASTEXITCODE -ne 0) { throw 'git push falhou; relatórios permanecem locais.' }
    $gitSummary.Add('Relatórios commitados e enviados para arena/01a0ec89-lia-code.')
} catch { $gitSummary.Add("Relatórios salvos; envio não concluído: $(Protect-Text ([string]$_.Exception.Message))") }
finally { if ($pushedLocation) { Pop-Location } }
Write-Host ($gitSummary -join [Environment]::NewLine)
if (($gitSummary -join ' ') -notmatch 'Relatórios commitados e enviados') { exit 1 }
exit 0
