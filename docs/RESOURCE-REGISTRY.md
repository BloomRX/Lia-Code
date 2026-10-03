# Registro de recursos externos da Lia

Este registro lista pesos e runtimes guardados fora do Git para que possam ser excluídos ao fim do projeto. O usuário autorizou downloads de modelos e, em 2026-09-30, ambientes TTS isolados/removíveis Piper + DirectML; não instalar ou atualizar runtimes globalmente nem outros stacks sem nova confirmação. **Não use `git clean` para remover esses recursos.**

## Avaliação TTS Piper Faber + DirectML — instalada em diretório removível

- **Uso/estado:** benchmark CPU vs DirectML `20260930-112224`; DirectML executou nós confirmados no perfil ONNX Runtime. CPU venceu latência do primeiro áudio; DirectML terminou antes o texto longo. Relatório: `benchmark-results/lia-piper-latency-20260930-112224.json`.
- **Raiz externa removível:** `%LOCALAPPDATA%\Lia-Code\tts\piper-directml-eval`. Contém peso, config, wheels, pip cache, venvs CPU/DirectML, manifestos de inventário de pacotes, perfis e WAVs. Para remover todo o experimento TTS, fechar processos e excluir somente essa pasta; não toca o Python/ORT CPU global.
- **Modelo Faber:** `models\faber-medium\pt_BR-faber-medium.onnx`, 63.201.294 bytes; origem oficial [`rhasspy/piper-voices`](https://huggingface.co/rhasspy/piper-voices/resolve/2f8dbe0bb0dde986411632bf014a13cdbe6596e7/pt/pt_BR/faber/medium/pt_BR-faber-medium.onnx), revisão `2f8dbe0bb0dde986411632bf014a13cdbe6596e7`; SHA-256 `858555e3a064209c57088fe6bd70c4c3dc54d03eaa00c45d5ecaf43a33f95aa7`. O card upstream identifica o dataset como CC0, mas não especifica claramente licença própria do checkpoint. **Avaliação local somente, sem redistribuição até esclarecer.**
- **Configuração da voz:** `pt_BR-faber-medium.onnx.json`, origem na mesma revisão; SHA-256 `b65310a5c057a8f99d6942f41cbb8a0a88670fc794f2c99a8dc0ce7a5cdf4a89`.
- **Piper runtime/phonemizer:** `piper-tts` 1.8.0 wheel Windows x64, SHA-256 `5da9bfdb05dfe15da3536859d422e605483ffa6d2b3ec2c5b9593bae6b5aa6a4`; origem PyPI; GPL-3.0-or-later. Instalada somente nos venvs externos, com eSpeak embutido.
- **ONNX Runtime DirectML:** 1.24.4 wheel CPython 3.14 Windows x64, SHA-256 `51d86bb949488e572b00422f344990a4a81d982416d73b6c0e4ced2bcd423d19`; origem PyPI; MIT. Instalado apenas no venv `env-directml`; versão CPU global preservada.
- **WAVs:** `audio\cpu\faber-cpu-short.wav`, `audio\cpu\faber-cpu-paragraph.wav`, `audio\directml\faber-directml-short.wav`, `audio\directml\faber-directml-paragraph.wav`. Revisão auditiva ainda pendente.
- **Dependências transitivas:** listas completas e metadados de licença ficam em `cpu-package-inventory.json` e `directml-package-inventory.json` sob a raiz externa, incluindo dependências PyPI baixadas pelo resolver.

## ASR local auxiliar do benchmark TTS — Whisper-small

- **Uso/estado:** transcrever somente o WAV de referência da Lia para preencher `ref_text` na avaliação privada Qwen/Chatterbox. O usuário revisa/corrige a hipótese antes da síntese. Não integra ASR ao produto Lia.
- **Modelo:** `openai/whisper-small`, revisão fixada `973afd24965f72e36ca33b3055d56a652f456b4d`, idioma/decodificação forçados para Portuguese/transcribe; licença Apache-2.0 conforme model card upstream.
- **Runtime:** reaproveita Transformers, Librosa, Torch e Protobuf já presentes nos ambientes isolados do notebook; nenhum pacote ASR novo é instalado no kernel global. Pesos e cache em `/content/lia_tts_candidate_eval/hf_home` no runtime Colab.
- **Privacidade:** áudio permanece no runtime Colab; só pesos públicos são baixados. O JSON de hipótese fica em `/content/lia_tts_candidate_eval/whisper_ref_transcription.json` (fora do Git) e poderá ser apagado ao limpar a pasta do experimento.
- **Limpeza:** fechar a sessão e excluir somente `/content/lia_tts_candidate_eval` quando os resultados já não forem necessários; isso também remove modelos, venvs, transcrição e WAVs locais do experimento.

## Phi-4-mini-instruct Q4_K_M — baixado, hash verificado e registrado

- **Uso:** comparação textual cross-family com o Qwen3-4B já em cache.
- **Arquivo:** `microsoft_Phi-4-mini-instruct-Q4_K_M.gguf`, aproximadamente **2,49 GB**.
- **Destino fora do Git:** `%LOCALAPPDATA%\Lia-Code\benchmark-cache\models\microsoft_Phi-4-mini-instruct-Q4_K_M.gguf`.
- **Origem:** [arquivo GGUF em bartowski/microsoft_Phi-4-mini-instruct-GGUF](https://huggingface.co/bartowski/microsoft_Phi-4-mini-instruct-GGUF/blob/915429cb42fe8eba71bd1d3117a7d63070892268/microsoft_Phi-4-mini-instruct-Q4_K_M.gguf), revisão fixada `915429cb42fe8eba71bd1d3117a7d63070892268`; arquivo declarado pelo Hub com 2,49 GB.
- **SHA-256 esperado:** `01999f17c39cc3074afae5e9c539bc82d45f2dd7faa3917c66cbef76fce8c0c2`.
- **Licença de origem:** MIT, conforme [cartão oficial do Microsoft Phi-4-mini-instruct](https://huggingface.co/microsoft/Phi-4-mini-instruct). A procedência/licença do arquivo quantizado será revisada antes de redistribuição.
- **Compatibilidade do runtime:** upstream llama.cpp adicionou suporte ao Phi-4-mini no [PR #12108](https://github.com/ggml-org/llama.cpp/pull/12108), mesclado em 2025-02-28. O runtime Vulkan local carregou o arquivo, mas avisou `Phi SWA is currently disabled`; nenhum runtime foi atualizado.
- **Estado:** baixado e usado nos relatórios `benchmark-results/lia-llm-comparison-20260930-072348.json` e `benchmark-results/lia-llm-comparison-20260930-082728.json`. SHA-256 verificado: `01999f17c39cc3074afae5e9c539bc82d45f2dd7faa3917c66cbef76fce8c0c2`; tamanho observado: 2.491.874.688 bytes. A primeira tentativa foi refeita após corrigir incompatibilidade com Windows PowerShell 5.1. O arquivo fica no cache até o fim do projeto; remover somente esse arquivo.
- **Instalações:** nenhuma. O arquivo usa o llama.cpp Vulkan já presente, sem atualizá-lo.

## Modelos existentes registrados no preflight

| Recurso | Caminho externo | Tamanho observado | Licença/origem | Estado |
|---|---|---:|---|---|
| Qwen3-4B-Instruct-2507 Q4_K_M — `Qwen_Qwen3-4B-Instruct-2507-Q4_K_M.gguf` | `%LOCALAPPDATA%\Lia-Code\benchmark-cache\models\` | 2,33 GiB | Apache-2.0; conversão GGUF Qwen/Bartowski | Usado no último teste |
| Qwen3-8B Q4_K_M — `Qwen_Qwen3-8B-Q4_K_M.gguf` | `%LOCALAPPDATA%\Lia-Code\benchmark-cache\models\` | 4,68 GiB | Apache-2.0; conversão GGUF Qwen/Bartowski | Existente; executado na rodada de 2026-09-30 com Chrome fechado |
| llama.cpp Vulkan b11249 | `%LOCALAPPDATA%\Lia-Code\benchmark-cache\llama-b11249-vulkan\` | Diretório de runtime | llama.cpp; não foi instalado/atualizado pelo teste atual | Usado pelo benchmark |

Outros arquivos GGUF que porventura existam no cache são inventariados/selecionados pelo teste; nenhum será apagado automaticamente.

## Arquivos gerados pelos testes

- Logs auxiliares do servidor ficam em `%LOCALAPPDATA%\Lia-Code\benchmark-cache\llm-<família>-<timestamp>.stdout.log` e `.stderr.log`.
- Os relatórios commitados de teste ficam em `benchmark-results/lia-llm-comparison-*.json` e `.log`; podem conter dados de hardware e respostas. Remover somente os relatórios deste projeto quando não forem mais necessários.
- Um download interrompido abruptamente pode deixar `microsoft_Phi-4-mini-instruct-Q4_K_M.gguf.partial-<timestamp>` na pasta `models`; verificar que não existe teste/download em andamento antes de apagar.

## Limpeza ao fim do projeto

Depois de preservar os resultados desejados e fechar Lia/benchmarks, estes comandos removem apenas os dois Qwen registrados, o Phi autorizado (se baixado) e o runtime Vulkan conhecido. Revise a lista antes de executar; não apague a pasta inteira se houver outros modelos do usuário.

```powershell
$cache = Join-Path $env:LOCALAPPDATA 'Lia-Code\benchmark-cache'
Remove-Item -LiteralPath (Join-Path $cache 'models\Qwen_Qwen3-4B-Instruct-2507-Q4_K_M.gguf') -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $cache 'models\Qwen_Qwen3-8B-Q4_K_M.gguf') -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $cache 'models\microsoft_Phi-4-mini-instruct-Q4_K_M.gguf') -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $cache 'llama-b11249-vulkan') -Recurse -Force -ErrorAction SilentlyContinue
```

Relatórios dentro do repositório devem ser removidos individualmente de `benchmark-results/` (e, se já enviados, de seus commits/histórico conforme a política do projeto). **Os comandos de limpeza acima são apenas instruções futuras; não executar até o usuário encerrar o projeto.**
