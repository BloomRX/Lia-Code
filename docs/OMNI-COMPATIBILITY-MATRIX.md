# Matriz preliminar de compatibilidade Omni

**Estado:** avaliação documental, sem downloads nem inferência. Revisada em 2026-09-29 a partir do preflight local `benchmark-results/lia-benchmark-20260929-221630.json` (commit `26a431b`). Esta matriz separa capacidades declaradas pelo modelo das comprovadas no hardware/runtime da Lia.

## Ambiente observado

| Item | Resultado do preflight | Interpretação |
|---|---|---|
| Sistema/CPU | Windows 11 Home, build 26200; Ryzen 5 5500, 6C/12T | Ambiente Windows x64 confirmado. |
| RAM | 15,89 GiB instalada; 5,09 GiB livres no início | Pouca margem para offload pesado à RAM enquanto Windows e aplicações estão ativos. |
| GPU | Radeon RX 580 2048SP; WMI reportou 4 GiB | WMI diverge do runtime; não usar esse número isoladamente. |
| Vulkan | llama.cpp enumerou `Vulkan0: AMD Radeon RX 580 2048SP (8192 MiB, 7367 MiB free)` | Confirma enumeração Vulkan e memória livre naquele instante, não execução/offload de modelo. |
| Runtime encontrado | Cache local `llama.cpp 0.5.0-dev (build 11249, commit 6d78fb072)`, binário Vulkan; não está no PATH | A versão exibida não basta para deduzir suporte a cada modelo/modalidade. |
| Outros runtimes/assets | Ollama ausente; nenhum asset com nome Omni detectado | Nenhum candidato Omni local foi testado. |
| Espaço no cache | 202,11 GiB livres | Espaço em disco disponível não implica compatibilidade ou VRAM suficiente. |

## Candidatos e rotas

| Candidato/rota | Entradas e saídas documentadas | Compatibilidade publicada | Encaixe na RX 580 / estado | Licença e decisão |
|---|---|---|---|---|
| **Qwen2.5-Omni-3B oficial via Transformers** | Texto, imagem, áudio e vídeo; resposta em texto e fala | O requisito teórico mínimo publicado para vídeo de 15 s em BF16 é 18,38 GiB; o projeto observa que uso real costuma ser pelo menos 1,2× o teórico. | **Não cabe no orçamento de 8 GiB em BF16**, ainda sem contabilizar margem operacional. Quantização não foi avaliada neste preflight e não deve ser presumida como solução. Nenhuma inferência local feita. | Apache-2.0 conforme repositório oficial. Manter apenas como referência de capacidades e baseline documental; não baixar nesta fase. |
| **Qwen2.5-Omni-3B GGUF via llama.cpp/MTMD** | A documentação atual do llama.cpp lista **entrada de áudio e visão/imagem** para esse modelo. O PR de suporte diz explicitamente que não implementou saída de áudio; vídeo não está listado como capacidade desse modelo no catálogo. | Há suporte upstream parcial em versões atuais, mas suporte genérico do runtime a imagem/áudio/vídeo não significa que todos os modelos suportem todas essas modalidades. | O binário local enumerou a GPU, mas o teste ocorreu apenas com `--list-devices`. A versão/capacidades específicas não foram validadas; essa rota, mesmo em upstream atual, **não satisfaz por si só** vídeo nativo + voz de saída. Memória, offload e qualidade ficam desconhecidos. | Os pesos mantêm a licença do modelo; conversões/quantizações também exigem conferir procedência e termos do repositório do arquivo. Não selecionar nem baixar agora. |
| **Arquitetura modular local (orquestrador + especialistas substituíveis)** | Pode combinar LLM/texto, visão/imagem, ASR para fala/áudio, extração de quadros/áudio para vídeo e TTS para voz | Capacidades, licenças, formatos e runtimes devem ser verificados separadamente para cada módulo; integração de interfaces não equivale a fundir pesos. | **Melhor hipótese para a prova de conceito futura**, pois permite limitar memória por etapa e substituir componentes. Ainda não é uma combinação validada no PC: nenhum módulo adicional foi instalado ou testado. Latência e qualidade dependem da orquestração. | Preferir pesos/ferramentas gratuitos; aprovar licença de cada componente e pedir confirmação antes de qualquer instalação/download. |

## Conclusão e próximo marco

1. O preflight foi concluído sem baixar ou carregar modelos. Há uma RX 580 2048SP com 8 GiB reconhecida pelo backend Vulkan e cerca de 7,2 GiB livres na enumeração observada. Isso **não** prova execução Omni.
2. A implementação oficial Qwen2.5-Omni-3B em BF16 para vídeo excede a VRAM disponível. A rota GGUF/llama.cpp oferece apenas um subconjunto documentado das modalidades Omni completas; a versão local também não foi qualificada para isso.
3. O próximo teste é a seleção do LLM textual-base entre famílias, usando somente GGUFs já em cache e o runtime existente. Comparar Qwen3-4B com Phi-4-mini, Granite 3.3-2B e Mistral 7B quando estiverem presentes/carregáveis. Não baixar pesos nem instalar/atualizar runtime nesta etapa; se faltar candidato, registrar e pedir autorização antes de prosseguir.
4. Depois de escolher a base textual, retomar a comparação documental dos especialistas para imagem/áudio/vídeo/voz e propor uma prova de conceito modular pequena.

## Fontes

- [Qwen2.5-Omni — repositório oficial](https://github.com/QwenLM/Qwen2.5-Omni): capacidades, licença e tabela de memória para Transformers/BF16.
- [llama.cpp — documentação multimodal](https://github.com/ggml-org/llama.cpp/blob/master/docs/multimodal.md): capacidades específicas dos modelos GGUF publicados, incluindo Qwen2.5 Omni.
- [llama.cpp PR #13784 — suporte Qwen2.5 Omni](https://github.com/ggml-org/llama.cpp/pull/13784): implementa áudio e visão de entrada; declara ausência de geração de áudio.
