# Claudinho.nvim: arquitetura e roadmap

Nov 11, 2026 · @Pedro · atualizado em Nov 12, 2026

## Visão e decisões

O Claudinho.nvim é um hard fork do [coder/claudecode.nvim](https://github.com/coder/claudecode.nvim): aproveita o protocolo que já funciona e reescreve a experiência inteira, como projeto próprio, sem vínculo com o upstream.

| Decisão                                           | Escolha                                                                                                                                                             | Por quê                                                     |
| ------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------- |
| Tipo de fork                                      | Hard fork sem vínculo: o git recomeça com um commit inicial e o repositório sai da rede de forks do GitHub                                                          | Liberdade total pra mudar API, comandos e UI                |
| Ponto de partida                                  | Código do upstream no commit `d123707` (12 nov 2026), sem o histórico                                                                                               | Protocolo, lockfile e tools MCP já testados                 |
| Nome                                              | Claudinho.nvim, namespace `claudinho` (`lua/claudinho/`), comando `:Claudinho`                                                                                      | Identidade própria                                          |
| Modelo de UI                                      | Caminho A: TUI do Claude no terminal + painéis do Neovim em volta                                                                                                   | Mantém slash commands, permissões e updates do CLI de graça |
| Caminho B (UI nativa em buffers, Claude headless) | Adiado, mas a arquitetura deixa a porta aberta                                                                                                                      | Controle total, porém reimplementa muito do CLI             |
| Dependências                                      | Zero por padrão, tudo via API nativa do Neovim                                                                                                                      | Instala e funciona sem nada além do plugin                  |
| Versão mínima do Neovim                           | 0.12                                                                                                                                                                | A mesma dos testes; libera as APIs de janela e winbar novas |
| Extensibilidade                                   | Adapters plugáveis (snacks, nui, telescope, fzf-lua…)                                                                                                               | Quem quiser pluga a lib preferida pela config               |
| Ciclo de cada feature                             | Ponta a ponta em `docs/features/<slug>/`: protótipo quando há UI, plano, spec, implementação, testes e docs; a próxima só começa quando a anterior fecha            | Evita acúmulo de backlog e cada entrega fica usável         |
| Sessões                                           | Várias ao mesmo tempo, uma por aba numerada, cada uma com servidor, porta e lock file próprios; o lock file leva o número da aba, que identifica a sessão no `/ide` | Seleção, @-mentions e diffs chegam só à sessão certa        |
| Comandos                                          | Comando único `:Claudinho` com subcomandos, sem atalho global imposto                                                                                               | Uma API nova e enxuta, sem herdar os `:ClaudeCode*`         |
| Claude fora do Neovim                             | Os providers `external` e `none` saem; o Claude roda só no terminal interno                                                                                         | Uma janela, um modelo de sessão                             |
| Idioma                                            | Mensagens, código, testes, `CHANGELOG.md` e `README.en.md` em inglês; `README.md` e `docs/` em português                                                            | O plugin fala inglês; o planejamento fica em português      |
| Versão                                            | Recomeça em `0.1.0` e sobe à mão no PR que fecha cada feature                                                                                                       | Sem ferramenta de release herdada do upstream               |

O foco é a experiência: diff, janela do terminal, envio de contexto, mouse e cliques, e onde cada informação do Claude aparece na tela.

## Ponto de partida

O upstream tem cerca de 16 mil linhas de Lua em `lua/claudecode/`. Dessas, cerca de 5 mil (servidor, lockfile e tools) são a base do fork; o resto é UI e vai ser reescrito ou reorganizado.

| Módulo                                     | Linhas     | O que faz                                                                    | Destino no fork                                                                                                               |
| ------------------------------------------ | ---------- | ---------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| `server/*` (tcp, frame, handshake, client) | \~2,9k     | WebSocket + JSON-RPC/MCP em Lua puro                                         | Manter o protocolo. Na UI base, perde o estado global (um servidor por aba) e passa a receber os hooks e o JSON da statusline |
| `lockfile.lua`                             | 341        | Arquivo em `~/.claude/ide/` que o CLI usa pra achar o Neovim                 | Manter. Na UI base, um por aba, com o número da aba no nome mostrado pelo `/ide`                                              |
| `tools/*`                                  | \~1,9k     | Tools MCP: openFile, openDiff, getDiagnostics, getOpenEditors, saveDocument… | Manter. O `openDiff` passa a respeitar a aba que pediu                                                                        |
| `diff.lua` + `diff_inline.lua`             | 2,5k + 643 | Abre a proposta, aceita/rejeita, lida com float, tab e foco                  | Reescrever (feature Diff), aproveitando o fluxo de resposta ao `openDiff`                                                     |
| `terminal.lua` + `terminal/*`              | \~2,9k     | Providers native, snacks, external, none + `paste_fix`                       | `snacks.lua` (970 linhas) sai na Fase 0; o resto é reescrito na UI base, e `external` e `none` saem. `paste_fix` fica         |
| `selection.lua` + `visual_commands.lua`    | 1,4k + 481 | Acompanha a seleção, envia @-mentions                                        | Na UI base, só passa a mirar a aba ativa; revisão completa na feature Envio de contexto                                       |
| `integrations.lua`                         | 557        | Lê a seleção de nvim-tree, neo-tree, oil, mini.files, netrw, snacks picker   | A leitura do snacks sai na Fase 0; o resto vira adapters opcionais na feature Envio de contexto                               |
| `init.lua` + `config.lua`                  | 1,5k + 236 | Setup, comandos `:ClaudeCode*`, validação da config                          | Reescrever com a API `:Claudinho` (UI base)                                                                                   |

O snacks aparece no provider `terminal/snacks.lua`, na leitura do picker em `integrations.lua` (com `pcall`), no health check, na escolha do provider `auto` e em `snacks_win_opts` (`terminal.lua`), e em checks de filetype (`snacks_picker_list`, `snacks_layout_box`) em `diff.lua` e `init.lua`. Hoje o `provider = "auto"` usa o `native` quando o snacks não está instalado. O que falta no `native` é janela flutuante, backdrop e o `hide_float` que o diff usa.

Do upstream ficam `PROTOCOL.md` e `ARCHITECTURE.md`, na raiz, como referência técnica; podem divergir do que o fork constrói. O resto das docs do upstream sai na Fase 0, incluindo o `lua/claudecode/README.md` (comportamento detalhado de diff e terminal), que continua público no upstream, no commit `d123707`. Vale ler essas três antes de reescrever cada área, junto com os testes em `tests/`.

## Fontes de dados além do protocolo IDE

O protocolo IDE só carrega seleção, @-mentions e chamadas de tool. O resto do que o Claude faz fica dentro da TUI, então os painéis precisam de outras fontes.

| Fonte                                                    | O que traz                                                                                                       | Como chega no Neovim                                                                  | Uso no fork                                                                                     |
| -------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| Protocolo IDE (WebSocket)                                | Seleção e @-mentions (Neovim → Claude); openDiff, openFile, getDiagnostics, saveDocument… (Claude → Neovim)      | Já implementado no `server/`                                                          | Diff, abrir arquivos, contexto                                                                  |
| [Hooks](https://code.claude.com/docs/en/hooks)           | Eventos do ciclo da sessão com JSON (`session_id`, `transcript_path`, e `permission_mode` em parte dos eventos)  | Hook `type: "http"`, que faz POST do JSON pro servidor da aba, com o token num header | Modo da sessão; depois, estado ao vivo: pensando, rodando tool X, esperando permissão, terminou |
| [Statusline](https://code.claude.com/docs/en/statusline) | JSON com `session_id`, `model.id`, `model.display_name`, `effort.level`, custo, % de contexto, `transcript_path` | Script de statusline que repassa o JSON pro servidor da aba                           | Modelo, esforço, custo e % de contexto                                                          |
| Transcript `.jsonl`                                      | Histórico completo da sessão, mensagem a mensagem                                                                | Leitura incremental do arquivo apontado por `transcript_path`                         | Lista de arquivos tocados, histórico, base pro caminho B                                        |

Os hooks e a statusline valem só pras sessões abertas pelo plugin: cada sessão inicia com `claude --settings <arquivo>`, um arquivo gerado só pra ela, somado aos settings do usuário e do projeto. O plugin nunca escreve em `~/.claude/settings.json`. A porta e o token do servidor da aba chegam ao processo por variável de ambiente.

A statusline não traz o modo de permissão; ele vem só dos hooks que trazem `permission_mode`. A lista de eventos e campos muda com as versões do CLI. Cada fonte deve tolerar campos ausentes e eventos desconhecidos.

## Arquitetura alvo

Nenhum módulo de UI conversa direto com o protocolo: as fontes publicam eventos num barramento e cada parte da UI só escuta o que precisa. Trocar uma fonte ou um pedaço da UI não mexe no resto. A spec da UI base decide quanto dessa estrutura entra já nela.

```text
 fontes                         barramento         UI
 ide_protocol (WebSocket) ──┐                   ┌─> janela, abas e terminal
 hooks (POST HTTP) ─────────┼─> events.lua ─────┼─> diff
 statusline (script) ───────┘                   ├─> status e painel
                                                └─> mouse
                     ui/adapters (window, select, input, notify): nativo ou lib
```

As respostas voltam pelo mesmo caminho ao contrário: o aceite de um diff ou o envio de uma seleção sai da UI e chega ao CLI pelo `ide_protocol`.

```text
lua/claudinho/
  core/          server/, lockfile.lua, tools/   (vem do upstream)
  events.lua     barramento: on(evento, fn), emit(evento, dados)
  sources/       ide_protocol.lua, hooks.lua, statusline.lua
  ui/
    adapters/    window.lua, select.lua, input.lua, notify.lua
    terminal.lua diff.lua panel.lua mouse.lua
  commands.lua   API pública e comandos
  config.lua     defaults + validação
```

Regra pros adapters: cada um tem uma implementação nativa e uma interface pequena. A config aceita um nome (`"snacks"`) ou uma tabela com as mesmas funções.

## Roadmap

As fases são áreas do plugin, entregues como features em sequência, sem datas fixas. Cada feature só fecha quando o plugin está em uso na sua config. A numeração das fases é estável e é a que os planos citam.

| Ordem | Feature                                   | Fases             |
| ----- | ----------------------------------------- | ----------------- |
| 1     | [Fork limpo](features/fork-limpo/plan.md) | 0                 |
| 2     | [UI base](features/base-ui/plan.md)       | 1, 5 e parte da 3 |
| 3     | Diff                                      | 2                 |
| 4     | Painel de informações                     | resto da 3        |
| 5     | Envio de contexto e mouse                 | 4                 |

O status de cada plano e spec fica no Index de `docs/features/README.md`.

Fase 0 · Fork limpo (detalhe no plano):

- [ ] Renomear `lua/claudecode/`, `plugin/` e todo identificador do plugin pro namespace `claudinho`
- [ ] Remover `terminal/snacks.lua`, `snacks_win_opts` e a leitura do snacks picker e explorer
- [ ] Remover as opções legadas de diff (`vertical_split`, `open_in_current_tab`, `auto_close_on_accept`, `show_diff_stats`) e o `queue_timeout`, com aviso pra quem ainda as usa
- [ ] Neovim mínimo 0.12 no loader e no CI
- [ ] Reduzir o repo ao que fica: sai release-please, Communique, skills de verificação e TLA+, scripts e fixtures `repro_issue_*` e as docs do upstream (`STORY.md` e outras)
- [ ] `README.md` (pt-BR) e `README.en.md` novos, `CLAUDE.md` curto, `CHANGELOG.md` novo, `LICENSE` com a linha do autor do fork
- [ ] `VERSION` em `0.1.0`
- [ ] Testes verdes
- [ ] Recomeço do git e desvínculo no GitHub, só com autorização a cada passo

Fase 1 · Janela do terminal, Fase 5 · Comandos e parte da Fase 3 (status): plano da UI base. A fundação técnica (`events.lua`, `sources/ide_protocol.lua`, interfaces de `ui/adapters` com implementação nativa) entra quando e como a spec da UI base decidir.

## Áreas de UX

Cada área vira uma feature em `docs/features/<slug>/`, com plano (`planner`) e spec (`specker`) a partir de `docs/features/_template/`. A tabela abaixo é o ponto de partida dos planos que faltam: as perguntas que eles precisam responder e as ideias que já surgiram.

| Área                  | Fase | Feature                   | Perguntas a responder                                                                      | Ideias iniciais                                                                                                                                                                          |
| --------------------- | ---- | ------------------------- | ------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Janela do terminal    | 1    | UI base                   | Respondidas no plano da UI base                                                            | Layouts `right`, `bottom`, `float` e `tab`; abas de sessão na winbar; esconder sem matar o processo                                                                                      |
| Diff                  | 2    | Diff                      | Onde abre? Como aceitar e rejeitar? Dá pra aceitar parte? Como ver vários diffs pendentes? | Winbar com `[Accept] [Reject] [Next hunk]` clicáveis; aceite por hunk revertendo hunks no buffer da proposta; fila de diffs pendentes                                                    |
| Painel de informações | 3    | UI base (status) + Painel | Que informações ficam sempre visíveis? Onde (winbar, statusline, painel lateral, float)?   | Estado (ocioso, pensando, rodando tool, esperando permissão), custo, % de contexto, arquivos editados clicáveis, aviso quando o Claude para; modelo, esforço e modo já entram na UI base |
| Envio de contexto     | 4    | Envio de contexto e mouse | Como mandar seleção, arquivo, pasta, diagnóstico? Que feedback aparece?                    | Um comando de envio que entende o contexto (visual, explorer, picker); confirmação visível do que foi enviado                                                                            |
| Mouse                 | 4    | Envio de contexto e mouse | Que ações merecem clique? Botão direito? Arrastar?                                         | Menu `PopUp` com "Send to Claude"; regiões clicáveis na winbar e statusline (`%@Func@`); clique nos itens do painel via `getmousepos()`                                                  |
| Comandos e atalhos    | 5    | UI base                   | Respondidas no plano da UI base                                                            | `:Claudinho` com subcomandos e completion; nenhum atalho global imposto, um preset opcional                                                                                              |

## Primeiros passos na sua máquina

O Claudinho substitui o claudecode numa branch da sua config, usando o gerenciador nativo do Neovim (`vim.pack`, 0.12+). Os dois não rodam lado a lado.

1. Clone o repositório, por exemplo em `~/dev/claudinho.nvim`.
2. Na config do Neovim, crie uma branch de teste, remova o claudecode e aponte pro Claudinho:

```lua
vim.pack.add({
  { src = "https://github.com/pedrohrb7/claudinho.nvim", version = "main" },
})
require("claudinho").setup({})
```

3. Pra testar mudanças sem dar push a cada uma, troque temporariamente o `vim.pack.add` por `vim.opt.rtp:prepend(vim.fn.expand("~/dev/claudinho.nvim"))`, apontando pro clone local. Pro uso do dia a dia, volte ao `vim.pack.add`; `vim.pack.update()` puxa as atualizações do GitHub.
4. Depois do recomeço do git da Fase 0, remova e instale o plugin de novo: o clone antigo do `vim.pack` não avança pro `main` reescrito.
5. Prepare o ambiente de testes com [mise](https://mise.jdx.dev): `mise install`, depois `mise run setup` (busted, luacheck, luacov) e `mise run all` (format, lint e testes). O `mise.toml` fixa Neovim 0.12.3 e LuaJIT, que os testes exigem.

## Decisões em aberto e riscos

Decisões tomadas:

- [x] Nome do plugin e do namespace Lua: Claudinho.nvim, namespace `claudinho` (`lua/claudinho/`, comando `:Claudinho`)
- [x] Versão mínima do Neovim: 0.12
- [x] Providers `external` e `none`: saem na UI base; o foco é o terminal interno
- [x] Hooks e statusline: arquivo de settings só da sessão (`claude --settings`, presente no CLI 2.1.323), somado ao `~/.claude/settings.json` do usuário
- [x] Compatibilidade com `:ClaudeCode*`: não, API nova com `:Claudinho <subcomando>`
- [x] Vínculo com o upstream: nenhum; git recomeçado e repositório fora da rede de forks
- [x] `PROTOCOL.md` e `ARCHITECTURE.md`: ficam na raiz até as docs técnicas serem estruturadas

Decisões a tomar:

- [ ] Quais integrações de explorer continuam (nvim-tree, neo-tree, oil, mini.files, netrw); até a feature Envio de contexto, ficam como estão

Riscos:

| Risco                                                                                                  | Impacto                                          | Mitigação                                                                                                                                             |
| ------------------------------------------------------------------------------------------------------ | ------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| O CLI muda o protocolo IDE, os hooks ou a statusline                                                   | Painéis param de atualizar, diff quebra          | Cada fonte isolada atrás do barramento; tolerar campos ausentes; testes com fixtures do JSON real                                                     |
| Sem o upstream, correções de protocolo não chegam sozinhas, e sem histórico comum não há `cherry-pick` | Bugs que o upstream já resolveu voltam           | Comparar à mão com o upstream a partir do `d123707` de tempos em tempos, só pra `server/` e `tools/`                                                  |
| Diff e terminal têm muitos casos de borda (float, tabs, foco, vários diffs)                            | Regressões difíceis de ver                       | Ler o `lua/claudecode/README.md` do upstream no `d123707` antes de reescrever; manter os testes de integração do upstream até a reescrita ter os seus |
| O servidor passa a existir uma vez por aba e a receber POSTs dos hooks e o JSON da statusline          | Regressões no protocolo, que hoje funciona       | Manter os testes de `server/`, `lockfile` e tools verdes durante a troca; testes de integração com duas abas e um cliente por servidor                |
| O script de statusline roda a cada atualização da TUI e não pode usar `curl`, `jq` nem `python`        | Sessão mais lenta ou status atrasado             | A spec da UI base mede o custo do script e escolhe o meio de repasse mais leve que só dependa do Neovim                                               |
| Mouse dentro do terminal vai pra TUI do Claude, não pro Neovim                                         | Cliques na área do Claude não dão pra customizar | Concentrar ações de mouse em winbar, statusline, painéis e diff, que são do Neovim                                                                    |
| Escopo "mudar tudo" cresce sem fim                                                                     | O fork nunca fica usável no dia a dia            | Cada feature termina com o plugin usado de verdade na sua config                                                                                      |
