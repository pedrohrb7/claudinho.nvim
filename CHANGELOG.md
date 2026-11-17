# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Claudinho.nvim is a hard fork of [claudecode.nvim](https://github.com/coder/claudecode.nvim), taken at [commit d123707](https://github.com/coder/claudecode.nvim/commit/d1237072eb7c55f97b2d3c44b7971546edad0238). The upstream history is not carried over.

## [Unreleased]

### Changed

- The whole API is now one command, `:Claudinho <subcommand>`: `toggle` (also what `:Claudinho` does alone), `open`, `hide`, `focus`, `new`, `tab <n>`, `tab-next`, `tab-prev`, `tab-close [n]`, `tab-restart <n>`, `kill-all`, `send`, `add <file> [start] [end]`, `tree-add`, `send-text <text>`, `diff-accept`, `diff-deny`, `close-all-diffs` and `select-model`. The command has completion for the subcommands, the tab numbers and files.
- `send`, `add`, `tree-add` and `send-text` act on the active Claude tab. With no tab, `send`, `add` and `tree-add` start the first one and deliver when it connects; with the active tab ended, they reply `Claude <n> has exited; run :Claudinho tab-restart <n>` and send nothing.
- `:Claudinho close-all-diffs` also rejects the diffs that wait for a tab in the background. Its summaries are informative notices, shown with `notify = true`; its warnings and `No Claude diffs to close` always show.
- `setup()` starts no server, process or lock file: each tab starts its own. It enables the selection tracking (`track_selection`), the tab cleanup on exit and the commands.
- `:checkhealth claudinho` reports each tab (process, port, clients, lock file), says when no tab is open and when informative notifications are off. The terminal provider check is gone.
- `terminal.lua` is now a facade over the active tab (`setup`, `get_active_terminal_bufnr`, `ensure_visible`, `open`, `send_to_terminal`).
- The log context of the send commands is now `Claudinho send`, `Claudinho add` and so on (it was `ClaudeCodeSend`, `ClaudeCodeAdd`...), also in the `context` field of `User ClaudinhoSendComplete`.
- `keymaps = { preset = true }` maps the `<leader>a*` keys to the subcommands (20 keys; `<leader>as` in Visual mode). A key that is already mapped is left alone, with a notice when `notify = true`. Nothing is mapped by default.

### Removed

- The `:ClaudeCode`, `:ClaudeCodeStart`, `:ClaudeCodeStop`, `:ClaudeCodeStatus`, `:ClaudeCodeSend`, `:ClaudeCodeTreeAdd`, `:ClaudeCodeAdd`, `:ClaudeCodeFocus`, `:ClaudeCodeOpen`, `:ClaudeCodeClose`, `:ClaudeCodeSendText`, `:ClaudeCodeDiffAccept`, `:ClaudeCodeDiffDeny`, `:ClaudeCodeCloseAllDiffs` and `:ClaudeCodeSelectModel` commands. Use the `:Claudinho` subcommands.
- The `native`, `external` and `none` terminal providers and custom table providers: Claude always runs in a Neovim terminal, in the Claude window. The extra arguments for `claude` in the old commands (`:ClaudeCode --resume`) are gone too.
- `require("claudinho").start()`, `.stop()`, `.default_queue()` and `.process_mention_queue()`, the `ClaudinhoShutdown` autocmd and the plugin-wide server state (`state.server`, `state.port`, `state.auth_token`).

## [0.1.0] - 2026-11-15

### Changed

- Renamed the plugin to Claudinho. The Lua module is now `require("claudinho")` (and `require("claudinho.<module>")`); `require("claudecode")` no longer exists.
- Renamed the loader to `plugin/claudinho.lua` and its globals to `vim.g.loaded_claudinho` and `vim.g.claudinho_auto_setup`. The old `vim.g.claudecode_*` config variables are ignored, without a warning.
- Renamed the `User` autocmd events to `ClaudinhoSendComplete`, `ClaudinhoDiffOpened` and `ClaudinhoDiffClosed`. Their `data` fields are unchanged.
- Renamed the inline diff highlight groups to `ClaudinhoInlineDiffAdd`, `ClaudinhoInlineDiffDelete`, `ClaudinhoInlineDiffAddSign` and `ClaudinhoInlineDiffDeleteSign`, with the same defaults.
- The terminal filetype is now `claudinho`, the health check is `:checkhealth claudinho`, and log and notification prefixes are `[Claudinho]` and `Claudinho ...`.
- The `:ClaudeCode*` commands, the lock file (`~/.claude/ide/<port>.lock`), the `x-claude-code-ide-authorization` header and the `CLAUDE_CODE_SSE_PORT` variable keep their names.
- The minimum Neovim version is now 0.12.
- `terminal.provider = "auto"` now always means the `native` terminal.
- The MCP server now reports its name as `claudinho-nvim` (was `claudecode-neovim`) in `initialize`. Checked against a real `claude` CLI: `/ide` connects, tools respond and diffs open, accept and deny work.
- Removed config keys no longer break `setup()`. Each one is ignored and reported once with a `[Claudinho]` warning that says what to use instead, if anything. `terminal.provider = "snacks"` is replaced by `"native"` with a warning.
- Claudinho refuses to run when claudecode.nvim is installed or loaded (`vim.g.loaded_claudecode` is set or `lua/claudecode/init.lua` is on the runtimepath). It shows one warning, and starts no server, terminal, commands or autocmds. Remove claudecode.nvim before installing Claudinho.

### Removed

- The `snacks` terminal provider (`terminal/snacks.lua`), together with `terminal.snacks_win_opts` and the provider `hide_float` hook.
- Reading the selection from the snacks picker and snacks explorer (`snacks_picker_list`).
- `diff_opts.vertical_split`: use `diff_opts.layout`.
- `diff_opts.open_in_current_tab`: use `diff_opts.open_in_new_tab`.
- `diff_opts.auto_close_on_accept` and `diff_opts.show_diff_stats`: they had no effect.
- `queue_timeout`: it had no effect.

[Unreleased]: https://github.com/pedrohrb7/claudinho.nvim/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/pedrohrb7/claudinho.nvim/releases/tag/v0.1.0
