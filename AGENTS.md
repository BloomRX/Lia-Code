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
- O usuário autorizou downloads de modelos escolhidos pelo agente, desde que cada recurso externo seja registrado com caminho para remoção. Não instalar ou atualizar software/runtimes sem confirmação.
- Manter pesos, runtimes e caches fora do repositório.
- Não trocar de branch: todo trabalho nesta sessão fica em `arena/01a0ec89-lia-code`.
- A raiz deve manter apenas `Update-Lia.bat` como launcher de benchmark; demais launchers ficam organizados em `benchmark/`.
- `Update-Lia.bat` sem argumentos roda a comparação textual cross-family. Pode baixar apenas pesos aprovados/registrados (atualmente Phi-4-mini Q4_K_M) ao cache externo; nunca instala/atualiza runtime. O preflight Omni permanece disponível como modo explícito. A comparação antiga 4B/8B e testes isolados permanecem disponíveis; personalidade não roda por padrão.

## Estado conhecido

- Qwen3-4B e Qwen3-8B foram comparados em quatro casos de texto; ambos completaram, com verificações de agenda/JSON aprovadas. Não houve vantagem qualitativa decisiva do 8B; usar 4B como baseline textual por menor exigência de VRAM, sem declarar modelo final.
- No teste cross-family 2026-09-29, somente Qwen3-4B estava disponível e foi executado. Phi/Granite/Mistral estavam ausentes; Qwen3-8B foi pulado por memória RAM livre insuficiente com Chrome aberto. Qwen3-4B produziu código/JSON corretos e não inventou dados, mas falhou na alocação de 90 minutos. A captura de logs de inicialização não trouxe evidência de offload GPU; o prompt de agenda e filtro de logs foram corrigidos para a próxima rodada.
- Os relatórios até agora não confirmaram quantas camadas foram efetivamente executadas na GPU (`startupEvidence` vazio).
- Testes de prompt Tsundere, até `prompt-v6-examples`, não produziram personalidade confiável. A resposta de autenticação ficou mais segura, mas o estilo continuou inconsistente. A bateria está preservada como opcional; aguardar a lista de personas do usuário antes de retomar.
- O usuário planeja fornecer personagens de anime para investigar personas múltiplas. Ao retomar, usar perfis comportamentais e exemplos com origem/licença clara; não presumir que dados de diálogo raspados estejam liberados.

## Próximo marco

O próximo teste único é `Update-Lia.bat` sem argumentos: baixar apenas o Phi-4-mini-instruct Q4_K_M autorizado, se ainda ausente, verificar SHA-256 e comparar com o Qwen3-4B já em cache. O caminho, licença, origem e checksum ficam em [`docs/RESOURCE-REGISTRY.md`](docs/RESOURCE-REGISTRY.md) para exclusão posterior. Não instalar/atualizar runtimes; registrar e ignorar os outros candidatos sem cache. O roteiro está em [`docs/OMNI-ROADMAP.md`](docs/OMNI-ROADMAP.md).
