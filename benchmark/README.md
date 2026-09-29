# Benchmark inicial da Lia-Code

## Executar no Windows

1. Baixe/cl clone esta branch do Lia-Code.
2. Execute `benchmark/Run-Lia-Benchmark.bat` com duplo clique.
3. Ao terminar, envie de volta os arquivos criados em `benchmark-results/`:
   - `lia-benchmark-<data-hora>.log`
   - `lia-benchmark-<data-hora>.json`

O script usa apenas componentes do Windows/PowerShell. Não instala programas, não baixa modelos e não altera drivers. Ele coleta informações básicas do Windows, CPU, RAM, GPU/driver, detecta Python/Git/Ollama/llama.cpp e, se Ollama já estiver instalado, lista somente os modelos locais. Não envia dados pela rede.

Os resultados ficam ignorados pelo Git porque podem conter identificadores do computador. Revise os arquivos antes de compartilhar; o nome do computador e identificadores de hardware podem aparecer no log.

## O que esta primeira fase mede (fase 0)

Esta rodada verifica o ambiente e os runtimes disponíveis. **Ainda não mede tokens por segundo, latência real de inferência nem qualidade do modelo.** Não é correto comparar modelos antes de escolhermos um runtime e uma configuração compatíveis com a RX 580. A informação de VRAM obtida via WMI pode ser incompleta; validaremos isso com o runtime escolhido.

Depois de analisar o relatório, a próxima rodada será um teste de inferência repetível, com modelo/configuração explicitamente selecionados, prompts fixos e medições de tempo, memória e erros. Nenhum modelo será baixado sem decisão explícita.
