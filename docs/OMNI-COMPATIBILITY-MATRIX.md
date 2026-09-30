# Matriz preliminar de compatibilidade Omni

**Estado:** avaliação documental de modalidades; revisada em 2026-09-30 com evidência textual Vulkan do relatório `benchmark-results/lia-llm-comparison-20260930-085425.json`. A matriz separa capacidades declaradas dos modelos daquelas comprovadas no hardware/runtime da Lia; Qwen3-4B só foi validado para texto.

## Ambiente observado

| Item | Resultado do preflight | Interpretação |
|---|---|---|
| Sistema/CPU | Windows 11 Home, build 26200; Ryzen 5 5500, 6C/12T | Ambiente Windows x64 confirmado. |
| RAM | 15,89 GiB instalada; 5,09 GiB livres no início | Pouca margem para offload pesado à RAM enquanto Windows e aplicações estão ativos. |
| GPU | Radeon RX 580 2048SP; WMI reportou 4 GiB | WMI diverge do runtime; não usar esse número isoladamente. |
| Vulkan | `Vulkan0: AMD Radeon RX 580 2048SP (8192 MiB, 7367 MiB free)` | Enumeração mais diagnóstico de Qwen3-4B com `--verbose`: `offloaded 37/37 layers to GPU`; confirma offload para inferência de texto, não capacidade Omni. |
| Runtime encontrado | Cache local `llama.cpp 0.5.0-dev (build 11249, commit 6d78fb072)`, binário Vulkan; não está no PATH | O diagnóstico verbose carregou Qwen3-4B: `offloaded 37/37 layers to GPU`; buffers finais 2375,91 MiB Vulkan model, 576 MiB KV, 79,01 MiB compute; 304,28 MiB CPU_Mapped e 14,01 MiB Vulkan_Host compute. Confirma offload para inferência textual, não suporte Omni. |
| Outros runtimes/assets | Ollama ausente; nenhum asset com nome Omni detectado | Nenhum candidato Omni local foi testado. |
| Espaço no cache | 202,11 GiB livres | Espaço em disco disponível não implica compatibilidade ou VRAM suficiente. |

## Candidatos e rotas

| Candidato/rota | Entradas e saídas documentadas | Compatibilidade publicada | Encaixe na RX 580 / estado | Licença e decisão |
|---|---|---|---|---|
| **Qwen2.5-Omni-3B oficial via Transformers** | Texto, imagem, áudio e vídeo; resposta em texto e fala | O requisito teórico mínimo publicado para vídeo de 15 s em BF16 é 18,38 GiB; o projeto observa que uso real costuma ser pelo menos 1,2× o teórico. | **Não cabe no orçamento de 8 GiB em BF16**, ainda sem contabilizar margem operacional. Quantização não foi avaliada neste preflight e não deve ser presumida como solução. Nenhuma inferência local feita. | Apache-2.0 conforme repositório oficial. Manter apenas como referência de capacidades e baseline documental; não baixar nesta fase. |
| **Qwen2.5-Omni-3B GGUF via llama.cpp/MTMD** | A documentação atual do llama.cpp lista **entrada de áudio e visão/imagem** para esse modelo. O PR de suporte diz explicitamente que não implementou saída de áudio; vídeo não está listado como capacidade desse modelo no catálogo. | Há suporte upstream parcial em versões atuais, mas suporte genérico do runtime a imagem/áudio/vídeo não significa que todos os modelos suportem todas essas modalidades. | O binário local enumerou a GPU, mas o teste ocorreu apenas com `--list-devices`. A versão/capacidades específicas não foram validadas; essa rota, mesmo em upstream atual, **não satisfaz por si só** vídeo nativo + voz de saída. Memória, offload e qualidade ficam desconhecidos. | Os pesos mantêm a licença do modelo; conversões/quantizações também exigem conferir procedência e termos do repositório do arquivo. Não selecionar nem baixar agora. |
| **Arquitetura modular local (orquestrador + especialistas substituíveis)** | Pode combinar LLM/texto, visão/imagem, ASR para fala/áudio, extração de quadros/áudio para vídeo e TTS para voz | Capacidades, licenças, formatos e runtimes devem ser verificados separadamente para cada módulo; integração de interfaces não equivale a fundir pesos. | **Melhor hipótese para a prova de conceito futura**, pois permite limitar memória por etapa e substituir componentes. Ainda não é uma combinação validada no PC: nenhum módulo adicional foi instalado ou testado. Latência e qualidade dependem da orquestração. | Preferir pesos/ferramentas gratuitos e registrar origem, licença e caminho externo de cada download autorizado; confirmar antes de instalar/atualizar software. |

## Conclusão e próximo marco

1. A base textual para a prova de conceito foi selecionada: **Qwen3-4B Q4_K_M**. Passou os checks de agenda, código Python, JSON e não-invenção; não mostrou desvantagem clara frente ao Qwen3-8B, que é maior. O Phi-4-mini foi inferior na rodada observada em agenda e código.
2. O diagnóstico confirmou inferência textual com Vulkan na RX 580 2048SP: `offloaded 37/37 layers to GPU`. Isso **não** prova capacidade multimodal Omni.
3. A implementação oficial Qwen2.5-Omni-3B em BF16 para vídeo excede a VRAM disponível. A rota GGUF/llama.cpp oferece apenas um subconjunto documentado das modalidades Omni completas; o runtime local ainda não foi qualificado para esses modelos.
4. Próximo: retomar a comparação documental dos especialistas para imagem/áudio/vídeo/voz e projetar uma prova de conceito modular pequena. Não baixar recursos nem instalar/atualizar runtime até registrar compatibilidade, licença e requisitos.

## Fontes

- [Qwen2.5-Omni — repositório oficial](https://github.com/QwenLM/Qwen2.5-Omni): capacidades, licença e tabela de memória para Transformers/BF16.
- [llama.cpp — documentação multimodal](https://github.com/ggml-org/llama.cpp/blob/master/docs/multimodal.md): capacidades específicas dos modelos GGUF publicados, incluindo Qwen2.5 Omni.
- [llama.cpp PR #13784 — suporte Qwen2.5 Omni](https://github.com/ggml-org/llama.cpp/pull/13784): implementa áudio e visão de entrada; declara ausência de geração de áudio.
