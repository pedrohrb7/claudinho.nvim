English version: README.en.md

# Claudinho

Claudinho (`claudinho.nvim`) conecta o Neovim ao Claude Code por um servidor WebSocket local que fala o protocolo MCP das extensões oficiais de IDE da Anthropic. Escrito em Lua puro, sem dependências.

É um hard fork do [claudecode.nvim](https://github.com/coder/claudecode.nvim), a partir do commit [`d123707`](https://github.com/coder/claudecode.nvim/commit/d1237072eb7c55f97b2d3c44b7971546edad0238). O histórico do git recomeça aqui; a atribuição ao projeto original fica neste link e no `LICENSE`.

> Esta é a fase "fork limpo": o código já usa o nome Claudinho, mas os comandos continuam `:ClaudeCode*` e o terminal é um split `native`. Veja [Comandos](#comandos).

## Requisitos

- Neovim >= 0.12
- A CLI `claude` ([Claude Code](https://docs.anthropic.com/en/docs/claude-code)) instalada e no `PATH`

## Instalação

Com o `vim.pack` do Neovim 0.12:

```lua
vim.pack.add({ "https://github.com/pedrohrb7/claudinho.nvim" })

require("claudinho").setup({})
```

O Claudinho não roda junto com o claudecode.nvim. Remova o claudecode.nvim antes (veja [Vindo do claudecode.nvim](#vindo-do-claudecodenvim)).

Para conferir a instalação, rode `:checkhealth claudinho`.

## Uso rápido

1. `:ClaudeCode` abre o terminal com o Claude em um split à direita.
2. Em modo visual, `:ClaudeCodeSend` envia a seleção ao Claude. Em uma árvore de arquivos (netrw, nvim-tree, neo-tree, oil.nvim, mini.files), `:ClaudeCodeTreeAdd` adiciona o arquivo sob o cursor.
3. Quando o Claude propõe uma edição, o diff abre no Neovim. `:ClaudeCodeDiffAccept` aceita e `:ClaudeCodeDiffDeny` rejeita.

O plugin não define nenhum mapeamento. Exemplo de mapeamento para enviar a seleção visual:

```lua
vim.keymap.set("v", "<leader>as", "<cmd>ClaudeCodeSend<cr>", { desc = "Send to Claude" })
```

Com lazy.nvim, o mesmo mapeamento fica em `keys`, com `mode = "v"`:

```lua
{ "<leader>as", "<cmd>ClaudeCodeSend<cr>", mode = "v", desc = "Send to Claude" }
```

## Comandos

Os comandos mantêm o nome `:ClaudeCode*` nesta fase e viram `:Claudinho*` na próxima. O lock file, o header de autenticação e as variáveis de ambiente da CLI também não mudam.

| Comando                                   | O que faz                                                                              |
| ----------------------------------------- | -------------------------------------------------------------------------------------- |
| `:ClaudeCodeStart`                        | Inicia o servidor                                                                      |
| `:ClaudeCodeStop`                         | Para o servidor                                                                        |
| `:ClaudeCodeStatus`                       | Mostra o estado do servidor                                                            |
| `:ClaudeCode [args]`                      | Alterna o terminal do Claude (mostrar/esconder), com argumentos opcionais para a CLI   |
| `:ClaudeCodeFocus [args]`                 | Foca o terminal, ou esconde se já estiver focado                                       |
| `:ClaudeCodeOpen [args]`                  | Abre o terminal                                                                        |
| `:ClaudeCodeClose`                        | Encerra a sessão e fecha o terminal                                                    |
| `:ClaudeCodeSend`                         | Envia a seleção visual (ou os arquivos selecionados na árvore) como @-mention          |
| `:ClaudeCodeTreeAdd`                      | Adiciona o arquivo (ou os arquivos selecionados) da árvore ao contexto                 |
| `:ClaudeCodeAdd {arquivo} [início] [fim]` | Adiciona um arquivo (e, opcionalmente, um intervalo de linhas) ao contexto             |
| `:ClaudeCodeSendText[!] {texto}`          | Digita o texto no terminal aberto e envia; com `!`, só insere. Só no provider `native` |
| `:ClaudeCodeDiffAccept`                   | Aceita o diff atual                                                                    |
| `:ClaudeCodeDiffDeny`                     | Rejeita o diff atual                                                                   |
| `:ClaudeCodeCloseAllDiffs`                | Fecha os diffs que o próprio Claudinho abriu                                           |
| `:ClaudeCodeSelectModel [args]`           | Escolhe um modelo (lista `models`) e abre o terminal com ele                           |

## Configuração

Os valores abaixo são os defaults reais (`lua/claudinho/config.lua` e `lua/claudinho/terminal.lua`). Você só precisa passar o que quer mudar.

```lua
require("claudinho").setup({
  port_range = { min = 10000, max = 65535 },
  auto_start = true,
  terminal_cmd = nil,        -- comando do Claude; nil usa "claude"
  env = {},                  -- variáveis de ambiente extras do terminal (strings)
  log_level = "info",        -- "trace" | "debug" | "info" | "warn" | "error"
  track_selection = true,
  focus_after_send = false,  -- foca o terminal depois de um envio aceito
  visual_demotion_delay_ms = 50,
  connection_wait_delay = 600,   -- ms de espera após a conexão antes de enviar @-mentions na fila
  connection_timeout = 10000,    -- ms para o Claude conectar antes de a fila falhar com erro

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
    provider = "auto",                -- "auto" (= "native") | "native" | "external" | "none" | tabela
    provider_opts = {
      external_terminal_cmd = nil,    -- string com "%s" ou função; obrigatório com provider "external"
    },
    split_side = "right",
    split_width_percentage = 0.30,
    diff_split_width_percentage = nil, -- largura com um diff aberto; nil usa split_width_percentage
    show_native_term_exit_tip = true,
    auto_close = true,
    auto_insert = true,
    fix_streamed_paste = "auto",      -- true | false | "auto"
    cwd = nil,                        -- diretório fixo
    git_repo_cwd = false,             -- usa a raiz do repositório git
    cwd_provider = nil,               -- function(ctx) -> diretório
  },
})
```

Notas:

- O terminal é um split `native`. O float vem com a UI base, em uma fase futura.
- `provider = "external"` roda o Claude em outro aplicativo de terminal, por exemplo `external_terminal_cmd = "alacritty -e %s"`. Sem um comando válido, volta para `native`.
- `provider = "none"` não abre terminal: você roda o `claude` por conta própria.
- `provider` também aceita uma tabela com `setup`, `open`, `close`, `simple_toggle`, `focus_toggle`, `get_active_bufnr` e `is_available`.

## Eventos

O Claudinho dispara autocmds `User`. Os dados chegam em `args.data`.

| Evento                  | Quando                                                                                                | `data`                                                                                                                                                             |
| ----------------------- | ----------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `ClaudinhoSendComplete` | Uma vez por arquivo, de forma síncrona, quando um envio é aceito com o Claude conectado (não na fila) | `file_path` (caminho absoluto; diretório termina em `/`), `start_line`, `end_line` (0-indexados, podem ser `nil`), `context`                                       |
| `ClaudinhoDiffOpened`   | Um diff abriu (sempre, mesmo com `auto_resize_terminal = false`)                                      | `tab_name`, `file_path`, `new_file_path`, `is_new_file`, `diff_window`, `target_window`, `terminal_window` (pode ser `nil`), `tab_number` (só em diff em nova aba) |
| `ClaudinhoDiffClosed`   | Um diff fechou                                                                                        | `tab_name`, `file_path`, `reason` (texto livre, não é enum estável)                                                                                                |

`context` de `ClaudinhoSendComplete` é uma etiqueta interna de log e pode mudar. Exemplo, focando uma sessão externa depois de um envio:

```lua
vim.api.nvim_create_autocmd("User", {
  pattern = "ClaudinhoSendComplete",
  callback = function(args)
    -- args.data.file_path, args.data.start_line, args.data.end_line
  end,
})
```

## Health check

`:checkhealth claudinho` confere a versão do Neovim, a CLI `claude`, o servidor e o provider de terminal.

## Vindo do claudecode.nvim

### Os dois plugins não rodam juntos

Se o claudecode.nvim estiver carregado, o Claudinho se desativa e avisa uma vez por sessão:

```
[Claudinho] claudecode.nvim is also loaded, and the two plugins cannot run together. Claudinho is disabled; remove claudecode.nvim to use it.
```

Remova o claudecode.nvim da sua configuração (e do `vim.pack`/gerenciador) antes de instalar o Claudinho. O Claudinho trata o claudecode.nvim como presente quando `vim.g.loaded_claudecode` está definida ou quando `lua/claudecode/init.lua` está no runtimepath. Assim, qualquer claudecode.nvim instalado desativa o Claudinho com o aviso, mesmo sem `setup()` e mesmo quando o `setup()` roda no init.lua antes dos arquivos `plugin/`. A única lacuna: um claudecode.nvim adicionado ao runtimepath depois do `setup()` do Claudinho (por exemplo, carregado tarde por lazy-loading) não é detectado. `:checkhealth claudinho` reporta o conflito como erro.

Depois do recomeço do histórico do git, quem instalou uma versão anterior deve remover o plugin e instalá-lo de novo, em vez de atualizar.

### O que mudou

| Superfície                                      | claudecode.nvim                                                                                                              | Claudinho                                                                                     |
| ----------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| Módulo                                          | `require("claudecode")`, `require("claudecode.<m>")`                                                                         | `require("claudinho")`, `require("claudinho.<m>")`; o antigo não existe                       |
| Loader                                          | `plugin/claudecode.lua`, Neovim >= 0.8.0                                                                                     | `plugin/claudinho.lua`, Neovim >= 0.12                                                        |
| `vim.g`                                         | `loaded_claudecode`, `claudecode_auto_setup`                                                                                 | `loaded_claudinho`, `claudinho_auto_setup`                                                    |
| Eventos `User`                                  | `ClaudeCodeSendComplete`, `ClaudeCodeDiffOpened`, `ClaudeCodeDiffClosed`                                                     | `ClaudinhoSendComplete`, `ClaudinhoDiffOpened`, `ClaudinhoDiffClosed` (mesmos `data`)         |
| Highlights                                      | `ClaudeCodeInlineDiff{Add,Delete,AddSign,DeleteSign}`                                                                        | `ClaudinhoInlineDiff{...}`, mesmos defaults                                                   |
| Filetype do terminal / health                   | `claudecode` / `:checkhealth claudecode`                                                                                     | `claudinho` / `:checkhealth claudinho`                                                        |
| Log e notificações                              | `[ClaudeCode]`, `ClaudeCode ...`                                                                                             | `[Claudinho]`, `Claudinho ...`                                                                |
| `terminal.provider`                             | `auto`, `native`, `snacks`, `external`, `none`, tabela                                                                       | `auto` (= `native`), `native`, `external`, `none`, tabela; `"snacks"` vira `native` com aviso |
| Interface de provider                           | `hide_float?` opcional                                                                                                       | Sem `hide_float`                                                                              |
| MCP `initialize`                                | `serverInfo.name = "claudecode-neovim"`                                                                                      | `"claudinho-nvim"`                                                                            |
| Comandos, lock file, header de auth, env do CLI | `:ClaudeCode*`, `~/.claude/ide/<port>.lock`, `ideName = "Neovim"`, `x-claude-code-ide-authorization`, `CLAUDE_CODE_SSE_PORT` | Iguais                                                                                        |

As variáveis de configuração `vim.g.claudecode_*` (por exemplo `claudecode_auto_setup`) são ignoradas, sem aviso. Use `vim.g.claudinho_*`. Já `vim.g.loaded_claudecode` conta como claudecode.nvim presente.

### Opções removidas

O plugin ignora estas chaves e avisa uma vez por chave e por sessão (`[Claudinho] ...`):

| Chave                            | Aviso                                                                       |
| -------------------------------- | --------------------------------------------------------------------------- |
| `diff_opts.vertical_split`       | Removida e ignorada. Use `diff_opts.layout`.                                |
| `diff_opts.open_in_current_tab`  | Removida e ignorada. Use `diff_opts.open_in_new_tab` (o valor é o inverso). |
| `diff_opts.auto_close_on_accept` | Removida e ignorada. Já não tinha efeito.                                   |
| `diff_opts.show_diff_stats`      | Removida e ignorada. Já não tinha efeito.                                   |
| `queue_timeout`                  | Removida e ignorada. Já não tinha efeito.                                   |
| `terminal.snacks_win_opts`       | Removida e ignorada.                                                        |
| `terminal.provider = "snacks"`   | O provider snacks foi removido. Usa o terminal `native`.                    |

Os avisos saem em inglês, como mensagens do plugin.
