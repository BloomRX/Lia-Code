# Avaliação documental de TTS — português brasileiro

**Estado:** Maria SAPI foi rejeitada pelo usuário por robótica/lentidão. O benchmark Piper Faber foi executado em Windows 11 build 26200: CPU e DirectML funcionaram; o perfil confirmou nós nos dois providers. O ambiente CPU global foi preservado. Nenhum teste auditivo de Faber foi registrado ainda; ASR continua separado.

## Conclusão curta

Para mensagens curtas e resposta rápida, **CPU ganhou nesta máquina**: latência mediana do primeiro áudio 80,5 ms versus 137,7 ms em DirectML; síntese total 297 ms versus 652 ms. No parágrafo maior, CPU ainda entregou o primeiro áudio antes (88,7 ms versus 219,5 ms), mas DirectML terminou o parágrafo mais rápido (1,155 s versus 1,494 s). Assim, não selecionar GPU automaticamente para menor latência percebida; CPU é o candidato default de resposta interativa neste benchmark, DirectML é uma opção de throughput para textos longos. A decisão de voz final depende de avaliação auditiva.

O benchmark fez uma rodada de aquecimento e quatro medições por texto; inclui fonemização e geração do primeiro chunk, mas não inclui inicialização do processo no primeiro áudio. O carregamento do modelo foi medido separadamente: 1,98 s CPU e 2,39 s DirectML. Resultados são específicos desta RX 580, texto e versões; não generalizar para outras GPUs.

| Texto | CPU: primeiro áudio | DirectML: primeiro áudio | CPU: total | DirectML: total | RTF CPU / DML |
|---|---:|---:|---:|---:|---:|
| Curto (2 frases) | **80,5 ms** | 137,7 ms | **297 ms** | 652 ms | 0,109 / 0,243 |
| Parágrafo (~60 palavras) | **88,7 ms** | 219,5 ms | 1,494 s | **1,155 s** | 0,072 / **0,056** |

DirectML executou nós confirmados no perfil ORT, portanto o resultado não é só um fallback CPU. Ainda assim, início mais lento pode vir do particionamento CPU↔GPU/custos de transferência e do tamanho pequeno do modelo; o benchmark mede latência, não qualidade de voz.

1. **Piper `pt_BR-faber-medium` ONNX** — voz masculina pt-BR, 22,05 kHz, peso de 63.201.294 bytes. A execução Windows está validada. O pacote Piper 1.8.0 usado é GPL-3.0-or-later e o peso upstream exato não declara claramente licença própria (o card declara CC0 para o dataset). Uso fica restrito a avaliação local, sem redistribuição pendente de esclarecer a licença do peso.
2. **Kokoro-82M v1.0** — continua como alternativa de variedade vocal, ainda não instalada/testada. Pesos/código e Misaki Apache-2.0; pipeline PT-BR inclui eSpeak NG e precisa de rota/backend AMD Windows validado.

**Decisão provisória de latência:** usar Piper CPU no caminho curto/interativo; manter DirectML para comparar em conteúdo longo, mas não promovê-lo como menor latência sem novos testes no formato real de resposta da Lia.

## Comparação

| Critério | Piper Faber medium (ONNX) | Kokoro-82M v1.0 |
|---|---|---|
| Idioma/voz | `pt_BR`, uma voz masculina Faber | `pt-BR`, `pf_dora`, `pm_alex`, `pm_santa` |
| Peso de voz/modelo | Cerca de 63 MB / ~15M parâmetros, conforme model card comunitário | 82M parâmetros; o card oficial não lista o tamanho exato do artefato na tabela de vozes |
| Licença declarada do peso | Card upstream atribui CC0 ao dataset, mas não declara claramente a licença do checkpoint exato; não redistribuir | Apache-2.0 para os pesos do modelo |
| Código de inferência | `piper-tts` 1.8.0: GPL-3.0-or-later; eSpeak bridge incluso | Pacote `kokoro`: Apache-2.0; `misaki`: Apache-2.0 |
| Dependências relevantes | ONNX Runtime CPU global preservado; DirectML 1.24.4 em venv isolado; engine Piper/eSpeak nos venvs | PyTorch, Transformers, Misaki e eSpeak NG no pipeline demonstrado; instalação/backend ainda não autorizados/testados para Kokoro |
| Hardware/backend | RX 580 Windows 11: CPU e Dml ativos; perfil ORT confirmou ambos. CPU mais rápida no primeiro áudio; DML terminou o parágrafo antes | Implementação oficial baseada em PyTorch; nenhuma evidência de backend AMD Windows validado para Kokoro |
| Qualidade PT-BR documentada | `medium` é rótulo de tamanho, não nota; WAVs do benchmark precisam de revisão humana | O guia lista três vozes pt-BR, mas não atribui grade; card alerta sobre limitações de G2P/treino não inglês |
| Situação | **Benchmark de latência executado**; CPU provisoriamente melhor para primeiro áudio/respostas curtas | **Não instalado nem testado**; possível comparador auditivo após resolver backend e dependências |

