# Status interativo: statusline clicável, modo ao vivo, comandos de esforço e modo e limites de uso - spec técnica

- **Date:** 2026-11-19
- **Status:** Draft
- **Plan:** [plan.md](plan.md)
- **Implementation log:** [log.md](log.md)
- **Decisões do usuário (2026-11-19):** na janela estreita, os itens de uso saem um de cada vez, o `7d` primeiro (antiga pergunta 2). As sugestões de prompt do Claude ficam ligadas por padrão, como no claudecode.nvim, e uma opção nova do plugin, `terminal.prompt_suggestions`, as desliga (antiga pergunta 1, seção 8). Com elas ligadas, a guarda nunca pode tomar o texto cinza por texto digitado nem mandar teclas por cima de texto real: a medição dos sinais possíveis (F17 a F19) mostrou que nenhum separa os dois em todos os casos, e o usuário decidiu que todo texto visível depois de `❯` conta como digitado, sem exceção para o exemplo `Try "..."` do início ([Open questions](#open-questions)).

## Summary

Tudo muda dentro do plugin, em Lua puro; o servidor da aba, o relay e as rotas `POST /claudinho/*` não mudam. Três peças novas e oito módulos alterados:

| Camada                                | O que muda                                                                                                                                                                                                                                            |
| ------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `sources/tui_screen.lua` (novo, puro) | Lê as últimas linhas do buffer do terminal da aba: campo de prompt (reconhecido, vazio ou com texto), diálogo ou tela desconhecida, e a linha de modo do rodapé                                                                                       |
| `tui_keys.lua` (novo)                 | A guarda (regras 9 a 13) e o envio de Shift+Tab, `/effort` e `/model <valor>` à TUI da aba ativa, no mesmo passo da leitura                                                                                                                           |
| `usage.lua` (novo)                    | O valor único de uso da conta (`rate_limits` mais recente), só em memória, e o relógio que tira a janela que zerou                                                                                                                                    |
| `sources/session_data.lua`            | `from_statusline` passa a devolver também `rate_limits` (validado) e `vim_mode`                                                                                                                                                                       |
| `session.lua`                         | A cada POST de statusline: lê o modo na tela da sessão (com releituras curtas quando a tela não decide), atualiza o uso e o `vim_mode`; com `terminal.prompt_suggestions = false`, o ambiente e os settings da sessão desligam as sugestões de prompt |
| `config.lua`                          | Chave nova `terminal.prompt_suggestions` (booleano, padrão `true`), validada como as outras chaves da base-ui                                                                                                                                         |
| `ui/status.lua`                       | Regiões clicáveis no modelo, no esforço e no modo; o uso à direita (`%=`), com cor por grupo de destaque e corte por largura; o handler de clique                                                                                                     |
| `ui/window.lua`                       | Instala o handler de clique e os grupos de uso, religa os grupos no `ColorScheme`, devolve o modo terminal tirado por um clique e redesenha quando o relógio tira uma janela de uso                                                                   |
| `commands.lua`, `init.lua`            | Subcomandos `select-effort` e `mode-next`, completion e preset (`<leader>ae`, `<leader>ap`); `select-model` passa pela guarda antes e depois da escolha e não abre uma segunda escolha                                                                |

## Background

O plano ([plan.md](plan.md), aprovado em 2026-11-19, sem perguntas abertas) define as regras 1 a 58. Esta spec as implementa sobre a base entregue pela [base-ui](../base-ui/spec.md):

- O relay (`sources/relay.lua`) já posta o JSON inteiro da statusline no servidor da aba; `session.lua` `apply_post` decodifica no loop principal e mescla `session_id`, `model`, `effort` e `mode` em `session.data`, chamando `sessions.on_change` quando algo muda, o que redesenha a janela.
- `ui/status.lua` monta `modelo · esforço · modo` a partir de `session.data` da aba ativa (`%!v:lua.require'claudinho.ui.status'.render()` na statusline local da janela).
- A barra de abas já usa regiões `%N@v:lua.ClaudinhoTabClick@ ... %X` (`ui/tabbar.lua`), instaladas por `window.setup()`.
- `terminal.send_to_terminal(text, { submit })` manda bytes ao canal do job da aba ativa e já responde `Cannot send text: ...` quando o canal fechou.
- `init.open_with_model()` abre `vim.ui.select` com `config.models` e manda `/model <valor>` sem olhar a tela.
- O adendo da base-ui que aponta para este plano (regras 47, 51, 52, 64, 66, 68 e 69) já está no [plano da base-ui](../base-ui/plan.md#addendum-2026-11-18-guarda-no-select-model-e-subcomandos-novos).

### Fatos medidos

Medidos pelo specker em 2026-11-19 com Claude Code 2.1.328 real, num terminal (`jobstart` com `term = true`) de um Neovim 0.12.3 headless, na pasta do repositório, com `--settings` cujo `statusLine` é um script que guarda o JSON e imprime uma linha vazia, como o relay. Nenhum prompt foi enviado à API. As telas estão na seção 11 do Design.

| #   | Fato                                                                                                                                                                                                                                                                                                                                                                                                                                   | Consequência                                                                                                                                                         |
| --- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| F1  | O campo de prompt é uma linha que começa com `❯` (U+276F) seguido de U+00A0 (espaço inseparável), entre duas linhas feitas só de `─` (U+2500) na largura toda. Linhas extras de um texto com várias linhas começam com dois espaços                                                                                                                                                                                                    | É a marca do campo de prompt. O eco de prompts antigos na conversa usa `❯` + espaço comum, e o menu de `/` usa `❯` recuado dois espaços: nenhum dos dois se confunde |
| F2  | Prompt vazio: `❯` + U+00A0 + só espaços. Com as sugestões de prompt ligadas (padrão do Claude), o prompt vazio mostra um exemplo cinza (`Try "edit init.lua to…"`, `Try "fix typecheck errors"`) no início da sessão e de novo depois de um Ctrl-U; depois de sair de um seletor com Esc, o prompt fica em branco, sem exemplo. O texto do buffer não traz a cor                                                                       | Sem sugestões, "vazio" é exato; com elas, o texto cinza e o texto digitado são iguais no texto do buffer                                                             |
| F3  | Com `promptSuggestionEnabled: false` no `--settings`, o prompt vazio é `❯` + U+00A0 + nada, já no início                                                                                                                                                                                                                                                                                                                               | Com `terminal.prompt_suggestions = false`, o reconhecimento é exato                                                                                                  |
| F4  | Linhas de modo no rodapé, abaixo da segunda linha `─`: `⏵⏵ auto mode on (shift+tab to cycle) · install gh for PR status`, `⏸ manual mode on · install gh for PR status`, `⏵⏵ accept edits on (shift+tab to cycle) · ...`, `⏸ plan mode on (shift+tab to cycle) · ...`. `⏵` é U+23F5 (duas vezes), `⏸` é U+23F8                                                                                                                         | A linha de modo pode trazer outros itens depois de `·`; existe uma linha explícita para o modo manual (`manual mode`), que mapeia para `default`                     |
| F5  | Ciclo do Shift+Tab nesta conta: auto, manual, accept edits, plan, auto                                                                                                                                                                                                                                                                                                                                                                 | O plugin nunca supõe o ciclo (regra 20)                                                                                                                              |
| F6  | O rodapé muda 15 a 44 ms depois do Shift+Tab; o comando de statusline começa cerca de 300 ms depois (debounce de 300 ms documentado), 7 de 7 vezes                                                                                                                                                                                                                                                                                     | Quando o POST chega, o rodapé já mostra o modo novo; a releitura (seção 2) cobre só a tela que ainda não decide                                                      |
| F7  | Com texto digitado (`hello world`), o Shift+Tab muda o modo e o texto continua igual                                                                                                                                                                                                                                                                                                                                                   | Regra 21 confirmada: o modo não exige prompt vazio                                                                                                                   |
| F8  | Com o menu de `/` aberto (`/eff` digitado), o Shift+Tab muda o modo e deixa o texto e o menu como estavam                                                                                                                                                                                                                                                                                                                              | O menu de autocompletar não é diálogo para a guarda; `/effort` e `/model` já recusam pelo texto no prompt                                                            |
| F9  | `/effort` + Enter num único `chansend` abre o seletor de esforço; o seletor e o de `/model` substituem o campo de prompt (borda `▔`, rodapé `←/→ to adjust · ... · Esc to cancel`), sem as linhas `─` nem `❯` + U+00A0                                                                                                                                                                                                                 | Com um seletor aberto, a tela não tem campo de prompt: a guarda recusa                                                                                               |
| F10 | O primeiro Ctrl-C troca a linha de modo por `Press Ctrl-C again to exit`, com o campo de prompt à vista                                                                                                                                                                                                                                                                                                                                | Sem cuidado, a regra "campo reconhecido e sem linha de modo = manual" mostraria `manual` aqui (seção 1)                                                              |
| F11 | O buffer de um terminal escondido (sem janela) continua atualizado                                                                                                                                                                                                                                                                                                                                                                     | A leitura funciona em abas em segundo plano e com a janela escondida (regra 29)                                                                                      |
| F12 | `--allow-dangerously-skip-permissions` abre antes um diálogo de aceite (`❯ No, exit` / `Yes, I accept`, `Enter to confirm · Esc to cancel`)                                                                                                                                                                                                                                                                                            | Mais uma tela sem campo de prompt; o texto `bypass permissions on` fica para a Task 3                                                                                |
| F13 | O JSON da statusline trouxe `rate_limits.five_hour` e `seven_day` com `used_percentage` inteiro e `resets_at` em segundos Unix já no primeiro POST da sessão, antes de qualquer resposta (dado da conta em cache)                                                                                                                                                                                                                      | O uso pode aparecer logo no início; o código não depende disso (regra 50)                                                                                            |
| F14 | No Neovim 0.12.3 embutido (`--embed --headless`, dirigido por RPC), um clique esquerdo numa região `%N@v:lua.F@` da statusline de outra janela chama a função sem trocar a janela atual, com `laststatus` 2 e 3; com o foco no terminal em modo terminal, o clique tira o modo terminal (`t` vira `nt`) antes de chamar a função; um `ModeChanged` `t:nt` dispara no mesmo passo e um `startinsert` no handler devolve o modo terminal | Regra 8 exige devolver o modo terminal (seção 5). O argumento `clicks` cresce (1, 2, 3) em cliques rápidos                                                           |
| F15 | `vim.json.decode` dá a `{}` a metatable de `vim.empty_dict()`; `[]` vem sem metatable                                                                                                                                                                                                                                                                                                                                                  | `rate_limits: {}` é objeto (substitui o valor); `rate_limits: []` não é (conta como ausente, regra 56)                                                               |
| F16 | Neovim 0.12 tem o item `%$Grupo$` na statusline, que herda os atributos anteriores (o fundo da `StatusLine`/`StatusLineNC`)                                                                                                                                                                                                                                                                                                            | A cor do uso muda só a frente; o fundo segue o da statusline, com ou sem foco (regra 48)                                                                             |
| F17 | Atributos das células do prompt, lidos na grade da tela (`screenattr()`, `screenchar()` e `nvim__inspect_cell(1, ...)`) com a janela do Claude num split visível: o texto cinza do início veio com uma cor de frente própria (`foreground`, sem `dim`) e, depois de um Ctrl-U, com `dim`; o texto digitado `hello`, `@READ` e `# note` veio sem atributo; o texto digitado `/effort` veio colorido (`fg_indexed`, `foreground`)        | Não há um atributo que separe o cinza do digitado: o estilo do cinza varia, e texto digitado também pode ter cor. A cor depende ainda do tema do Claude              |
| F18 | Com a janela num float, `nvim__inspect_cell(1, ...)` lê o que está embaixo do float, e `screenattr()` dá o mesmo valor para o texto cinza e para o digitado; com a janela escondida, em outra aba do Neovim ou com o prompt fora da tela (rolagem), não há células a ler. `nvim__inspect_cell` é uma API experimental (`__`)                                                                                                           | Mesmo um sinal de cor só existiria para a janela visível em split, com o prompt na tela                                                                              |
| F19 | O cursor do terminal só aparece como cursor da janela quando ela está em modo terminal (fora dele, e com a janela escondida, a posição lida não acompanha o terminal); e com Ctrl-A o cursor fica no começo de um texto real, como fica antes de um texto cinza. No modo bash (`!` digitado), o `❯` do prompt dá lugar a `!`                                                                                                           | O cursor não separa os dois casos. O modo bash não é campo reconhecido: a guarda recusa (seguro)                                                                     |

Pela documentação do Claude Code ([Status line](https://code.claude.com/docs/en/statusline), "When the status line updates"): o comando roda no início da sessão, a cada mensagem do assistente, no fim do `/compact`, numa troca de modo, numa troca do modo vim, quando uma janela de `rate_limits` chega ao `resets_at`, e com debounce de 300 ms; um POST novo cancela o script em andamento. A escolha no seletor de `/effort` não está na lista: o esforço novo aparece no próximo POST (base-ui regra 49), e o roteiro manual registra se a escolha dispara uma execução. O JSON traz `vim.mode` (`NORMAL`, `INSERT`, `VISUAL`, `VISUAL LINE`) quando o modo vim do prompt está ligado (`editorMode: "vim"`).

## Design

### 0. Módulos

| Arquivo                                  | Tipo     | Responsabilidade                                                                                       |
| ---------------------------------------- | -------- | ------------------------------------------------------------------------------------------------------ |
| `lua/claudinho/sources/tui_screen.lua`   | novo     | `parse(lines)` puro; `read(buf)` pega as últimas linhas do buffer e chama `parse`, sem erro            |
| `lua/claudinho/tui_keys.lua`             | novo     | `ready`, `mode_next`, `select_effort`, `send_model`; respostas da guarda                               |
| `lua/claudinho/usage.lua`                | novo     | Estado único do uso, `update`, `windows(now)`, relógio de reset                                        |
| `lua/claudinho/sources/session_data.lua` | alterado | `rate_limits(t)` e `from_statusline` com `rate_limits` e `vim_mode`                                    |
| `lua/claudinho/session.lua`              | alterado | `apply_post`: leitura do modo, releituras, uso, `vim_mode`; variável de ambiente das sugestões         |
| `lua/claudinho/session_settings.lua`     | alterado | `promptSuggestionEnabled = false` no arquivo de settings, só com `terminal.prompt_suggestions = false` |
| `lua/claudinho/ui/status.lua`            | alterado | Itens, regiões, uso, cores, largura, `build`/`render`, `click`, grupos                                 |
| `lua/claudinho/ui/window.lua`            | alterado | `setup` instala o clique e os grupos de uso; `ModeChanged`; `ColorScheme` religa os dois conjuntos     |
| `lua/claudinho/commands.lua`             | alterado | `select-effort`, `mode-next`, preset                                                                   |
| `lua/claudinho/init.lua`                 | alterado | `open_with_model` com a guarda e a trava de escolha aberta                                             |
| `lua/claudinho/sessions.lua`             | alterado | `VimLeavePre` para o relógio do uso (`usage.stop()`); `kill_all` não apaga o uso                       |
| `lua/claudinho/config.lua`               | alterado | `terminal.prompt_suggestions` nos padrões e em `normalize_new_keys`                                    |
| `lua/claudinho/types.lua`                | alterado | Classes novas (`ClaudinhoScreen`, `ClaudinhoUsageWindow`) e campos de `ClaudinhoSession`               |

### 1. Leitura da tela (`sources/tui_screen.lua`)

#### Entrada

`read(buf)` pega as últimas `M.TAIL = 120` linhas do buffer (`nvim_buf_get_lines(buf, -121, -1, false)`, ou todas quando há menos), dentro de `pcall`. Buffer inválido ou erro: devolve `nil` (regra 37). Nada da tela é guardado, registrado em log nem enviado (regra 36); o logger recebe só o resultado (`mode`, `prompt`) e nunca o texto.

#### `parse(lines)` -> `ClaudinhoScreen`

```lua
---@class ClaudinhoScreen
---@field prompt "empty"|"text"|nil  -- nil: campo de prompt não reconhecido
---@field mode string|nil            -- código (`default`, `plan`, ...) ou rótulo desconhecido como veio; nil: a tela não decide
---@field mode_line boolean          -- achou uma linha de modo
```

Passos, de baixo para cima, sobre as linhas sem as linhas em branco do fim (só espaços e U+00A0):

1. **Regra inferior (R2):** a linha mais baixa que, sem espaços no fim, é feita só de `─` e tem pelo menos `M.MIN_RULE = 20` deles. Rodapé = as linhas abaixo dela, no máximo `M.MAX_FOOTER = 8`. Sem R2, ou com mais linhas abaixo, o campo não é reconhecido.
2. **Entrada:** subindo a partir de R2, as linhas que começam com dois espaços são continuação; a primeira linha que não é continuação tem de começar com `❯` + U+00A0 (`"\226\157\175\194\160"`), e a linha logo acima dela tem de ser outra regra (R1). No máximo `M.MAX_INPUT = 60` linhas entre R1 e R2. Se algo falha, o campo não é reconhecido.
3. **Prompt:** o texto depois de `❯` + U+00A0 mais as continuações (sem os dois espaços). Só espaços e U+00A0: `"empty"`; senão `"text"`. Isso vale com as sugestões ligadas ou desligadas: o texto cinza conta como `"text"` (rodapé da seção 8), inclusive o exemplo do início (`Try "..."`), sem exceção (decisão do usuário, 2026-11-19).
4. **Linha de modo:** procurada no rodapé quando o campo foi reconhecido; senão, nas últimas `M.FALLBACK_LINES = 4` linhas (regra 30). A primeira linha, de cima para baixo, que casa (abaixo) define o modo.
5. **Decisão do modo (regras 31 e 33):**

| Tela                                                                                               | `mode`                               |
| -------------------------------------------------------------------------------------------------- | ------------------------------------ |
| Linha de modo com rótulo conhecido                                                                 | o código da tabela de rótulos        |
| Linha de modo com rótulo desconhecido                                                              | o rótulo como veio (ex.: `foo mode`) |
| Campo reconhecido, sem linha de modo, e nenhuma linha do rodapé é aviso passageiro (`M.TRANSIENT`) | `default`                            |
| Campo reconhecido, sem linha de modo, com aviso passageiro no rodapé (F10)                         | `nil` (mantém o último)              |
| Campo não reconhecido e sem linha de modo                                                          | `nil`                                |

`M.TRANSIENT` (padrões Lua, ancorados depois dos espaços do começo): `^Press Ctrl%-[CD] again to exit`. A lista cresce só com telas reais (fixtures).

#### Linha de modo (regra 30)

Na linha sem espaços (e U+00A0) no começo:

- **Com símbolo:** começa com um símbolo de `M.MODE_SYMBOLS = { "⏵⏵", "⏸" }` seguido de um espaço. O rótulo é o texto do espaço até a primeira ocorrência de ` on` que é seguida do fim da linha, de ` (` ou de `·`.
- **Sem símbolo:** começa com um rótulo conhecido seguido de ` on` e do fim da linha, de ` (` ou de `·` (ex.: `auto mode on`).
- O rótulo, sem espaços nas pontas, tem de 1 a `M.MAX_LABEL = 32` células de largura e não tem `·`, `(`, `)`, `⏵`, `⏸` nem `❯`. Qualquer outra linha não é linha de modo (regra 32): `install gh for PR status`, avisos (`⚠ ...`) e dicas nunca viram modo.

Rótulos conhecidos (`M.LABELS`):

| Rótulo na tela       | Código              | Mostrado (`status.MODES`) |
| -------------------- | ------------------- | ------------------------- |
| `manual mode`        | `default`           | `manual`                  |
| `accept edits`       | `acceptEdits`       | `accept edits`            |
| `plan mode`          | `plan`              | `plan`                    |
| `auto mode`          | `auto`              | `auto`                    |
| `bypass permissions` | `bypassPermissions` | `bypass permissions`      |

`manual mode` não está na tabela da regra 31: é a linha explícita que o 2.1.328 mostra no modo manual (F4). Sem o mapeamento, o status mostraria `manual mode` em vez de `manual`, contra a regra 6. `bypass permissions` entra pela regra 31 e só fica se a Task 3 confirmar o texto; se o texto for outro, a linha da tabela muda para o texto medido. `don't ask` não foi visto; se aparecer, o rótulo como veio já mostra o mesmo texto que `dontAsk`.

#### Guarda sobre a tela

`M.ready(screen, need_empty)` -> `"ok" | "busy" | "text"`:

- `screen == nil` ou `screen.prompt == nil`: `"busy"` (diálogo aberto ou tela não reconhecida, regras 9 e 11).
- `need_empty` e `screen.prompt ~= "empty"`: `"text"` (regra 10).
- Senão `"ok"`.

A hipótese H1, que a Task 3 confirma com telas reais, é que todo diálogo (pedido de permissão de arquivo e de comando, aprovação de plano, confiança da pasta, seletores, `/config` e outros menus) esconde o campo de prompt, como os seletores medidos (F9). Se uma tela de diálogo mostrar R1, `❯` + U+00A0 e R2, a Task 3 para e a spec ganha um adendo com o marcador desse diálogo antes da Task 4.

### 2. Modo ao vivo e dados do POST (`session.lua`)

`apply_post(session, kind, body)` continua no loop principal. Para `kind == "statusline"`, depois de mesclar `session_id`, `model` e `effort` como hoje:

1. `session.vim_mode = fields.vim_mode` (string ou `nil`; `nil` quando o JSON não traz `vim`, isto é, modo vim desligado). Fica fora de `session.data`: não é status.
2. `fields.rate_limits ~= nil` -> `changed = require("claudinho.usage").update(fields.rate_limits) or changed` (seção 4).
3. Leitura da tela: `screen = tui_screen.read(session.buf)`; `screen and screen.mode` diferente de `session.data.mode` -> grava e `changed = true` (regras 29 e 38: só o buffer da sessão que postou).
4. `changed` -> `report("on_change", session)`: um redraw só para dados, modo e uso (regra 52).

**Releitura:** quando a leitura do passo 3 não decide (`screen == nil` ou `screen.mode == nil`), `apply_post` agenda releituras em `M.REREAD_MS = { 150, 400, 1000 }` (acumulado, com `vim.defer_fn`). Cada POST de statusline incrementa `session.screen_gen`; uma releitura só age se o `gen` dela ainda é o atual, a sessão não está `closing` e o processo está `running`. A primeira releitura que decide grava o modo e para as outras. Isso cobre o primeiro POST antes do primeiro desenho do rodapé (critério "Modo desde o início") e o POST que chega com um aviso passageiro; F6 mostra que numa troca de modo o rodapé já está pronto.

**Hooks (regra 34):** o caminho do hook não muda. Hook e tela gravam `session.data.mode` na ordem em que o loop principal processa os POSTs; vale o último.

**Antes de qualquer leitura decisiva (regra 35):** `session.data.mode` fica `nil`, como hoje.

**Custo (regra 37):** uma leitura é um `nvim_buf_get_lines` de até 121 linhas e um laço sobre elas; acontece no máximo uma vez por POST (debounce de 300 ms do Claude) mais três releituras. A Task 15 mede o tempo de `parse` sobre a fixture maior (alvo: menos de 1 ms).

### 3. A guarda e o envio (`tui_keys.lua`)

```lua
M.REPLIES = {
  busy = "Claude %d: finish the open prompt in Claude first",
  text = "Claude %d: clear the prompt first",
  text_suggestions = "Claude %d: clear the prompt first (gray suggestions count too)", -- prompt_suggestions ~= false
  vim = "Claude %d: switch the Claude prompt to insert mode first",
}
M.SHIFT_TAB = "\27[Z"

---@return boolean ok
---@return string|nil reply  -- já formatado, para notify.reply
function M.ready(s, need_empty) end   -- lê a tela de s.buf agora
function M.mode_next() end            -- regras 19 a 22
function M.select_effort() end        -- regras 17 e 18
function M.send_model(value) end      -- regra 15, segunda checagem
```

Ordem comum, sempre na aba ativa (regras 4 e 24):

1. Sem aba ativa: `notify.reply(sessions.NO_TABS)`, devolve `false` (regras 13 e 26).
2. Aba encerrada: `notify.reply(sessions.exited_message(s))`, devolve `false`.
3. `session.vim_mode` não `nil` e diferente de `INSERT`: resposta `vim`, nada enviado. Com o prompt em modo NORMAL do vim, `/effort` viraria comandos de edição; o Shift+Tab também fica de fora, por segurança, já que o comportamento dele no NORMAL não foi medido.
4. `M.ready(s, need_empty)` sobre `tui_screen.read(s.buf)`; `"busy"` ou `"text"` vira `notify.reply` com o texto da tabela (regra 11; `notify.reply` sempre aparece, regra 89 da base-ui) e nada é enviado nem guardado.
5. Envio pelo `terminal.send_to_terminal`, na mesma função e sem nenhum `yield`, `vim.wait`, `schedule` ou `defer` entre a leitura e o `chansend` (regra 12): o buffer do terminal só muda quando o loop roda. O canal fechado responde como hoje (`Cannot send text: ...`).

| Ação            | `need_empty` | Bytes                                                  | Depois                                                                                                                                                     |
| --------------- | ------------ | ------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `mode_next`     | não          | `send_to_terminal("\27[Z", { submit = false })`        | Nada: não mostra nem foca a janela, não muda o modo do Neovim nem o cursor (regras 8 e 22). O status muda pelo POST que a troca de modo dispara (regra 20) |
| `select_effort` | sim          | `send_to_terminal("/effort")` (o `\r` vem do `submit`) | `window.show({ focus = true })` e, se o modo atual não é terminal, `vim.cmd.startinsert()`, mesmo com `terminal.auto_insert = false` (regra 18)            |
| `send_model`    | sim          | `send_to_terminal("/model " .. value)`                 | Nada além do envio (como hoje)                                                                                                                             |

Cada ação devolve `true` quando enviou. `mode_next` e `select_effort` aceitam e ignoram argumentos.

#### `select-model` (`init.open_with_model`, regras 14 a 16)

```text
sem config.models               -> erro de hoje
aba ativa encerrada             -> exited_message; a escolha não abre
aba ativa rodando               -> tui_keys.ready(s, true); falha -> resposta da regra 11; a escolha não abre
picking == true                 -> nada (regra 16)
picking = true; vim.ui.select(models, ..., function(choice)
  picking = false
  cancelado ou valor inválido   -> como hoje
  sem abas agora                -> sessions.new(" --model " .. shellescape(value))   (sem guarda)
  aba ativa agora encerrada     -> exited_message
  senão                         -> tui_keys.send_model(value)   (guarda de novo na aba ativa agora)
end)
```

`picking` é um campo de módulo em `init.lua`. Um erro lançado por `vim.ui.select` volta `picking` a `false` (`pcall`) e é registrado no log. A trava depende do contrato do `vim.ui.select` (`on_choice(nil)` ao cancelar), que os seletores conhecidos (o padrão, telescope ui-select, fzf-lua, snacks, mini.pick, dressing) cumprem; o README registra.

### 4. Limites de uso

#### Dado (`sources/session_data.lua`)

`M.rate_limits(t)`:

- `t` não é tabela, é um array (`t[1] ~= nil`), ou é tabela vazia sem a metatable de `vim.empty_dict()` (F15): `nil` (ausente: o valor não muda, regras 50 e 56).
- Senão devolve `{ five_hour = W|nil, seven_day = W|nil }` (pode ser `{}`), com `W = { used = number, resets_at = number|nil }`:
  - `used`: `used_percentage` número finito (`x == x`, diferente de `±math.huge`) e `>= 0`; senão a janela fica fora (regra 43). Valor acima de 100 entra como veio.
  - `resets_at`: número finito `> 0`; senão `nil` e o item sai sem a hora (regra 46).
  - Janela que não é tabela fica fora. `spend_limit` e campos novos são ignorados.

`from_statusline(t)` ganha `rate_limits = M.rate_limits(t.rate_limits)` e `vim_mode = str(type(t.vim) == "table" and t.vim.mode or nil)`. Nada disso afeta `model`, `effort` ou `session_id` (regra 56).

#### Estado (`usage.lua`)

```lua
M.state = { value = nil, timer = nil }  -- value: { five_hour?: W, seven_day?: W }

function M.update(value) end   -- substitui o valor inteiro (regra 50); devolve changed; arma ou para o relógio
function M.windows(now) end    -- { five_hour?: W, seven_day?: W } sem as janelas com resets_at <= now (regra 53)
function M.stop() end          -- para o relógio (VimLeavePre); não apaga o valor
function M.reset() end         -- só para testes
```

- O valor vive só neste módulo (regra 55): nunca vai para disco, log, lock file ou outra sessão. `sessions.kill_all` e o fechamento de abas não o tocam; `VimLeavePre` só chama `usage.stop()`.
- Ordem de chegada: `update` é chamado no loop principal na ordem dos POSTs, de qualquer aba (regra 50). O plugin nunca calcula uso (regra 57): só filtra a janela vencida.
- `now` é `vim.uv.clock_gettime("realtime")` em segundos com fração (`sec + nsec / 1e9`), lido em `usage.now()` para os testes trocarem.

**Relógio (regra 53).** Enquanto o valor tem uma janela com `resets_at` no futuro, um timer `vim.uv` repete a cada `M.TICK_MS = 500` ms. Cada tique compara o relógio de parede com os `resets_at`; quando uma janela vence, ela sai de `M.state.value` e `window.refresh()` roda (via `vim.schedule`). Sem janela no futuro, o timer para e é fechado. O relógio de parede, e não um timer de um tiro até o reset, é o que garante o 1 s depois de uma suspensão do computador: os timers do libuv usam o relógio monotônico, que no Linux não anda durante a suspensão. O `render` também filtra pelo relógio, então qualquer redraw já mostra o certo.

### 5. Statusline (`ui/status.lua`)

#### Lado esquerdo (regras 1 a 6)

`M.items(data)` devolve a lista `{ { id = 1, text = model }, { id = 2, text = effort }, { id = 3, text = mode_label(mode) } }` sem os ausentes. `M.text(data)` continua igual (texto plano, base dos testes da base-ui). Cada item vira `%<id>@v:lua.ClaudinhoStatusClick@<texto com % dobrado>%X`; o separador `·` fica fora das regiões (regra 1). Item ausente não tem região (regra 5).

#### Uso (regras 39 a 48)

- `M.percent(used)` = `math.floor(used + 0.5)` (meio para cima: `23.5` -> `24`, `79.4` -> `79`, `79.5` -> `80`).
- `M.level(pct)`: `pct >= 95` -> `ClaudinhoUsageError`; `pct >= 80` -> `ClaudinhoUsageWarn`; senão `nil` (regra 47, sobre o valor já arredondado).
- `M.format_reset(resets_at, now)` (regras 44 e 45), com `os.date("*t", ...)` no fuso do processo do Neovim; segundos descartados (`math.floor(resets_at)`, depois só hora e minuto):
  - `days` = diferença de datas de calendário: `(os.time{ year, month, day, hour = 12 }` do reset `-` o mesmo de hoje`) / 86400`, arredondado (o meio-dia evita o erro de 1 h do horário de verão).
  - `days == 0`: `HH:MM`; `1 <= days <= 6`: `<Ddd> HH:MM`; `days >= 7`: `<Mmm> <D> HH:MM`.
  - Dias e meses vêm de tabelas fixas em inglês (`M.DAYS` indexada por `wday`, 1 = `Sun`; `M.MONTHS`), nunca de `%a`/`%b` do `os.date` (que seguem o locale).
- Item: `5h <pct>% (<reset>)`, ou `5h <pct>%` sem `resets_at`; a mesma forma para `7d`. Ordem `5h`, `7d`, separados por `·` (regras 40 e 41).
- Sem região de clique (regra 42).
- Cor: o item inteiro entre `%$<grupo>$` e `%*`; separador e espaços na cor normal (regra 48). `%$` herda o fundo da `StatusLine` ou `StatusLineNC` (F16).

#### Largura (regra 58)

`M.layout(left_width, usage, width)` devolve a variante do lado direito que cabe:

| Ordem | Variante                                                                      |
| ----- | ----------------------------------------------------------------------------- |
| 1     | `5h` e `7d` com as horas                                                      |
| 2     | `5h` e `7d` sem as horas                                                      |
| 3     | só `5h` sem a hora (decisão do usuário: um item de cada vez, o `7d` primeiro) |
| 4     | nada                                                                          |

Cabe quando `left_width + M.MIN_GAP + right_width <= width`, com `M.MIN_GAP = 2` (com o lado esquerdo vazio, `right_width <= width`). Larguras por `vim.fn.strdisplaywidth` do texto plano. O lado esquerdo nunca é cortado por causa do uso; se ele sozinho passa da largura, o Neovim corta como hoje. `width` é `vim.o.columns` com `laststatus = 3` e `nvim_win_get_width(vim.g.statusline_winid)` nos outros casos. Sem nenhuma janela de uso, o lado direito fica vazio, sem separador (regra 54).

#### Texto final

`M.build(data, usage, width, now)` (puro) = itens do lado esquerdo + `%=` + variante escolhida; `%` do texto vira `%%`. Sem lado esquerdo e sem uso: `""` (regra 54 com a regra 51 da base-ui). `M.render()` lê a aba ativa (`sessions.active()`), `usage.windows(usage.now())` e a largura da janela que está sendo desenhada; a aba sem dado e a encerrada mostram o mesmo uso que as outras (regra 51). Trocar de aba não muda o lado direito.

#### Grupos (regra 49)

```lua
M.HIGHLIGHTS = { ClaudinhoUsageWarn = "DiagnosticWarn", ClaudinhoUsageError = "DiagnosticError" }
function M.setup_highlights()  -- nvim_set_hl(0, name, { link = target, default = true })
```

`default = true` nunca passa por cima de uma definição do usuário, feita antes ou depois do `setup`. Um `:colorscheme` roda `:hi clear`, que apaga grupos definidos uma vez; o `ColorScheme` do plugin religa só o padrão, então a definição do usuário feita num `ColorScheme` próprio ou depois do `:colorscheme` vale, em qualquer ordem dos autocmds. O README mostra o exemplo com `ColorScheme`.

#### Clique

```lua
M.CLICK_FUNC = "ClaudinhoStatusClick"
function M.click(minwid, clicks, button, mods) end
function M.install_click_handler() end   -- _G[M.CLICK_FUNC] = M.click
```

- `button ~= "l"`: nada (regra 2). `clicks` e `mods` não importam: cada chamada é uma ação (regra 3, F14).
- `restore = M.left_mode` (ver abaixo) é lido na hora, e a ação roda em `vim.schedule`, fora do tratamento do mouse:
  - `1`: `require("claudinho").open_with_model()` (regra 14); `2`: `tui_keys.select_effort()`; `3`: `tui_keys.mode_next()`.
  - Se a ação não abriu a escolha de modelo nem mandou o `/effort` (ela devolve `false`, ou é o `mode_next`), e `restore` é `"t"`, `vim.cmd.startinsert()` devolve o modo terminal na janela atual se ela ainda mostra um terminal; com `restore == "i"`, `nvim_feedkeys("gi", "n", false)` devolve o modo inserção (regra 8).
- `M.left_mode`: gravado pelo autocmd `ModeChanged` de `window.setup` com padrão `t:*` e `i:*` (`vim.v.event.old_mode`), e apagado num `vim.schedule` do próprio autocmd. Como o handler roda no mesmo passo de entrada que tirou o modo (F14), ele só vê o valor quando foi o próprio clique que tirou o modo. A Task 12 confirma se o clique em modo inserção tira o modo; se não tirar, o ramo `"i"` não roda e fica coberto só por teste unitário.

### 6. Janela (`ui/window.lua`)

`M.setup()` passa a:

- chamar `status.setup_highlights()` e `status.install_click_handler()` junto com os da barra de abas;
- religar os dois conjuntos de grupos no `ColorScheme`;
- criar o `ModeChanged` da seção 5 no augroup `ClaudinhoWindow`.

`usage.lua` chama `require("claudinho.ui.window").refresh()` quando o relógio tira uma janela; sem janela visível, `refresh` não desenha nada e o próximo `show` já desenha o certo. `M.teardown()` não muda (o relógio é de `usage.lua`).

### 7. Comandos e preset (`commands.lua`)

- `M.SUBCOMMANDS` ganha `select-effort` e `mode-next`, logo depois de `select-model` (regra 23); a completion lista os dois e não completa argumentos deles (regra 25).
- `handlers["select-effort"] = function() tui_keys.select_effort() end` e `handlers["mode-next"] = function() tui_keys.mode_next() end`; `opts.fargs` extras são ignorados (regra 24).
- `M.PRESET` ganha, depois de `<leader>am`:
  - `{ "<leader>ae", "n", "<cmd>Claudinho select-effort<cr>", "Claudinho: open the Claude effort selector" }`
  - `{ "<leader>ap", "n", "<cmd>Claudinho mode-next<cr>", "Claudinho: next Claude permission mode" }`

  A proteção de tecla já mapeada e o aviso (`notify.info`, `once`) são os de hoje (regra 28).

- Os subcomandos não dependem do mouse nem da statusline (regra 27).

### 8. Sugestões de prompt (`terminal.prompt_suggestions`)

Decisão do usuário (2026-11-19): por padrão as sugestões de prompt ficam como o Claude as mostra (o exemplo cinza do início e as sugestões depois das respostas, como no claudecode.nvim), e uma opção do plugin as desliga.

#### Configuração

| Chave                         | Tipo     | Padrão | Efeito                                                                                                                                                                 |
| ----------------------------- | -------- | ------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `terminal.prompt_suggestions` | booleano | `true` | `true`: o plugin não mexe em nada (valem os settings do usuário, `/config` e `CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION`). `false`: as abas do plugin iniciam sem sugestões |

- `config.defaults.terminal` passa a ter `prompt_suggestions = true`; é a primeira chave de `terminal` com padrão (o comentário dos padrões e o README mudam junto).
- `normalize_new_keys`: quando `config.terminal` é tabela, `check(config.terminal, "prompt_suggestions", "terminal.prompt_suggestions", true, is_boolean)`. Um valor que não é booleano dá `[Claudinho] terminal.prompt_suggestions = <valor> is not valid; using true.` e vale `true`. Um `terminal` que não é tabela continua com a resposta de hoje de `terminal.setup`.
- A sessão lê a chave do `config` dela ao iniciar (`session.config`): mudar a config vale para abas novas e para `tab-restart`.

Com `false`:

- `session_settings.build(progpath, relay, opts)` devolve também `promptSuggestionEnabled = false` (`opts.prompt_suggestions == false`). O `--settings` fica acima dos settings de usuário e de projeto e abaixo dos gerenciados (F3: o prompt vazio fica exato já no início).
- `session.lua` `build_env` põe `CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION = "false"` antes de `config.env`: a variável vence o `promptSuggestionEnabled` de qualquer arquivo, e um `export` no shell do usuário ligaria as sugestões de novo. Uma entrada em `config.env` passa por cima, por escolha do usuário.
- Um settings gerenciado que liga as sugestões vence o `--settings`; aí vale o que a guarda faz com as sugestões ligadas (abaixo).

Com `true`, nada entra no arquivo de settings nem no ambiente.

#### A guarda com as sugestões ligadas

Nenhum sinal separa o texto cinza do texto digitado em todos os casos (F2, F17 a F19): o texto do buffer não traz a cor; a cor das células só existe com a janela visível num split e com o prompt na tela, depende de uma API experimental e do tema do Claude, o estilo do cinza varia (cor própria no início, `dim` depois de um Ctrl-U) e texto digitado também pode ter cor (`/effort`); o cursor do terminal só é legível com a janela em modo terminal e fica no começo de um texto real depois de um Ctrl-A. A guarda é sempre a mesma, com as sugestões ligadas ou não, e vale a base mais segura, que nunca manda teclas por cima de texto real:

- Qualquer texto visível depois de `❯` + U+00A0 conta como `"text"` (regra 10: na dúvida, não vazio). O Shift+Tab não muda (não exige prompt vazio, F7).
- `select-effort`, `select-model` e os cliques no esforço e no modelo respondem `M.REPLIES.text`. Com `terminal.prompt_suggestions ~= false`, a resposta ganha a dica: `Claude <n>: clear the prompt first (gray suggestions count too)`.

Limites exatos dessa base, com as sugestões ligadas:

| Momento                                                       | Prompt                        | `/effort` e `/model`                                                                                                                 |
| ------------------------------------------------------------- | ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| Início da sessão, antes do primeiro prompt                    | Exemplo cinza `Try "..."`     | Recusados; o exemplo volta depois de apagar o que foi digitado (F2)                                                                  |
| Depois de um Ctrl-U                                           | Exemplo cinza                 | Recusados                                                                                                                            |
| Depois de uma resposta, com sugestão cinza                    | Sugestão                      | Recusados até o usuário digitar uma tecla (o Claude descarta a sugestão) e apagá-la; a Task 3 mede se a sugestão ou o exemplo voltam |
| Depois de sair de um seletor com Esc, ou sem sugestão à vista | Em branco                     | Enviados                                                                                                                             |
| `terminal.prompt_suggestions = false`                         | Sempre em branco quando vazio | Enviados sempre que vazio                                                                                                            |

Decisão do usuário (2026-11-19): o exemplo do início não ganha exceção; a primeira linha da tabela vale como está.

### 9. Contratos públicos antes e depois

| Contrato                       | Antes                                                                                                                               | Depois                                                                                                                 |
| ------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| `:Claudinho` subcomandos       | ..., `close-all-diffs`, `select-model`                                                                                              | ..., `close-all-diffs`, `select-model`, `select-effort`, `mode-next`                                                   |
| `select-model` com aba rodando | Abre a escolha e manda `/model <v>` às cegas                                                                                        | Guarda antes de abrir e de novo antes de enviar; respostas da regra 11; não abre segunda escolha                       |
| Preset                         | 20 teclas                                                                                                                           | 22 teclas (`<leader>ae`, `<leader>ap`)                                                                                 |
| Statusline da janela           | `modelo · esforço · modo`, só leitura                                                                                               | O mesmo texto, com regiões de clique, e o uso à direita                                                                |
| Grupos de destaque             | `ClaudinhoTab*`                                                                                                                     | Mais `ClaudinhoUsageWarn` (-> `DiagnosticWarn`) e `ClaudinhoUsageError` (-> `DiagnosticError`)                         |
| Global Lua                     | `_G.ClaudinhoTabClick`                                                                                                              | Mais `_G.ClaudinhoStatusClick`                                                                                         |
| Arquivo de settings da sessão  | `statusLine`, `hooks`                                                                                                               | Mais `promptSuggestionEnabled: false`, só com `terminal.prompt_suggestions = false`                                    |
| Ambiente do processo da aba    | `CLAUDE_CODE_SSE_PORT`, `ENABLE_IDE_INTEGRATION`, `FORCE_CODE_TERMINAL`, `CLAUDINHO_PORT`, `CLAUDINHO_TOKEN`, `no_proxy`/`NO_PROXY` | Mais `CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false`, antes de `config.env`, só com `terminal.prompt_suggestions = false` |
| Config                         | Sem a chave                                                                                                                         | `terminal.prompt_suggestions` (booleano, padrão `true`)                                                                |
| Rotas HTTP, relay, lock file   | -                                                                                                                                   | Sem mudança                                                                                                            |

### 10. Segurança, privacidade, observabilidade e rollout

- **Teclas na TUI:** só as três ações desta feature, só depois da guarda, e o texto do `/model` vem só de `config.models` (já validado como string não vazia). `send-text`, `send`, `add` e `tree-add` não mudam (fora do escopo).
- **Privacidade:** a tela é lida e descartada; só o modo (código ou rótulo curto) fica em `session.data`. O uso fica só em memória. Nenhum log tem texto da tela, o JSON de `rate_limits` ou o texto do prompt.
- **Observabilidade:** `logger.debug("status", ...)` com o resultado da leitura (`Claude <n>: screen mode=<m> prompt=<empty|text|none>`), o motivo de uma recusa da guarda (`busy`, `text`, `vim`) e o vencimento de uma janela de uso (`usage: five_hour reset`). Não há métrica nem alerta (plugin local).
- **Rollout:** sem flag; entra na release `0.3.0`. Reverter é reverter os commits da feature; nada fica em disco.

### 11. Telas medidas (base das fixtures)

`<nbsp>` marca U+00A0. As linhas de cima de cada tela são a conversa e o cabeçalho. O aviso `⚠ Transcript saving is off ... CLAUDE_CODE_CHILD_SESSION marker` vem do ambiente da medição (um Neovim aberto dentro de outra sessão do Claude); ele fica numa fixture como aviso de rodapé e, nas outras, sai. O travessão do texto original vira `-` nas fixtures.

```text
# start (auto), sugestões ligadas
                                                              ● high · /effort
────────────────────────────────────────────────────────────────────────────────
❯<nbsp>Try "edit init.lua to…"
────────────────────────────────────────────────────────────────────────────────
  ⚠ Transcript saving is off - inherited CLAUDE_CODE_CHILD_SESSION marker · r…

  ⏵⏵ auto mode on (shift+tab to cycle) · install gh for PR status

# start, promptSuggestionEnabled = false: a linha do prompt é só "❯<nbsp>"
# depois de Shift+Tab: as linhas de modo de F4, a mesma estrutura acima
# texto digitado:            ❯<nbsp>hello world
# texto em duas linhas:      ❯<nbsp>line one
#                              line two
# menu de / (com "/eff"):    linhas "    /figma:...", "    /code-review ..." acima de R1; ❯<nbsp>/eff
# depois de Esc num seletor: ❯<nbsp> seguido de espaços (vazio)
# eco na conversa:           ❯ /effort   (espaço comum)   e   ⎿  Cancelled
# primeiro Ctrl-C:           a última linha vira "  Press Ctrl-C again to exit"

# seletor de /effort (sem R1/R2 nem ❯<nbsp>)
▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔ ctrl+y to paste deleted text ▔
  Effort

                   Faster                             Smarter
                   ────────────────────▲─────────────────────
                   low     medium     high     xhigh      max
                ~1.5x the estimated cost of medium (the default)


  ←/→ to adjust · s to use this session only · Enter to save · Esc to cancel

# seletor de /model
▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔
  Select model
  Your pick is the default for new sessions. For other models, use --model.

  ❯ 1.  Default (recommended) ✔  Opus 5.5 · Best for everyday, complex tasks
    2.  Opus 5.5                 For complex work and everyday tasks
    ↓ 4 more

  ● High effort ←/→ to adjust

  s to use this session only · Enter to save · Esc to cancel

# aceite do modo bypass (--allow-dangerously-skip-permissions)
  ...in Bypass Permissions mode.

  https://code.claude.com/docs/en/security

  ❯ No, exit
    Yes, I accept

  Enter to confirm · Esc to cancel
```

## Alternatives considered

| Decisão                              | Escolhida                                                                                                                                            | Alternativas e por que não                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| ------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Como reconhecer o campo de prompt    | Estrutura R1, `❯` + U+00A0, R2, rodapé curto, de baixo para cima                                                                                     | Lista de textos de diálogos (`Do you want to...`): frágil e aberta (um diálogo novo passaria). Cor das células: o buffer não traz atributos (testado: `inspect_pos` e extmarks vazios), e a grade da tela só existe para a janela visível (F18). Reconhecimento positivo recusa tudo o que não conhece (regra 11)                                                                                                                                                                                                                                                                                               |
| Prompt vazio com sugestões cinza     | Sugestões ligadas por padrão (decisão do usuário); todo texto visível conta como digitado; `terminal.prompt_suggestions = false` torna o vazio exato | Desligar por padrão: recusado pelo usuário. Cor das células na grade (`screenattr`, `nvim__inspect_cell`): o cinza muda de estilo, texto digitado também tem cor, e nada se lê com a janela em float, escondida ou com o prompt fora da tela (F17, F18). Cursor do terminal: só legível em modo terminal e igual com Ctrl-A (F19). Rastrear teclas do usuário (`vim.on_key`): perde colagens, @-mentions vindos do MCP e envios do próprio plugin. Exceção textual para o exemplo `Try "..."`: recusada pelo usuário (com a janela escondida ou num float, um texto digitado nesse formato receberia as teclas) |
| Quando ler o modo                    | Em cada POST de statusline, mais três releituras quando a tela não decide                                                                            | Ler num timer: custo constante e sem gatilho. `TermRequest`: o Claude não manda OSC numa troca de modo. Ler no `on_lines` do buffer: dispara a cada redesenho da TUI (spinner), muito mais vezes que o POST                                                                                                                                                                                                                                                                                                                                                                                                     |
| Onde fica a guarda                   | Módulo próprio (`tui_keys.lua`), usado pelos comandos, pelo clique e pelo `select-model`                                                             | Dentro de `terminal.send_to_terminal`: mudaria `send-text`, `send` e `add`, fora do escopo                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| Modo vim do prompt                   | `vim.mode` do JSON da statusline (o Claude reroda a statusline ao trocar)                                                                            | Ler `-- INSERT --` no rodapé: o NORMAL pode não ter indicador e `hideVimModeIndicator` esconde o INSERT                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| Relógio do reset                     | Timer de 500 ms com relógio de parede, só enquanto há reset futuro                                                                                   | Timer de um tiro até o `resets_at`: atrasa depois de suspensão (relógio monotônico). Depender do POST que o Claude roda no reset: não vale para aba encerrada nem para o valor sem aba                                                                                                                                                                                                                                                                                                                                                                                                                          |
| Cor do uso                           | `%$Grupo$` + grupos ligados a `DiagnosticWarn`/`Error`                                                                                               | `%#Grupo#`: usa o fundo do grupo, não o da statusline. Grupos com `fg` copiado: perdem a troca automática de cor com o colorscheme                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| Restaurar o modo depois de um clique | `ModeChanged` marca o modo que saiu no mesmo passo; o handler devolve                                                                                | `vim.on_key` em toda tecla: custo em cada tecla do usuário para um caso raro                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| Fixtures de tela                     | Texto das telas reais em `tests/fixtures/tui/<versão>/`, capturadas por script                                                                       | Telas escritas à mão: não provam o reconhecimento contra a TUI real                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |

## Trade-offs

- **Formato da TUI:** o reconhecimento depende de três glifos e da estrutura do campo de prompt do 2.1.328. Uma versão que mude isso faz a guarda recusar tudo e o modo voltar a vir só dos hooks, sem nunca enviar às cegas (risco aceito pelo usuário). As fixtures ficam por versão para a próxima atualização comparar.
- **Sugestões de prompt ligadas (padrão):** o usuário mantém as sugestões cinza, e o plugin nunca manda teclas por cima de texto real; em troca, `/effort` e `/model` são recusados enquanto houver texto cinza no prompt (início da sessão, depois de um Ctrl-U, sugestão depois de uma resposta), com a dica na resposta. `terminal.prompt_suggestions = false` troca as sugestões pelo vazio exato.
- **Corrida residual (regra 12):** a checagem e o `chansend` são uma chamada Lua só, mas o Claude pode abrir um diálogo entre o último desenho e a chegada dos bytes. A janela é de um redraw da TUI; fica registrada no README.
- **`manual` por ausência:** a regra 31 conclui `manual` com o campo reconhecido e sem linha de modo. Um aviso passageiro que não está em `M.TRANSIENT` pode mostrar `manual` até o próximo POST; a lista cresce com fixtures.
- **Relógio:** 2 acordadas por segundo do Neovim enquanto há uso com reset futuro (na prática, sempre para assinantes), em troca do reset em até 1 s mesmo depois de suspensão.
- **Trava da escolha de modelo:** um seletor que não chame `on_choice` ao cancelar deixa a trava presa até reiniciar o Neovim; os seletores conhecidos cumprem o contrato.

## Testing

### Suítes

`check`, `unit`, `format` e `integration` do `CLAUDE.md` raiz, sempre; `integration` também no Neovim 0.12.0 (`on-demand`) na Task 15; `all` no fim.

### Testes novos e alterados

| Arquivo                                             | Casos                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| --------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `tests/unit/sources/tui_screen_spec.lua` (novo)     | Cada fixture de `tests/fixtures/tui/2.1.328/`: `prompt` e `mode` esperados (tabela no próprio spec). Campo vazio, com texto, com duas linhas, com espaços e U+00A0 depois de `❯`; o exemplo cinza `Try "..."` (`start_auto.txt`) e a sugestão cinza da Task 3 dão `"text"`; o modo bash (`!`) não é campo reconhecido. Eco `❯ ` e menu ` ❯` não contam como campo. Sem R1, sem R2, rodapé longo, entrada longa: não reconhecido. Linhas de modo: os cinco rótulos conhecidos, com e sem dica, com ` · ...` depois, sem símbolo (`auto mode on`), rótulo desconhecido (`⏵⏵ foo mode on` -> `foo mode`), rótulo de 33 células, rótulo com `·` ou `(`. `install gh for PR status` e avisos nunca viram modo. Ctrl-C passageiro: `nil`. Seletores e diálogos: `prompt = nil`, modo da linha das últimas 4 linhas ou `nil`. `ready`: `busy`, `text`, `ok`. `read` de buffer inválido: `nil` sem erro. `parse` de lista vazia e de linhas não string: sem erro                                                         |
| `tests/unit/sources/session_data_spec.lua`          | `rate_limits`: as duas janelas; uma só; `{}` (objeto vazio) vira `{}`; `[]`, string, número e `null` viram `nil`; `used_percentage` decimal, 0, 100, 103 entram; negativo, string, `null`, NaN e infinito tiram a janela; `resets_at` ausente, string, 0 e negativo viram `nil`; `spend_limit` e campo novo ignorados. `vim_mode`: `INSERT`, `NORMAL`, sem `vim`, `vim` de tipo errado. Os casos de hoje continuam iguais                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| `tests/unit/usage_spec.lua` (novo)                  | `update` substitui o valor inteiro e devolve `changed`; janela ausente no novo valor sai; `windows(now)` tira janela vencida (antes, no instante e depois do `resets_at`) e mantém a sem `resets_at`; relógio: arma com reset futuro, não arma sem, para quando o último vence, chama `window.refresh` só quando algo vence (timer e relógio trocados no teste); `stop` para sem apagar; o valor não muda sem `update`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| `tests/unit/ui/status_spec.lua`                     | Os casos de hoje. `items`/regiões: ids 1, 2 e 3 só para os presentes; separador fora das regiões; `%` dobrado. `percent` (23.5, 79.4, 79.5, 94.4, 94.5, 0, 103). `level` nos limites 79, 80, 94, 95, 100. `format_reset` com `TZ` fixo (`America/Sao_Paulo` e `America/New_York` na troca de horário): hoje, amanhã depois da meia-noite, 6 dias, 7 dias, segundos descartados (`09:05:59` -> `09:05`), nomes em inglês com `LC_TIME` de outro idioma. `build`: os exemplos do plano, item sem hora, item ausente sem separador sobrando, só o lado direito, os dois vazios (`""`), `%$ClaudinhoUsageWarn$`/`%*` só em volta do item, cor por item. `layout`: as quatro variantes com larguras de borda, lado esquerdo nunca cortado. `click`: botão `r`, `m` e rolagem não fazem nada; `l` com `clicks` 1 e 2 age duas vezes; minwid 1, 2 e 3 chamam a ação certa; restaura o modo terminal só quando o clique o tirou e a ação não moveu o foco. `setup_highlights` não passa por cima de um grupo já definido |
| `tests/unit/session_spec.lua`                       | POST de statusline com tela fixture (buffer falso com as linhas) grava o modo, inclusive em aba que não é a ativa; tela que não decide mantém o modo e agenda releituras (150, 400, 1000 ms com `defer_fn` trocado); um POST novo cancela as releituras antigas; a sessão `closing` ignora; hook depois da tela e tela depois do hook (vale o último); modo `nil` antes da primeira leitura decisiva; erro na leitura mantém o modo; `rate_limits` chama `usage.update` e um POST sem ele não chama; uma mudança só de uso também chama `on_change`; `vim_mode` gravado e limpo; o logger nunca recebe texto da tela (spy). com `terminal.prompt_suggestions = false`, `build_env` tem `CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false` e `config.env` passa por cima; com `true` (padrão) e sem a chave, a variável não entra; `session_settings.write` recebe a opção da config da sessão                                                                                                                          |
| `tests/unit/session_settings_spec.lua`              | `build` sem opção e com `prompt_suggestions = true` tem exatamente `statusLine` e `hooks` (como hoje); com `prompt_suggestions = false`, exatamente `statusLine`, `hooks` e `promptSuggestionEnabled = false`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| `tests/unit/config_spec.lua`                        | `terminal.prompt_suggestions`: padrão `true`; `false` aceito; `"no"`, `0` e uma tabela dão o erro `terminal.prompt_suggestions = <valor> is not valid; using true.` e valem `true`; `terminal` que não é tabela não ganha erro novo; `auto_insert` e `fix_streamed_paste` continuam lidos como vêm                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| `tests/unit/sessions_spec.lua`                      | `kill_all` e fechar todas as abas não apagam o uso; `VimLeavePre` chama `usage.stop()`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| `tests/unit/tui_keys_spec.lua` (novo)               | Sem abas: `No Claude tabs open`, nada enviado. Aba encerrada: a resposta de hoje. `vim_mode` `NORMAL`: resposta `vim`. Tela de diálogo e tela desconhecida: resposta `busy` para as três ações. Texto no prompt: `mode_next` envia `\27[Z` sem `\r`; `select_effort` e `send_model` respondem `text` (com `prompt_suggestions = false`) ou `text_suggestions` (padrão), e o exemplo cinza `Try "..."` e uma sugestão cinza contam como texto. Prompt vazio: `select_effort` envia `/effort\r`, mostra a janela com foco e entra em modo terminal mesmo com `auto_insert = false`; `send_model` envia `/model <v>\r`. `mode_next` não chama `window.show` nem muda janela, modo ou cursor. Leitura e envio na mesma chamada (spy de ordem, nenhum `schedule` entre os dois). As respostas aparecem com `notify` ligado e desligado. Canal fechado: `Cannot send text: ...`                                                                                                                                        |
| `tests/unit/init_spec.lua`                          | `open_with_model`: sem abas abre a escolha sem guarda e cria a aba com `--model`; aba encerrada responde sem abrir; aba rodando com tela `busy` ou `text` responde sem abrir; com a tela pronta abre; segunda chamada com a escolha aberta não abre outra; o `on_choice` checa de novo na aba ativa naquele momento (troca de aba no meio, texto digitado no meio); cancelar libera a trava; erro do `vim.ui.select` libera a trava                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| `tests/unit/commands_spec.lua`                      | `select-effort` e `mode-next` na lista e na completion, sem completion de argumento; argumentos extras ignorados; os handlers chamam `tui_keys`; sem abas, `No Claude tabs open` e nenhuma aba criada                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| `tests/unit/keymaps_spec.lua`                       | Preset ligado cria `<leader>ae` e `<leader>ap` com os rhs e descrições da seção 7; tecla já mapeada pelo usuário continua dele, com o aviso só com `notify`; preset desligado não cria nenhuma                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| `tests/integration/window_spec.lua`                 | `setup` instala `_G.ClaudinhoStatusClick` e os grupos de uso; grupo definido pelo usuário antes e depois do `setup` e depois de um `:colorscheme` (num `ColorScheme`) continua dele; sem definição, segue `DiagnosticWarn`/`DiagnosticError` depois do `:colorscheme`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| `tests/integration/status_click_spec.lua` (novo)    | Neovim filho (`nvim --embed --headless --clean`, dirigido por RPC, F14) com uma aba no stub de TUI: clique esquerdo em cada região com `laststatus` 2 e 3, com foco no editor (modo normal e inserção) e no terminal (modo terminal); `laststatus=3` com foco fora do Claude: nada; janela e modo do Neovim iguais depois do clique no modo; clique direito e do meio e clique no uso: nada; `mouse=`: nada; clique duplo no modo manda dois Shift+Tab                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| `tests/integration/criteria_status_spec.lua` (novo) | Com o stub de TUI e POSTs pelo `http_post`: 20 trocas de modo seguidas, cada uma refletida em menos de 1 s; modo no primeiro POST antes de qualquer prompt (e com o rodapé desenhado depois do POST, pela releitura); aba em segundo plano atualiza o próprio modo; guarda: diálogo, texto no prompt e seletor aberto recusam com a resposta certa e o log de bytes do stub fica vazio; uso de uma aba aparece na outra no redraw da troca; janela com `resets_at` daqui a 2 s sai em até 1 s depois, com a aba rodando, escondida e encerrada; janela estreita corta horas e depois itens; `laststatus=0` com os subcomandos funcionando                                                                                                                                                                                                                                                                                                                                                                        |
| `tests/bin/claude_tui.lua` (novo, apoio)            | Stub de TUI rodado com `nvim --clean -l`: põe o TTY em modo cru, desenha uma tela de fixture, grava os bytes recebidos em `CLAUDINHO_TUI_LOG` e troca de tela conforme um roteiro em `CLAUDINHO_TUI_SCRIPT` (ex.: `\27[Z` passa ao próximo modo, `/effort\r` abre o seletor, `\27` volta)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |

### Regras do plano e testes

| Regras             | Testes                                                                                             |
| ------------------ | -------------------------------------------------------------------------------------------------- |
| 1, 5, 6            | `status_spec` (regiões, texto do lado esquerdo igual ao `text` da base-ui)                         |
| 2, 3, 4            | `status_spec` (`click`), `status_click_spec`                                                       |
| 7, 8               | `status_click_spec`, `tui_keys_spec` (`mode_next` sem trocar janela nem modo)                      |
| 9, 10              | `tui_screen_spec` (fixtures de diálogo, seletores, texto), `tui_keys_spec`, `criteria_status_spec` |
| 11, 12, 13         | `tui_keys_spec`                                                                                    |
| 14, 15, 16         | `status_spec` (minwid 1), `init_spec`                                                              |
| 17, 18             | `tui_keys_spec`, `criteria_status_spec`                                                            |
| 19, 20, 21, 22     | `tui_keys_spec`, `session_spec` (o envio não mexe em `data.mode`), F7, roteiro manual              |
| 23, 24, 25, 26, 27 | `commands_spec`, `tui_keys_spec`, `criteria_status_spec` (`laststatus=0`)                          |
| 28                 | `keymaps_spec`                                                                                     |
| 29, 34, 35, 37, 38 | `session_spec`, `criteria_status_spec`                                                             |
| 30, 31, 32, 33     | `tui_screen_spec`                                                                                  |
| 36                 | `session_spec` e `tui_screen_spec` (spy do logger)                                                 |
| 39, 40, 41, 42     | `status_spec` (`build`, `click` sem região no uso)                                                 |
| 43, 46, 56         | `session_data_spec`, `status_spec` (`percent`)                                                     |
| 44, 45             | `status_spec` (`format_reset` com `TZ` e `LC_TIME`)                                                |
| 47, 48             | `status_spec` (`level`, `%$...$`)                                                                  |
| 49                 | `status_spec` (`setup_highlights`), `window_spec`                                                  |
| 50, 52, 57         | `usage_spec`, `session_spec`                                                                       |
| 51, 54             | `status_spec` (aba encerrada, aba sem dado, só o lado direito, tudo vazio), `criteria_status_spec` |
| 53                 | `usage_spec`, `criteria_status_spec`                                                               |
| 55                 | `usage_spec`, `sessions_spec`                                                                      |
| 58                 | `status_spec` (`layout`), `criteria_status_spec`                                                   |

## Implementation order

Stacks fora da lista do template, como na base-ui: `test-runner` para medição e gate, `docs-writer` para docs, `usuário` para o que nenhum agente executa. Nenhuma task faz commit até a Task 16. Nenhuma task espera decisão do usuário: as perguntas da spec foram decididas em 2026-11-19 (Open questions).

### Task 1 - Linha de base de testes e cobertura

- **Stack:** test-runner (sem código)
- **Files:** nenhum arquivo do repo (os números vão para `log.md`, escrito pelo `/implement`)
- **Depends on:** -
- **Done when:** o `log.md` registra, sobre o `HEAD` e com `BUSTED_SEED=12345 CI=true`: totais do `unit` (sucessos, falhas, erros, pendentes) e o tempo; warnings do `check`; cobertura total e por arquivo de `lua/claudinho/`; totais do `integration` no 0.12.3; `claude --version`
- **Status:** pending

### Task 2 - Fixtures de tela medidas e script de captura

- **Stack:** lua
- **Files:** `tests/fixtures/tui/2.1.328/*.txt`, `scripts/dump_tui_screen.lua`
- **Depends on:** Task 1
- **Done when:** as telas da seção 11 estão em `tests/fixtures/tui/2.1.328/` (uma por arquivo, com U+00A0 real depois de `❯`, sem travessão; nomes como `start_auto.txt`, `start_no_suggestion.txt`, `manual.txt`, `accept_edits.txt`, `plan.txt`, `typed_text.txt`, `multiline.txt`, `slash_menu.txt`, `empty_after_esc.txt`, `ctrl_c.txt`, `effort_picker.txt`, `model_picker.txt`, `bypass_accept.txt`); o comentário de cabeçalho de `scripts/dump_tui_screen.lua` (em inglês) diz de onde vêm as fixtures e como capturar uma nova (a origem de cada tela medida está na seção 11 desta spec); `scripts/dump_tui_screen.lua`, rodado com `:luafile scripts/dump_tui_screen.lua <nome>` numa sessão real do claudinho, grava as últimas 120 linhas do buffer da aba ativa em `tests/fixtures/tui/<versão do claude>/<nome>.txt` (a versão vem de `claude --version`), recusa sobrescrever um arquivo que existe e não envia nada; `check` e `format` verdes
- **Status:** pending

### Task 3 - Captura das telas que faltam

- **Stack:** usuário (com o script da Task 2, numa pasta de rascunho com git e um arquivo qualquer, sem segredos na tela)
- **Files:** `tests/fixtures/tui/**`
- **Depends on:** Task 2
- **Done when:** existem fixtures do 2.1.328 (ou da versão instalada, registrada no log) para: pedido de permissão de edição de arquivo, pedido de permissão de comando Bash, aprovação de plano, pergunta de confiança da pasta, Claude trabalhando (spinner) com o prompt vazio e com texto, `/config` aberto, `bypass permissions on` (sessão com `--permission-mode bypassPermissions`, só se o usuário aceitar o diálogo de bypass numa pasta de rascunho), prompt com `editorMode: "vim"` em INSERT e em NORMAL, o prompt com uma sugestão cinza depois de uma resposta (sugestões ligadas, o padrão) e o prompt logo depois de digitar uma tecla sobre ela e apagá-la (anotar no log se a sugestão ou o exemplo `Try "..."` voltam); o usuário revisou cada arquivo; a sessão principal conferiu a hipótese H1 (nenhum diálogo mostra R1, `❯` + U+00A0 e R2) e registrou no log; se H1 falhar, a feature para aqui e volta ao specker
- **Status:** pending

### Task 4 - Leitura da tela da TUI

- **Stack:** lua
- **Files:** `lua/claudinho/sources/tui_screen.lua`, `lua/claudinho/types.lua`, `tests/unit/sources/tui_screen_spec.lua`
- **Depends on:** Task 3
- **Done when:** a seção 1 está aplicada (no passo 3, todo texto visível depois de `❯` + U+00A0 é `"text"`, inclusive o exemplo `Try "..."`); os casos de `tui_screen_spec` passam sobre todas as fixtures de `tests/fixtures/tui/`; `parse` não lança erro com nenhuma entrada; `check`, `unit` e `format` verdes
- **Status:** pending

### Task 5 - Limites de uso e modo vim no JSON da statusline

- **Stack:** lua
- **Files:** `lua/claudinho/sources/session_data.lua`, `lua/claudinho/types.lua`, `tests/unit/sources/session_data_spec.lua`, `tests/fixtures/claude/statusline_*.json`
- **Depends on:** Task 1
- **Done when:** a seção 4 "Dado" está aplicada; fixtures novas `statusline_rate_limits_both.json`, `statusline_rate_limits_one.json`, `statusline_rate_limits_empty.json`, `statusline_rate_limits_wrong_types.json` e `statusline_vim_normal.json`; os casos de `session_data_spec` passam, os antigos sem mudança; gate verde (`check`, `unit`, `format`)
- **Status:** pending

### Task 6 - Valor único de uso e relógio de reset

- **Stack:** lua
- **Files:** `lua/claudinho/usage.lua`, `lua/claudinho/types.lua`, `tests/unit/usage_spec.lua`
- **Depends on:** Task 5
- **Done when:** a seção 4 "Estado" está aplicada; `usage_spec` passa com timer e relógio trocados no teste; nenhum dado de uso vai a log ou disco; gate verde
- **Status:** pending

### Task 7 - Statusline: regiões, uso, cores e largura

- **Stack:** lua
- **Files:** `lua/claudinho/ui/status.lua`, `tests/unit/ui/status_spec.lua`
- **Depends on:** Task 6
- **Done when:** a seção 5 está aplicada, com as quatro variantes da largura; `M.text` devolve o mesmo de hoje para os casos da base-ui; os casos de `status_spec` passam, inclusive com `TZ` e `LC_TIME` trocados; gate verde
- **Status:** pending

### Task 8 - Modo ao vivo e uso nos POSTs da sessão

- **Stack:** lua
- **Files:** `lua/claudinho/session.lua`, `lua/claudinho/session_settings.lua`, `lua/claudinho/sessions.lua`, `lua/claudinho/config.lua`, `lua/claudinho/types.lua`, `tests/unit/session_spec.lua`, `tests/unit/session_settings_spec.lua`, `tests/unit/sessions_spec.lua`, `tests/unit/config_spec.lua`, `tests/integration/session_spec.lua`, `tests/integration/relay_spec.lua`
- **Depends on:** Task 4, Task 6
- **Done when:** a seção 2 está aplicada; a seção 8 "Configuração" está aplicada (`terminal.prompt_suggestions`, padrão `true`, validação, settings e ambiente só com `false`); `kill_all` não toca no uso e `VimLeavePre` chama `usage.stop()`; os casos novos de `session_spec`, `session_settings_spec`, `sessions_spec` e `config_spec` passam; `relay_spec` e `session_spec` de integração continuam verdes com o padrão (arquivo de settings igual ao de hoje) e ganham um caso com `prompt_suggestions = false`; gate verde, incluindo `integration`
- **Status:** pending

### Task 9 - Guarda e envio de teclas; `select-model` com a guarda

- **Stack:** lua
- **Files:** `lua/claudinho/tui_keys.lua`, `lua/claudinho/init.lua`, `lua/claudinho/types.lua`, `tests/unit/tui_keys_spec.lua`, `tests/unit/init_spec.lua`
- **Depends on:** Task 8
- **Done when:** a seção 3 está aplicada, com a resposta `text_suggestions` da seção 8 quando `terminal.prompt_suggestions ~= false`; `tui_keys_spec` e os casos novos de `init_spec` passam; os textos das respostas são exatamente os de `M.REPLIES`; nenhum caso de teste manda tecla com texto (cinza ou digitado) depois de `❯`; `send-text`, `send`, `add` e `tree-add` sem mudança (os specs deles passam sem alteração); gate verde
- **Status:** pending

### Task 10 - Subcomandos `select-effort` e `mode-next` e preset

- **Stack:** lua
- **Files:** `lua/claudinho/commands.lua`, `tests/unit/commands_spec.lua`, `tests/unit/keymaps_spec.lua`
- **Depends on:** Task 9
- **Done when:** a seção 7 está aplicada; `commands_spec` e `keymaps_spec` passam; `:Claudinho select-effort` e `:Claudinho mode-next` sem abas respondem `No Claude tabs open` e não criam aba; gate verde
- **Status:** pending

### Task 11 - Janela: clique, grupos de uso, modo devolvido e redraw do reset

- **Stack:** lua
- **Files:** `lua/claudinho/ui/window.lua`, `lua/claudinho/ui/status.lua`, `tests/integration/window_spec.lua`, `tests/unit/ui/status_spec.lua`
- **Depends on:** Task 7, Task 9
- **Done when:** a seção 6 está aplicada e o `ModeChanged` da seção 5 existe; os casos novos de `window_spec` passam; `teardown` remove os autocmds novos; gate verde, incluindo `integration`
- **Status:** pending

### Task 12 - Stub de TUI e critérios de integração

- **Stack:** lua
- **Files:** `tests/bin/claude_tui.lua`, `tests/helpers/**`, `tests/integration/status_click_spec.lua`, `tests/integration/criteria_status_spec.lua`, `tests/fixtures/tui/**`
- **Depends on:** Task 10, Task 11
- **Done when:** `status_click_spec` e `criteria_status_spec` passam no 0.12.3, cada arquivo em menos de 40 s (limite do runner); o log registra se o clique em modo inserção tira o modo inserção (seção 5); um defeito de código achado aqui vira pedido de escopo registrado no log, não mudança silenciosa; gate verde, incluindo `integration`
- **Status:** pending

### Task 13 - README.md e README.en.md

- **Stack:** docs-writer
- **Files:** `README.md`, `README.en.md`
- **Depends on:** Task 12
- **Done when:** nas duas línguas, com as mesmas seções: a linha **Modo** da tabela da statusline diz que o modo vem da linha de modo do rodapé da TUI a cada atualização da statusline e dos hooks; os cliques nos três itens; o uso à direita (`5h <n>% (<reset>) · 7d <n>% (<reset>)`, a tabela de formatos da hora, os limites de 80% e 95%, `ClaudinhoUsageWarn` e `ClaudinhoUsageError` com um exemplo num `ColorScheme`, só para assinantes do claude.ai, a partir do primeiro dado da conta, e que o `statusLine` do `~/.claude/settings.json` não roda nas abas do plugin); `select-effort` e `mode-next` na tabela de comandos e `<leader>ae`/`<leader>ap` na do preset; a guarda (o que o plugin espera ver na TUI) e as três respostas; o `select-model` com a guarda; a chave `terminal.prompt_suggestions` (padrão `true`, as sugestões cinza do Claude como sempre; `false` as desliga nas abas do plugin) na seção de configuração, e na seção da guarda que, com elas ligadas, texto cinza no prompt conta como texto (a tabela de limites da seção 8) e que `false` torna o prompt vazio exato; **Limitações** sem a frase antiga sobre o modo e com: modo lido do rodapé, rótulo desconhecido como veio, formato novo do rodapé faz o status manter o último modo e a guarda recusar, a corrida residual, uso atrasado quando gasto fora do claudinho, contas diferentes em abas diferentes, `spend_limit` fora, seletor que não chama `on_choice`; sem travessão; `format` verde
- **Status:** pending

### Task 14 - CHANGELOG.md, ARCHITECTURE.md, PROTOCOL.md e CLAUDE.md

- **Stack:** docs-writer
- **Files:** `CHANGELOG.md`, `ARCHITECTURE.md`, `PROTOCOL.md`, `CLAUDE.md`
- **Depends on:** Task 12
- **Done when:** `## [Unreleased]` tem Added (cliques na statusline, `select-effort`, `mode-next`, preset, modo ao vivo, limites de uso e os dois grupos) (também `terminal.prompt_suggestions`) e Changed (`select-model` com a guarda), em inglês; `ARCHITECTURE.md` cita `sources/tui_screen.lua`, `tui_keys.lua` e `usage.lua` na seção do claudinho; `PROTOCOL.md` cita a chave que o arquivo de settings ganha e a variável que o ambiente ganha com `terminal.prompt_suggestions = false`; `CLAUDE.md` lista os três módulos novos em `## Structure`, sem mudar `## Test suites` nem `## Workflow`; sem travessão; `format` verde
- **Status:** pending

### Task 15 - Verificação final e medição

- **Stack:** test-runner (sem código), com o roteiro manual feito pelo usuário
- **Files:** nenhum arquivo do repo (resultados no `log.md`)
- **Depends on:** Task 13, Task 14
- **Done when:** `all` verde; `integration` verde no 0.12.3 e no 0.12.0 (`on-demand`), com o plenary no SHA do CI; o log tem a tabela antes/depois (testes, cobertura total e por arquivo) explicando cada diferença, e o tempo de `tui_screen.parse` sobre a maior fixture (alvo: menos de 1 ms); o usuário fez o roteiro manual e o resultado de cada passo está no log, com `claude --version`; `git status docs/backlog` sem entrada nova
- **Status:** pending

### Task 16 - Fechamento: release 0.3.0

- **Stack:** usuário (a sessão principal só roda cada comando com autorização explícita no momento)
- **Files:** `docs/features/status-interativo/plan.md`, `docs/features/status-interativo/spec.md`, `docs/features/README.md`, `VERSION`, `CHANGELOG.md`
- **Depends on:** Task 15
- **Done when:** o trabalho da feature está commitado no `main` com autorização do usuário; plano e spec em `Implemented` e o Index atualizado, também commitados; `mise run release minor --dry-run` mostra `0.3.0`; `mise run release minor` gravou `0.3.0`, fez o commit `chore(release): 0.3.0` e criou a tag local `v0.3.0`; o push fica com o usuário
- **Status:** pending

## Verification

### Suítes ao fim

`check`, `unit`, `format`, `integration` (0.12.3, e 0.12.0 sob demanda) e `all`, pelo `test-runner`.

### Comandos de critério (sessão principal, só leitura)

```sh
# A tela nunca vai para log nem disco: nenhuma escrita de arquivo nos módulos novos
rg -n "io.open|fs_open|writefile" lua/claudinho/sources/tui_screen.lua lua/claudinho/tui_keys.lua lua/claudinho/usage.lua
# Os únicos bytes que a feature manda à TUI
rg -n "send_to_terminal\(" lua/claudinho/tui_keys.lua lua/claudinho/init.lua
# Travessão nas docs e no código
rg -n "\x{2014}" README.md README.en.md CHANGELOG.md CLAUDE.md lua tests docs/features/status-interativo
```

### Roteiro manual do usuário

No Neovim 0.12.3 do mise, com o `claude` real, numa config de teste com `require("claudinho").setup({ notify = true, keymaps = { preset = true } })`. Cada resultado vai para o log da Task 15.

1. `:Claudinho`: sem nenhum prompt, a statusline mostra `<modelo> · <esforço> · <modo>` em até 1 s depois do primeiro status; à direita, o uso, se a conta já tiver dado (F13). O prompt vazio mostra o exemplo cinza do Claude, como sempre (padrão `terminal.prompt_suggestions = true`).
2. Numa aba ociosa, 20 Shift+Tab digitados na TUI: o modo da statusline acompanha cada um em até 1 s (20 de 20). Anotar o texto de cada linha de modo.
3. 5 cliques no modo e depois 5 `:Claudinho mode-next`: o mesmo ciclo dos Shift+Tab; com o foco no terminal em modo terminal, depois do clique o modo terminal continua.
4. Com `hello` digitado no prompt: clique no modo troca o modo e o texto fica; clique no esforço, `:Claudinho select-effort`, clique no modelo e `:Claudinho select-model` respondem `Claude <n>: clear the prompt first (gray suggestions count too)` e o texto fica. Com o exemplo cinza `Try "..."` à vista (início da sessão, ou depois de um Ctrl-U), a mesma resposta, e nada é digitado; depois de uma resposta com sugestão cinza, também.
5. Prompt vazio: clique no esforço abre o seletor do Claude, foca o terminal em modo terminal; escolher um nível com `s` (só a sessão) muda o esforço; anotar se a statusline muda sem outro prompt.
6. Clique no modelo abre a escolha do plugin; trocar de aba antes de escolher: o `/model` vai para a aba ativa no momento da escolha; com a escolha aberta, outro clique no modelo não abre a segunda.
7. Pedir uma edição de arquivo com o modo manual, para aparecer o pedido de permissão: clique no modo e `:Claudinho mode-next` respondem `Claude <n>: finish the open prompt in Claude first` e o pedido continua aberto e sem resposta. Repetir com a aprovação de plano (modo plan).
8. `:set laststatus=3` com o foco no Claude: os três cliques funcionam; com o foco num arquivo, a statusline global não tem o status do Claude. `:set mouse=`: clique não faz nada, os subcomandos funcionam.
9. `<leader>ae` e `<leader>ap` fazem o mesmo que os subcomandos; com `<leader>ap` já mapeado por você antes do `setup`, a sua tecla continua.
10. Duas abas: prompt na aba 2, trocar para a aba 1 (ociosa): o uso da direita é o que a aba 2 recebeu, no mesmo redraw. `:Claudinho kill-all` e `:Claudinho new`: o uso continua à vista.
11. Uso perto do limite (ou com `ClaudinhoUsageWarn` ligado a `Error` para ver a troca): cor só no item; com a janela sem foco, o fundo é o da statusline sem foco. `:hi ClaudinhoUsageWarn guifg=#ff00ff` dentro de um `ColorScheme` e `:colorscheme` de novo: a sua cor fica.
12. Janela estreita (`:vertical resize 50`, depois 40, 30): saem as horas, depois o `7d`, depois o `5h`; modelo, esforço e modo nunca são cortados pelo uso. Tema claro e escuro.
13. Deixar a statusline à vista quando a janela de 5 horas zerar (ou suspender o computador e acordar depois do reset): o item `5h` some em até 1 s, sem prompt.
14. `terminal = { prompt_suggestions = false }` e `:Claudinho new`: o prompt vazio não tem texto cinza nem no início nem depois de uma resposta; clique no esforço com o prompt vazio abre o seletor na hora. `terminal = { prompt_suggestions = "no" }`: o erro `terminal.prompt_suggestions = "no" is not valid; using true.` e as sugestões continuam.

## Open questions

Nenhuma em aberto. Decididas pelo usuário em 2026-11-19:

| #   | Pergunta                                                    | Decisão                                                                                                                         | Onde está nesta spec             |
| --- | ----------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- | -------------------------------- |
| 1   | Ordem dos itens de uso na janela estreita                   | Um de cada vez, o `7d` primeiro (variante "só `5h`")                                                                            | Seção 5, Task 7                  |
| 2   | Sugestões de prompt cinza                                   | Ligadas por padrão, como no claudecode.nvim; `terminal.prompt_suggestions = false` as desliga                                   | Seção 8, Tasks 8 e 13            |
| 3   | Exceção para o exemplo `Try "..."` com as sugestões ligadas | Sem exceção (opção A): todo texto visível depois de `❯` conta como digitado; o plugin nunca manda teclas por cima de texto real | Seção 1 passo 3, seção 8, Task 4 |

Registro das opções da pergunta 3, para consulta. Nenhum sinal separa o texto cinza do digitado em todos os casos (F2, F17 a F19).

- **A (escolhida): sem exceção.** Nunca manda teclas por cima de texto real, em nenhum caso. Limite: no começo da sessão e depois de um Ctrl-U, `/effort` e `/model` respondem `clear the prompt first (gray suggestions count too)` até o prompt ficar em branco (por exemplo depois de sair de um menu com Esc, ou depois do primeiro prompt); quem quer as duas coisas usa `terminal.prompt_suggestions = false`.
- **B (recusada): o exemplo do início conta como vazio.** O prompt inteiro numa linha só que casa com `^Try ".+"$` ou `^Try ".+…$` vale como vazio, com um veto: se a janela do Claude está visível num split com a linha do prompt na tela e as células desse texto não têm atributo nenhum (texto comum, F17), conta como digitado. Libera o começo da sessão. Limite: com a janela escondida, num float, em outra aba do Neovim ou com o prompt fora da tela, um texto que o usuário tenha digitado exatamente nesse formato (`Try "..."`, o prompt inteiro) recebe o `/effort` ou o `/model <valor>` no fim e é enviado. Usa `nvim__inspect_cell`, API experimental, no veto.
- **C (recusada): cor das células como sinal geral.** Não recomendada: o cinza muda de estilo, texto digitado também tem cor (`/effort`), e nada se lê fora de um split visível (F17, F18); pode mandar teclas por cima de texto real colorido.
