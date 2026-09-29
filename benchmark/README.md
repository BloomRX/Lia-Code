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

## Fase 1 — benchmark de inferência local

Execute `benchmark/Update-and-Run-Lia-Benchmark.bat`. Ele valida que o clone está na branch da sessão, faz `git pull --ff-only` dessa branch e inicia `run-inference-benchmark.ps1`. Na primeira execução, o script pede confirmação antes de baixar o llama.cpp com Vulkan e o modelo Qwen3-4B-Instruct-2507 Q4_K_M (aproximadamente 2,5 GB). Não instala drivers nem altera configurações do Windows. Os downloads ficam em `%LOCALAPPDATA%\Lia-Code\benchmark-cache`, fora do repositório, e são reutilizados nas próximas execuções.

O teste roda `llama-bench` com parâmetros fixos (256 tokens de prompt, até 64 tokens gerados, 6 threads, 2 repetições): primeiro CPU (`-ngl 0`), depois tenta Vulkan na RX AMD se o runtime a detectar. Registra saída bruta, duração e erros. Isso mede throughput, não qualidade de respostas nem consumo de VRAM com precisão; se Vulkan não reconhecer a placa, o benchmark CPU ainda é guardado e enviado.

Ao terminar, tenta fazer commit e push apenas dos dois relatórios de inferência para `origin/arena/01a0ec89-lia-code`. O processo para se estiver em outra branch ou se houver alterações staged, para evitar incluir outros arquivos. Requer Git autenticado no Windows. Se push falhar, os resultados continuam em `benchmark-results/`.

A linha de comando de atualização automática é limitada a `git pull --ff-only origin arena/01a0ec89-lia-code`; se houver divergência ou alterações que impeçam o avanço seguro, ela para sem sobrescrever arquivos.
