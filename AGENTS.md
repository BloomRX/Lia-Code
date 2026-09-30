# Lia-Code — instruções de continuidade para agentes

## Objetivo principal

Criar a **Lia como assistente Omni local-first**: uma única experiência de usuário que conversa por texto, entende imagens, fala/áudio e vídeo, e responde por texto e voz. A arquitetura deve permitir que o usuário escolha entre várias personas no futuro.

Não tratar o benchmark de personalidade como objetivo principal da sessão. É uma fase subordinada e está pausada até o usuário reunir personagens de referência.

## Decisão de arquitetura registrada — 2026-09-29

**Começar com módulos especializados, substituíveis, coordenados por um orquestrador local — não fundir checkpoints nem treinar um modelo monolítico agora.** A Lia entregue ao usuário continua sendo uma única assistente Omni; modularidade é a estratégia para chegar lá com hardware limitado. Em paralelo, avaliar modelos Omni unificados quantizados como candidatos de substituição quando houver prova de runtime e memória.

- Camadas a investigar: LLM/texto e orquestração; visão; ASR/entendimento de áudio; TTS; vídeo, inicialmente combinando amostragem de quadros com áudio sincronizado.
- Usar interfaces comuns entre os módulos para poder trocar um especialista por um modelo unificado sem refazer a aplicação.
- Não “juntar” pesos de LLM, ASR, TTS e visão por simples merge: arquiteturas, tokenizers e objetivos diferem. Qualquer adaptação conjunta/LoRA fica para depois de uma prova de conceito e de um conjunto de dados aprovado.
- Não declarar a Lia “Omni” só por aceitar imagens; testar entradas e saídas de cada modalidade separadamente e em conjunto.

Motivo para começar modular: o alvo atual é uma RX 580 com 8 GB de VRAM. Como referência, a documentação oficial do Qwen2.5-Omni lista 18,38 GB como mínimo teórico BF16 para inferência de vídeo de 15 segundos com Transformers (e alerta que o uso real costuma ser maior). Isso não exclui quantização ou outros runtimes, mas exige uma prova prática antes de escolher esse caminho. [Documentação oficial](https://github.com/QwenLM/Qwen2.5-Omni#minimum-gpu-memory-requirements).

## Restrições permanentes do usuário

- Preferir ferramentas e pesos gratuitos; verificar licenças de modelo, runtime, conversões e dados antes de usar.
- Pedir confirmação antes de downloads grandes ou instalações adicionais.
- Manter pesos, runtimes e caches fora do repositório.
- Não trocar de branch: todo trabalho nesta sessão fica em `arena/01a0ec89-lia-code`.
- A raiz deve manter apenas `Update-Lia.bat` como launcher de benchmark; demais launchers ficam organizados em `benchmark/`.
- `Update-Lia.bat` sem argumentos agora roda apenas o preflight Omni sem downloads: hardware, cache e enumeração de dispositivos do runtime. A comparação textual 4B/8B é explicitamente `Update-Lia.bat quality-both`. Não reativar a bateria de personalidade por padrão sem pedido do usuário.

## Estado conhecido

- Qwen3-4B e Qwen3-8B foram comparados em quatro casos de texto; ambos completaram, com verificações de agenda/JSON aprovadas. Não houve vantagem qualitativa decisiva do 8B; usar 4B como baseline textual por menor exigência de VRAM, sem declarar modelo final.
- Os relatórios não confirmaram quantas camadas foram efetivamente executadas na GPU (`serverStartupEvidence` estava vazio).
- Testes de prompt Tsundere, até `prompt-v6-examples`, não produziram personalidade confiável. A resposta de autenticação ficou mais segura, mas o estilo continuou inconsistente. A bateria está preservada como opcional; aguardar a lista de personas do usuário antes de retomar.
- O usuário planeja fornecer personagens de anime para investigar personas múltiplas. Ao retomar, usar perfis comportamentais e exemplos com origem/licença clara; não presumir que dados de diálogo raspados estejam liberados.

## Próximo marco

O próximo teste único é `Update-Lia.bat` sem argumentos: executar o preflight Omni sem downloads, capturando dados do sistema/cache e a enumeração `llama-cli --list-devices` quando disponível. Esse resultado só informa prontidão do ambiente, não compatibilidade multimodal de um modelo. Depois de receber o relatório, produzir uma matriz **sem downloads** de candidatos omni e runtimes para Windows/RX 580/Vulkan: texto, imagem, fala/áudio, vídeo com áudio, voz de saída, quantização, memória, latência, suporte real por runtime e licença. Só então propor uma prova de conceito mínima; solicitar confirmação antes de baixar pesos ou instalar ferramentas. O roteiro está em [`docs/OMNI-ROADMAP.md`](docs/OMNI-ROADMAP.md).
