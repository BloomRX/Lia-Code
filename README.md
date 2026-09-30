# Lia-Code

Projeto para desenvolver a Lia como uma assistente local **omnimodal** e extensível a várias personas.

## Próximo passo

Escolher primeiro um LLM-base local por comparação de qualidade e recursos, antes de integrar imagem, áudio, vídeo e voz. Consulte [`docs/OMNI-ROADMAP.md`](docs/OMNI-ROADMAP.md) para o plano, restrições e critérios de decisão.

## Benchmarks atuais

Os testes e launchers ficam documentados em [`benchmark/README.md`](benchmark/README.md). `Update-Lia.bat` na raiz compara LLMs de texto de diferentes famílias; apenas pesos autorizados/registrados podem ser baixados ao cache externo. Consulte [`docs/RESOURCE-REGISTRY.md`](docs/RESOURCE-REGISTRY.md) para removê-los depois. O preflight Omni fica como modo explícito. A bateria de personalidade está pausada enquanto aguardamos referências para personas múltiplas.
