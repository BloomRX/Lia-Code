# Lia-Code — instruções de continuidade para agentes

## Objetivo principal

Criar a **Lia como assistente Omni local-first**: uma única experiência de usuário que conversa por texto, entende imagens, fala/áudio e vídeo, e responde por texto e voz. A arquitetura deve permitir que o usuário escolha entre várias personas no futuro.

Não tratar o benchmark de personalidade como objetivo principal da sessão. É uma fase subordinada e está pausada até o usuário reunir personagens de referência.

## Plano principal confirmado pelo usuário — 2026-10-01

**Primeiro desenvolver, adaptar e validar separadamente os modelos especialistas da Lia (LLM, TTS, visão, ASR/áudio e outros necessários); somente depois integrar os modelos aprovados no sistema Lia-Omni.** Não antecipar a integração Omni enquanto os modelos especialistas ainda não atingiram seus próprios critérios de qualidade/compatibilidade. O Qwen3-4B é apenas baseline textual, e o Piper Plus é apenas uma tentativa TTS que não atingiu a qualidade desejada; nenhum dos dois está aprovado como modelo final.

“Criar modelos próprios” pode significar adaptar um modelo-base para a Lia; não implica treinar todas as arquiteturas do zero. Após o desenvolvimento isolado, “juntar” significa integrar/orquestrar modelos por interfaces, não fundir os pesos heterogêneos num checkpoint monolítico. Manter componentes substituíveis e avaliar eventual adaptação conjunta apenas como etapa posterior, com prova de conceito e dados aprovados.

- Desenvolver e avaliar LLM/texto, TTS, visão, ASR/entendimento de áudio e vídeo em trilhas separadas.
- Só iniciar a fase de integração Lia-Omni quando os especialistas selecionados estiverem aprovados de forma independente; então validar os fluxos combinados.
- Interfaces modulares são uma decisão de implementação para a integração futura, não uma mudança da sequência escolhida pelo usuário.
- Não declarar a Lia “Omni” só por aceitar imagens; testar entradas e saídas de cada modalidade separadamente e em conjunto.

Motivo para começar modular: o alvo atual é uma RX 580 com 8 GB de VRAM. Como referência, a documentação oficial do Qwen2.5-Omni lista 18,38 GB como mínimo teórico BF16 para inferência de vídeo de 15 segundos com Transformers (e alerta que o uso real costuma ser maior). Isso não exclui quantização ou outros runtimes, mas exige uma prova prática antes de escolher esse caminho. [Documentação oficial](https://github.com/QwenLM/Qwen2.5-Omni#minimum-gpu-memory-requirements).

## Restrições permanentes do usuário

- Preferir ferramentas e pesos gratuitos; verificar licenças de modelo, runtime, conversões e dados antes de usar.
- O usuário autoriza baixar pesos e recursos necessários quando origem, licença/SHA e caminho externo para remoção forem registrados. Em 2026-09-30, autorizou explicitamente ambientes TTS isolados/removíveis com Piper/DirectML para comparação; isso não autoriza instalar/atualizar runtimes globalmente ou adicionar outros stacks sem confirmação.
- Manter pesos, runtimes, venvs e caches fora do repositório.
- Não trocar de branch: todo trabalho nesta sessão fica em `arena/01a0ec89-lia-code`.
- A raiz deve manter apenas `Update-Lia.bat` como launcher de benchmark; demais scripts ficam organizados em `benchmark/`.
- `Update-Lia.bat` sem argumentos executa Piper Faber em venvs CPU e DirectML externos, gera WAVs e relatório de latência, instala somente no diretório removível autorizado. Outros modos permanecem explícitos; personalidade não roda por padrão.

## Estado conhecido

- Benchmarks históricos de quatro prompts não mostraram vantagem qualitativa decisiva do Qwen3-8B. A comparação mais recente usou cinco prompts e reforçou o Qwen3-4B como baseline por eficiência, sem declará-lo modelo final.
- Na comparação cross-family de 2026-09-30, Qwen3-4B e 8B passaram código/JSON e não inventaram contexto. Ambos somaram 90 minutos na agenda com quatro itens numerados: 4B deu prioridade mais coerente (15/20/30/25); 8B também foi razoável (20/30/30/10). Não houve vantagem clara do 8B.
- A rodada `20260930-082728` testou Qwen3-4B e Phi-4-mini; Qwen3-8B foi pulado porque Chrome estava aberto. Qwen3-4B passou agenda (15/20/30/25), Python, JSON e não invenção de contexto. Phi falhou agenda (30+25+40+45, sem unidade; total 140) e Python inválido; JSON e não-invenção passaram. Phi SWA estava desativado.
- Phi-4-mini Q4_K_M foi baixado para `%LOCALAPPDATA%\Lia-Code\benchmark-cache\models\microsoft_Phi-4-mini-instruct-Q4_K_M.gguf`, SHA-256 verificado e registrado em `docs/RESOURCE-REGISTRY.md`.
- O diagnóstico `20260930-085425` confirmou uso efetivo de Vulkan no Qwen3-4B: runtime escolheu `Vulkan0`/RX 580 2048SP e registrou `offloaded 37/37 layers to GPU`. No carregamento final: Vulkan model buffer 2375,91 MiB, KV buffer 576 MiB e compute buffer 79,01 MiB; CPU_Mapped model buffer 304,28 MiB e Vulkan_Host compute buffer 14,01 MiB. Chrome estava fechado, VRAM livre pré-teste 7367 MiB. Não instalar/atualizar runtime.
- Preflight TTS `20260930-091635`: Windows SAPI encontrou `Microsoft Maria Desktop` pt-BR e `Microsoft Zira Desktop` en-US; gerou `lia-sapi-ptbr-20260930-091635.wav` (860.206 bytes) no cache externo, sem downloads/instalações. Usuário rejeitou Maria como robótica/lenta, sem naturalidade/persona; buscar TTS neural.
- Testes de prompt Tsundere, até `prompt-v6-examples`, não produziram personalidade confiável. A resposta de autenticação ficou mais segura, mas o estilo continuou inconsistente. A bateria está preservada como opcional; aguardar a lista de personas do usuário antes de retomar.
- O usuário planeja fornecer personagens de anime para investigar personas múltiplas. Ao retomar, usar perfis comportamentais e exemplos com origem/licença clara; não presumir que dados de diálogo raspados estejam liberados.

## Próximo marco

O Qwen3-4B é a base textual selecionada; offload Vulkan confirmado (`37/37` camadas). Maria SAPI foi rejeitada. Benchmark `20260930-112224` confirmou Piper Faber CPU e DirectML na RX 580. Em texto curto: CPU primeiro áudio 80,5 ms / total 297 ms; DML 137,7 ms / total 652 ms. Em parágrafo: CPU primeiro áudio 88,7 ms / total 1,494 s; DML 219,5 ms / total 1,155 s. Nós DML confirmados; RTF 0,109/0,243 curto e 0,072/0,056 parágrafo. CPU provisoriamente preferível para resposta interativa por menor primeiro áudio; DML vence total em texto longo. Processo aquecido, 4 medições, carregamento do modelo separado (CPU 1,98 s; DML 2,39 s). WAVs externos em `%LOCALAPPDATA%\Lia-Code\tts\piper-directml-eval\audio`; pedir avaliação auditiva de qualidade antes de escolher a voz. Faber checkpoint license não explicitada para o peso; não redistribuir. ASR segue separado.
