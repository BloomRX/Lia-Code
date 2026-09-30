# Lia Omni — roadmap e próximo marco

## Objetivo do projeto

Desenvolver uma assistente local para a Lia com capacidades **omnimodais**: conversar por texto, perceber imagens, entender fala/áudio e vídeo e responder por texto e voz. A arquitetura e a interface devem permitir trocar a persona sem refazer o sistema; a lista de personagens de referência e o trabalho de personalidade ficam para uma fase posterior, quando o usuário a reunir.

## Restrições e estado atual

- Priorizar software e pesos gratuitos, respeitando licenças e termos dos dados.
- Hardware-alvo inicial: Windows, Radeon RX 580 com 8 GB de VRAM. Não presumir que um modelo “3B” ou um arquivo GGUF caiba na VRAM: encoders de áudio/vídeo, contexto e buffers também consomem memória.
- Confirmar antes de iniciar downloads grandes ou instalar runtimes adicionais. Modelos e caches ficam fora do repositório.
- Os relatórios atuais comparam Qwen3 4B e 8B **somente em tarefas de texto**; ambos foram viáveis nos testes qualitativos, sem vantagem clara do 8B. Isso não demonstra capacidade multimodal nem confirma o número de camadas efetivamente descarregadas na GPU (`serverStartupEvidence` dos relatórios está vazio).
- O `Update-Lia.bat` padrão está pausado na etapa de personalidade: ele roda apenas a comparação de qualidade 4B/8B. A bateria de personalidade permanece disponível separadamente, mas não é prioridade até chegar a lista de personas.

## Próximo marco: viabilidade multimodal, sem download

Antes de escolher ou baixar um modelo, produzir uma matriz de compatibilidade com:

1. **Modalidades de entrada:** texto, imagem, fala, áudio não verbal e vídeo (incluindo áudio sincronizado).
2. **Modalidades de saída:** texto e voz; qualidade e latência de fala em português brasileiro.
3. **Runtime e sistema:** suporte real no Windows e no backend Vulkan/RX 580 para cada modalidade; formatos de peso, quantizações, encoders/projetores auxiliares e dependências.
4. **Recursos:** VRAM/RAM estimadas para contexto curto e cenários práticos, velocidade, latência inicial e funcionamento com Chrome aberto/fechado.
5. **Licenças:** licença dos pesos, código, quantizações convertidas e conjuntos de dados.

Uma opção a investigar é Qwen2.5-Omni-3B: o projeto oficial descreve entradas de texto, imagem, áudio e vídeo e geração de texto e fala. Porém, a tabela oficial de memória para Transformers/BF16 indica 18,38 GB como mínimo teórico para 15 segundos de vídeo e observa que o uso real tende a ser pelo menos 1,2× maior. Portanto, **a execução oficial sem quantização não cabe na RX 580 de 8 GB**; qualquer quantização ou runtime alternativo precisará de uma checagem própria, incluindo suporte end-to-end a áudio e vídeo. Não baixar esse modelo até concluir a matriz e pedir confirmação.

## Fases seguintes

- **Fase A — compatibilidade:** comparar modelos omni pequenos e runtimes, sem baixar pesos.
- **Fase B — prova de conceito:** após confirmação, testar o candidato de menor risco com amostras próprias pequenas para texto, imagem, fala, vídeo e fala de saída. Registrar qualidade, memória, latência e limites por modalidade.
- **Fase C — integração Lia:** estabelecer interface única de conversa, streaming, interrupção de fala, permissões de câmera/microfone e funcionamento offline; manter módulos substituíveis quando um único modelo não cobrir uma tarefa.
- **Fase D — personas:** depois que o usuário trouxer a lista de personagens, criar perfis configuráveis e exemplos originais para cada persona, com conjunto de avaliação separado. Só então comparar prompt, adapters/LoRA e outras técnicas, após verificar hardware, licença e dados.

## Critérios de decisão

Não chamar a Lia de “Omni” apenas porque o modelo aceita imagens. O candidato precisa passar testes explícitos de texto + imagem, fala de entrada, áudio não verbal, vídeo com áudio e fala de saída, além de funcionar dentro do orçamento de recursos e das licenças aprovadas. Se o RX 580 não sustentar tudo localmente, documentar uma arquitetura em módulos e manter claro quais partes são locais, opcionais ou dependem de hardware externo.

## Referências

- [Qwen2.5-Omni — repositório oficial](https://github.com/QwenLM/Qwen2.5-Omni) — modalidades e arquitetura Thinker–Talker; tabela de requisitos de memória.
- [Qwen2.5-Omni — anúncio oficial](https://qwenlm.github.io/blog/qwen2.5-omni/) — capacidades multimodais declaradas.
