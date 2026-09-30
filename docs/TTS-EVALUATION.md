# Avaliação documental de TTS — português brasileiro

**Estado:** shortlist, sem download, instalação ou geração local de áudio. O foco escolhido pelo usuário é TTS, como primeira fatia do fluxo de voz; ASR continuará sendo um módulo separado, mas será integrado mais tarde para validar o ciclo completo fala→texto→resposta→fala.

## Conclusão curta

Dois candidatos justificam uma prova de áudio depois que a rota de runtime for aprovada:

1. **Piper `pt_BR-faber-medium` ONNX** — primeiro candidato para avaliação de baixo consumo: arquivo de voz de aproximadamente 63 MB, uma voz masculina pt-BR, 22,05 kHz, voz/dataset declarados CC0 e inferência comunitária direta com ONNX Runtime CPU. O engine Piper atual é GPL-3.0-or-later; o exemplo ONNX sem Piper é fornecido por um rehost comunitário e requer eSpeak NG, cuja licença é GPL-3.0-or-later. Windows e a combinação final de dependências ainda não foram testados.
2. **Kokoro-82M v1.0** — alternativa de maior interesse por variedade vocal: pesos e pacote Python Apache-2.0, frontend Misaki Apache-2.0 e três vozes pt-BR documentadas. A cadeia para português usa eSpeak NG `pt-br`/phonemização; avaliar essa dependência GPL separadamente. As notas de vozes alertam que dados G2P/treino em línguas não inglesas podem ser escassos; as vozes brasileiras não têm nota de qualidade publicada no `VOICES.md`.

**Nenhum foi escolhido ainda.** O Faber é a hipótese de menor custo para uma primeira medição CPU; Kokoro é a alternativa principal para comparar voz/naturalidade. Nenhuma das licenças do componente implica a licença de todo o bundle.

## Comparação

| Critério | Piper Faber medium (ONNX) | Kokoro-82M v1.0 |
|---|---|---|
| Idioma/voz | `pt_BR`, uma voz masculina Faber | `pt-BR`, `pf_dora`, `pm_alex`, `pm_santa` |
| Peso de voz/modelo | Cerca de 63 MB / ~15M parâmetros, conforme model card comunitário | 82M parâmetros; o card oficial não lista o tamanho exato do artefato na tabela de vozes |
| Licença declarada do peso | CC0 para voz Faber e dataset OHF Voice Datasets segundo os cards consultados; confirmar o card upstream na revisão exata antes de obter o arquivo | Apache-2.0 para os pesos do modelo |
| Código de inferência | Engine Piper ativo: GPL-3.0-or-later. Há exemplo comunitário de inferência direta ONNX sob MIT, sem dependência do pacote Piper | Pacote `kokoro`: Apache-2.0; `misaki`: Apache-2.0 |
| Dependências relevantes | Exemplo ONNX requer ONNX Runtime CPU e eSpeak NG. eSpeak NG é GPL-3.0-or-later. Exemplo publicado é para macOS/Linux; Windows precisa validação própria | PyTorch, Transformers, Misaki e eSpeak NG para o pipeline demonstrado/idioma. Verificar versões e todas as licenças antes de instalar |
| Hardware/backend | Rota ONNX CPU indicada pelo model card; nenhuma execução foi feita no Ryzen 5 5500. GPU não é necessária para a hipótese inicial | Implementação oficial baseada em PyTorch; nenhuma evidência de Vulkan/DirectML Windows na máquina alvo. Não presumir aceleração RX 580 |
| Qualidade PT-BR documentada | Voz rotulada como `medium` no ecossistema Piper (rótulo de tamanho do modelo, não nota de qualidade); amostras ainda precisam de revisão humana | O guia lista três vozes pt-BR, mas não lhes atribui grade; o card alerta que línguas não inglesas podem ter G2P/treino limitados |
| Situação | **Primeiro candidato para benchmark leve**, condicionado a revisar origem/revisão e dependências | **Comparador de qualidade vocal**, condicionado a conseguir uma rota local aprovada e revisar eSpeak/licenças |

## Licenças: não colapsar o stack

- O repositório atual `OHF-Voice/piper1-gpl` é GPL-3.0-or-later; o `rhasspy/piper` original MIT foi arquivado. O engine atual pode ser livre de usar, mas é copyleft, então não corresponde à preferência de licença mais permissiva.
- O peso `pt_BR-faber-medium` declara CC0 e seu card de checkpoint identifica o dataset OHF Voice Datasets também como CC0. Usar o peso em um runtime independente não torna o runtime Piper MIT; conferir separadamente os arquivos exatos e a procedência de um rehost.
- O card comunitário Trelis mostra uma rota ONNX direta sem o pacote `piper-tts`, rotula o exemplo como MIT e usa eSpeak NG como subprocesso. Isso evita depender do engine Piper no código de exemplo, mas **não** remove a dependência GPL do executável e não prova que o pacote completo seja licenciável apenas como MIT.
- O Kokoro oficial declara pesos Apache-2.0; o repositório de código e Misaki também trazem Apache-2.0. Isso não relicencia eSpeak NG, que é GPL-3.0-or-later. O modelo utiliza material CC BY identificado no próprio card; manter atribuições se for distribuir artefatos derivados ou o pacote completo.
- Ainda não há decisão de distribuição comercial/closed-source; portanto registrar a cadeia de componentes em vez de concluir que “TTS é Apache/MIT” pelo modelo isolado.

