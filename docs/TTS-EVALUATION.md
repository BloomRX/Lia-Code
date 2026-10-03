# Avaliação documental de TTS — português brasileiro

**Estado:** Maria SAPI foi rejeitada pelo usuário por robótica/lentidão. O benchmark Piper Faber foi executado em Windows 11 build 26200: CPU e DirectML funcionaram; o perfil confirmou nós nos dois providers. O ambiente CPU global foi preservado. Nenhum teste auditivo de Faber foi registrado ainda; ASR continua separado.

## Conclusão curta

Este documento registra dois objetivos diferentes: benchmark rápido de motores/vozes prontos e o objetivo do projeto de **desenvolver/adaptar um modelo TTS especializado para a Lia**. Piper Faber CPU venceu alguns testes de latência neste hardware, mas isso não o torna o modelo final; Kokoro continua candidato documental de comparação, não escolha final. A tentativa Piper Plus com a voz da Lia ficou metálica/robótica e não está aprovada. Não repetir aquele treino às cegas.

Para mensagens curtas e resposta rápida, **CPU ganhou no benchmark Piper Faber desta máquina**: latência mediana do primeiro áudio 80,5 ms versus 137,7 ms em DirectML; síntese total 297 ms versus 652 ms. No parágrafo maior, CPU ainda entregou o primeiro áudio antes (88,7 ms versus 219,5 ms), mas DirectML terminou o parágrafo mais rápido (1,155 s versus 1,494 s). Isso compara execução/latência desse voicepack, não naturalidade ou adaptação da voz da Lia.

## Execução Colab Qwen/Chatterbox na T4 — resultado atual

A referência usada foi `16,74 s`, 44,1 kHz, estéreo. Na execução anterior, sem o limite publicado ainda, Qwen usou `language='Portuguese'` mas produziu 655,28 s de áudio nas frases 1 e 2 (1.727,62 s e 1.720,46 s de geração); o usuário ouviu início fora de PT-BR e repetição. O runner usava então um `REF_TEXT` curto fixo, não confirmado contra a referência completa; isso pode ter afetado a clonagem, mas não prova a causa da falha. Após aplicar `max_new_tokens=128`, rejeitar WAVs >15 s e impor timeout de 180 s, o runaway desapareceu nas três frases. Qwen continuou em FP32/SDPA. Não declarar PT-BR garantido só pelo idioma genérico do parâmetro.

**Medições do usuário, T4 (pares: duração do áudio / tempo de geração):**

| Modelo | Carga | Frase 1 | Frase 2 | Frase 3 | RTF das frases |
|---|---:|---:|---:|---:|---|
| Chatterbox-Multilingual-pt-br | 17,49 s | 3,68 / 5,38 s | 5,44 / 5,12 s | 4,00 / 4,15 s | 1,462 / 0,942 / 1,037 |
| Qwen3-TTS Base 0.6B, FP32 | 3,00 s | 2,80 / 9,96 s | 5,36 / 13,23 s | 3,76 / 9,60 s | 3,558 / 2,468 / 2,554 |

**Avaliação auditiva do usuário:** ambos pronunciaram bem e preservaram a semelhança com a voz original. Chatterbox mantém leve timbre metálico/agudo; Qwen soa sem emoção. Baixa personalidade era esperada nesta prova neutra e não é evidência contra a identidade vocal. Chatterbox ficou perto de tempo real; Qwen ainda gerou 2,5–3,6 vezes mais devagar que a duração do áudio, medição sem streaming/TTFA.

Whisper-small local levou 22,70 s e gerou hipótese de 244 caracteres, aceita com Enter. O trecho final reconhecido (“Volte em assim, traidora!”) parece linguisticamente suspeito; confirmar/corrigir antes de usar a transcrição em dados de adaptação. O WAV e JSON detalhado permanecem privados no runtime. Whisper emitiu aviso de attention mask, sem impedir a execução; a fonte atual passa `attention_mask` explicitamente, ainda não validada. A hipótese aprovada agora fica em cache junto ao SHA-256 do WAV e revisão Whisper: novas rodadas com o mesmo WAV reutilizam a transcrição e dispensam inferência/confirmação; outro WAV aciona ASR novamente.

