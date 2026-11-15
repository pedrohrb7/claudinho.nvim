Versão em português: README.md

# Claudinho

Claudinho (`claudinho.nvim`) connects Neovim to Claude Code through a local WebSocket server that speaks the MCP protocol of Anthropic's official IDE extensions. Written in pure Lua, with no dependencies.

It is a hard fork of [claudecode.nvim](https://github.com/coder/claudecode.nvim), taken from commit [`d123707`](https://github.com/coder/claudecode.nvim/commit/d1237072eb7c55f97b2d3c44b7971546edad0238). The git history restarts here; credit to the original project lives in this link and in `LICENSE`.

> This is the "clean fork" phase: the code already uses the Claudinho name, but the commands are still `:ClaudeCode*` and the terminal is a `native` split. See [Commands](#commands).

## Requirements

- Neovim >= 0.12
- The `claude` CLI ([Claude Code](https://docs.anthropic.com/en/docs/claude-code)) installed and on your `PATH`

## Installation

With the `vim.pack` of Neovim 0.12:

```lua
vim.pack.add({ "https://github.com/pedrohrb7/claudinho.nvim" })

require("claudinho").setup({})
```

Claudinho does not run alongside claudecode.nvim. Remove claudecode.nvim first (see [Coming from claudecode.nvim](#coming-from-claudecodenvim)).

To check the install, run `:checkhealth claudinho`.

## Quick start

1. `:ClaudeCode` opens the Claude terminal in a split on the right.
2. In visual mode, `:ClaudeCodeSend` sends the selection to Claude. In a file tree (netrw, nvim-tree, neo-tree, oil.nvim, mini.files), `:ClaudeCodeTreeAdd` adds the file under the cursor.
3. When Claude proposes an edit, the diff opens in Neovim. `:ClaudeCodeDiffAccept` accepts it and `:ClaudeCodeDiffDeny` rejects it.

The plugin defines no keymaps. Example mapping to send the visual selection:

```lua
vim.keymap.set("v", "<leader>as", "<cmd>ClaudeCodeSend<cr>", { desc = "Send to Claude" })
```

With lazy.nvim, the same mapping goes in `keys`, with `mode = "v"`:

```lua
{ "<leader>as", "<cmd>ClaudeCodeSend<cr>", mode = "v", desc = "Send to Claude" }
```

## Commands

The commands keep the `:ClaudeCode*` name in this phase and become `:Claudinho*` in the next one. The lock file, the auth header and the CLI environment variables do not change either.

| Command                               | What it does                                                                                |
| ------------------------------------- | ------------------------------------------------------------------------------------------- |
| `:ClaudeCodeStart`                    | Starts the server                                                                           |
| `:ClaudeCodeStop`                     | Stops the server                                                                            |
| `:ClaudeCodeStatus`                   | Shows the server state                                                                      |
| `:ClaudeCode [args]`                  | Toggles the Claude terminal (show/hide), with optional arguments for the CLI                |
| `:ClaudeCodeFocus [args]`             | Focuses the terminal, or hides it when already focused                                      |
| `:ClaudeCodeOpen [args]`              | Opens the terminal                                                                          |
| `:ClaudeCodeClose`                    | Ends the session and closes the terminal                                                    |
| `:ClaudeCodeSend`                     | Sends the visual selection (or the files selected in a tree) as an @-mention                |
| `:ClaudeCodeTreeAdd`                  | Adds the file (or the selected files) from the tree to the context                          |
| `:ClaudeCodeAdd {file} [start] [end]` | Adds a file (and, optionally, a line range) to the context                                  |
| `:ClaudeCodeSendText[!] {text}`       | Types the text into the open terminal and submits it; with `!`, only inserts. `native` only |
| `:ClaudeCodeDiffAccept`               | Accepts the current diff                                                                    |
| `:ClaudeCodeDiffDeny`                 | Rejects the current diff                                                                    |
| `:ClaudeCodeCloseAllDiffs`            | Closes the diffs Claudinho itself opened                                                    |
| `:ClaudeCodeSelectModel [args]`       | Picks a model (from `models`) and opens the terminal with it                                |

## Configuration

The values below are the real defaults (`lua/claudinho/config.lua` and `lua/claudinho/terminal.lua`). Pass only what you want to change.

```lua
require("claudinho").setup({
  port_range = { min = 10000, max = 65535 },
  auto_start = true,
  terminal_cmd = nil,        -- Claude command; nil uses "claude"
  env = {},                  -- extra environment variables for the terminal (strings)
  log_level = "info",        -- "trace" | "debug" | "info" | "warn" | "error"
  track_selection = true,
  focus_after_send = false,  -- focus the terminal after an accepted send
  visual_demotion_delay_ms = 50,
  connection_wait_delay = 600,   -- ms to wait after connecting before sending queued @-mentions
  connection_timeout = 10000,    -- ms Claude has to connect before the queue fails with an error

  diff_opts = {
    layout = "vertical",              -- "vertical" | "horizontal" | "unified"
    open_in_new_tab = false,
    keep_terminal_focus = false,      -- give focus back to the terminal when the diff opens
    hide_terminal_in_new_tab = false, -- with open_in_new_tab, do not show the terminal in the new tab
    on_new_file_reject = "keep_empty", -- "keep_empty" | "close_window"
    auto_resize_terminal = true,      -- false = you own the width via ClaudinhoDiffOpened/Closed
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
    provider = "auto",                -- "auto" (= "native") | "native" | "external" | "none" | table
    provider_opts = {
      external_terminal_cmd = nil,    -- string with "%s" or a function; required with provider "external"
    },
    split_side = "right",
    split_width_percentage = 0.30,
    diff_split_width_percentage = nil, -- width while a diff is open; nil uses split_width_percentage
    show_native_term_exit_tip = true,
    auto_close = true,
    auto_insert = true,
    fix_streamed_paste = "auto",      -- true | false | "auto"
    cwd = nil,                        -- fixed directory
    git_repo_cwd = false,             -- use the git repository root
    cwd_provider = nil,               -- function(ctx) -> directory
  },
})
```

Notes:

- The terminal is a `native` split. The float arrives with the base UI, in a later phase.
- `provider = "external"` runs Claude in another terminal application, for example `external_terminal_cmd = "alacritty -e %s"`. Without a valid command it falls back to `native`.
- `provider = "none"` opens no terminal: you run `claude` yourself.
- `provider` also accepts a table with `setup`, `open`, `close`, `simple_toggle`, `focus_toggle`, `get_active_bufnr` and `is_available`.

## Events

Claudinho fires `User` autocmds. The data arrives in `args.data`.

| Event                   | When                                                                                              | `data`                                                                                                                                                           |
| ----------------------- | ------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ClaudinhoSendComplete` | Once per file, synchronously, when a send is accepted while Claude is connected (not when queued) | `file_path` (absolute path; a directory ends in `/`), `start_line`, `end_line` (0-indexed, may be `nil`), `context`                                              |
| `ClaudinhoDiffOpened`   | A diff opened (always, even with `auto_resize_terminal = false`)                                  | `tab_name`, `file_path`, `new_file_path`, `is_new_file`, `diff_window`, `target_window`, `terminal_window` (may be `nil`), `tab_number` (only for new-tab diffs) |
| `ClaudinhoDiffClosed`   | A diff closed                                                                                     | `tab_name`, `file_path`, `reason` (free text, not a stable enum)                                                                                                 |

The `context` field of `ClaudinhoSendComplete` is an internal log tag and may change. Example:

```lua
vim.api.nvim_create_autocmd("User", {
  pattern = "ClaudinhoSendComplete",
  callback = function(args)
    -- args.data.file_path, args.data.start_line, args.data.end_line
  end,
})
```

## Health check

`:checkhealth claudinho` checks the Neovim version, the `claude` CLI, the server and the terminal provider.

## Coming from claudecode.nvim

### The two plugins do not run together

If claudecode.nvim is loaded, Claudinho disables itself and warns once per session:

```
[Claudinho] claudecode.nvim is also loaded, and the two plugins cannot run together. Claudinho is disabled; remove claudecode.nvim to use it.
```

Remove claudecode.nvim from your config (and from `vim.pack` or your plugin manager) before installing Claudinho. Claudinho treats claudecode.nvim as present when `vim.g.loaded_claudecode` is set or `lua/claudecode/init.lua` is on the runtimepath. So any installed claudecode.nvim disables Claudinho with the warning, even if its `setup()` is never called, and also when `setup()` runs from init.lua before the `plugin/` files load. The one remaining gap: a claudecode.nvim added to the runtimepath after Claudinho's setup (for example lazy-loaded later) is not detected. `:checkhealth claudinho` reports the conflict as an error.

After the git history restart, anyone who installed an earlier version should remove the plugin and install it again instead of updating.

### What changed

| Surface                                   | claudecode.nvim                                                                                                              | Claudinho                                                                                            |
| ----------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| Module                                    | `require("claudecode")`, `require("claudecode.<m>")`                                                                         | `require("claudinho")`, `require("claudinho.<m>")`; the old one does not exist                       |
| Loader                                    | `plugin/claudecode.lua`, Neovim >= 0.8.0                                                                                     | `plugin/claudinho.lua`, Neovim >= 0.12                                                               |
| `vim.g`                                   | `loaded_claudecode`, `claudecode_auto_setup`                                                                                 | `loaded_claudinho`, `claudinho_auto_setup`                                                           |
| `User` events                             | `ClaudeCodeSendComplete`, `ClaudeCodeDiffOpened`, `ClaudeCodeDiffClosed`                                                     | `ClaudinhoSendComplete`, `ClaudinhoDiffOpened`, `ClaudinhoDiffClosed` (same `data`)                  |
| Highlights                                | `ClaudeCodeInlineDiff{Add,Delete,AddSign,DeleteSign}`                                                                        | `ClaudinhoInlineDiff{...}`, same defaults                                                            |
| Terminal filetype / health                | `claudecode` / `:checkhealth claudecode`                                                                                     | `claudinho` / `:checkhealth claudinho`                                                               |
| Log and notifications                     | `[ClaudeCode]`, `ClaudeCode ...`                                                                                             | `[Claudinho]`, `Claudinho ...`                                                                       |
| `terminal.provider`                       | `auto`, `native`, `snacks`, `external`, `none`, table                                                                        | `auto` (= `native`), `native`, `external`, `none`, table; `"snacks"` becomes `native` with a warning |
| Provider interface                        | optional `hide_float?`                                                                                                       | No `hide_float`                                                                                      |
| MCP `initialize`                          | `serverInfo.name = "claudecode-neovim"`                                                                                      | `"claudinho-nvim"`                                                                                   |
| Commands, lock file, auth header, CLI env | `:ClaudeCode*`, `~/.claude/ide/<port>.lock`, `ideName = "Neovim"`, `x-claude-code-ide-authorization`, `CLAUDE_CODE_SSE_PORT` | Same                                                                                                 |

The `vim.g.claudecode_*` config variables (for example `claudecode_auto_setup`) are ignored, without a warning. Use `vim.g.claudinho_*`. `vim.g.loaded_claudecode`, however, counts as claudecode.nvim being present.

### Removed options

The plugin ignores these keys and warns once per key and per session (`[Claudinho] ...`):

| Key                              | Warning                                                                 |
| -------------------------------- | ----------------------------------------------------------------------- |
| `diff_opts.vertical_split`       | Removed and ignored. Use `diff_opts.layout` instead.                    |
| `diff_opts.open_in_current_tab`  | Removed and ignored. Use `diff_opts.open_in_new_tab` instead (inverse). |
| `diff_opts.auto_close_on_accept` | Removed and ignored. It had no effect.                                  |
| `diff_opts.show_diff_stats`      | Removed and ignored. It had no effect.                                  |
| `queue_timeout`                  | Removed and ignored. It had no effect.                                  |
| `terminal.snacks_win_opts`       | Removed and ignored.                                                    |
| `terminal.provider = "snacks"`   | The snacks provider was removed. Using the native terminal.             |