## Protocolo proposto para a prova de áudio

Depois de aprovar a rota de runtime, comparar primeiro Faber e Kokoro em execução CPU, com os mesmos textos e áudio em WAV:

1. Amostra pt-BR de ~100–150 palavras, contendo perguntas, números, siglas, nomes e pontuação; usar texto original da Lia, sem imitar voz de pessoa real.
2. Trecho curto de 1–2 frases para medir latência inicial e comportamento em mensagens breves; Kokoro documenta possível queda de qualidade em enunciados muito curtos.
3. Parágrafo maior para avaliar prosódia, pronúncia e artefatos de chunking; verificar também cortes, retomada/interrupção e normalização de números.
4. Avaliação humana cega (naturalidade, clareza, sotaque pt-BR e preferência), latência para primeiro áudio, duração de síntese/áudio (real-time factor), RAM e eventual uso de GPU.
5. Usar ao menos um falante feminino e um masculino quando disponíveis; a preferência de voz/persona continua em aberto. Não clonar pessoa real sem autorização específica.
6. Depois dos testes isolados, fazer uma amostra do pipeline de voz: ASR recebe fala de entrada; Qwen3-4B responde; TTS lê o texto. Medir latência total, sincronização e evitar que o microfone transcreva o próprio áudio da Lia (iniciar em half-duplex/fones; AEC só depois de validar).

## Dependências e próximo gate

- O runtime local já confirmado é `llama.cpp` Vulkan para Qwen3-4B; ele não fornece, por si só, inferência Kokoro ou Piper. Não reutilizar o mesmo executável como se fosse compatível com esses vocoders.
- ONNX Runtime, PyTorch, eSpeak NG e qualquer frontend TTS ainda não foram confirmados como instalados. **Não os instalar nem atualizar sem autorização.** A autorização permanente para baixar pesos não cobre runtimes/dependências.
- O próximo passo implementado é um preflight via `Update-Lia.bat` sem argumentos: tenta consultar apenas vozes Windows `System.Speech`/SAPI já instaladas e gera uma amostra WAV local se encontrar voz pt-BR. Se a API/voz não estiver disponível, registra isso sem instalar ou baixar nada. Esse resultado é somente baseline/fallback do Windows, não prova de TTS neural.
- Se não houver voz nativa utilizável, a decisão seguinte será escolher a rota (ONNX CPU/Faber primeiro ou Kokoro/PyTorch) e revisar o pacote/termos. Só então preparar o teste pelo launcher único `Update-Lia.bat`; baixar pesos apenas com registro de origem, revisão, licença, SHA-256 e caminho externo em [`RESOURCE-REGISTRY.md`](RESOURCE-REGISTRY.md).

## Fontes primárias consultadas

- [Model card oficial Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M) — licença dos pesos, uso e idiomas.
- [VOICES.md oficial do Kokoro](https://huggingface.co/hexgrad/Kokoro-82M/blob/main/VOICES.md) — vozes pt-BR, `lang_code='p'`, `espeak-ng pt-br` e ressalva de dados G2P/treino.
- [Código e dependências do Kokoro](https://github.com/hexgrad/kokoro/blob/main/pyproject.toml) e [LICENSE](https://github.com/hexgrad/kokoro/blob/main/LICENSE); [LICENSE do Misaki](https://github.com/hexgrad/misaki/blob/main/LICENSE).
- [eSpeak NG](https://github.com/espeak-ng/espeak-ng) — licença GPL-3.0-or-later.
- [Piper engine ativo](https://github.com/OHF-Voice/piper1-gpl) e [repositório antigo](https://github.com/rhasspy/piper) — confirmar diferença GPL atual/MIT arquivado.
- [Card do checkpoint upstream Piper Faber medium](https://huggingface.co/datasets/rhasspy/piper-checkpoints/blob/main/pt/pt_BR/faber/medium/MODEL_CARD) — pt_BR, 22,05 kHz, voz medium e dataset CC0.
- [Rehost e exemplo direto ONNX Faber](https://huggingface.co/Trelis/piper-pt-br-faber-medium) — 63 MB, licença declarada CC0 e exemplo de inferência separado do engine Piper; precisa conferir a revisão com upstream antes de baixar.
