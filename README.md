English version: README.en.md

# Claudinho

Claudinho (`claudinho.nvim`) conecta o Neovim ao Claude Code por um servidor WebSocket local que fala o protocolo MCP das extensões oficiais de IDE da Anthropic. Escrito em Lua puro, sem dependências.

É um hard fork do [claudecode.nvim](https://github.com/coder/claudecode.nvim), a partir do commit [`d123707`](https://github.com/coder/claudecode.nvim/commit/d1237072eb7c55f97b2d3c44b7971546edad0238). O histórico do git recomeça aqui; a atribuição ao projeto original fica neste link e no `LICENSE`.

O Claude roda no terminal do Neovim, em uma janela única com abas: cada aba é uma sessão do `claude` com o próprio servidor e o próprio lock file. Tudo se faz com o comando `:Claudinho <subcomando>`.

## Requisitos

- Neovim >= 0.12
- A CLI `claude` ([Claude Code](https://docs.anthropic.com/en/docs/claude-code)) instalada e no `PATH`

## Instalação

Com o `vim.pack` do Neovim 0.12:

```lua
vim.pack.add({ "https://github.com/pedrohrb7/claudinho.nvim" })

require("claudinho").setup({})
```

O `setup()` não inicia nada: nenhum servidor nem lock file nasce até você abrir uma aba. Se o claudecode.nvim estiver instalado, os dois plugins rodam, mas o recomendado é removê-lo (veja [Vindo do claudecode.nvim](#vindo-do-claudecodenvim)).

Para conferir a instalação, rode `:checkhealth claudinho`.

## Uso rápido

1. `:Claudinho` abre a janela do Claude e cria a aba 1. Com a janela visível, o mesmo comando a esconde (é o `toggle`). Esconder nunca encerra a sessão.
2. `:Claudinho new` abre outra aba, `:Claudinho tab 2` vai para a aba 2 e `:Claudinho tab-close` encerra a aba ativa.
3. Em modo visual, `:Claudinho send` envia a seleção ao Claude. Em uma árvore de arquivos (netrw, nvim-tree, neo-tree, oil.nvim, mini.files), `:Claudinho tree-add` adiciona o arquivo sob o cursor. `:Claudinho add %` adiciona o buffer atual.
4. Quando o Claude propõe uma edição, o diff abre no Neovim. `:Claudinho diff-accept` aceita e `:Claudinho diff-deny` rejeita.

Nenhum atalho é criado por padrão. Há um preset opcional (veja [Atalhos](#atalhos)); para mapear só um, por exemplo o envio da seleção:

```lua
vim.keymap.set("x", "<leader>as", ":Claudinho send<cr>", { desc = "Send to Claude" })
```

Com lazy.nvim, o mesmo mapeamento fica em `keys`, com `mode = "x"`:

```lua
{ "<leader>as", ":Claudinho send<cr>", mode = "x", desc = "Send to Claude" }
```

## Comandos

`:Claudinho` sem subcomando é o mesmo que `:Claudinho toggle`. O comando completa os subcomandos, os números das abas (em `tab`, `tab-close` e `tab-restart`) e arquivos (em `add`). Um subcomando desconhecido mostra um erro com a lista dos válidos.

| Subcomando                     | O que faz                                                                                                                                                     |
| ------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `toggle`                       | Esconde a janela se ela está visível; senão a mostra. Sem abas, cria a aba 1                                                                                  |
| `open`                         | Mostra a janela e foca o terminal (já visível, só foca). Sem abas, cria a aba 1                                                                               |
| `hide`                         | Esconde a janela. A sessão continua rodando                                                                                                                   |
| `focus`                        | Mostra e foca a janela; com ela em foco, esconde. Sem abas, cria a aba 1                                                                                      |
| `new`                          | Cria uma aba nova, com o menor número livre, na pasta atual do Neovim (`:pwd`)                                                                                |
| `tab <n>`                      | Ativa a aba `n` e mostra a janela                                                                                                                             |
| `tab-next`, `tab-prev`         | Ativam a aba seguinte ou a anterior (dão a volta)                                                                                                             |
| `tab-close [n]`                | Encerra a aba `n`, ou a ativa sem número: rejeita os diffs dela, encerra o processo e remove o lock file. Não pede confirmação                                |
| `tab-restart <n>`              | Reabre o Claude numa aba encerrada, com o mesmo número e na mesma pasta, retomando a conversa (`--resume`) quando ela é conhecida. Numa aba rodando, só avisa |
| `kill-all`                     | Encerra todas as abas, rejeita todos os diffs e fecha a janela. Não pede confirmação                                                                          |
| `send`                         | Envia a seleção visual (ou os arquivos selecionados na árvore) como @-mention para a aba ativa                                                                |
| `add {arquivo} [início] [fim]` | Adiciona um arquivo (e, opcionalmente, um intervalo de linhas) ao contexto da aba ativa                                                                       |
| `tree-add`                     | Adiciona o arquivo (ou os arquivos selecionados) da árvore ao contexto                                                                                        |
| `send-text {texto}`            | Digita o texto no terminal da aba ativa e envia. `:Claudinho! send-text {texto}` ou `send-text! {texto}` só insere, sem enviar                                |
| `diff-accept`, `diff-deny`     | Aceita ou rejeita o diff da janela atual                                                                                                                      |
| `close-all-diffs`              | Fecha os diffs que o próprio Claudinho abriu, de todas as abas; os pedidos que esperam a ativação de uma aba são rejeitados                                   |
| `select-model`                 | Escolhe um modelo (lista `models`). Com uma aba rodando, envia `/model <valor>` a ela; sem abas, cria a aba 1 com `claude --model <valor>`                    |

`send`, `add` e `tree-add` sem nenhuma aba criam a aba 1 e entregam o @-mention quando ela conectar. Com a aba ativa encerrada, eles respondem `Claude <n> has exited; run :Claudinho tab-restart <n>` e não enviam nada. Os envios vão só para a aba ativa: as outras não recebem nada do editor.

## Abas, winbar e statusline

A janela do Claude mostra o terminal da aba ativa. Trocar de aba troca só o que a janela mostra: a aba que sai continua rodando, conectada ao próprio servidor.

A winbar da janela é a barra de abas, em todos os layouts: `<n> <título>` para cada aba, separadas por `│`, e um `+` no fim.

- O título é o que o Claude dá ao terminal, sem o símbolo de status do começo (`✳`, spinners). Título vazio ou genérico (`claude`, `Claude Code`, o comando configurado) vira `Claude <n>`. Passando de `window.tab_title_max` colunas, o título é cortado com `…`.
- Clicar com o botão esquerdo numa aba a ativa; clicar no `+` abre uma aba nova. Sem espaço para todas, a barra mostra a aba ativa, o `+` e as vizinhas que couberem, com `‹` e `›` para o que ficou de fora. O número e as marcas nunca são cortados.
- `● diff`: a aba tem um diff esperando ativação. Um diff pedido por uma aba em segundo plano não abre; ele abre, na ordem de chegada, quando você ativa a aba.
- `[exited]`: o processo da aba terminou. A aba continua na barra com a saída final visível, e nenhuma aba fecha sozinha. Use `:Claudinho tab-restart <n>` para reabri-la ou `:Claudinho tab-close <n>` para tirá-la.
- Grupos de destaque (só definem o padrão, então você pode sobrescrevê-los): `ClaudinhoTabActive` (liga a `TabLineSel`), `ClaudinhoTab` (`TabLine`), `ClaudinhoTabMark` (`WarningMsg`), `ClaudinhoTabExited` (`Comment`), `ClaudinhoTabNew` (`TabLine`) e `ClaudinhoTabFill` (`TabLineFill`).

A statusline da janela mostra o status da aba ativa, desenhado pelo Neovim: modelo com versão, esforço e modo, separados por `·` (por exemplo `Opus 5.5 · high · plan`). Um item sem dado fica fora; sem nenhum dado, a statusline fica vazia. A TUI do Claude não repete o status.

| Item    | De onde vem                                                                                                                                                                                                                            |
| ------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Modelo  | Nome do modelo que o Claude informa; a versão, quando falta no nome, sai do id (`claude-opus-5-5` vira `Opus 5.5`)                                                                                                                     |
| Esforço | `effort.level` informado pelo Claude (`low`, `medium`, `high`, `xhigh`, `max`), como vem                                                                                                                                               |
| Modo    | `permission_mode` do último hook da sessão: `default` e `manual` mostram `manual`; `plan`, `auto`, `accept edits` (`acceptEdits`), `don't ask` (`dontAsk`) e `bypass permissions` (`bypassPermissions`); outro valor aparece como veio |

Para obter isso, cada aba inicia com `claude --settings <arquivo>`, um arquivo temporário gerado só para ela, com a statusline e três hooks (`SessionStart`, `UserPromptSubmit` e `Stop`) que repassam os dados ao Neovim. Os hooks só observam: nunca bloqueiam nada. Seus settings de usuário e de projeto continuam valendo, e os hooks do plugin se somam aos seus; só a `statusLine` é sobreposta. O plugin nunca escreve em `~/.claude/settings.json`, em `~/.claude.json` nem em `.claude/` do projeto, e apaga o arquivo da aba quando ela fecha.

Sair do Neovim equivale a `kill-all`, sem perguntas: os diffs pendentes são rejeitados, as abas encerram e os lock files saem.

## Layouts

`window.layout` define onde fica a janela do Claude. O padrão é `right`. O layout vem só da configuração: para trocar, mude a config e reinicie o Neovim.

| Layout   | Onde fica                                                                              | Tamanho (config, padrão)               |
| -------- | -------------------------------------------------------------------------------------- | -------------------------------------- |
| `right`  | Split vertical na borda direita, na altura toda, ao lado de todos os splits do editor  | Largura, `window.right.width` = 0.30   |
| `left`   | Split vertical na borda esquerda, na altura toda, ao lado de todos os splits do editor | Largura, `window.left.width` = 0.30    |
| `bottom` | Split horizontal na borda de baixo, na largura toda                                    | Altura, `window.bottom.height` = 0.30  |
| `float`  | Janela flutuante centralizada                                                          | `window.float.width` e `height` = 0.80 |
| `tab`    | Aba do Neovim própria, com a janela ocupando a aba inteira                             | -                                      |

- Todo tamanho é uma fração em (0, 1) da largura (ou da altura) do editor. Os tamanhos de `right` e de `left` são independentes: com o layout `left` só valem os de `window.left`, com o `right` só os de `window.right`. As duas tabelas são validadas qualquer que seja o layout em uso.
- `window.right.diff_width` e `window.left.diff_width` (padrão `nil`) são a largura da janela enquanto um diff está aberto. Com `nil`, vale a largura normal. Os dois só se aplicam ao layout do mesmo lado.
- O `left` é o espelho do `right`. Com um explorer de arquivos (nvim-tree, `:Lexplore`) também na borda esquerda, a ordem das colunas segue quem abriu por último, e o diff abre na área do editor, não ao lado do explorer.
- No `float`, a janela se esconde quando um diff abre, para não cobri-lo, e volta com `toggle`, `open` ou `focus`. A borda usa `'winborder'` quando ele não está vazio, senão `"rounded"`.
- Fechar a janela com os comandos do Neovim (`:q`, `<C-w>c`) é o mesmo que esconder. `:q` na última janela do editor fecha a janela do Claude antes e o Neovim sai.
- Um valor de layout inválido cai em `"right"`, com uma mensagem de erro que lista os válidos: `right, left, bottom, float, tab`.

## Configuração

Os valores abaixo são os defaults reais (`lua/claudinho/config.lua`). Você só precisa passar o que quer mudar.

```lua
require("claudinho").setup({
  port_range = { min = 10000, max = 65535 },
  terminal_cmd = nil,        -- comando do Claude; nil usa "claude"
  env = {},                  -- variáveis de ambiente extras do terminal (strings)
  log_level = "info",        -- "trace" | "debug" | "info" | "warn" | "error"
  track_selection = true,
  focus_after_send = false,  -- foca o terminal depois de um envio aceito
  visual_demotion_delay_ms = 50,
  connection_wait_delay = 600,   -- ms de espera após a conexão antes de enviar @-mentions na fila
  connection_timeout = 10000,    -- ms para o Claude conectar antes de a fila falhar com erro

  window = {
    layout = "right",        -- "right" | "left" | "bottom" | "float" | "tab"
    right = {
      width = 0.30,          -- fração da largura do editor, em (0, 1)
      diff_width = nil,      -- nil ou fração em (0, 1): largura com um diff aberto
    },
    left = {
      width = 0.30,          -- como right.width, com o layout "left"
      diff_width = nil,      -- como right.diff_width, com o layout "left"
    },
    bottom = { height = 0.30 },
    float = { width = 0.80, height = 0.80 },
    tab_title_max = 24,      -- maior título na winbar, em colunas
  },

  keymaps = { preset = false },  -- true mapeia o preset (veja Atalhos)
  notify = false,                -- notificações informativas (erros e respostas aparecem sempre)

  diff_opts = {
    layout = "vertical",              -- "vertical" | "horizontal" | "unified"
    open_in_new_tab = false,
    keep_terminal_focus = false,      -- devolve o foco ao terminal quando o diff abre
    hide_terminal_in_new_tab = false, -- com open_in_new_tab, não mostra o terminal na nova aba
    on_new_file_reject = "keep_empty", -- "keep_empty" | "close_window"
    auto_resize_terminal = true,      -- false = você controla a largura via ClaudinhoDiffOpened/Closed
  },

  models = {
    { name = "Claude Opus (Latest)", value = "opus" },
    { name = "Claude Opus (Latest, 1M context)", value = "opus[1m]" },
    { name = "Claude Sonnet (Latest)", value = "sonnet" },
    { name = "Claude Sonnet (Latest, 1M context)", value = "sonnet[1m]" },
    { name = "Claude Haiku (Latest)", value = "haiku" },
    { name = "Default (account recommended)", value = "default" },
  },

  terminal = {
    auto_insert = true,        -- entra em modo terminal ao focar uma aba rodando
    fix_streamed_paste = "auto", -- true | false | "auto"
  },
})
```

Notas:

- Os valores novos inválidos (`window.*`, `keymaps.preset`, `notify`) não quebram o `setup()`: o valor volta ao padrão e sai uma mensagem de erro que nomeia a chave, o valor recebido e o valor usado. As chaves antigas (`port_range`, `diff_opts`, `models` e outras) continuam levantando erro no `setup()` quando inválidas.
- O Claude sempre roda no terminal do Neovim, na janela de `window.layout`. Não há outros providers de terminal.
- Uma aba nova inicia sempre na pasta atual do Neovim (`:pwd`, a da janela atual). Nenhuma opção muda isso.
- `terminal_cmd` pode ter argumentos (`"claude --verbose"`); o primeiro termo precisa ser um executável, senão a aba não é criada e sai um erro.
- `terminal.auto_insert` e `terminal.fix_streamed_paste` são as únicas chaves de `terminal`; elas são lidas como vierem, sem entrar nos defaults.
- `diff_opts.auto_resize_terminal` vale para os layouts `right` e `left`: o plugin redimensiona a janela do Claude durante o diff (usando `diff_width`, ou a largura normal) e a devolve ao fechar.
- Com `vim.g.claudinho_auto_setup = { ... }` definido antes dos arquivos `plugin/`, o Claudinho roda o `setup()` sozinho com essa tabela.

## Atalhos

Nenhum atalho é criado por padrão. Com `keymaps = { preset = true }`, o `setup()` mapeia os subcomandos com o prefixo `<leader>a`:

| Tecla                       | Modo | Comando                                          |
| --------------------------- | ---- | ------------------------------------------------ |
| `<leader>ac`                | n    | `:Claudinho toggle`                              |
| `<leader>af`                | n    | `:Claudinho focus`                               |
| `<leader>an`                | n    | `:Claudinho new`                                 |
| `<leader>al`, `<leader>ah`  | n    | `:Claudinho tab-next`, `:Claudinho tab-prev`     |
| `<leader>a1` a `<leader>a9` | n    | `:Claudinho tab 1` a `:Claudinho tab 9`          |
| `<leader>ax`                | n    | `:Claudinho tab-close`                           |
| `<leader>am`                | n    | `:Claudinho select-model`                        |
| `<leader>ab`                | n    | `:Claudinho add %` (o buffer atual)              |
| `<leader>as`                | x    | `:Claudinho send` (a seleção visual)             |
| `<leader>aa`, `<leader>ad`  | n    | `:Claudinho diff-accept`, `:Claudinho diff-deny` |

O preset nunca sobrescreve um mapeamento seu: uma tecla já mapeada fica de fora, com um aviso informativo (veja [Notificações](#notificações)).

## Notificações

O Claudinho separa três classes de mensagem:

- Erros (comando do Claude ausente, porta ou lock file que falha, subcomando ou argumento inválido, valor de config inválido) aparecem sempre.
- Respostas a um comando que não fez o pedido (`No Claude tabs open`, `Claude <n> is still running`, envio para uma aba encerrada) também aparecem sempre.
- Avisos informativos aparecem só com `notify = true`: um diff pendente numa aba em segundo plano (`Claude <n>: pending diff for <arquivo>`), `Claude <n> exited`, as chaves removidas, o claudecode.nvim instalado e as teclas do preset já mapeadas. Com `notify = false`, o estado continua visível: as marcas `● diff` e `[exited]` na barra de abas e o `:checkhealth claudinho`.

Os textos saem em inglês, como mensagens do plugin.

## Limitações

- O modo só aparece depois do primeiro prompt da sessão, e muda no prompt ou no fim de turno seguinte: o Claude não o informa à statusline.
- Com a statusline do plugin, a TUI do Claude esconde dicas do rodapé, como `esc to interrupt`.
- O status fica vazio enquanto a pasta não tem a confiança aceita no Claude, e também com `disableAllHooks` ou `allowManagedHooksOnly` nos settings. As abas funcionam do mesmo jeito, só sem o status.
- Com `laststatus=3`, a statusline da janela do Claude só aparece quando ela está em foco; com `laststatus=0`, nunca.
- Recarregar os módulos do plugin com abas abertas não é suportado: o estado em memória se perde e as abas antigas só fecham com o Neovim.
- O token de cada aba fica no ambiente do processo do Claude e dos filhos dele (`CLAUDINHO_TOKEN`), a mesma fronteira do lock file, que o seu usuário já lê.

## Conexão do CLI e o `/ide`

Cada aba tem o próprio lock file em `~/.claude/ide/`, com `ideName = "Neovim (Claudinho <n>)"`, e o processo dela já nasce conectado ao servidor da própria aba. Dentro de uma aba, o `/ide` lista só as abas do mesmo Neovim.

Um claude aberto fora do Neovim continua isolado: o plugin não muda a configuração dele nem mexe nos lock files que não criou.

- **Conexão automática.** Com `autoConnectIde` ligado nos settings do Claude, com `--ide` ou com `CLAUDE_CODE_AUTO_CONNECT_IDE=1`, um claude aberto fora do Neovim pode se conectar sozinho a uma aba, quando a pasta dela é a única, entre os lock files, que contém a pasta do claude externo. O plugin aceita esse comportamento e não tenta impedi-lo. Para evitá-lo, abra o claude externo com `CLAUDE_CODE_AUTO_CONNECT_IDE=0` ou mantenha o `autoConnectIde` desligado (o padrão do CLI). Sem essas opções, um claude externo só se conecta com um `/ide` explícito seu.
- **Sessão externa conectada.** Um claude externo conectado a uma aba, sozinho ou pelo `/ide`, passa a ser cliente dela: recebe a seleção quando a aba está ativa, os diffs seguem as regras da aba, e fechar a aba o desconecta sem encerrá-lo.
- **Dois Neovims.** Num claude aberto fora do Neovim, dois Neovims com abas de mesmo número aparecem no `/ide` com o mesmo nome, e o CLI mostra a pasta de cada um para distingui-los. Se os dois estão na mesma pasta, as linhas ficam iguais. Dentro de uma aba o caso não ocorre, pelo que está dito acima.

## Eventos

O Claudinho dispara autocmds `User`. Os dados chegam em `args.data`.

| Evento                  | Quando                                                                                                | `data`                                                                                                                                                             |
| ----------------------- | ----------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `ClaudinhoSendComplete` | Uma vez por arquivo, de forma síncrona, quando um envio é aceito com o Claude conectado (não na fila) | `file_path` (caminho absoluto; diretório termina em `/`), `start_line`, `end_line` (0-indexados, podem ser `nil`), `context`                                       |
| `ClaudinhoDiffOpened`   | Um diff abriu (sempre, mesmo com `auto_resize_terminal = false`)                                      | `tab_name`, `file_path`, `new_file_path`, `is_new_file`, `diff_window`, `target_window`, `terminal_window` (pode ser `nil`), `tab_number` (só em diff em nova aba) |
| `ClaudinhoDiffClosed`   | Um diff fechou                                                                                        | `tab_name`, `file_path`, `reason` (texto livre, não é enum estável)                                                                                                |

`context` de `ClaudinhoSendComplete` é uma etiqueta interna de log e pode mudar. Exemplo:

```lua
vim.api.nvim_create_autocmd("User", {
  pattern = "ClaudinhoSendComplete",
  callback = function(args)
    -- args.data.file_path, args.data.start_line, args.data.end_line
  end,
})
```

## Health check

`:checkhealth claudinho` confere a versão do Neovim, o `setup()`, a CLI `claude` e as abas: sem abas, uma linha informativa; por aba, a porta, o número de clientes e o lock file (com erro se o lock file sumiu), ou o código de saída de uma aba encerrada. Também mostra, como aviso, o claudecode.nvim instalado e cada chave removida que a sua config ainda tem (`Removed config key: <chave>`), mesmo com `notify = false`.

## Vindo do claudecode.nvim

### Os dois plugins rodam, mas o recomendado é remover o claudecode.nvim

O Claudinho não se desativa mais quando o claudecode.nvim está presente: os dois carregam e funcionam. Mas o Claudinho substitui o claudecode.nvim, e manter os dois só traz confusão. Remova o claudecode.nvim da sua configuração (e do `vim.pack` ou do gerenciador).

Com `notify = true`, o Claudinho avisa uma vez por sessão:

```
[Claudinho] claudecode.nvim is also installed. Both plugins run, but Claudinho replaces it: remove claudecode.nvim.
```

O `:checkhealth claudinho` sempre mostra o aviso. A detecção vale quando `vim.g.loaded_claudecode` está definida ou quando `lua/claudecode/init.lua` está no runtimepath.

Depois do recomeço do histórico do git, quem instalou uma versão anterior deve remover o plugin e instalá-lo de novo, em vez de atualizar.

### O que mudou

| Superfície                    | claudecode.nvim                                                          | Claudinho                                                                             |
| ----------------------------- | ------------------------------------------------------------------------ | ------------------------------------------------------------------------------------- |
| Módulo                        | `require("claudecode")`, `require("claudecode.<m>")`                     | `require("claudinho")`, `require("claudinho.<m>")`; o antigo não existe               |
| Loader                        | `plugin/claudecode.lua`, Neovim >= 0.8.0                                 | `plugin/claudinho.lua`, Neovim >= 0.12                                                |
| `vim.g`                       | `loaded_claudecode`, `claudecode_auto_setup`                             | `loaded_claudinho`, `claudinho_auto_setup`                                            |
| Comandos                      | `:ClaudeCode*` (17 comandos)                                             | `:Claudinho <subcomando>` (veja a tabela abaixo)                                      |
| Servidor                      | Um servidor por Neovim, iniciado no `setup()` (`auto_start`)             | Nenhum no `setup()`; um servidor por aba                                              |
| Lock file                     | `~/.claude/ide/<porta>.lock`, `ideName = "Neovim"`                       | Um por aba, `ideName = "Neovim (Claudinho <n>)"`                                      |
| Terminal                      | Providers `auto`, `native`, `snacks`, `external`, `none` e tabela        | Só o terminal do Neovim, em uma janela única com abas                                 |
| Lado e tamanho                | `terminal.split_side`, `terminal.split_width_percentage`                 | `window.layout` e os tamanhos em `window.*`                                           |
| Eventos `User`                | `ClaudeCodeSendComplete`, `ClaudeCodeDiffOpened`, `ClaudeCodeDiffClosed` | `ClaudinhoSendComplete`, `ClaudinhoDiffOpened`, `ClaudinhoDiffClosed` (mesmos `data`) |
| Highlights                    | `ClaudeCodeInlineDiff{Add,Delete,AddSign,DeleteSign}`                    | `ClaudinhoInlineDiff{...}`, mesmos defaults                                           |
| Filetype do terminal e health | `claudecode` / `:checkhealth claudecode`                                 | `claudinho` / `:checkhealth claudinho`                                                |
| Log e notificações            | `[ClaudeCode]`, `ClaudeCode ...`                                         | `[Claudinho]`, `Claudinho ...`                                                        |
| MCP `initialize`              | `serverInfo.name = "claudecode-neovim"`                                  | `"claudinho-nvim"`                                                                    |
| Header de auth, env do CLI    | `x-claude-code-ide-authorization`, `CLAUDE_CODE_SSE_PORT`                | Iguais                                                                                |

As variáveis de configuração `vim.g.claudecode_*` (por exemplo `claudecode_auto_setup`) são ignoradas, sem aviso. Use `vim.g.claudinho_*`.

### Comandos

| claudecode.nvim                           | Claudinho                                                               |
| ----------------------------------------- | ----------------------------------------------------------------------- |
| `:ClaudeCode [args]`                      | `:Claudinho toggle`                                                     |
| `:ClaudeCodeOpen`                         | `:Claudinho open`                                                       |
| `:ClaudeCodeFocus`                        | `:Claudinho focus`                                                      |
| `:ClaudeCodeClose`                        | `:Claudinho tab-close` (a aba ativa)                                    |
| `:ClaudeCodeSend`                         | `:Claudinho send`                                                       |
| `:ClaudeCodeTreeAdd`                      | `:Claudinho tree-add`                                                   |
| `:ClaudeCodeAdd {arquivo} [início] [fim]` | `:Claudinho add {arquivo} [início] [fim]`                               |
| `:ClaudeCodeSendText[!] {texto}`          | `:Claudinho send-text[!] {texto}`                                       |
| `:ClaudeCodeDiffAccept`                   | `:Claudinho diff-accept`                                                |
| `:ClaudeCodeDiffDeny`                     | `:Claudinho diff-deny`                                                  |
| `:ClaudeCodeCloseAllDiffs`                | `:Claudinho close-all-diffs`                                            |
| `:ClaudeCodeSelectModel`                  | `:Claudinho select-model`                                               |
| `:ClaudeCodeStart`, `Stop`, `Status`      | Sem substituto: o ciclo da sessão é o da aba (`new`, `tab-close`, ...)  |
| (não existia)                             | `new`, `hide`, `tab`, `tab-next`, `tab-prev`, `tab-restart`, `kill-all` |

Os `:ClaudeCode*` não existem mais. Também saíram os providers `snacks`, `external` e `none`, e o provider em forma de tabela.

### Opções removidas

O plugin ignora estas chaves e o resto da configuração funciona. O aviso nomeia a chave e o que a substitui, sai uma vez por chave e por sessão, e só aparece com `notify = true`; o `:checkhealth claudinho` sempre as lista.

| Chave                                                                                  | Use no lugar                                                                   |
| -------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| `diff_opts.vertical_split`                                                             | `diff_opts.layout`                                                             |
| `diff_opts.open_in_current_tab`                                                        | `diff_opts.open_in_new_tab` (o valor é o inverso)                              |
| `diff_opts.auto_close_on_accept`, `diff_opts.show_diff_stats`, `queue_timeout`         | Nada: já não tinham efeito                                                     |
| `terminal.provider` (qualquer valor, inclusive `"snacks"`)                             | Nada: o Claude roda sempre no terminal do Neovim, na janela de `window.layout` |
| `terminal.provider_opts`, `terminal.external_terminal_cmd`, `terminal.snacks_win_opts` | Nada: terminais externos não são mais suportados                               |
| `terminal.split_side`                                                                  | `window.layout`                                                                |
| `terminal.split_width_percentage`                                                      | `window.right.width` (ou `window.left.width`, veja abaixo)                     |
| `terminal.diff_split_width_percentage`                                                 | `window.right.diff_width` (ou `window.left.diff_width`)                        |
| `terminal.auto_close`                                                                  | Nada: nenhuma aba fecha sozinha; use `:Claudinho tab-close`                    |
| `terminal.show_native_term_exit_tip`                                                   | Nada                                                                           |
| `auto_start`, `terminal.auto_start`                                                    | Nada: o `setup()` não inicia nada; cada aba inicia o próprio servidor          |
| `terminal.cwd`, `terminal.git_repo_cwd`, `terminal.cwd_provider`                       | Nada: uma aba nova inicia na pasta atual do Neovim (`:pwd`)                    |
| `cwd`, `git_repo_cwd`, `cwd_provider` (no topo da config)                              | Nada: igual às três acima                                                      |

Quem precisava de uma pasta fixa para o Claude deve mudar a pasta do Neovim (`:cd`) antes de abrir a aba.

### Quem usava `terminal.split_side = "left"`

O padrão do claudecode.nvim era o lado direito; quem escolhia `"left"` tem agora o layout `left`. O aviso de `terminal.split_width_percentage` cita `window.right.*`, que é o caso comum: com o layout `left`, os tamanhos ficam em `window.left`.

```lua
-- antes
terminal = {
  split_side = "left",
  split_width_percentage = 0.30,
  diff_split_width_percentage = 0.45,
}

-- depois
window = {
  layout = "left",
  left = { width = 0.30, diff_width = 0.45 },
}
```