## Licenças: não colapsar o stack

- O repositório atual `OHF-Voice/piper1-gpl` é GPL-3.0-or-later; o `rhasspy/piper` original MIT foi arquivado. O engine atual pode ser livre de usar, mas é copyleft, então não corresponde à preferência de licença mais permissiva.
- O card upstream do Faber identifica o dataset OHF Voice Datasets como CC0, mas não deixa inequívoca a licença do peso ONNX exato. O benchmark baixou a revisão upstream oficial, registrou SHA-256 e origem no relatório; até esclarecer a licença do peso, manter apenas para avaliação local e não redistribuir.
- O card comunitário Trelis mostra uma rota ONNX direta sem o pacote `piper-tts`, rotula o exemplo como MIT e usa eSpeak NG como subprocesso. Isso evita depender do engine Piper no código de exemplo, mas **não** remove a dependência GPL do executável e não prova que o pacote completo seja licenciável apenas como MIT.
- O Kokoro oficial declara pesos Apache-2.0; o repositório de código e Misaki também trazem Apache-2.0. Isso não relicencia eSpeak NG, que é GPL-3.0-or-later. O modelo utiliza material CC BY identificado no próprio card; manter atribuições se for distribuir artefatos derivados ou o pacote completo.
- Ainda não há decisão de distribuição comercial/closed-source; portanto registrar a cadeia de componentes em vez de concluir que “TTS é Apache/MIT” pelo modelo isolado.

## Protocolo proposto para a prova de áudio

Próxima etapa: avaliação auditiva cega dos WAVs Faber (mesmo texto, CPU vs DirectML) e, se o usuário aprovar a voz, investigar Kokoro como contraste de qualidade. Os WAVs estão fora do repo em `%LOCALAPPDATA%\Lia-Code\tts\piper-directml-eval\audio`.

1. Amostra pt-BR de ~100–150 palavras, contendo perguntas, números, siglas, nomes e pontuação; usar texto original da Lia, sem imitar voz de pessoa real.
2. Trecho curto de 1–2 frases para medir latência inicial e comportamento em mensagens breves; Kokoro documenta possível queda de qualidade em enunciados muito curtos.
3. Parágrafo maior para avaliar prosódia, pronúncia e artefatos de chunking; verificar também cortes, retomada/interrupção e normalização de números.
4. Avaliação humana cega (naturalidade, clareza, sotaque pt-BR e preferência), latência para primeiro áudio, duração de síntese/áudio (real-time factor), RAM e eventual uso de GPU.
5. Usar ao menos um falante feminino e um masculino quando disponíveis; a preferência de voz/persona continua em aberto. Não clonar pessoa real sem autorização específica.
6. Depois dos testes isolados, fazer uma amostra do pipeline de voz: ASR recebe fala de entrada; Qwen3-4B responde; TTS lê o texto. Medir latência total, sincronização e evitar que o microfone transcreva o próprio áudio da Lia (iniciar em half-duplex/fones; AEC só depois de validar).

## Dependências e próximo gate

