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

- Benchmarks históricos de quatro prompts não mostraram vantagem qualitativa decisiva do Qwen3-8B. A comparação mais recente usou cinco prompts e reforçou o Qwen3-4B como baseline por eficiência, sem declará-lo modelo final.
- Na comparação cross-family de 2026-09-30, Qwen3-4B e 8B passaram código/JSON e não inventaram contexto. Ambos somaram 90 minutos na agenda com quatro itens numerados: 4B deu prioridade mais coerente (15/20/30/25); 8B também foi razoável (20/30/30/10). Não houve vantagem clara do 8B.
- A rodada `20260930-082728` testou Qwen3-4B e Phi-4-mini; Qwen3-8B foi pulado porque Chrome estava aberto. Qwen3-4B passou agenda (15/20/30/25), Python, JSON e não invenção de contexto. Phi falhou agenda (30+25+40+45, sem unidade; total 140) e Python inválido; JSON e não-invenção passaram. Phi SWA estava desativado.
- Phi-4-mini Q4_K_M foi baixado para `%LOCALAPPDATA%\Lia-Code\benchmark-cache\models\microsoft_Phi-4-mini-instruct-Q4_K_M.gguf`, SHA-256 verificado e registrado em `docs/RESOURCE-REGISTRY.md`.
- Os logs de ambas as rodadas só dizem `model loaded`, sem camadas/buffers Vulkan; o uso efetivo da GPU ainda não está comprovado. Não instalar/atualizar runtime.
- Testes de prompt Tsundere, até `prompt-v6-examples`, não produziram personalidade confiável. A resposta de autenticação ficou mais segura, mas o estilo continuou inconsistente. A bateria está preservada como opcional; aguardar a lista de personas do usuário antes de retomar.
- Testes de prompt Tsundere, até `prompt-v6-examples`, não produziram personalidade confiável. A resposta de autenticação ficou mais segura, mas o estilo continuou inconsistente. A bateria está preservada como opcional; aguardar a lista de personas do usuário antes de retomar.
- O usuário planeja fornecer personagens de anime para investigar personas múltiplas. Ao retomar, usar perfis comportamentais e exemplos com origem/licença clara; não presumir que dados de diálogo raspados estejam liberados.

## Próximo marco

O próximo teste único é `Update-Lia.bat` sem argumentos: diagnóstico focado no Qwen3-4B, com logging verbose para registrar backend Vulkan, camadas e buffers, e duas amostras curtas. Não baixar pesos nem instalar/atualizar runtime. O Phi já baixado permanece registrado para remoção posterior. O roteiro está em [`docs/OMNI-ROADMAP.md`](docs/OMNI-ROADMAP.md).
