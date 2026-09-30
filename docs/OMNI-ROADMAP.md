# Lia Omni — roadmap e próximo marco

## Objetivo do projeto

Desenvolver uma assistente local para a Lia com capacidades **omnimodais**: conversar por texto, perceber imagens, entender fala/áudio e vídeo e responder por texto e voz. A arquitetura e a interface devem permitir trocar a persona sem refazer o sistema; a lista de personagens de referência e o trabalho de personalidade ficam para uma fase posterior, quando o usuário a reunir.

## Restrições e estado atual

- Priorizar software e pesos gratuitos, respeitando licenças e termos dos dados.
- Hardware-alvo inicial: Windows, Radeon RX 580 com 8 GB de VRAM. Não presumir que um modelo “3B” ou um arquivo GGUF caiba na VRAM: encoders de áudio/vídeo, contexto e buffers também consomem memória.
- O usuário autorizou downloads de pesos escolhidos pelo agente desde que cada recurso seja registrado com origem/caminho de exclusão. Não instalar ou atualizar runtime sem confirmação. Modelos e caches ficam fora do repositório.
- Os relatórios cross-family comparam modelos **somente em tarefas de texto**. Qwen3-4B é a recomendação provisória por resultados funcionais e menor tamanho; Qwen3-8B não mostrou vantagem clara. A execução de 2026-09-30 08:27 pulou o 8B porque Chrome estava aberto. Isso não demonstra capacidade multimodal nem confirma offload GPU: os logs registraram `model loaded`, sem camadas/buffers Vulkan.
- O próximo teste via `Update-Lia.bat` sem argumentos é um diagnóstico focado no Qwen3-4B, com logging verbose de inicialização para buscar evidência explícita de offload Vulkan. Não baixar pesos nem instalar/atualizar runtime; manter só duas amostras curtas.
- O preflight Omni já confirmou a enumeração Vulkan da RX 580 2048SP, mas não carregou modelo. O WMI reportou 4 GiB enquanto Vulkan enumerou 8192 MiB; essa divergência precisa ser tratada com evidência do runtime durante inferência.
- A bateria de personalidade permanece pausada até chegar a lista de personas.

## Próximo marco: validar a base textual no runtime

Usar Qwen3-4B como baseline provisório e capturar logs detalhados do `llama-server` para confirmar se houve offload Vulkan, quantas camadas foram carregadas e quais buffers foram alocados. Sem evidência, não afirmar que o modelo executou na GPU. Essa rodada não baixa pesos nem altera o runtime; o Phi já baixado continua no [`RESOURCE-REGISTRY.md`](RESOURCE-REGISTRY.md) para limpeza posterior. Só depois de validar a base textual retomar a matriz de compatibilidade Omni:

1. **Modalidades de entrada:** texto, imagem, fala, áudio não verbal e vídeo (incluindo áudio sincronizado).
2. **Modalidades de saída:** texto e voz; qualidade e latência de fala em português brasileiro.
3. **Runtime e sistema:** suporte real no Windows e no backend Vulkan/RX 580 para cada modalidade; formatos de peso, quantizações, encoders/projetores auxiliares e dependências.
4. **Recursos:** VRAM/RAM estimadas para contexto curto e cenários práticos, velocidade, latência inicial e funcionamento com Chrome aberto/fechado.
5. **Licenças:** licença dos pesos, código, quantizações convertidas e conjuntos de dados.

Uma opção a investigar é Qwen2.5-Omni-3B: o projeto oficial descreve entradas de texto, imagem, áudio e vídeo e geração de texto e fala. Porém, a tabela oficial de memória para Transformers/BF16 indica 18,38 GB como mínimo teórico para 15 segundos de vídeo e observa que o uso real tende a ser pelo menos 1,2× maior. Portanto, **a execução oficial sem quantização não cabe na RX 580 de 8 GB**; qualquer quantização ou runtime alternativo precisará de uma checagem própria, incluindo suporte end-to-end a áudio e vídeo. Não baixar esse modelo até concluir a matriz e pedir confirmação.

## Fases seguintes

- **Fase A — compatibilidade:** comparar modelos omni pequenos e runtimes, sem baixar pesos.
- **Fase B — prova de conceito:** após selecionar candidatos e registrar cada recurso baixado, testar o candidato de menor risco com amostras próprias pequenas para texto, imagem, fala, vídeo e fala de saída. Registrar qualidade, memória, latência e limites por modalidade; confirmar separadamente antes de instalar/atualizar ferramentas.
- **Fase C — integração Lia:** estabelecer interface única de conversa, streaming, interrupção de fala, permissões de câmera/microfone e funcionamento offline; manter módulos substituíveis quando um único modelo não cobrir uma tarefa.
- **Fase D — personas:** depois que o usuário trouxer a lista de personagens, criar perfis configuráveis e exemplos originais para cada persona, com conjunto de avaliação separado. Só então comparar prompt, adapters/LoRA e outras técnicas, após verificar hardware, licença e dados.

## Critérios de decisão

Não chamar a Lia de “Omni” apenas porque o modelo aceita imagens. O candidato precisa passar testes explícitos de texto + imagem, fala de entrada, áudio não verbal, vídeo com áudio e fala de saída, além de funcionar dentro do orçamento de recursos e das licenças aprovadas. Se o RX 580 não sustentar tudo localmente, documentar uma arquitetura em módulos e manter claro quais partes são locais, opcionais ou dependem de hardware externo.

## Referências

- [Qwen2.5-Omni — repositório oficial](https://github.com/QwenLM/Qwen2.5-Omni) — modalidades e arquitetura Thinker–Talker; tabela de requisitos de memória.
- [Qwen2.5-Omni — anúncio oficial](https://qwenlm.github.io/blog/qwen2.5-omni/) — capacidades multimodais declaradas.
