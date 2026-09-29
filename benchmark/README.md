# Benchmark inicial da Lia-Code

## Executar no Windows

1. Baixe/cl clone esta branch do Lia-Code.
2. Execute `benchmark/Run-Lia-Benchmark.bat` com duplo clique.
3. Ao terminar, envie de volta os arquivos criados em `benchmark-results/`:
   - `lia-benchmark-<data-hora>.log`
   - `lia-benchmark-<data-hora>.json`

O script usa apenas componentes do Windows/PowerShell. Não instala programas, não baixa modelos e não altera drivers. Ele coleta informações básicas do Windows, CPU, RAM, GPU/driver, detecta Python/Git/Ollama/llama.cpp e, se Ollama já estiver instalado, lista somente os modelos locais.

Ao final, ele tenta automaticamente criar um commit contendo **apenas** os dois relatórios desta execução e fazer push para `origin/arena/01a0ec89-lia-code`. O processo recusa enviar se a branch atual for diferente da branch esperada ou se houver arquivos já staged. Git precisa estar instalado e autenticado; se o push falhar, os relatórios permanecem em `benchmark-results/` para envio manual. Nenhum outro arquivo do repositório é incluído pelo script.

Os relatórios incluem detalhes do sistema e dos dispositivos, mas omitem nome do computador e identificadores PnP. Ainda assim, revise-os se preferir não compartilhar informações de hardware. O diretório fica ignorado pelo Git em uso normal; o script adiciona explicitamente apenas os relatórios gerados.

## O que esta primeira fase mede (fase 0)

Esta rodada verifica o ambiente e os runtimes disponíveis. **Ainda não mede tokens por segundo, latência real de inferência nem qualidade do modelo.** Não é correto comparar modelos antes de escolhermos um runtime e uma configuração compatíveis com a RX 580. A informação de VRAM obtida via WMI pode ser incompleta; validaremos isso com o runtime escolhido.

Depois de analisar o relatório, a próxima rodada será um teste de inferência repetível, com modelo/configuração explicitamente selecionados, prompts fixos e medições de tempo, memória e erros. Nenhum modelo será baixado sem decisão explícita.
