# Registro de recursos externos da Lia

Este registro lista pesos e runtimes guardados fora do Git para que possam ser excluídos ao fim do projeto. A autorização do usuário permite ao agente baixar modelos escolhidos, desde que origem/licença/caminho sejam registrados. **Nenhum runtime/software adicional está autorizado para instalação ou atualização. Não use `git clean` para remover esses recursos.**

## Phi-4-mini-instruct Q4_K_M — autorizado, pendente de download

- **Uso:** comparação textual cross-family com o Qwen3-4B já em cache.
- **Arquivo:** `microsoft_Phi-4-mini-instruct-Q4_K_M.gguf`, aproximadamente **2,49 GB**.
- **Destino fora do Git:** `%LOCALAPPDATA%\Lia-Code\benchmark-cache\models\microsoft_Phi-4-mini-instruct-Q4_K_M.gguf`.
- **Origem:** [arquivo GGUF em bartowski/microsoft_Phi-4-mini-instruct-GGUF](https://huggingface.co/bartowski/microsoft_Phi-4-mini-instruct-GGUF/blob/915429cb42fe8eba71bd1d3117a7d63070892268/microsoft_Phi-4-mini-instruct-Q4_K_M.gguf), revisão fixada `915429cb42fe8eba71bd1d3117a7d63070892268`; arquivo declarado pelo Hub com 2,49 GB.
- **SHA-256 esperado:** `01999f17c39cc3074afae5e9c539bc82d45f2dd7faa3917c66cbef76fce8c0c2`.
- **Licença de origem:** MIT, conforme [cartão oficial do Microsoft Phi-4-mini-instruct](https://huggingface.co/microsoft/Phi-4-mini-instruct). A procedência/licença do arquivo quantizado será revisada antes de redistribuição.
- **Compatibilidade do runtime:** upstream llama.cpp adicionou suporte ao Phi-4-mini no [PR #12108](https://github.com/ggml-org/llama.cpp/pull/12108), mesclado em 2025-02-28; ainda precisamos verificar se o runtime Vulkan local carrega esse arquivo.
- **Estado:** o primeiro teste não encontrou Phi no cache. O próximo `Update-Lia.bat` fará o download somente se esse arquivo estiver ausente e houver pelo menos 3 GiB livres; só moverá o GGUF para o cache após validar o SHA-256. O teste não baixará candidatos adicionais.
- **Instalações:** nenhuma. O arquivo usa o llama.cpp Vulkan já presente, sem atualizá-lo.

## Modelos existentes registrados no preflight

| Recurso | Caminho externo | Tamanho observado | Licença/origem | Estado |
|---|---|---:|---|---|
| Qwen3-4B-Instruct-2507 Q4_K_M — `Qwen_Qwen3-4B-Instruct-2507-Q4_K_M.gguf` | `%LOCALAPPDATA%\Lia-Code\benchmark-cache\models\` | 2,33 GiB | Apache-2.0; conversão GGUF Qwen/Bartowski | Usado no último teste |
| Qwen3-8B Q4_K_M — `Qwen_Qwen3-8B-Q4_K_M.gguf` | `%LOCALAPPDATA%\Lia-Code\benchmark-cache\models\` | 4,68 GiB | Apache-2.0; conversão GGUF Qwen/Bartowski | Existente; foi pulado no último teste por margem de RAM |
| llama.cpp Vulkan b11249 | `%LOCALAPPDATA%\Lia-Code\benchmark-cache\llama-b11249-vulkan\` | Diretório de runtime | llama.cpp; não foi instalado/atualizado pelo teste atual | Usado pelo benchmark |

Outros arquivos GGUF que porventura existam no cache são inventariados/selecionados pelo teste; nenhum será apagado automaticamente.

## Arquivos gerados pelos testes

- Logs auxiliares do servidor ficam em `%LOCALAPPDATA%\Lia-Code\benchmark-cache\llm-<família>-<timestamp>.stdout.log` e `.stderr.log`.
- Os relatórios commitados de teste ficam em `benchmark-results/lia-llm-comparison-*.json` e `.log`; podem conter dados de hardware e respostas. Remover somente os relatórios deste projeto quando não forem mais necessários.
- Um download interrompido abruptamente pode deixar `microsoft_Phi-4-mini-instruct-Q4_K_M.gguf.partial-<timestamp>` na pasta `models`; verificar que não existe teste/download em andamento antes de apagar.

## Limpeza ao fim do projeto

Depois de preservar os resultados desejados e fechar Lia/benchmarks, estes comandos removem apenas os dois Qwen registrados, o Phi autorizado (se baixado) e o runtime Vulkan conhecido. Revise a lista antes de executar; não apague a pasta inteira se houver outros modelos do usuário.

```powershell
$cache = Join-Path $env:LOCALAPPDATA 'Lia-Code\benchmark-cache'
Remove-Item -LiteralPath (Join-Path $cache 'models\Qwen_Qwen3-4B-Instruct-2507-Q4_K_M.gguf') -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $cache 'models\Qwen_Qwen3-8B-Q4_K_M.gguf') -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $cache 'models\microsoft_Phi-4-mini-instruct-Q4_K_M.gguf') -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $cache 'llama-b11249-vulkan') -Recurse -Force -ErrorAction SilentlyContinue
```

Relatórios dentro do repositório devem ser removidos individualmente de `benchmark-results/` (e, se já enviados, de seus commits/histórico conforme a política do projeto). **Os comandos de limpeza acima são apenas instruções futuras; não executar até o usuário encerrar o projeto.**
