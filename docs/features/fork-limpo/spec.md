# Fase 0 · Fork limpo - spec técnica

- **Date:** 2026-11-12
- **Status:** In progress
- **Approved:** 2026-11-14, pelo usuário, mantendo a integração local no Neovim 0.12.0 e no 0.12.3 (Task 13)
- **Addendum 2026-11-14:** o agente de stack das Tasks 2 a 8 se chama `lua`, não `lua-neovim`. Só o nome muda; nenhuma task muda de escopo.
- **Addendum 2026-11-15:** a guarda contra o claudecode.nvim também o detecta pelo runtimepath, e o `:checkhealth` reporta o conflito; ver o adendo no fim da [seção 6](#6-guarda-contra-o-claudecodenvim-task-7).
- **Plan:** [plan.md](plan.md)
- **Implementation log:** [log.md](log.md)

## Summary

Transforma o checkout do upstream (`coder/claudecode.nvim` no commit `d123707`) no Claudinho.nvim 0.1.0. Tudo é Lua puro e ferramental, sem serviço nem dado persistido. Mudam estas camadas:

| Camada                     | O que muda                                                                                                                                                                           |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Código (`lua/`, `plugin/`) | Namespace `claudinho`, snacks removido, opções legadas removidas com aviso, guarda contra o claudecode.nvim carregado, Neovim mínimo 0.12, nome do servidor MCP (verificado à parte) |
| Testes (`tests/`)          | Renomeados; saem só os specs do que foi removido; testes novos para os avisos, o loader, o health check e o namespace                                                                |
| Ferramental                | `mise.toml`, `mise.lock`, `.github/workflows/test.yml`, `.luacov`, `.gitignore`, fixtures e scripts reduzidos ao que o CI e os testes usam                                           |
| Docs do fork               | `README.md`, `README.en.md`, `CLAUDE.md`, `CHANGELOG.md`, `LICENSE`, notas em `PROTOCOL.md` e `ARCHITECTURE.md` (tarefas de docs desta feature)                                      |
| Git                        | Recomeço com um commit inicial, executado só pelo usuário (Task 14)                                                                                                                  |

## Background

Implementa o [plano aprovado](plan.md) (regras 1 a 45 e casos de borda), o `docs/PRD.md` aprovado em 2026-11-12 e a fronteira com a [UI base](../base-ui/plan.md): comandos `:ClaudeCode*`, providers `external`/`none`, opções `terminal.*` não ligadas ao snacks e `ideName = "Neovim"` ficam como estão.

Fatos do código em que a spec se apoia (conferidos em `HEAD`):

- O snacks aparece em `terminal/snacks.lua` (970 linhas), `integrations.lua:23-102`, `health.lua:74-81`, `terminal.lua:2,23,134-146,212,275,292,479,533-538,663,672,705`, `init.lua:814,1199`, `diff.lua:185-186,239,994-1016,1349-1350` (mais as chamadas de `hide_terminal_float_for_diff` em `:1645` e `:1843`), `types.lua:43,86,99,101`, `utils.lua:32`, `terminal/native.lua:155-173,305`, `terminal/owned.lua:10-11` e `terminal/external.lua:67`.
- `hide_float` só existe no provider snacks; `terminal.hide_float` (`terminal.lua:642-652`) só é chamado por `diff.lua:1008`.
- Opções legadas: `config.lua:24,129,166-178,218-229`, `types.lua:131`.
- Neovim mínimo hoje: `plugin/claudecode.lua:1-2`, `health.lua:25-31`, `test.yml:95-98,117-118`, `tests/mocks/vim.lua:736`.
- `init.lua:8-38` lê `VERSION` por um padrão de caminho `lua[/\\]claudecode[/\\]init%.lua$`; `.luacov` inclui `^lua/claudecode/`.
- `server/init.lua:333` devolve `serverInfo.name = "claudecode-neovim"`; nenhum teste afirma esse nome hoje (`tests/unit/server_spec.lua:128` chama o handler).
- As fixtures `netrw`, `nvim-tree`, `oil` e `mini-files` têm `lua/plugins/dev-claudecode.lua` como **link simbólico** para `dev-config.lua` da raiz, que a regra 19 remove.
- `tests/integration/diff_legacy_swap_spec.lua` testa a função `diff.open_diff` (não bloqueante, sem chamador no plugin), não uma opção legada.
- O `CLAUDE.md` da raiz não tem tabela `Test suites` nem `Local runtime`. Esta spec usa os nomes da seção [Suítes](#suítes) e pede a tabela no `CLAUDE.md` novo (Task 10).
- O agente de stack para Lua é o `lua` (`~/.claude/agents/lua.md`), criado pelo usuário antes do `/implement` (decidido em 2026-11-12; nome confirmado em 2026-11-14; ver [Pré-condição do /implement](#pré-condição-do-implement)).

## Design

### Ordem dos passos

A ordem segue as duas restrições do plano (suíte verde ao fim de cada passo; recomeço do git por último) e reduz o trabalho: o que sai, sai antes do rename, para não renomear código que vai ser apagado.

| Passo | Task | Regras          | Por que nesta posição                                                                                         |
| ----- | ---- | --------------- | ------------------------------------------------------------------------------------------------------------- |
| 0     | 1    | 29              | Números de antes, sobre o código intacto                                                                      |
| 1     | 2    | 18 a 24         | Tira o que é só do upstream (incluindo `mise run check` chamando a skill `verify-*`) antes de mexer em código |
| 2     | 3    | 15 a 17         | Cria o mecanismo de chave removida que o passo do snacks reaproveita                                          |
| 3     | 4    | 8 a 14          | Apaga o snacks antes do rename (970 linhas e ~600 citações em testes a menos para renomear)                   |
| 4     | 5    | 1 a 4, 6        | Rename mecânico sobre a árvore já reduzida                                                                    |
| 5     | 6    | 2, 43 a 45      | Loader e health check já com o nome novo                                                                      |
| 6     | 7    | 7               | Usa `plugin/claudinho.lua` e `init.lua` renomeados                                                            |
| 7     | 8    | 5               | Precisa do plugin completo para a sessão real com o `claude`                                                  |
| 8     | 9-12 | 25, 26, 31 a 37 | Docs descrevem o estado final do código                                                                       |
| 9     | 13   | 27, 29, 30, 39  | Gate final, medição e roteiro manual                                                                          |
| 10    | 14   | 38 a 42         | Sempre o último; executado pelo usuário                                                                       |

Nenhuma task faz commit. Toda a Fase 0 fica na árvore de trabalho até a Task 14.

### 1. O que sai do repo (Task 2)

**Caminhos apagados** (regra 19, menos o grupo Snacks, que é da Task 4): `DEVELOPMENT.md`, `AGENTS.md`, `STORY.md`, `CHANGELOG.md`, `lua/README.md`, `lua/claudecode/README.md`, `lua/claudecode/server/README.md`, `lua/claudecode/terminal/README.md`, `lua/claudecode/tools/README.md`, `plugin/README.md`, `scripts/README.md`, `.github/workflows/release-please.yaml`, `.github/workflows/release-notes.yaml`, `.github/workflows/issue-triage.yaml`, `.github/workflows/pr-title.yaml`, `.github/ISSUE_TEMPLATE/`, `release-please-config.json`, `.release-please-manifest.json`, `communique.toml`, `reviewfixer.yaml`, `.devcontainer/`, `dev-config.lua`, `.agents/`, `scripts/tla/`, `scripts/release-please-runner.js`, `scripts/run-release-please.sh`, `scripts/test-release-please-runner.js`, `scripts/fixtures/`, `scripts/package.json`, `scripts/package-lock.json`, `scripts/repro_issue_*`, `fixtures/issue-*`, `fixtures/cursor-toggle-repro/` (com o `__pycache__` não versionado), `fixtures/paste-repro/`, `fixtures/remote-diff/`.

O `CHANGELOG.md` do upstream sai aqui; o novo nasce na Task 11.

**Fixtures que ficam e apontavam para `dev-config.lua`.** Antes de apagar `dev-config.lua`, cada link `fixtures/{netrw,nvim-tree,oil,mini-files}/lua/plugins/dev-claudecode.lua` vira um arquivo comum com o conteúdo atual de `dev-config.lua`. As tasks seguintes editam cada cópia. Motivo: a regra 19 apaga `dev-config.lua` e a regra 18 só lista as pastas das fixtures, então um arquivo compartilhado novo em `fixtures/` ficaria fora da árvore aprovada; cada fixture já é uma config completa e independente.

**`mise.toml`** (regra 21), ferramenta por ferramenta:

| Ferramenta ou bloco                                                   | Decisão | Motivo                                                                                                      |
| --------------------------------------------------------------------- | ------- | ----------------------------------------------------------------------------------------------------------- |
| `communique`                                                          | Sai     | Só gerava release notes                                                                                     |
| task `reviewfix` (e o `reviewfixer` dela)                             | Sai     | Regra 21                                                                                                    |
| passo `proof-static.sh` da task `check`                               | Sai     | A skill `verify-claudecode-nvim` sai; a descrição da task vira "Check Lua syntax and run luacheck"          |
| `websocat`                                                            | Sai     | Só os `scripts/repro_issue_{238,248,277}.sh` o usavam; o roteiro manual da regra 30 usa o `claude` real     |
| `jq`                                                                  | Sai     | Mesmo motivo; o roteiro lê o lock file com `cat`                                                            |
| `node`                                                                | Fica    | Runtime do `prettier`, que o mise instala pelo backend npm (`mise.lock`: `backend = "npm:prettier"`)        |
| `prettier`                                                            | Fica    | O `treefmt.toml` formata `*.md`, `*.json`, `*.yml` com ele (READMEs, `docs/`, `test.yml`, `lazy-lock.json`) |
| `actionlint`                                                          | Fica    | O `treefmt.toml` checa `.github/workflows/test.yml`, que fica                                               |
| `zizmor`                                                              | Fica    | Idem (auditoria do workflow, `--offline`)                                                                   |
| `lua` 5.5.0                                                           | Fica    | Só pelo LuaRocks embutido, que `mise run setup` usa para montar os rocks de teste para o LuaJIT             |
| `fzf`                                                                 | Fica    | `fixtures/bin/common.sh` (regra 21)                                                                         |
| `luajit`, `neovim` 0.12.3, `treefmt`, `stylua`, `shfmt`, `shellcheck` | Ficam   | Testes, format e lint                                                                                       |

O comentário de `websocat`/`jq` sai junto. O `mise.lock` é gerado de novo com o comando que o próprio `mise.toml` documenta (`mise lock -p linux-x64,macos-arm64`), nunca editado à mão; as entradas de `communique`, `jq`, `websocat` e `reviewfixer` precisam sumir. Se a rede falhar (hoje o download do `lua@5.5.0` em lua.org cai por reset), a task registra o bloqueio no log e o lock é refeito antes da Task 13; entradas a mais não são lidas por `mise install --locked` (premissa a confirmar no primeiro CI).

**`.github/workflows/test.yml`** (regra 20):

| Job                 | Mudança                                                                                                                                                                       |
| ------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `unit-tests`        | Saem "Install release tooling dependencies" e "Run release tooling tests"; ficam checkout, mise, cache dos rocks, setup, luacheck, testes, format-check e resumo de cobertura |
| `integration-tests` | Sai "Reject-on-quit regression gate (#238)"; ficam as duas rodadas, a checagem da pasta de cache e o helper do `openDiff`. A matriz muda na Task 6                            |
| `covered-lock`      | Sai inteiro                                                                                                                                                                   |
| `Required`          | Continua dependendo de `unit-tests` e `integration-tests` (o `covered-lock` já era só consultivo)                                                                             |

A checagem "the integration tests left the real cache folder alone" fica: o comentário dela cita `diff_legacy_swap_spec.lua`, que fica (ver Testes).

**Outros:** `.gitignore` perde `/scripts/node_modules/`. Comentários que citam arquivos removidos são reescritos sem a referência (regra 22): `tests/unit/diff_reject_on_quit_spec.lua:10-12` passa a apontar `tests/integration/diff_quit_reject_spec.lua` (que cobre o `:q` real); `tests/unit/mention_queue_spec.lua:4` perde a frase do modelo `verify-mention-queue`; `tests/unit/version_spec.lua:36` vira "matches the VERSION file"; `init.lua:12-13` deixa de citar o release-please.

**Versão** (regras 23 e 24): `VERSION` passa a `0.1.0`. O `init.lua` continua lendo o arquivo; nada mais muda no código.

### 2. Chaves removidas da config (Task 3, ampliada na Task 4)

Um mecanismo único, guiado por tabela, em `config.lua`. A UI base reaproveita a mesma tabela para as chaves que ela remove (regra 71 do plano dela).

```lua
---@class ClaudinhoRemovedOption
---@field path string[]     -- caminho da chave na config do usuário
---@field value any?        -- quando presente, só esse valor conta como removido
---@field replace_with any? -- valor posto no lugar (sem ele, a chave sai)
---@field message string    -- texto do aviso, em inglês

M.removed_options = { ... } -- uma entrada por linha da tabela de avisos abaixo

---Devolve uma cópia da config sem as chaves removidas e avisa uma vez por chave e por sessão.
---Nunca altera o argumento nem levanta erro, qualquer que seja o tipo do valor.
---@param user_config table|nil
---@return table
function M.without_removed_options(user_config) end
```

Contrato:

- Copia raso o nível de cima, `diff_opts` e `terminal` (quando são tabelas) e só então remove ou troca as chaves. Funções, metatables (`cwd_provider` chamável) e o resto passam intactos. A tabela do usuário nunca é alterada, o que também deixa de injetar `git_repo_cwd`/`cwd`/`cwd_provider` na tabela `terminal` dele.
- Uma chave conta como presente quando é `~= nil` (`false` conta). Com `value`, só esse valor conta.
- `diff_opts` ou `terminal` que não são tabela ficam como estão; a validação de hoje responde por eles.
- Cada aviso sai por `vim.notify_once(message, vim.log.levels.WARN)`, na ordem da tabela. O `notify_once` do Neovim guarda as mensagens já mostradas na sessão, fora do plugin, então vale "um por chave e por sessão" mesmo com `setup()` repetido ou um reload do plugin (regra 17).
- `init.setup` chama `opts = config.without_removed_options(opts)` logo no começo e passa essa cópia para `config.apply` e para `terminal.setup`. É no `init.setup`, e não no `config.apply`, porque `terminal.setup` recebe `opts.terminal` cru (`init.lua:487-494`).
- `config.apply` perde o mapeamento legado (`config.lua:218-229`); `config.validate` perde os asserts de `queue_timeout` e das quatro chaves legadas; `M.defaults` perde `queue_timeout`; `types.lua` perde os campos.

Avisos (texto exato; o prefixo é o mesmo do logger renomeado):

| Chave                                    | Ação                 | Mensagem                                                                                                       | Task |
| ---------------------------------------- | -------------------- | -------------------------------------------------------------------------------------------------------------- | ---- |
| `diff_opts.vertical_split`               | Remove               | `[Claudinho] diff_opts.vertical_split was removed and is ignored. Use diff_opts.layout instead.`               | 3    |
| `diff_opts.open_in_current_tab`          | Remove               | `[Claudinho] diff_opts.open_in_current_tab was removed and is ignored. Use diff_opts.open_in_new_tab instead.` | 3    |
| `diff_opts.auto_close_on_accept`         | Remove               | `[Claudinho] diff_opts.auto_close_on_accept was removed and is ignored. It had no effect.`                     | 3    |
| `diff_opts.show_diff_stats`              | Remove               | `[Claudinho] diff_opts.show_diff_stats was removed and is ignored. It had no effect.`                          | 3    |
| `queue_timeout`                          | Remove               | `[Claudinho] queue_timeout was removed and is ignored. It had no effect.`                                      | 3    |
| `terminal.snacks_win_opts`               | Remove               | `[Claudinho] terminal.snacks_win_opts was removed and is ignored.`                                             | 4    |
| `terminal.provider` com valor `"snacks"` | Troca por `"native"` | `[Claudinho] terminal.provider = "snacks" was removed. Using the native terminal.`                             | 4    |

As mensagens já nascem com `[Claudinho]` na Task 3, antes do rename, para não reescrever os testes delas na Task 5.

Consequência aceita pelo plano: quem usava `vertical_split = false` (horizontal) passa a ter o `layout` padrão `"vertical"` até trocar a chave; o aviso diz qual.

### 3. Remoção do snacks (Task 4)

| Arquivo                                                                                         | Mudança                                                                                                                                                                                                                                                                                                                                            | Regra     |
| ----------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------- |
| `terminal/snacks.lua`                                                                           | Apagado                                                                                                                                                                                                                                                                                                                                            | 8         |
| `terminal.lua`                                                                                  | `get_provider`: sai o ramo `snacks` e o "tenta snacks" do `auto`, que cai no `native`; `setup` deixa de aceitar `"snacks"` como provider e de aceitar `snacks_win_opts`; saem `defaults.snacks_win_opts`, o validador e o campo em `build_config`; sai `M.hide_float`; comentários e a mensagem de `send_to_terminal` passam a citar só o `native` | 8, 10, 12 |
| `terminal/native.lua`                                                                           | Saem `stop_snacks_terminal` e as duas chamadas (`:173`, `:305`)                                                                                                                                                                                                                                                                                    | 8         |
| `terminal/owned.lua`                                                                            | Saem `SNACKS_MARK`, `stop_other` e `stop_buffer`: só o provider snacks marcava buffers com essa variável, e no namespace novo nada a define, então o código fica morto. Ficam `NATIVE_MARK`, `job_ended`, `is_live`, `find`                                                                                                                        | 8         |
| `terminal/external.lua`, `utils.lua`                                                            | Só comentários (`:67`; `:32` passa a dizer "a terminal plugin's auto-insert")                                                                                                                                                                                                                                                                      | 8         |
| `integrations.lua`                                                                              | Saem o ramo `snacks_picker_list` e `_get_snacks_picker_selection`; o cabeçalho deixa de citar o snacks. Num buffer desses, `get_selected_files_from_tree` responde "Not in a supported tree buffer", como para qualquer filetype não suportado                                                                                                     | 11        |
| `init.lua`                                                                                      | `:814`: sai `snacks_picker_list` da lista de buffers de árvore (o `:ClaudeCodeSend` trata o buffer como qualquer outro). `:1199`: a descrição de `:ClaudeCodeSendText` termina em "native provider only"                                                                                                                                           | 11        |
| `diff.lua`                                                                                      | Saem `hide_terminal_float_for_diff`, `terminal_windows` e as duas chamadas; o comentário de `:239` deixa de citar o Snacks. **Ficam** os filetypes `snacks_picker_list` e `snacks_layout_box` nas listas de sidebar de `find_main_editor_window` (`:185-186`) e de `_setup_blocking_diff` (`:1349-1350`)                                           | 12        |
| `health.lua`                                                                                    | `auto` mostra `ok("Terminal provider 'auto': native terminal")`; sai o ramo `snacks`                                                                                                                                                                                                                                                               | 13        |
| `types.lua`                                                                                     | Sai `"snacks"` do alias de provider, `snacks_win_opts`, `hide_float?`; a doc de `auto_insert` deixa de citar o snacks                                                                                                                                                                                                                              | 8, 12     |
| `config.lua`                                                                                    | As duas entradas de snacks na tabela de chaves removidas; o comentário de `keep_terminal_focus` deixa de falar de float                                                                                                                                                                                                                            | 9, 10     |
| `fixtures/snacks-explorer/`, `fixtures/snacks-picker/`, `fixtures/netrw/lua/plugins/snacks.lua` | Apagados                                                                                                                                                                                                                                                                                                                                           | 14        |
| `fixtures/*/lua/plugins/dev-claudecode.lua`                                                     | O comentário de provider lista `"auto"` (native), `"native"`, `"external"`, `"none"`; sai a linha de `snacks_win_opts`. O `auto` já é o `native`, o que cumpre "a fixture netrw passa a usar o terminal native"                                                                                                                                    | 14        |

**Por que os filetypes do snacks ficam em `diff.lua`.** Eles não são integração com o snacks: são nomes de janelas de sidebar de um plugin de terceiros, na mesma lista de `aerial` e `tagbar`, que o plugin também não integra. Vieram de correções de regressão (#236, #165): sem eles, o diff abre dentro da sidebar do Snacks Explorer de quem usa o snacks por conta própria. Removê-los muda comportamento fora das remoções listadas, o que o plano proíbe. O critério "`rg -i snacks` sem resultado" passa a ter as exceções da seção [Critérios verificáveis](#critérios-verificáveis). Decidido pelo usuário em 2026-11-12: os filetypes ficam e as exceções valem.

**`init.lua:814` sai** porque a regra 11 pede exatamente isso: num picker do snacks, os comandos de envio agem como em qualquer explorer não suportado.

### 4. Rename para `claudinho` (Task 5)

Procedimento, nos arquivos dos **Files** da Task 5 (nunca em `docs/`):

1. Movimentos com `mv` (sem `git mv`, que mexe no índice): `lua/claudecode/` para `lua/claudinho/`, `plugin/claudecode.lua` para `plugin/claudinho.lua`, `tests/unit/claudecode_add_command_spec.lua` para `tests/unit/add_command_spec.lua`, `claudecode_send_command_spec.lua` para `send_command_spec.lua`, `claudecode_send_text_command_spec.lua` para `send_text_command_spec.lua`, e cada `fixtures/*/lua/plugins/dev-claudecode.lua` para `dev-claudinho.lua`.
2. Substituições, nesta ordem:

| #   | De                                                               | Para                     | Observação                                                                                                                                                                                                                                                                                                                                                                                                          |
| --- | ---------------------------------------------------------------- | ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| a   | `claudecode-neovim`                                              | (protegido)              | Fica até a Task 8 (regra 5)                                                                                                                                                                                                                                                                                                                                                                                         |
| b   | `PartialClaudeCodeConfig`                                        | `PartialClaudinhoConfig` | Único caso no meio de palavra                                                                                                                                                                                                                                                                                                                                                                                       |
| c   | `CLAUDECODE_`                                                    | `CLAUDINHO_`             | `CLAUDINHO_MINIMAL_INIT`, `CLAUDINHO_INTEGRATION_TEST`                                                                                                                                                                                                                                                                                                                                                              |
| d   | `claudecode` (minúsculo)                                         | `claudinho`              | Módulos, `vim.g`/`vim.b`, filetype do terminal, ids internos, `claudinho_diffs` no cache, `claudinho.nvim` em comentários                                                                                                                                                                                                                                                                                           |
| e   | `ClaudeCode` seguido de maiúscula, quando o sufixo não é comando | `Claudinho`              | Regex: `\bClaudeCode(?!(?:Add\|CloseAllDiffs\|Close\|DiffAccept\|DiffDeny\|Focus\|Open\|SelectModel\|SendText\|Send\|Start\|Status\|Stop\|TreeAdd)(?:_visual)?\b)(?=[A-Z])`. Renomeia eventos, augroups, highlights e tipos; preserva `:ClaudeCodeSend`, `ClaudeCodeSend->TreeAdd`, `ClaudeCodeTreeAdd_visual`                                                                                                      |
| f   | `ClaudeCode` isolado                                             | Revisão manual           | Lista de `rg -n -w ClaudeCode`. Fica quando nomeia o comando `:ClaudeCode` (`nvim_create_user_command`, `vim.cmd("ClaudeCode ...")`, `call.vals[1] == "ClaudeCode"`, descrições de teste do comando, dica `:ClaudeCode` do health, `init.lua:1204`). Vira `Claudinho` no prefixo `[ClaudeCode]`, nos títulos `ClaudeCode Error`/`Warning`/`Tool Registration`, em `ClaudeCode:` de mensagens e em `ClaudeCode.nvim` |

Na regex da linha e, cada `\|` é só o escape do Markdown para `|` dentro da tabela; a regex real usa `|` (por exemplo em `perl -pi -e 's/<regex>/Claudinho/g'`).

3. "Claude Code" com espaço é o nome do CLI e fica, salvo a mensagem do loader (Task 6) e o nome do plugin no health check (`claudinho.nvim 0.1.0 is set up`, `Call require("claudinho").setup()`).
4. Testes com linha de log cortada na largura (`tests/unit/logger_spec.lua:165-220`, `tests/unit/server/log_lines_spec.lua:192-209`, `tests/unit/tools/tool_log_lines_spec.lua`): `[Claudinho] ` tem 12 caracteres contra 13 de `[ClaudeCode] `, e o limite de "metade da largura" (`2 * #NAME`) cai de 26 para 24. Os textos esperados são recalculados para a saída real; a lógica de corte não muda.
5. Fixtures de explorer: o spec do lazy troca `"coder/claudecode.nvim", dev = true` por `dir = vim.fn.fnamemodify(vim.fn.stdpath("config"), ":h:h"), name = "claudinho.nvim"` (o mesmo cálculo de raiz que a fixture `repro` usa), porque o `dev = true` apontava para `~/projects/claudecode.nvim`. O cabeçalho "Thomas's personal config" é reescrito. `fixtures/bin/repro` usa `${TMPDIR}/claudinho.nvim-repro`.
6. Fora do código: `.luacov` (`^lua/claudinho/`), `.luacheckrc` (comentário), cabeçalho do `mise.toml`, `test.yml` (link `.../start/claudinho.nvim`), `scripts/manual_test_helper.lua`, `scripts/run_integration_tests_individually.sh`.

Referências a issues do upstream (`#236`, `issue #277`) em comentários e testes ficam: apontam para `coder/claudecode.nvim` e explicam por que o código existe.

### 5. Neovim mínimo 0.12 (Task 6)

`plugin/claudinho.lua`, na ordem final (o passo 3 entra na Task 7):

```lua
if vim.fn.has("nvim-0.12") ~= 1 then
  vim.api.nvim_err_writeln("Claudinho requires Neovim >= 0.12")
  return
end
if vim.g.loaded_claudinho then
  return
end
vim.g.loaded_claudinho = 1
-- 3. guarda de conflito (Task 7): if require("claudinho.conflict").check() then return end
if vim.g.claudinho_auto_setup then
  vim.defer_fn(function()
    require("claudinho").setup(vim.g.claudinho_auto_setup)
  end, 0)
end
-- pcall(require, "claudinho") com a notificação de erro de hoje, renomeada
```

`nvim_err_writeln` fica: só roda em Neovim anterior a 0.12, onde existe (o `err` de `nvim_echo` só chegou na 0.11).

`health.lua:check_neovim`: `ok("Neovim >= 0.12")` ou `error_("Neovim >= 0.12 is required")`. O fallback `report_*` de `vim.health` fica (fora de escopo remover código de versões anteriores).

`tests/mocks/vim.lua:736`: `has` devolve 1 para `"nvim-0.12"` em vez de `"nvim-0.8.0"`; os demais recursos continuam 0, para não mudar os caminhos que os testes de hoje exercitam.

CI: matriz `neovim-version: ["stable", "v0.12.0"]`. A tag `v0.12.0` existe (release publicada em 2026-03-29, commit `fc7e5cf6`, assets `nvim-linux-x86_64.tar.gz`), e o `rhysd/action-setup-vim` fixado (v1.4.2) já trata esse nome de asset desde a v1.4.0. O comentário das linhas 96-97 vira "v0.12.0 is the minimum that plugin/claudinho.lua and the health check support"; o da linha 118 troca "dropping 0.8" por "dropping the minimum Neovim the matrix runs". O `mise.toml` continua com `neovim = "0.12.3"`.

Comentários sobre Neovim 0.8 a 0.11 (caso de borda do plano), caso a caso:

| Onde                                                                                                                 | Decisão                       | Motivo                                                                                                      |
| -------------------------------------------------------------------------------------------------------------------- | ----------------------------- | ----------------------------------------------------------------------------------------------------------- |
| Loader, health check, matriz e comentários do `test.yml`, mock `has`                                                 | Mudam                         | Declaram a versão mínima                                                                                    |
| `init.lua:338`, `lockfile.lua:29,293`, `server/init.lua:10`, `server/tcp.lua:466`, `tools/open_file.lua:245,462,519` | Ficam                         | Explicam código de compatibilidade que fica (fora de escopo); a fase que reescrever cada área limpa os dois |
| `terminal.fix_streamed_paste` (`< 0.12.2`)                                                                           | Fica                          | 0.12.0 e 0.12.1, ainda suportadas, têm o bug                                                                |
| `tests/selection_test.lua` (casos `nvim-0.11` via `_G.vim._has`) e guardas `has("nvim-0.9")` de specs de integração  | Ficam                         | Testam ramos que existem; as guardas nunca disparam na 0.12, então nada fica pendente                       |
| READMEs internos e o passo #238 do CI                                                                                | Saem com os arquivos (Task 2) | -                                                                                                           |

### 6. Guarda contra o claudecode.nvim (Task 7)

Novo `lua/claudinho/conflict.lua`:

```lua
local M = {}
M.MESSAGE = "[Claudinho] claudecode.nvim is also loaded, and the two plugins cannot run together. "
  .. "Claudinho is disabled; remove claudecode.nvim to use it."

---True when claudecode.nvim is loaded (it sets vim.g.loaded_claudecode); warns once per session.
---A minimal stub without vim.g counts as no conflict.
---@return boolean
function M.check() end

return M
```

- `plugin/claudinho.lua` chama `check()` depois de marcar `vim.g.loaded_claudinho` (então um novo `source` não repete o aviso) e para ali: sem auto-setup e sem `require("claudinho")`.
- `init.setup` chama `check()` antes de tudo e, com conflito, devolve `M` sem config, terminal, servidor, comandos nem autocmds (`state.initialized` continua `false`). É necessário porque o lazy.nvim chama `setup(opts)` direto, sem passar pelo `plugin/`.
- O aviso é o mesmo texto nos dois caminhos e sai por `vim.notify_once`, então aparece uma vez.
- Claudinho carregado antes do claudecode.nvim carrega normalmente (caso de borda); o README manda remover o upstream.

#### Adendo 2026-11-15 - detecção também pelo runtimepath

Motivo (achado major do `code-reviewer`, reproduzido em headless no 0.12.3): `check()` só lia `vim.g.loaded_claudecode`, que o claudecode.nvim define no seu `plugin/claudecode.lua`. O Neovim só carrega os arquivos de `plugin/` depois do `init.lua`. Na instalação que o README ensina (`vim.pack.add(...)` e depois `require("claudinho").setup({})` no `init.lua`), o `setup()` do Claudinho roda antes do `plugin/` do claudecode.nvim, não o vê, e os dois plugins rodam. O caso de borda aceito acima ("Claudinho carregado antes do claudecode.nvim carrega normalmente") é, na prática, o caminho principal de instalação. Achado minor: com a guarda desligando o `setup()`, `:checkhealth claudinho` dizia "setup() has not been called" e não citava o conflito.

Decisão do usuário (2026-11-15), que substitui os pontos acima onde divergem:

| Ponto                    | Antes                                                            | Depois                                                                                                                                                                                                                                                                                                                                                |
| ------------------------ | ---------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Contrato de `check()`    | Conflito quando `vim.g.loaded_claudecode` está definido          | Conflito quando `vim.g.loaded_claudecode` está definido **ou** `vim.api.nvim_get_runtime_file("lua/claudecode/init.lua", false)` devolve uma lista não vazia. Um stub mínimo sem `vim.g` ou sem `vim.api.nvim_get_runtime_file` continua contando como sem conflito. Aviso igual: mesmo `MESSAGE`, uma vez por sessão, por `vim.notify_once` com WARN |
| Detecção pura            | Não existia                                                      | `conflict.detected()` faz só a detecção, sem aviso; `check()` é `detected()` mais o `notify_once`. O health check usa `detected()`, para que `:checkhealth` não emita o aviso                                                                                                                                                                         |
| Caso de borda            | Claudinho carregado antes do claudecode.nvim carrega normalmente | Claudinho detecta o claudecode.nvim sempre que ele estiver no runtimepath no momento do `check()`. Um claudecode.nvim posto no runtimepath depois (por exemplo, lazy-loaded após o `setup()` do Claudinho) continua não detectado                                                                                                                     |
| Consequência aceita      | -                                                                | Qualquer claudecode.nvim instalado desliga o Claudinho, mesmo que o `setup()` dele nunca seja chamado e mesmo que esteja bloqueado com `vim.g.loaded_claudecode = 1` (o README já manda removê-lo)                                                                                                                                                    |
| `:checkhealth claudinho` | `setup() has not been called` com a guarda ativa                 | Com `state.initialized == false` e `conflict.detected()` verdadeiro: erro com o texto de `conflict.MESSAGE` e um conselho em inglês para remover o claudecode.nvim e reiniciar o Neovim, no lugar de `setup() has not been called`; o resto do health segue como depois de um setup que falhou. Sem conflito, a mensagem de hoje fica igual           |

`plugin/claudinho.lua` e `init.setup` não mudam: os dois já chamam `check()` nos pontos descritos acima, e o `notify_once` garante um aviso só quando os dois caminhos detectam.

Arquivos afetados: `lua/claudinho/conflict.lua`, `lua/claudinho/health.lua`, `tests/unit/conflict_spec.lua`, `tests/unit/health_spec.lua`, `tests/integration/loader_spec.lua`, e na parte de docs `README.md` e `README.en.md`. `health.lua` e `health_spec.lua` ficam fora dos **Files** da Task 7.

Testes novos:

| Arquivo                             | Casos                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| ----------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `tests/unit/conflict_spec.lua`      | `nvim_get_runtime_file` devolve `{ "/x/lua/claudecode/init.lua" }` sem `loaded_claudecode`: `check()` verdadeiro, um `notify_once(MESSAGE, WARN)`, e a chamada foi `("lua/claudecode/init.lua", false)`. Com `loaded_claudecode` e o runtimepath: verdadeiro e um aviso só. Runtimepath vazio (`{}`) e sem `loaded_claudecode`: falso e nenhum aviso. `vim.api` sem `nvim_get_runtime_file` e sem `vim.g`: falso. `detected()` não chama `notify_once`. `init.setup` com conflito só pelo runtimepath: nada é configurado e `state.initialized` fica `false`                                                                                                                                                                                                           |
| `tests/unit/health_spec.lua`        | Não inicializado e `conflict.detected()` verdadeiro: um erro com `conflict.MESSAGE` e o conselho de remover o claudecode.nvim, nenhum `setup() has not been called`, nenhum `notify_once`. Não inicializado sem conflito: `setup() has not been called` como hoje                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| `tests/integration/loader_spec.lua` | Neovim filho com um init de verdade (`-u <init.lua>`, plugins ligados, `XDG_CONFIG_HOME`, `XDG_DATA_HOME` e `XDG_STATE_HOME` num diretório temporário para não ler a config e os pacotes do usuário). Um claudecode.nvim falso num diretório temporário (`lua/claudecode/init.lua` que devolve `{}` e `plugin/claudecode.lua` que define `vim.g.loaded_claudecode = 1`) entra no runtimepath junto com o repo; o init chama `require("claudinho").setup({ auto_start = false })` e registra que `vim.g.loaded_claudecode` ainda é `nil` naquele momento (prova que nenhum `plugin/` foi carregado). No `VimEnter`: a mensagem aparece uma vez em `:messages` e `exists(':ClaudeCodeStart') == 0`. Controle sem o diretório falso: o mesmo init cria `:ClaudeCodeStart` |

Os casos atuais de `plugin_loader_spec` continuam valendo sem mudança (o `vim` mínimo deles não tem `nvim_get_runtime_file`, então conta como sem conflito). Na tabela [Regras do plano e testes](#regras-do-plano-e-testes), a regra 7 passa a ser coberta também por `health_spec`.

Critérios verificáveis, exceção (c) do `rg -i claudecode`: passa a incluir o caminho `lua/claudecode/init.lua` em `lua/claudinho/conflict.lua` e o nome `claudecode` em `conflict_spec`, `health_spec` e `loader_spec` (o claudecode.nvim falso).

Docs (seção 8, `README.md` e `README.en.md`, seção "Vindo do claudecode.nvim" / "Coming from claudecode.nvim" e o aviso perto da instalação):

- Dizer que qualquer claudecode.nvim instalado (no runtimepath) desliga o Claudinho, mesmo sem o `setup()` dele e mesmo com `vim.g.loaded_claudecode = 1`; "carregado" vira "instalado".
- Tirar a frase de que o Claudinho carrega normalmente quando carrega primeiro. No lugar: um claudecode.nvim carregado depois do `setup()` do Claudinho (lazy-load) não é detectado, e por isso ele deve ser removido de qualquer jeito.
- Trocar "`vim.g.claudecode_*` ignoradas sem aviso" por: `vim.g.claudecode_auto_setup` e `vim.g.claudecode_user_config` são ignoradas sem aviso; `vim.g.loaded_claudecode` é lida pela guarda.
- Dizer que `:checkhealth claudinho` mostra o conflito como erro, com a mesma mensagem.

### 7. Nome do servidor MCP (Task 8)

`server/init.lua:333` passa a `name = "claudinho-nvim"`, e `tests/unit/server_spec.lua` ganha a asserção de `serverInfo.name`. A troca só fica se o usuário confirmar, com um `claude` real, os passos 1 a 6 do [roteiro manual](#roteiro-manual-do-usuário): `/ide` conecta, as tools respondem e o `openDiff` abre e aceita.

Fallback: se algum passo falhar só com o nome novo (confirmado ao voltar o nome antigo), o nome fica `claudecode-neovim`, a asserção do teste passa a afirmar esse valor com um comentário do motivo, o resultado vai para o `log.md`, e um adendo datado desta spec registra o motivo (regra 5). Evidência indireta de que não há dependência: outras integrações do protocolo (Zed, Obsidian) usam nomes próprios no `initialize`; não há documentação oficial do protocolo, por isso o teste real decide.

### 8. Docs do fork (Tasks 9 a 12, escopo desta feature)

Escritas pelo `docs-writer`, na passada de documentação do `/implement`, a partir destas exigências. São parte do escopo do plano (regras 25, 26, 31 a 37), não uma atualização opcional.

| Arquivo                          | Conteúdo exigido                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `README.md` / `README.en.md`     | pt-BR / inglês, mesmo conteúdo; primeira linha `English version: README.en.md` / `Versão em português: README.md`. O que é e de onde vem (hard fork, link para `https://github.com/coder/claudecode.nvim/commit/d1237072eb7c55f97b2d3c44b7971546edad0238`); requisitos (Neovim >= 0.12, CLI `claude`); instalação com `vim.pack.add({ "https://github.com/pedrohrb7/claudinho.nvim" })` e `require("claudinho").setup({})`; config (defaults reais de `config.lua` e `terminal.lua`); comandos `:ClaudeCode*` com a nota de que viram `:Claudinho` na próxima fase; exemplo de mapeamento visual `<cmd>ClaudeCodeSend<cr>` com `mode = "v"` (citado por `tests/integration/select_mode_send_spec.lua:1`); eventos `ClaudinhoSendComplete`, `ClaudinhoDiffOpened`, `ClaudinhoDiffClosed` com os campos de `data`; `:checkhealth claudinho`; o terminal é um split `native` até a UI base trazer o float. Seção "Vindo do claudecode.nvim" / "Coming from claudecode.nvim": tabela da regra 3, chaves removidas (regras 10 e 15) com o aviso de cada uma, `vim.g.claudecode_*` ignoradas sem aviso, os dois plugins não rodam juntos (remover o claudecode.nvim antes), e depois do recomeço do git remover e instalar o plugin de novo (regra 42). Escritos do zero |
| `CLAUDE.md`                      | Inglês, curto: visão; comandos do `mise` (`install`, `setup`, `check`, `test`, `format`, `format-check`, `all`); estrutura de pastas; como rodar testes; seção `## Test suites` com a tabela da seção [Suítes](#suítes); regra de idioma (mensagens, código, testes e `README.en.md` em inglês; `README.md` e `docs/` em português); regra de versão (regra 24); `## Workflow` com `- docs layout: features`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| `CHANGELOG.md`                   | Inglês, Keep a Changelog. Linha de hard fork com o link do commit `d123707`. Entrada `0.1.0` (data do fechamento) com **Changed** (namespace e identificadores da regra 3, Neovim mínimo 0.12, `auto` sempre `native`, nome do servidor MCP se a Task 8 o trocou, aviso para chaves removidas) e **Removed** (provider snacks, leitura do snacks picker/explorer, `snacks_win_opts`, `hide_float`, as cinco chaves da regra 15). Nada do histórico do upstream                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| `LICENSE`                        | Mantém o aviso MIT da Coder Technologies Inc.; acrescenta abaixo a linha `Copyright (c) 2026 pedrohrb7` (decidido pelo usuário em 2026-11-12)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| `PROTOCOL.md`, `ARCHITECTURE.md` | Só caminhos e nomes da regra 3 (`lua/claudecode/` para `lua/claudinho/`, augroups e eventos), e no topo a nota: "This document describes the upstream claudecode.nvim at commit d123707 and may diverge from what Claudinho.nvim builds (for example, the snacks terminal provider was removed in 0.1.0)." Comandos `:ClaudeCode*` e o link para `coder/claudecode.nvim` ficam                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |

### Contratos públicos (antes e depois)

| Superfície                                      | Antes                                                                                                                        | Depois                                                                                        |
| ----------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| Módulo                                          | `require("claudecode")`, `require("claudecode.<m>")`                                                                         | `require("claudinho")`, `require("claudinho.<m>")`; o antigo não existe                       |
| Loader                                          | `plugin/claudecode.lua`, Neovim >= 0.8.0                                                                                     | `plugin/claudinho.lua`, Neovim >= 0.12                                                        |
| `vim.g`                                         | `loaded_claudecode`, `claudecode_auto_setup`, `claudecode_user_config`                                                       | `loaded_claudinho`, `claudinho_auto_setup`, `claudinho_user_config`                           |
| Eventos `User`                                  | `ClaudeCodeSendComplete`, `ClaudeCodeDiffOpened`, `ClaudeCodeDiffClosed`                                                     | `ClaudinhoSendComplete`, `ClaudinhoDiffOpened`, `ClaudinhoDiffClosed` (mesmos `data`)         |
| Highlights                                      | `ClaudeCodeInlineDiff{Add,Delete,AddSign,DeleteSign}`                                                                        | `ClaudinhoInlineDiff{...}`, mesmos defaults                                                   |
| Filetype do terminal / health                   | `claudecode` / `:checkhealth claudecode`                                                                                     | `claudinho` / `:checkhealth claudinho`                                                        |
| Log e notificações                              | `[ClaudeCode]`, `ClaudeCode ...`                                                                                             | `[Claudinho]`, `Claudinho ...`                                                                |
| `terminal.provider`                             | `auto`, `native`, `snacks`, `external`, `none`, tabela                                                                       | `auto` (= `native`), `native`, `external`, `none`, tabela; `"snacks"` vira `native` com aviso |
| Interface de provider                           | `hide_float?` opcional                                                                                                       | Sem `hide_float`                                                                              |
| MCP `initialize`                                | `serverInfo.name = "claudecode-neovim"`                                                                                      | `"claudinho-nvim"` (ou o antigo, pelo fallback da Task 8)                                     |
| Comandos, lock file, header de auth, env do CLI | `:ClaudeCode*`, `~/.claude/ide/<port>.lock`, `ideName = "Neovim"`, `x-claude-code-ide-authorization`, `CLAUDE_CODE_SSE_PORT` | Iguais (regra 6)                                                                              |

### Segurança, observabilidade e rollout

- **Segurança e privacidade:** nenhuma mudança em autenticação, token, lock file ou bind em 127.0.0.1. A guarda de conflito evita dois servidores registrando os mesmos comandos. O mecanismo de chaves removidas só lê a config.
- **Observabilidade:** o logger muda só o prefixo. Os avisos novos saem em WARN por `vim.notify_once`, também com `log_level = "error"`, porque são de config e não de runtime. Não há request id num plugin local; o log do servidor continua identificando o cliente (`client_<n>`).
- **Rollout:** sem feature flag; é uma release única, `0.1.0`. Reverter antes da Task 14: descartar a árvore de trabalho (`HEAD` intacto). Depois da Task 14: o `git bundle` do passo 1.

### Critérios verificáveis

Os critérios do plano, com as exceções que as próprias regras exigem (os avisos das regras 9, 10 e 16 precisam nomear as chaves, e a regra 28 pede testes para eles). Exceções aceitas pelo usuário em 2026-11-12, junto com a decisão de manter os filetypes do snacks em `diff.lua`:

| Critério                                                             | O que pode sobrar                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| -------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `rg -i claudecode` (fora de `docs/`, que é registro de planejamento) | (a) os comandos `:ClaudeCode*` e o que os nomeia (descrições, contextos de log como `ClaudeCodeSend->TreeAdd`, testes dos comandos); (b) atribuição e migração em `README.md`, `README.en.md`, `CHANGELOG.md` e nas notas de `PROTOCOL.md`/`ARCHITECTURE.md`, incluindo o link `coder/claudecode.nvim`; (c) `loaded_claudecode` e `claudecode.nvim` em `lua/claudinho/conflict.lua` e nos testes dele; (d) testes que provam que o antigo sumiu (`namespace_spec`, `loader_spec`); (e) `claudecode-neovim` só se o fallback da Task 8 valeu |
| `rg -i snacks lua/ plugin/ tests/`                                   | `lua/claudinho/config.lua` (duas entradas de chave removida), `lua/claudinho/diff.lua` (os dois filetypes de sidebar, nas duas listas), `tests/unit/removed_options_spec.lua`, `tests/integration/removed_options_spec.lua`, `tests/unit/diff_find_main_editor_window_spec.lua`, `tests/unit/tree_buffer_classification_spec.lua`, `tests/unit/terminal_spec.lua` (caso do `auto` com um módulo `snacks` presente)                                                                                                                          |
| Chaves da regra 15 no código                                         | Só `lua/claudinho/config.lua` (tabela de chaves removidas) e os dois `removed_options_spec.lua`                                                                                                                                                                                                                                                                                                                                                                                                                                             |

## Alternatives considered

| Decisão                                  | Alternativas                                                                                                                     | Escolha e motivo                                                                                                                                                 |
| ---------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Ordem                                    | Rename primeiro, como a lista do plano; ou remoções, legadas e snacks antes                                                      | Remoções antes: o rename não toca código que vai sumir, o diff dele fica menor, e cada passo continua verde. O plano deixa a ordem para a spec                   |
| Aviso uma vez por sessão                 | `vim.notify_once`; tabela no módulo; tabela em `vim.g`                                                                           | `vim.notify_once`: é a API do Neovim para isso, sobrevive a reload do plugin; tabela no módulo zera no `:Lazy reload`; `vim.g` exporia estado interno ao usuário |
| Onde tirar as chaves removidas           | Dentro de `config.apply`; função própria chamada por `init.setup`                                                                | Função própria: `terminal.setup` lê `opts.terminal` cru, então limpar só no `apply` deixaria o terminal ver `snacks_win_opts` e `"snacks"`                       |
| Guarda de conflito                       | Só no `plugin/`; `plugin/` e `setup()`                                                                                           | Os dois: o lazy.nvim chama `setup` direto, e o `plugin/` sozinho não impediria o Claudinho de subir                                                              |
| Filetypes do snacks em `diff.lua`        | Remover junto com o snacks; manter                                                                                               | Manter: são sidebars de terceiros (como `aerial`), vieram de correções (#236, #165), e removê-los muda comportamento fora das remoções do plano                  |
| `owned.stop_other`/`SNACKS_MARK`         | Manter; remover                                                                                                                  | Remover: só o provider snacks marcava buffers, e no namespace novo nenhum buffer terá a marca                                                                    |
| Config de dev das fixtures               | Manter `dev-config.lua` (contra a regra 19); arquivo compartilhado novo em `fixtures/` (fora da regra 18); uma cópia por fixture | Uma cópia por fixture: cumpre as regras 18 e 19, e cada fixture já é uma config completa                                                                         |
| Testes do wrapper em `terminal_spec.lua` | Apagar os casos que usam o mock do snacks; migrá-los para um provider de teste                                                   | Migrar: testam o wrapper (`terminal_cmd`, `env`, `opts_override`, args, toggle), não o snacks; só os casos do próprio snacks e de `hide_float` saem (regra 27)   |
| `diff_legacy_swap_spec.lua`              | Apagar, como o exemplo da regra 27; manter                                                                                       | Manter: testa `diff.open_diff`, que não é removida; a regra 27 só tira testes de funções removidas, e o exemplo do plano se enganou de arquivo                   |
| Rename                                   | À mão; script de substituição com lista de exceções e revisão                                                                    | Script na ordem da tabela da seção 4, com revisão manual só dos casos ambíguos (`ClaudeCode` isolado, linhas de log com largura)                                 |

## Trade-offs

- `vim.notify_once` deduplica pelo texto: se uma mensagem mudar, ela aparece de novo na mesma sessão. Aceito, porque o texto é fixo.
- Quatro cópias da config de dev nas fixtures, em troca de não ter arquivo fora da árvore aprovada.
- Manter os dois filetypes do snacks em `diff.lua` deixa a palavra no código, em troca de não reabrir o bug do diff na sidebar.
- O rename é uma task grande (cerca de 200 arquivos). É mecânico e não se divide sem deixar a suíte vermelha no meio; a revisão se apoia na tabela de substituições e nas listas da revisão manual registradas no log.
- `diff.open_diff` (sem chamador no plugin) e seus testes ficam até a feature Diff.

## Testing

### Suítes

O `CLAUDE.md` da raiz não tem a tabela `Test suites`; estes são os nomes usados aqui e na Task 10:

| Suíte         | Comando                                                                             | Quando                                                                                      |
| ------------- | ----------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| `check`       | `mise run check`                                                                    | Sempre (sintaxe e luacheck, 0 warnings)                                                     |
| `unit`        | `mise run test` (busted com cobertura, ordem aleatória; `BUSTED_SEED` fixa a ordem) | Sempre                                                                                      |
| `format`      | `mise run format-check`                                                             | Sempre                                                                                      |
| `integration` | `./scripts/run_integration_tests_individually.sh` (plenary, Neovim real)            | Sempre no Neovim do mise (0.12.3); `on-demand` no 0.12.0 (`mise exec neovim@0.12.0 -- ...`) |
| `all`         | `mise run all`                                                                      | Gate final                                                                                  |

`integration` local usa o plenary instalado em `~/.local/share/nvim/site/pack/vendor/start/plenary.nvim`, fixado no mesmo SHA do CI (`74b06c6c75e4eeb3108ec01852001636d85a932b`). Se essa pasta faltar, `tests/minimal_init.lua` clona o plenary sem fixar versão; nesse caso, reinstalar no SHA do CI antes de comparar resultados.

### Testes novos e alterados

| Arquivo                                                                                | Task    | Casos                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| -------------------------------------------------------------------------------------- | ------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `tests/unit/removed_options_spec.lua` (novo)                                           | 3, 4    | Para cada linha da tabela de avisos: um `notify_once` com o texto exato e WARN; a chave some da cópia (ou `provider` vira `"native"`); o argumento não muda. Valor de tipo errado (`vertical_split = "sim"`, `queue_timeout = {}`) só avisa, sem erro. `vertical_split = false` não muda `layout` (fica `"vertical"`); `open_in_current_tab = true` não muda `open_in_new_tab`. `init.setup` com chaves removidas não falha, passa a cópia para `terminal.setup` (que recebe `provider = "native"` e não recebe `snacks_win_opts`) e o resto da config vale (`split_side = "left"` guardado). Config sem chave removida: nenhum aviso. `diff_opts = "x"` continua falhando na validação de hoje |
| `tests/integration/removed_options_spec.lua` (novo)                                    | 3, 4    | Neovim real (pendente sob o mock, como os outros): `setup` com as sete chaves mostra sete notificações; um segundo `setup` igual não mostra nenhuma (regra 17)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| `tests/unit/config_spec.lua`                                                           | 3       | Defaults sem `queue_timeout` e sem as quatro chaves; `validate` aceita config sem `queue_timeout`. As tabelas de exemplo dos casos de `external_terminal_cmd` perdem as chaves legadas (o teste continua)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| `tests/unit/command_args_spec.lua`                                                     | 3, 4    | Comentário da linha 162 sem a chave legada; linhas `package.loaded[...snacks] = nil` saem                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| `tests/mocks/vim.lua`                                                                  | 3, 6    | `notify_once` (deduplica numa tabela que o teste pode zerar e chama `notify`); `has("nvim-0.12") == 1`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| `tests/unit/terminal_spec.lua`                                                         | 4       | O mock do snacks dá lugar a um provider de teste em `package.loaded["claudecode.terminal.native"]`, com as mesmas asserções do wrapper. Saem os casos do snacks (disponibilidade, `snacks_win_opts`, "With Snacks available") e o bloco `hide_float`. Novos: `auto` escolhe o `native` mesmo com um módulo `snacks` em `package.loaded`; `setup` com `provider = "snacks"` direto (sem `init`) avisa valor inválido e mantém o anterior; `require("...terminal").hide_float == nil`                                                                                                                                                                                                             |
| `tests/unit/native_terminal_toggle_spec.lua`                                           | 4       | Sai o bloco "a Claude that the snacks provider started" (`:2030-2110`)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| `tests/unit/health_spec.lua`                                                           | 4, 5, 6 | Sai "errors when snacks provider is configured"; novo: `auto` reporta `Terminal provider 'auto': native terminal`. Novos (Task 6): `has("nvim-0.12") == 1` dá OK `Neovim >= 0.12`; `0` dá erro `Neovim >= 0.12 is required`. Nome `claudinho.nvim 0.1.0 is set up` (Task 5)                                                                                                                                                                                                                                                                                                                                                                                                                     |
| `tests/unit/tree_buffer_classification_spec.lua`                                       | 4       | Com filetype `snacks_picker_list`: `:ClaudeCodeSend` segue o caminho de buffer comum (não chama `get_selected_files_from_tree`) e `get_selected_files_from_tree` responde "Not in a supported tree buffer"                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| `tests/unit/diff_inline_spec.lua`                                                      | 4, 5    | Saem as chaves `snacks_win_opts` dos exemplos. Novo (Task 5): os quatro highlights definidos são `ClaudinhoInlineDiff*` com os valores e `default = true` de hoje                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| `tests/unit/terminal/send_text_spec.lua`, `tests/unit/terminal/none_provider_spec.lua` | 4       | Saem as linhas `package.loaded[...snacks] = nil`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| `tests/unit/diff_keep_terminal_focus_float_spec.lua`                                   | 4       | Comentário sem "(e.g. Snacks)"; o caso continua (terminal flutuante genérico)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| `tests/integration/diff_new_tab_mode_spec.lua`                                         | 4       | Opção `snacks_auto_insert` vira `auto_insert_on_bufenter`; a descrição troca "as with Snacks" por "as some terminal plugins do"                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| `tests/unit/namespace_spec.lua` (novo)                                                 | 5       | `package.searchpath("claudinho", package.path)` existe e `package.searchpath("claudecode", package.path)` é `nil` (robusto a mocks de outros specs em `package.loaded`); `require("claudinho").setup` é função; `version:string()` igual ao `VERSION`                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| Testes renomeados (todos os de `tests/`)                                               | 5       | Asserções de nome passam a afirmar o novo: `ClaudinhoSendComplete` (`send_complete_event_spec`), `ClaudinhoDiffOpened`/`Closed` (`diff_auto_resize_events_spec`, `diff_bulk_close_reentrancy_spec`, `diff_left_window_spec`), augroup `ClaudinhoSelection` (`selection_test`), `ClaudinhoMCPDiff`, filetype `claudinho` do terminal native, prefixo `[Claudinho]` (`logger_spec`, `log_lines_spec`, `tool_log_lines_spec`, `init_spec`), caminhos do `.luacov` (`luacov_config_spec`), `CLAUDINHO_MINIMAL_INIT` (`integration_runner_spec`)                                                                                                                                                     |
| `tests/unit/plugin_loader_spec.lua` (novo)                                             | 6, 7    | `dofile("plugin/claudinho.lua")` com um `vim` mínimo por caso: `has("nvim-0.12") == 0` escreve `Claudinho requires Neovim >= 0.12` por `nvim_err_writeln`, não define `loaded_claudinho`, não agenda `defer_fn` e não carrega `claudinho`; com 1, define `loaded_claudinho`; segundo `dofile` não faz nada; `claudinho_auto_setup` agenda `setup` com a tabela; `claudecode_auto_setup` sozinho não agenda nada nem avisa. Task 7: com `loaded_claudecode`, avisa uma vez e não agenda nem carrega                                                                                                                                                                                              |
| `tests/unit/conflict_spec.lua` (novo)                                                  | 7       | `check()` falso sem `loaded_claudecode`; verdadeiro e um `notify_once(MESSAGE, WARN)` com ele; `vim.g` ausente conta como sem conflito. `init.setup` com conflito: não chama `config.apply`, `terminal.setup`, `nvim_create_user_command`, `nvim_create_autocmd` nem o servidor, e `state.initialized` fica `false`                                                                                                                                                                                                                                                                                                                                                                             |
| `tests/integration/loader_spec.lua` (novo)                                             | 7       | Neovim filho real (`vim.v.progpath --headless -u NONE`, `rtp^=<repo>`, `runtime plugin/claudinho.lua`): com `let g:loaded_claudecode = 1`, a mensagem aparece uma vez em `:messages`, `exists(':ClaudeCodeStart') == 0`, e um `require("claudinho").setup({ auto_start = false })` depois não cria comandos nem repete a mensagem; sem ela, o `setup` cria `:ClaudeCodeStart`                                                                                                                                                                                                                                                                                                                   |
| `tests/unit/server_spec.lua`                                                           | 8       | `initialize` devolve `serverInfo.name == "claudinho-nvim"` (ou o valor do fallback) e `serverInfo.version == require("claudinho").version:string()`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| `tests/unit/version_spec.lua`                                                          | 2, 5    | Descrição sem release-please; caminhos `lua/claudinho` (Task 5). Continua comparando com o arquivo `VERSION` (sem fixar `0.1.0`, para não quebrar a cada versão)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| `tests/unit/diff_reject_on_quit_spec.lua`, `tests/unit/mention_queue_spec.lua`         | 2       | Só comentários (regra 22)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |

### Testes que saem (regra 27)

| Arquivo                                                                                                                                                                              | Task | Por quê                                             |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---- | --------------------------------------------------- |
| `tests/unit/terminal/snacks_spec.lua`, `snacks_close_spec.lua`, `snacks_failed_start_spec.lua`, `snacks_reload_spec.lua`, `snacks_toggle_spec.lua`, `snacks_unfocused_show_spec.lua` | 4    | Provider snacks removido (cerca de 123 blocos `it`) |
| `tests/unit/snacks_picker_integration_spec.lua`                                                                                                                                      | 4    | Leitura do picker removida (18)                     |
| `tests/integration/diff_terminal_float_spec.lua`                                                                                                                                     | 4    | Caminho `hide_float` do diff removido (15)          |
| `tests/integration/diff_terminal_float_reload_spec.lua`                                                                                                                              | 4    | Provider snacks depois de reload (3)                |
| Casos dentro de `terminal_spec`, `native_terminal_toggle_spec`, `health_spec`                                                                                                        | 4    | Listados acima                                      |

Nenhum teste é desligado nem marcado como pendente. `tests/integration/diff_legacy_swap_spec.lua` fica (testa `diff.open_diff`, que fica).

### Regras do plano e testes

| Regra            | Coberta por                                                                                                             |
| ---------------- | ----------------------------------------------------------------------------------------------------------------------- |
| 1                | `namespace_spec`                                                                                                        |
| 2, 43            | `plugin_loader_spec`                                                                                                    |
| 3, 4             | Testes renomeados (eventos, augroups, filetype, prefixo), `diff_inline_spec` (highlights), `health_spec`; critério `rg` |
| 5                | `server_spec` + roteiro manual (passos 1 a 6)                                                                           |
| 6                | `init_spec` (registra `ClaudeCode*`), `lockfile_test` (`ideName = "Neovim"`), `handshake_spec` (header), sem mudança    |
| 7                | `conflict_spec`, `plugin_loader_spec`, `loader_spec`                                                                    |
| 8                | `terminal_spec` (auto = native mesmo com `snacks` carregado)                                                            |
| 9, 10            | `removed_options_spec` (unit e integration)                                                                             |
| 11               | `tree_buffer_classification_spec`                                                                                       |
| 12               | `terminal_spec` (`hide_float == nil`), `diff_keep_terminal_focus_float_spec`, suítes de diff inalteradas                |
| 13, 44           | `health_spec`                                                                                                           |
| 14, 18, 19       | Comandos de árvore da Verificação                                                                                       |
| 15               | `config_spec`                                                                                                           |
| 16, 17           | `removed_options_spec` (unit e integration)                                                                             |
| 20, 21, 45       | `format` (actionlint e zizmor no `test.yml`), `mise install --locked`, primeiro CI depois da Task 14                    |
| 22               | Comando de referências da Verificação                                                                                   |
| 23               | `version_spec`, `namespace_spec` + `cat VERSION`                                                                        |
| 24 a 26, 31 a 37 | Revisão das docs (Tasks 9 a 12) com o checklist da Verificação                                                          |
| 27, 29           | Tasks 1 e 13: contagem e cobertura antes e depois                                                                       |
| 28               | As linhas 7, 9, 10, 16, 43, 44 acima                                                                                    |
| 30               | `mise run all` + roteiro manual                                                                                         |
| 38 a 42          | Task 14 (manual)                                                                                                        |

## Implementation order

### Pré-condição do /implement

O agente de stack `lua` existe em `~/.claude/agents/` antes de o `/implement` começar. O usuário o cria (decidido em 2026-11-12); nenhuma task desta spec o cria. Sem ele, o `/implement` para antes da Task 2 e avisa.

Stacks: `lua` (Tasks 2 a 8) fica fora da lista do template, pela pré-condição acima. `test-runner` e `docs-writer` são os agentes de mesmo nome. A Task 14 nunca é delegada.

### Task 1 - Linha de base de testes e cobertura

- **Stack:** test-runner (sem código)
- **Files:** nenhum arquivo do repo (os números vão para `log.md`, escrito pelo `/implement`)
- **Depends on:** -
- **Done when:** o `log.md` registra, sobre o `HEAD` atual e com um `BUSTED_SEED` anotado: totais do `unit` (sucessos, falhas, erros, pendentes); warnings do `check`; cobertura total e por arquivo de `lua/claudecode/` e `plugin/` (`./.luarocks/bin/luacov` e `scripts/coverage-summary.sh luacov.report.out "$PWD"`); totais do `integration` no Neovim 0.12.3, ou o registro de que o plenary não está instalado
- **Status:** done

### Task 2 - Remover o que é só do upstream e recomeçar a versão

- **Stack:** lua
- **Files:** `DEVELOPMENT.md`, `AGENTS.md`, `STORY.md`, `CHANGELOG.md`, `lua/README.md`, `lua/claudecode/README.md`, `lua/claudecode/server/README.md`, `lua/claudecode/terminal/README.md`, `lua/claudecode/tools/README.md`, `plugin/README.md`, `scripts/**`, `.github/**`, `release-please-config.json`, `.release-please-manifest.json`, `communique.toml`, `reviewfixer.yaml`, `.devcontainer/**`, `dev-config.lua`, `.agents/**`, `fixtures/issue-*/**`, `fixtures/cursor-toggle-repro/**`, `fixtures/paste-repro/**`, `fixtures/remote-diff/**`, `fixtures/netrw/lua/plugins/dev-claudecode.lua`, `fixtures/nvim-tree/lua/plugins/dev-claudecode.lua`, `fixtures/oil/lua/plugins/dev-claudecode.lua`, `fixtures/mini-files/lua/plugins/dev-claudecode.lua`, `mise.toml`, `mise.lock`, `.gitignore`, `VERSION`, `lua/claudecode/init.lua`, `tests/unit/version_spec.lua`, `tests/unit/diff_reject_on_quit_spec.lua`, `tests/unit/mention_queue_spec.lua`
- **Depends on:** Task 1
- **Done when:** nenhum caminho da regra 19 existe, exceto os do grupo Snacks; `scripts/` tem só `coverage-summary.sh`, `run_integration_tests_individually.sh` e `manual_test_helper.lua`; `.github/workflows/` tem só `test.yml`, sem os passos de release tooling, o passo #238 e o job `covered-lock`; as quatro `dev-claudecode.lua` são arquivos comuns; o `mise.toml` segue a tabela da seção 1 e o `mise.lock` foi gerado de novo (ou o bloqueio de rede está no log); `VERSION` é `0.1.0` e `require("claudecode").version:string()` também; `check`, `unit` e `format` verdes, com a mesma contagem de testes da Task 1
- **Status:** done

### Task 3 - Chaves legadas removidas, com aviso

- **Stack:** lua
- **Files:** `lua/claudecode/config.lua`, `lua/claudecode/init.lua`, `lua/claudecode/types.lua`, `tests/unit/config_spec.lua`, `tests/unit/init_spec.lua`, `tests/unit/command_args_spec.lua`, `tests/unit/removed_options_spec.lua`, `tests/integration/removed_options_spec.lua`, `tests/mocks/vim.lua`, `fixtures/netrw/lua/plugins/dev-claudecode.lua`, `fixtures/nvim-tree/lua/plugins/dev-claudecode.lua`, `fixtures/oil/lua/plugins/dev-claudecode.lua`, `fixtures/mini-files/lua/plugins/dev-claudecode.lua`
- **Depends on:** Task 2
- **Done when:** `config.removed_options` e `config.without_removed_options` seguem o contrato da seção 2 com as cinco linhas da Task 3; `init.setup` usa a cópia; defaults, tipos e validação sem as cinco chaves; os casos de `removed_options_spec` e `config_spec` passam; as chaves só aparecem em `config.lua` e nos dois specs; `check`, `unit` e `format` verdes
- **Status:** done

### Task 4 - Remover o snacks

- **Stack:** lua
- **Files:** `lua/claudecode/terminal/snacks.lua`, `lua/claudecode/terminal.lua`, `lua/claudecode/terminal/native.lua`, `lua/claudecode/terminal/owned.lua`, `lua/claudecode/terminal/external.lua`, `lua/claudecode/utils.lua`, `lua/claudecode/integrations.lua`, `lua/claudecode/init.lua`, `lua/claudecode/diff.lua`, `lua/claudecode/health.lua`, `lua/claudecode/types.lua`, `lua/claudecode/config.lua`, `tests/unit/terminal/**`, `tests/unit/snacks_picker_integration_spec.lua`, `tests/unit/terminal_spec.lua`, `tests/unit/native_terminal_toggle_spec.lua`, `tests/unit/health_spec.lua`, `tests/unit/diff_inline_spec.lua`, `tests/unit/command_args_spec.lua`, `tests/unit/diff_keep_terminal_focus_float_spec.lua`, `tests/unit/tree_buffer_classification_spec.lua`, `tests/unit/removed_options_spec.lua`, `tests/integration/diff_terminal_float_spec.lua`, `tests/integration/diff_terminal_float_reload_spec.lua`, `tests/integration/diff_new_tab_mode_spec.lua`, `tests/integration/removed_options_spec.lua`, `fixtures/snacks-explorer/**`, `fixtures/snacks-picker/**`, `fixtures/netrw/**`, `fixtures/nvim-tree/lua/plugins/dev-claudecode.lua`, `fixtures/oil/lua/plugins/dev-claudecode.lua`, `fixtures/mini-files/lua/plugins/dev-claudecode.lua`
- **Depends on:** Task 3
- **Done when:** a tabela da seção 3 está aplicada; `rg -i snacks lua/ plugin/ tests/` só acha as exceções da seção Critérios verificáveis (com caminhos ainda em `claudecode`); os testes da tabela de Testing para a Task 4 passam; a queda na contagem é só a dos testes listados em "Testes que saem"; `check`, `unit` e `format` verdes
- **Status:** done

### Task 5 - Rename para claudinho

- **Stack:** lua
- **Files:** `lua/**`, `plugin/**`, `tests/**`, `fixtures/netrw/**`, `fixtures/nvim-tree/**`, `fixtures/oil/**`, `fixtures/mini-files/**`, `fixtures/repro/**`, `fixtures/bin/**`, `fixtures/nvim-aliases.sh`, `scripts/manual_test_helper.lua`, `scripts/run_integration_tests_individually.sh`, `.luacov`, `.luacheckrc`, `mise.toml`, `.github/workflows/test.yml`
- **Depends on:** Task 4
- **Done when:** o procedimento da seção 4 está aplicado, com as listas da revisão manual (passo f e linhas de log) no log; `lua/claudecode/` e `plugin/claudecode.lua` não existem; `namespace_spec` e os testes renomeados passam; `serverInfo.name` ainda é `claudecode-neovim`; o comando de critério do nome antigo só mostra as exceções (a) e (d); a cobertura volta a medir `lua/claudinho/` (não cai a zero); `check`, `unit` e `format` verdes, com a mesma contagem da Task 4 mais os testes novos
- **Status:** done

### Task 6 - Neovim mínimo 0.12

- **Stack:** lua
- **Files:** `plugin/claudinho.lua`, `lua/claudinho/health.lua`, `tests/mocks/vim.lua`, `tests/unit/health_spec.lua`, `tests/unit/plugin_loader_spec.lua`, `.github/workflows/test.yml`
- **Depends on:** Task 5
- **Done when:** loader, health check, mock e matriz seguem a seção 5 (matriz `["stable", "v0.12.0"]`, comentários reescritos); os casos de `plugin_loader_spec` e `health_spec` da Task 6 passam; `check`, `unit` e `format` (actionlint e zizmor no `test.yml`) verdes
- **Status:** done

### Task 7 - Guarda contra o claudecode.nvim carregado

- **Stack:** lua
- **Files:** `lua/claudinho/conflict.lua`, `plugin/claudinho.lua`, `lua/claudinho/init.lua`, `tests/unit/conflict_spec.lua`, `tests/unit/plugin_loader_spec.lua`, `tests/integration/loader_spec.lua`
- **Depends on:** Task 6
- **Done when:** a seção 6 está aplicada; `conflict_spec`, `plugin_loader_spec` e `loader_spec` passam (este no `integration`, ou pendente sob o mock no `unit`); `check`, `unit` e `format` verdes
- **Status:** done

### Task 8 - Nome do servidor MCP, com verificação real

- **Stack:** lua
- **Files:** `lua/claudinho/server/init.lua`, `tests/unit/server_spec.lua`
- **Depends on:** Task 7
- **Done when:** `serverInfo.name` é `claudinho-nvim` e `server_spec` afirma o nome e a versão; o usuário fez os passos 1 a 6 do roteiro manual e confirmou que passaram, e o resultado está no log. Se falharam só com o nome novo, vale o fallback da seção 7 (nome antigo, teste e comentário ajustados, motivo no log, e o `/implement` pede ao `specker` o adendo desta spec); `check` e `unit` verdes
- **Status:** done

### Task 9 - README.md e README.en.md (docs, escopo desta feature)

- **Stack:** docs-writer
- **Files:** `README.md`, `README.en.md`
- **Depends on:** Task 8
- **Done when:** os dois arquivos cumprem a linha de READMEs da tabela da seção 8, com os mesmos blocos nas duas línguas; todo valor de config citado bate com `config.lua` e `terminal.lua`; os links cruzados estão na primeira linha; `format` verde
- **Status:** done

### Task 10 - CLAUDE.md curto (docs, escopo desta feature)

- **Stack:** docs-writer
- **Files:** `CLAUDE.md`
- **Depends on:** Task 8
- **Done when:** o arquivo cumpre a linha de `CLAUDE.md` da seção 8, inclusive `## Test suites` e `## Workflow` com `- docs layout: features`; nenhum caminho citado deixou de existir; `format` verde
- **Status:** done

### Task 11 - CHANGELOG.md novo e LICENSE (docs, escopo desta feature)

- **Stack:** docs-writer
- **Files:** `CHANGELOG.md`, `LICENSE`
- **Depends on:** Task 8
- **Done when:** o `CHANGELOG.md` cumpre a seção 8 (Keep a Changelog, linha do hard fork com o link de `d123707`, entrada `0.1.0` com Changed e Removed, nada do upstream); o `LICENSE` mantém o aviso da Coder e tem logo abaixo a linha `Copyright (c) 2026 pedrohrb7`; `format` verde
- **Status:** done

### Task 12 - Notas em PROTOCOL.md e ARCHITECTURE.md (docs, escopo desta feature)

- **Stack:** docs-writer
- **Files:** `PROTOCOL.md`, `ARCHITECTURE.md`
- **Depends on:** Task 8
- **Done when:** só caminhos e nomes da regra 3 mudaram, mais a nota do topo da seção 8; `format` verde
- **Status:** done

### Task 13 - Verificação final e medição

- **Stack:** test-runner (sem código)
- **Files:** nenhum arquivo do repo (resultados no `log.md`)
- **Depends on:** Task 9, Task 10, Task 11, Task 12
- **Done when:** `all` verde; `integration` verde no 0.12.3 e no 0.12.0, com o plenary local fixado no SHA do CI; os comandos de critério da Verificação só mostram as exceções permitidas; o log tem a tabela antes/depois (testes por estado e cobertura total e por arquivo) e explica cada diferença pelos testes de "Testes que saem" e pelos novos; o usuário fez o roteiro manual inteiro (regra 30) e revisou a árvore e o diff contra o `HEAD` (regra 39)
- **Status:** pending

### Task 14 - Recomeço do git e do remoto (usuário, não delegável)

- **Stack:** usuário (manual; nenhum agente executa)
- **Files:** nenhum (operações de git e no GitHub)
- **Depends on:** Task 13
- **Done when:** o usuário rodou o fluxo da regra 40 (ver "Recomeço do git" na Verificação), passo a passo e com autorização em cada um, ou decidiu não rodá-lo; a decisão está no log e num adendo datado desta spec. Com o fluxo rodado: `git log` com um commit só, o remoto sem branches nem tags do upstream, e o CI verde no commit novo
- **Status:** pending

## Verification

### Suítes ao fim

`check`, `unit`, `format`, `integration` (0.12.3) e o `on-demand` `integration` no 0.12.0, depois `all`. Se o `mise` tentar instalar o `lua@5.5.0` e o download de lua.org cair (problema de rede desta máquina hoje), rodar `mise install` de novo quando o site responder; não é falha da feature.

### Comandos de critério (sessão principal, só leitura)

```sh
# Nome antigo: tokens distintos fora de docs/ (comparar com as exceções de Critérios verificáveis)
rg -o -i -N --no-filename --hidden -g '!.git/' -g '!docs/' '[A-Za-z0-9_./:>-]*claudecode[A-Za-z0-9_./-]*' . | sort | uniq -c
# Nome antigo fora dos arquivos de docs, sem os comandos: deve sobrar só conflict.lua, seus testes e namespace/loader_spec
rg -n -i --hidden -g '!.git/' -g '!docs/' -g '!README*.md' -g '!CHANGELOG.md' -g '!PROTOCOL.md' -g '!ARCHITECTURE.md' claudecode . \
  | rg -v 'ClaudeCode(Add|CloseAllDiffs|Close|DiffAccept|DiffDeny|Focus|Open|SelectModel|SendText|Send|Start|Status|Stop|TreeAdd)?(_visual)?\b'
# ClaudeCode isolado: só contextos do comando :ClaudeCode
rg -n -w ClaudeCode lua plugin tests fixtures scripts
# Snacks e chaves legadas
rg -n -i snacks lua/ plugin/ tests/
rg -n 'vertical_split|open_in_current_tab|auto_close_on_accept|show_diff_stats|queue_timeout' lua plugin tests fixtures
# Referências a arquivos removidos (regra 22): sem resultado
rg -n 'repro_issue|release-please|communique|verify-[a-z-]+|covered\.lock|scripts/tla|dev-config\.lua' lua plugin tests scripts fixtures mise.toml .github
# Árvore (regras 18 e 19): nenhum caminho removido existe
for p in DEVELOPMENT.md AGENTS.md STORY.md dev-config.lua reviewfixer.yaml communique.toml release-please-config.json \
  .release-please-manifest.json .devcontainer .agents scripts/tla scripts/fixtures .github/ISSUE_TEMPLATE \
  fixtures/snacks-explorer fixtures/snacks-picker fixtures/netrw/lua/plugins/snacks.lua lua/claudecode plugin/claudecode.lua; do
  test -e "$p" && echo "AINDA EXISTE: $p"; done
ls -A; ls fixtures scripts .github/workflows
cat VERSION   # 0.1.0
```

### Checklist das docs (Tasks 9 a 12)

Primeira linha de cada README aponta para o outro; mesmas seções nas duas línguas; instalação com `vim.pack` e `require("claudinho")`; Neovim >= 0.12; comandos `:ClaudeCode*` com a nota da próxima fase; eventos novos; `:checkhealth claudinho`; seção "Vindo do claudecode.nvim" com a tabela da regra 3, as chaves removidas, o conflito e a reinstalação depois do recomeço; `CHANGELOG.md` em inglês, Keep a Changelog, só `0.1.0`; `LICENSE` com as duas linhas; `PROTOCOL.md` e `ARCHITECTURE.md` com a nota e nada além de caminhos e nomes; `CLAUDE.md` com `Test suites` e `docs layout: features`.

### Roteiro manual do usuário

Feito pelo usuário, no Neovim 0.12.3 do mise, com o claudecode.nvim fora da config. Os passos 1 a 6 também são a verificação da Task 8.

1. Na raiz do repo: `source fixtures/nvim-aliases.sh && repro`. A fixture carrega o plugin da árvore de trabalho, com terminal `native` e `auto_start = false`.
2. `:checkhealth claudinho`: OK `Neovim >= 0.12`, `claudinho.nvim 0.1.0 is set up`, provider `native`, nenhuma menção ao snacks.
3. `:ClaudeCodeStart`, depois `:ClaudeCode`: abre um split com o `claude` real. Em outro terminal, `cat ~/.claude/ide/*.lock` mostra `"ideName":"Neovim"`.
4. No Claude, `/ide`: o Neovim aparece e conecta.
5. Pergunte ao Claude qual arquivo está aberto e se há erros nele: ele responde usando as tools (`getOpenEditors`, `getDiagnostics`).
6. Peça ao Claude uma mudança em `a.txt`: o diff abre; aceite com `:w` no buffer proposto (ou `:ClaudeCodeDiffAccept`); o Claude confirma e `a.txt` muda. Peça outra e rejeite com `:ClaudeCodeDiffDeny`: o Claude recebe a rejeição.
7. Selecione linhas de `b.txt` em modo visual e rode `:ClaudeCodeSend`: o @-mention aparece no Claude. Rode `:ClaudeCodeAdd %`: o arquivo aparece.
8. `:lua vim.api.nvim_create_autocmd("User", { pattern = "ClaudinhoSendComplete", callback = function(a) print(vim.inspect(a.data)) end })` e envie de novo: os dados aparecem.
9. Avisos: `nvim --clean --cmd "set rtp^=." -c 'lua require("claudinho").setup({ auto_start = false, queue_timeout = 1, diff_opts = { vertical_split = true }, terminal = { provider = "snacks", snacks_win_opts = {} } })'`: quatro avisos em inglês, cada um com a chave; `:messages` confere. Repetir o mesmo `setup` em `:lua`: nenhum aviso novo; `:ClaudeCode` abre um split native.
10. Conflito: `nvim --clean --cmd "let g:loaded_claudecode = 1" --cmd "set rtp^=."`: aparece o aviso de conflito uma vez, e `:ClaudeCodeStart` dá E492. (Se o `--clean` não carregar o `plugin/`, acrescentar `-c "runtime plugin/claudinho.lua"`.)
11. Opcional, se houver um Neovim 0.11 à mão (ex.: `mise exec neovim@0.11 -- nvim --clean --cmd "set rtp^=."`): aparece `Claudinho requires Neovim >= 0.12` e não existe `:ClaudeCodeStart`.
12. Revisão da árvore (regra 39): `git status --short` e `git diff --stat HEAD`.

### Recomeço do git (Task 14, só o usuário executa)

Cada passo só com a autorização do usuário no momento (regra 38). Antes do passo 2, o usuário confirma as perdas da regra 41.

1. **Backup:** `git bundle create <caminho fora do repo>/claudecode-history.bundle --all` e `git bundle verify <arquivo>`.
2. **Histórico novo:** `git checkout --orphan fresh-main`, `git add -A`, conferir `git status`, `git commit -m "chore: initial commit of claudinho.nvim 0.1.0"`; apagar os outros branches locais (`main`, `docs/fork-planning`) e as tags locais; `git branch -m main`; `git reflog expire --expire=now --all && git gc --prune=now`.
3. **Desvincular no GitHub:** se `pedrohrb7/claudinho.nvim` mostra "forked from coder/claudecode.nvim", usar "Leave fork network" nas Settings (público e menor que 1 GB) ou apagar e recriar com o mesmo nome. Se não é fork, o passo não existe.
4. **Push:** `git push --force origin main`; apagar no remoto os branches e as tags do upstream (`git push origin --delete <ref>`). Depois, remover e instalar de novo o plugin na config do Neovim (regra 42).
5. **Depois:** o CI roda no commit novo e precisa passar; o usuário ajusta as regras de branch que exigiam `covered-lock` ou `pr-title`.

## Open questions

Nenhuma em aberto. Decididas pelo usuário em 2026-11-12:

1. **Agente para as tasks de Lua:** o usuário cria o agente `lua` antes do `/implement`; as Tasks 2 a 8 usam esse nome (ver Pré-condição do /implement).
2. **Linha do autor no `LICENSE`:** `Copyright (c) 2026 pedrohrb7`, abaixo do aviso MIT da Coder (Task 11).
3. **Exceções dos critérios:** os filetypes `snacks_picker_list`/`snacks_layout_box` ficam em `diff.lua`, e as exceções de `rg` de Critérios verificáveis valem.