**Leitura de decisão:** os dois candidatos passam uma triagem inicial de pronúncia/semelhança vocal nesta referência; isso não aprova nenhum para produção nem resolve licença, fine-tuning, expressão ou execução na RX 580/Windows. Próximo teste TTS deve isolar expressividade/prosódia com texto controlado e parâmetros oficialmente suportados, separando emoção/persona de identidade de voz. Preservar os WAVs/relatórios no Colab privado e não adicionar ASR ao produto.

## Desenvolvimento do TTS próprio da Lia — direção confirmada

O objetivo não é apenas escolher um clone pronto: selecionar uma base pré-treinada que possa ser adaptada para a voz/estilo da Lia, desenvolver e avaliar o especialista TTS separadamente, e só depois integrá-lo à Lia-Omni. “Modelo próprio” pode ser fine-tuning/adaptação de pesos; não pressupõe treinar uma arquitetura do zero. A integração futura conecta o TTS e os demais especialistas, sem fundir checkpoints.

### Triagem documental dos candidatos (sem baixar nem instalar)

| Base/candidato | O que está realmente documentado sobre PT-BR | Adaptação para a voz Lia | Licença e hardware | Parecer atual |
|---|---|---|---|---|
| **Qwen3-TTS Base 0.6B/1.7B** | Lista “Portuguese” e usa o idioma genérico `Portuguese`/`pt`; não encontrei declaração oficial de que o modelo-base seja treinado ou avaliado especificamente em pt-BR, nem evidência de cobertura de variantes brasileiras. Logo, “português suportado” não comprova português brasileiro natural. | O repositório oficial documenta fine-tuning single-speaker (áudio + transcrição + referência). É o fluxo de adaptação mais diretamente documentado até aqui. | Checkpoint/model card declara Apache-2.0. Exemplo oficial carrega CUDA/BF16/FlashAttention; Windows + RX 580/DirectML e treino/inferência na GPU da Lia não foram validados. ~97–101 ms first-packet é número declarado no paper, não benchmark na nossa máquina. | **Candidato a PoC de adaptação**, condicionado a uma audição PT-BR prévia e verificação de requisitos reais. Não selecionado. Fontes: [model card Base 0.6B](https://huggingface.co/Qwen/Qwen3-TTS-12Hz-0.6B-Base), [fine-tuning oficial](https://github.com/QwenLM/Qwen3-TTS/tree/main/finetuning), [relatório](https://arxiv.org/html/2601.15621v1). |
| **Chatterbox Multilingual V3 — pack pt-BR** | Há evidência de modelo regional dedicado, não só rótulo de idioma: o model card declara locale `pt-BR`; o Space oficial se chama “Portuguese (Brazil)”, usa texto de exemplo brasileiro, mantém `FIXED_LANGUAGE_ID='pt'` e carrega o T3 `t3_pt_br.safetensors` junto de tokenizer/decoder compartilhados. Portanto o `pt` é apenas o ID interno; a especialização brasileira está no checkpoint/dados do pack. A demonstração ainda precisa ser ouvida por falante nativo com frases da Lia; metadados não garantem a qualidade percebida. | O pack é um fine-tune **de língua/região**, não um modelo da voz Lia. O código oficial do Space contém clonagem de voz por referência e o carregador explícito do checkpoint pt-BR. Não encontramos receita oficial completa para fazer novo fine-tuning de speaker; existem receitas comunitárias, que não estão validadas para esse pack e não devem ser confundidas com suporte upstream. | A Resemble declara a família Chatterbox MIT, mas a licença exata e os ativos auxiliares do repositório específico pt-BR devem ser conferidos antes de distribuir um derivado. O Space oficial usa PyTorch/CUDA (com fallback CPU), mas não valida RX 580/Windows. | **Melhor candidato documental para um teste concreto de sotaque pt-BR e clonagem; ainda não aprovado como modelo final/adaptável da voz Lia.** Fontes: [ficha específica pt-BR](https://huggingface.co/ResembleAI/Chatterbox-Multilingual-pt-br), [Space oficial (descrição/demo)](https://huggingface.co/spaces/ResembleAI/Chatterbox-Multilingual-TTS-pt-br), [código do carregador pt-BR](https://huggingface.co/spaces/ResembleAI/Chatterbox-Multilingual-TTS-pt-br/raw/main/chatterbox/src/chatterbox/tts.py), [repositório oficial](https://github.com/resemble-ai/chatterbox), [licença declarada pela Resemble](https://www.resemble.ai/learn/models/chatterbox-multilingual). |
| **OmniVoice BR-PT v1.5 (comunidade)** | Modelo já refinado com dados brasileiros; ficha identifica locale pt-BR, mas o ID interno continua `pt` e o próprio autor chama o fine-tune de experimental. A avaliação publicada é auto-relatada em 20 prompts de ASR; exige escuta humana. | É uma adaptação de idioma/sotaque com voice cloning por referência, não fine-tune da voz Lia. Serve como referência de quão longe um corpus pt-BR especializado pode levar uma base. | O código é Apache-2.0, mas o checkpoint original `k2-fsa/OmniVoice` declara pesos CC-BY-NC por restrição dos dados; portanto não é candidato para distribuição/uso comercial sem autorização explícita. Runtime oficial é PyTorch com rotas CUDA/MPS; RX 580 Windows não validado. | **Só benchmark privado** se quisermos avaliar som pt-BR; excluir como base de produto enquanto licença não permitir. Fontes: [ficha BR-PT v1.5](https://huggingface.co/edwixx/omnivoice-brpt-v15), [licença dos pesos OmniVoice](https://huggingface.co/k2-fsa/OmniVoice). |
| **Piper Plus multilingual (tentativa atual)** | Base multilíngue com ramo `pt`, não base PT-BR exclusiva. Token nasal foi corrigido no manifesto, mas a saída do modelo Lia continuou robótica/metálica. | Já teve adaptação single-speaker por 500 épocas; esse fato não prova boa adaptação nem qualidade. Não repetir sem comparar base vs fine-tune e revisar dados/receita. | Checkpoint-base sem licença clara; a tentativa atual não deve ser redistribuída. | **Não aprovado**; preservar como resultado experimental e diagnosticar, não como rota automaticamente escolhida. |

**Conclusão da verificação:** a ressalva do usuário procede. “Português na lista” é só cobertura nominal. Para pt-BR, o Chatterbox regional e OmniVoice BR-PT têm declarações de treinamento/ajuste mais específicas; o segundo tem bloqueio de licença para produto, e o primeiro não tem uma receita upstream confirmada para fine-tune da voz Lia. Qwen3-TTS tem o caminho oficial de adaptação mais claro, mas a evidência pública consultada não separa pt-BR de pt genérico. Assim, ainda não há um vencedor único: comparar primeiro **Qwen3-TTS Base** e **Chatterbox pt-BR** (e, se restritamente privado, OmniVoice BR-PT) com frases de contraste pt-BR e avaliação de falante nativo; depois selecionar base e adapter de speaker.

**Teste de idioma necessário antes de qualquer treino:** usar sentenças de vocabulário brasileiro, numerais, nasalização e pares de pronúncia típicos, gírias/formas de tratamento da Lia, e conferir ausência de redução vocálica/realizações de pt-PT. Avaliar percepção por falante nativo, inteligibilidade e semelhança vocal em separado. Ter `pt`/`Portuguese` como language ID não satisfaz esse critério.

**Próximo trabalho TTS:** (1) diagnosticar a tentativa Piper Plus sem mais treino; (2) verificar a duração total e consistência dos dados de Lia; (3) preparar um conjunto fixo de frases teste pt-BR e ouvir amostras demonstrativas dos candidatos, sem assumir que demos do fornecedor representam performance local; (4) fechar licenças, receita de fine-tuning e rota RX 580/Windows/Colab; (5) somente então fazer PoC isolada e comparar qualidade + first-audio latency + RTF + memória. Maior latência poderá ser aceita se a melhoria de qualidade justificar; latência é métrica, não veto automático. Nenhum modelo novo foi baixado ou instalado nesta triagem.

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
