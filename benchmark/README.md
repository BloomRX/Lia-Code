# Benchmarks da Lia-Code

## Um clique para o próximo teste

Para executar o próximo teste Omni, use **`Update-Lia.bat` na raiz, sem argumentos**. Ele atualiza a branch uma vez e executa um preflight sem baixar nem carregar modelos: coleta hardware, inventaria assets Omni já presentes no cache e tenta enumerar os dispositivos com `llama-cli --list-devices`. O relatório é salvo e enviado. Esse preflight não comprova suporte multimodal de um modelo específico nem estima a VRAM livre durante inferência; prepara a decisão de compatibilidade. A etapa de personalidade permanece pausada. Para repetir a comparação textual, use `Update-Lia.bat quality-both` ou `benchmark\Test-Lia-Quality.bat`; para testes isolados existem `Update-Lia.bat quality`, `Update-Lia.bat quality-8b`, `benchmark\Test-Lia-8B.bat` e `Update-Lia.bat speed`. A bateria de personalidade segue disponível em `benchmark\Test-Lia-Personality.bat`, mas não roda por padrão. Os relatórios ficam em `benchmark-results/` e são enviados para `origin/arena/01a0ec89-lia-code` quando Git estiver autenticado.

O atualizador faz backup de relatórios rastreados que estejam localmente alterados para `%LOCALAPPDATA%\Lia-Code\report-backups`, restaura apenas esses arquivos gerados e então executa `git pull --ff-only`. Alterações de código não são restauradas nem descartadas.

Para repetir o benchmark de velocidade, use `Update-Lia.bat speed`. Ambos os modos usam a branch `arena/01a0ec89-lia-code`.

## Fase 0 — diagnóstico de ambiente

`Update-Lia.bat` sem argumentos executa `benchmark/run-benchmark.ps1`: registra Windows, CPU, RAM, GPU/driver, espaço no cache, modelos Omni já presentes e runtimes encontrados. Quando acha `llama-cli` no cache ou PATH, captura versão e saída de `--list-devices`; isso confirma apenas a enumeração do backend, não o offload de um modelo Omni. Não instala nada nem baixa ou carrega pesos. A leitura de VRAM via WMI pode estar ausente/incorreta; os detalhes vão para `benchmark-results/`.

## Fase 1 — velocidade local

`Update-Lia.bat speed` compara CPU (`-ngl 0`) com offload Vulkan (`-ngl 99`) no modelo Qwen3-4B-Instruct-2507 Q4_K_M, usando 256 tokens de prompt, até 64 tokens de geração, seis threads e duas repetições. Métricas são throughput; não são avaliação de qualidade.

O runtime llama.cpp e o modelo GGUF são baixados somente se faltarem, com confirmação, para `%LOCALAPPDATA%\Lia-Code\benchmark-cache`; o modelo tem cerca de 2,5 GB. Nenhum driver é instalado ou alterado.

## Fase 2 — qualidade das respostas

O modo de qualidade executa quatro prompts fixos via servidor local compatível com Chat Completions, vinculado somente a `127.0.0.1`: persona Casual/Tsundere, Modo Sério, programação Python e cumprimento de instruções/JSON. Guarda prompt, resposta, latência e uma rubrica para avaliação humana. Só o formato JSON recebe checagem automática objetiva; não há um “placar de inteligência” automático. `quality-8b` baixa, com confirmação, o Qwen3-8B Q4_K_M de aproximadamente 5,03 GB, sob Apache-2.0, e o executa no mesmo runtime/prompts. O modo 8B desativa o modo de pensamento interno no template para comparar as respostas finais dentro do mesmo limite de tokens; isso não mede a capacidade de raciocínio profundo. Na RX 580 de 8 GB, feche o Chrome antes desse teste maior; o carregamento pode falhar se a VRAM disponível cair abaixo do necessário.

As respostas são evidência comparável para avaliar o modelo, não garantias de personalidade ou correção. Se o cache/modelo não existir, primeiro rode `Update-Lia.bat speed`.

## Fase 3 — personalidade (prompt, sem treino de pesos)

A bateria de personalidade (dez respostas no Qwen3-4B) está preservada em `benchmark\Test-Lia-Personality.bat`, mas foi retirada do ciclo padrão. Na rodada mais recente, `prompt-v6-examples` manteve respostas seguras para frustração e autenticação, mas ainda recorreu a emojis e a Tsundere ficou inconsistente. Vamos retomar esta fase quando houver uma lista de personas de referência e exemplos escritos/selecionados com cuidado.

A próxima retomada deve criar perfis configuráveis para diferentes arquétipos/personas, um conjunto de exemplos de treino e um conjunto separado de avaliação. Antes de escolher LoRA ou outra técnica, verificar a viabilidade no hardware e a licença do modelo/dos dados. Não baixar runtime, datasets grandes nem iniciar fine-tuning sem confirmação.

## Privacidade e envio dos resultados

Os scripts evitam o cabeçalho de transcrição do PowerShell e substituem o caminho do perfil por `%USERPROFILE%` nos logs. Os logs contêm especificações do hardware e saídas do modelo. O auto-submit adiciona somente o `.log` e `.json` gerados daquela execução; ele para se estiver em outra branch ou se houver alterações já staged. Se o push falhar, os relatórios ficam em `benchmark-results/`.
