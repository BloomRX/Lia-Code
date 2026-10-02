# Lia Omni — roadmap e próximo marco

## Objetivo do projeto

Desenvolver uma assistente local para a Lia com capacidades **omnimodais**: conversar por texto, perceber imagens, entender fala/áudio e vídeo e responder por texto e voz. A arquitetura e a interface devem permitir trocar a persona sem refazer o sistema; a lista de personagens de referência e o trabalho de personalidade ficam para uma fase posterior, quando o usuário a reunir.

## Restrições e estado atual

- Priorizar software e pesos gratuitos, respeitando licenças e termos dos dados.
- Hardware-alvo inicial: Windows, Radeon RX 580 com 8 GB de VRAM. Não presumir que um modelo “3B” ou um arquivo GGUF caiba na VRAM: encoders de áudio/vídeo, contexto e buffers também consomem memória.
- O usuário autorizou downloads de pesos escolhidos pelo agente desde que cada recurso seja registrado com origem/caminho de exclusão. Não instalar ou atualizar runtime sem confirmação. Modelos e caches ficam fora do repositório.
- As comparações avaliaram LLMs **somente em tarefas de texto**. Qwen3-4B foi selecionado como base textual da prova de conceito: passou agenda, Python, JSON e não-invenção; o Qwen3-8B não mostrou vantagem clara e é maior. A execução de 08:27 pulou o 8B porque Chrome estava aberto, mas ele foi testado numa rodada anterior.
- O diagnóstico `benchmark-results/lia-llm-comparison-20260930-085425.json` confirmou offload Vulkan: RX 580 2048SP escolhida; `offloaded 37/37 layers to GPU`; buffers finais: Vulkan model 2375,91 MiB, KV 576 MiB, compute 79,01 MiB. Também registrou 304,28 MiB `CPU_Mapped` e 14,01 MiB `Vulkan_Host` compute; não afirmar que todo byte do arquivo está em VRAM.
- O WMI reportou 4 GiB enquanto Vulkan enumerou 8192 MiB; usar evidência do runtime, não o WMI isolado. Nenhum runtime foi atualizado.
- Próximo foco escolhido: TTS primeiro, com ASR separado mas correlacionado no fluxo de voz. A avaliação documental de Piper Faber ONNX e Kokoro, dependências/licenças e protocolo de audição está em [`TTS-EVALUATION.md`](TTS-EVALUATION.md). Sem downloads ou instalações nesta fase.
- A bateria de personalidade permanece pausada até chegar a lista de personas.

## Sequência obrigatória confirmada pelo usuário — 2026-10-01

A ordem do projeto é: **(1) desenvolver/adaptar e aprovar cada modelo especialista separadamente; (2) só então integrar os modelos aprovados na Lia-Omni.** Não antecipar a construção/integração do sistema Omni enquanto LLM, TTS e os demais especialistas ainda estiverem em avaliação. “Integrar/juntar” significa conectá-los por interfaces e orquestração, não fundir seus pesos em um checkpoint.

“Modelo próprio” pode ser obtido por adaptação de um modelo-base; não pressupõe treinar arquitetura do zero. O Qwen3-4B é somente baseline de LLM, não modelo final aprovado. A tentativa Piper Plus é somente experimento TTS e não atingiu a qualidade desejada; não chamá-lo de TTS final nem repetir o treino sem diagnóstico/critério.

## Próximo marco: desenvolver e validar modelos especialistas

Trabalhar em trilhas isoladas, começando pelo TTS conforme foco escolhido, e avaliar os próximos especialistas sem integração prematura. A base textual Qwen3-4B já passou por alguns testes e o runtime Vulkan carregou todas as camadas reportadas; isso valida apenas um baseline de inferência textual, não um LLM final nem multimodalidade. Não baixar novos modelos nem instalar/atualizar runtime nesta fase sem respeitar os gates e autorizações registrados. O Phi já baixado continua registrado para limpeza posterior:

1. **Modalidades de entrada:** texto, imagem, fala, áudio não verbal e vídeo (incluindo áudio sincronizado).
2. **Modalidades de saída:** texto e voz; qualidade e latência de fala em português brasileiro.
3. **Runtime e sistema:** suporte real no Windows e no backend Vulkan/RX 580 para cada modalidade; formatos de peso, quantizações, encoders/projetores auxiliares e dependências.
4. **Recursos:** VRAM/RAM estimadas para contexto curto e cenários práticos, velocidade, latência inicial e funcionamento com Chrome aberto/fechado.
5. **Licenças:** licença dos pesos, código, quantizações convertidas e conjuntos de dados.

Uma opção a investigar é Qwen2.5-Omni-3B: o projeto oficial descreve entradas de texto, imagem, áudio e vídeo e geração de texto e fala. Porém, a tabela oficial de memória para Transformers/BF16 indica 18,38 GB como mínimo teórico para 15 segundos de vídeo e observa que o uso real tende a ser pelo menos 1,2× maior. Portanto, **a execução oficial sem quantização não cabe na RX 580 de 8 GB**; qualquer quantização ou runtime alternativo precisará de uma checagem própria, incluindo suporte end-to-end a áudio e vídeo. Não baixar esse modelo até concluir a matriz e pedir confirmação.

## Fases seguintes

- **Fase A — compatibilidade e seleção de cada especialista:** comparar candidatos de LLM, TTS, visão, ASR/áudio e vídeo; conferir formato, licença de código/pesos/dependências, suporte real em Windows/Vulkan e limites de memória. A shortlist e os pontos de risco estão em [`OMNI-MODULAR-ARCHITECTURE.md`](OMNI-MODULAR-ARCHITECTURE.md). Sem baixar pesos antes do gate de autorização/registro.
- **Fase B — desenvolver/adaptar e aprovar modelos separadamente:** registrar origem, revisão, licença e caminho externo dos pesos; adaptar/testar cada modelo com dados próprios aprovados. Se exigir instalar, compilar ou atualizar runtime/dependências, pedir autorização antes. Medir qualidade, memória, latência e limites por especialista. Nenhum módulo passa a final por mera execução bem-sucedida.
- **Fase C — integração Lia-Omni (bloqueada até aprovação da Fase B):** somente depois de os modelos especialistas selecionados atingirem os critérios independentes, estabelecer interface única de conversa, streaming, interrupção de fala, permissões de câmera/microfone e funcionamento offline. Integrar por interfaces/orquestração, sem fundir checkpoints heterogêneos.
- **Fase D — personas:** depois que o usuário trouxer a lista de personagens, criar perfis configuráveis e exemplos originais para cada persona, com conjunto de avaliação separado. Só então comparar prompt, adapters/LoRA e outras técnicas, após verificar hardware, licença e dados.

## Critérios de decisão

Não chamar a Lia de “Omni” apenas porque o modelo aceita imagens. O candidato precisa passar testes explícitos de texto + imagem, fala de entrada, áudio não verbal, vídeo com áudio e fala de saída, além de funcionar dentro do orçamento de recursos e das licenças aprovadas. Se o RX 580 não sustentar tudo localmente, documentar uma arquitetura em módulos e manter claro quais partes são locais, opcionais ou dependem de hardware externo.

## Referências

- [Qwen2.5-Omni — repositório oficial](https://github.com/QwenLM/Qwen2.5-Omni) — modalidades e arquitetura Thinker–Talker; tabela de requisitos de memória.
- [Qwen2.5-Omni — anúncio oficial](https://qwenlm.github.io/blog/qwen2.5-omni/) — capacidades multimodais declaradas.