- O runtime local para Qwen3-4B continua sendo `llama.cpp` Vulkan e não fornece inferência TTS. O preflight TTS confirmou ORT CPU 1.24.4 global; o benchmark DirectML 1.24.4 e Piper 1.8.0 foram instalados apenas em venvs externos removíveis. Não misturar esses runtimes com o LLM.
- Kokoro/PyTorch não foram instalados. Qualquer pacote futuro deve ficar isolado e requer autorização; pesos têm autorização permanente de download desde que origem, licença, SHA-256 e caminho externo sejam registrados.
- Preflight SAPI `20260930-091635` confirmou uma voz pt-BR instalada; o usuário a rejeitou por robótica/lentidão. Guardar o WAV somente até o usuário não precisar mais dele; caminho e hash estão no relatório correspondente.
- Inventário `20260930-110046`: Windows 11 build 26200, Python 3.14.3 e ONNX Runtime 1.24.4 com `CPUExecutionProvider` (mais `AzureExecutionProvider`). Sem DirectML, PyTorch/Kokoro, Piper ou eSpeak visíveis; nenhum modelo em cache. O CPU continua instalado.
- O usuário prioriza a menor latência e autorizou um ambiente separado/removível para comparar CPU e RX 580/DirectML, sem substituir o runtime CPU global. `Update-Lia.bat` sem argumentos passa a baixar os recursos pinados, criar venvs externos separados para CPU e DirectML e medir Faber com confirmação dos nós realmente executados pelo provider; isso não presume que a RX 580 será mais rápida.
- A instalação de comparação usa `piper-tts` 1.8.0 (GPL-3.0-or-later; inclui fonemização e dados eSpeak) e ONNX Runtime DirectML 1.24.4 (MIT), somente nos venvs externos. WHEELS, cache pip, modelos, perfil ORT e WAVs ficam sob `%LOCALAPPDATA%\Lia-Code\tts\piper-directml-eval`; apagar essa pasta remove o experimento e preserva Python/ORT CPU globais.
- O checkpoint oficial Faber é pinado por revisão e SHA-256. O card atribui CC0 ao dataset, mas não esclarece separadamente a licença do peso exato; registrar essa ressalva no manifesto e limitar o uso a avaliação local, sem redistribuição pendente de esclarecimento. O teste mede latência, mas voz/sotaque/naturalidade ainda requerem avaliação auditiva do usuário.
- O benchmark só conta como GPU quando o perfil de execução registra nós em `DmlExecutionProvider`; caso contrário marca como falha/fallback, sem declarar vitória da GPU. Pesos ficam autorizados para download desde que origem, revisão, licença, SHA-256 e diretório externo sejam registrados em [`RESOURCE-REGISTRY.md`](RESOURCE-REGISTRY.md).

## Fontes primárias consultadas

- [Model card oficial Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M) — licença dos pesos, uso e idiomas.
- [VOICES.md oficial do Kokoro](https://huggingface.co/hexgrad/Kokoro-82M/blob/main/VOICES.md) — vozes pt-BR, `lang_code='p'`, `espeak-ng pt-br` e ressalva de dados G2P/treino.
- [Código e dependências do Kokoro](https://github.com/hexgrad/kokoro/blob/main/pyproject.toml) e [LICENSE](https://github.com/hexgrad/kokoro/blob/main/LICENSE); [LICENSE do Misaki](https://github.com/hexgrad/misaki/blob/main/LICENSE).
- [eSpeak NG](https://github.com/espeak-ng/espeak-ng) — licença GPL-3.0-or-later.
- [Piper engine ativo](https://github.com/OHF-Voice/piper1-gpl) e [repositório antigo](https://github.com/rhasspy/piper) — confirmar diferença GPL atual/MIT arquivado.
- [Card do checkpoint upstream Piper Faber medium](https://huggingface.co/datasets/rhasspy/piper-checkpoints/blob/main/pt/pt_BR/faber/medium/MODEL_CARD) — pt_BR, 22,05 kHz, voz medium e dataset CC0.
- [Rehost e exemplo direto ONNX Faber](https://huggingface.co/Trelis/piper-pt-br-faber-medium) — 63 MB, licença declarada CC0 e exemplo de inferência separado do engine Piper; precisa conferir a revisão com upstream antes de baixar.
