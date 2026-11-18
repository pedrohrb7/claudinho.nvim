# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Claudinho.nvim is a hard fork of [claudecode.nvim](https://github.com/coder/claudecode.nvim), taken at [commit d123707](https://github.com/coder/claudecode.nvim/commit/d1237072eb7c55f97b2d3c44b7971546edad0238). The upstream history is not carried over.

## [Unreleased]

## [0.2.0] - 2026-11-18

### Added

- The `left` layout: `window.layout = "left"` opens the Claude window on the left edge, over the whole height, beside every editor split. It is the mirror of `right` and has its own sizes, `window.left.width` and `window.left.diff_width` (both validated whatever layout is in use). The default layout is still `right`.
- Claude tabs: each tab is one `claude` process with its own WebSocket server, auth token, lock file and tab folder (the `:pwd` at creation). Open them with `:Claudinho new`, switch with `tab <n>`, `tab-next` and `tab-prev`, close with `tab-close`, restart an ended one with `tab-restart` and stop them all with `kill-all`. An ended tab stays until it is restarted or closed. All tabs are stopped when Neovim exits.
- The Claude window, one for the whole Neovim, in one of five layouts set by `window.layout`: `right` (default), `left`, `bottom`, `float` or `tab`. Hiding the window never stops a tab. A tab bar in the window's winbar shows the tabs with the title Claude sets, a mark for a diff that waits and `[exited]` for an ended process; a click on a tab activates it and a click on `+` opens a new one.
- The `window` config section: `layout`, `right.width`, `right.diff_width`, `left.width`, `left.diff_width`, `bottom.height`, `float.width`, `float.height` and `tab_title_max`. A wrong value falls back to the default.
- The status of the active tab in the Claude window's statusline: model, effort and permission mode, read from the settings that each session passes to `claude` (see Changed).
- The whole API is now one command, `:Claudinho <subcommand>`: `toggle` (also what `:Claudinho` does alone), `open`, `hide`, `focus`, `new`, `tab <n>`, `tab-next`, `tab-prev`, `tab-close [n]`, `tab-restart <n>`, `kill-all`, `send`, `add <file> [start] [end]`, `tree-add`, `send-text <text>`, `diff-accept`, `diff-deny`, `close-all-diffs` and `select-model`. The command has completion for the subcommands, the tab numbers and files.
- `keymaps = { preset = true }` maps the `<leader>a*` keys to the subcommands (20 keys; `<leader>as` in Visual mode). A key that is already mapped is left alone, with a notice when `notify = true`. Nothing is mapped by default.
- `notify` (default `false`): informative notices, such as the keymap and removed-key warnings, show only when it is `true`. Warnings and errors always show.

### Changed

- `send`, `add`, `tree-add` and `send-text` act on the active Claude tab. With no tab, `send`, `add` and `tree-add` start the first one and deliver when it connects; with the active tab ended, they reply `Claude <n> has exited; run :Claudinho tab-restart <n>` and send nothing.
- `:Claudinho close-all-diffs` also rejects the diffs that wait for a tab in the background. Its summaries are informative notices, shown with `notify = true`; its warnings and `No Claude diffs to close` always show.
- One server and one lock file per tab, instead of one per Neovim. The lock file's `ideName` is `Neovim (Claudinho <n>)`, so each tab shows on its own in the `/ide` list of the Claude CLI.
- Each session starts `claude` with `--settings <file>`: a private file in Neovim's temporary folder (mode 0600) with a `statusLine` and the `SessionStart`, `UserPromptSubmit` and `Stop` hooks, which report the model, effort, permission mode and session id back to the tab's server. Nothing is written to `~/.claude/` or to the project's `.claude/`.
- A diff asked by a tab that is not active waits until that tab is activated; `close-all-diffs` and exiting Neovim reject it.
- `setup()` starts no server, process or lock file: each tab starts its own. It enables the selection tracking (`track_selection`), the tab cleanup on exit and the commands.
- `:checkhealth claudinho` reports each tab (process, port, clients, lock file), says when no tab is open and when informative notifications are off. The terminal provider check is gone.
- `terminal.lua` is now a facade over the active tab (`setup`, `get_active_terminal_bufnr`, `ensure_visible`, `open`, `send_to_terminal`).
- The log context of the send commands is now `Claudinho send`, `Claudinho add` and so on (it was `ClaudeCodeSend`, `ClaudeCodeAdd`...), also in the `context` field of `User ClaudinhoSendComplete`.
- A diff reads the Claude window's size from `window.right.width` and `window.right.diff_width` (they replace `terminal.split_width_percentage` and `terminal.diff_split_width_percentage`). Only the `right` and `left` layouts are resized while a diff is open; the Claude window has a fixed width, so the other windows of the tab share the rest equally, and the diff keeps at least a third of the screen. A diff that opens in a new tab puts the Claude window to the right, to the left with `window.layout = "left"`, or below with `window.layout = "bottom"`.
- Removed config keys warn only with `notify = true` (read as given, before the config is merged), and `:checkhealth claudinho` lists each one the config still has. `terminal.provider` is a removed key with any value (`"snacks"` no longer becomes `"native"`).
- New tabs always start in Neovim's current directory (`:pwd`).
- claudecode.nvim installed next to Claudinho is now a warning, not a refusal: both plugins run, `setup()` configures everything and `:Claudinho` exists. With `notify = true`, `[Claudinho] claudecode.nvim is also installed. Both plugins run, but Claudinho replaces it: remove claudecode.nvim.` shows once per session. `:checkhealth claudinho` shows a WARN for it, with or without `setup()`. `plugin/claudinho.lua` no longer checks for it.

### Fixed

- A key typed in a Claude terminal whose process just ended no longer wipes its buffer and closes the tab, and wiping the buffer of a tab no longer raises `E937: Attempt to delete a buffer that is in use`.
- `:wqa` with running Claude tabs no longer stops with `E948: Job still running` when nothing can cancel the exit: on `ExitPre` the plugin rejects the pending diffs and stops the tab processes. With modified buffers, `:wqa` writes them and stops once with E948, with the tabs and diffs intact; run `:wqa` or `:qa` again to leave. `:qa` with modified buffers gives E37/E162 and keeps the tabs; `:qa!` leaves and ends them. Writing a diff proposal buffer while Neovim exits no longer accepts the diff.
- A cancelled exit no longer ends the tabs or rejects their diffs.
- The `--resume` session id is accepted only as a UUID and is passed to `claude` as one argument (`--resume=<id>`).
- `:Claudinho tab-restart <n>` on a tab without a session id replies `Claude <n>: no session to resume, started a new one`.
- Closing a tab answers `DIFF_REJECTED` to the diffs that wait for it.
- A split opened from the Claude window no longer inherits its tab bar, statusline and window options.
- A failed first start is reported once, and `add` and `tree-add` stop at the first file instead of repeating the error.
- Claudinho's pending diffs no longer share a global with claudecode.nvim (`_G.claudinho_deferred_responses`).

### Removed

- The `:ClaudeCode`, `:ClaudeCodeStart`, `:ClaudeCodeStop`, `:ClaudeCodeStatus`, `:ClaudeCodeSend`, `:ClaudeCodeTreeAdd`, `:ClaudeCodeAdd`, `:ClaudeCodeFocus`, `:ClaudeCodeOpen`, `:ClaudeCodeClose`, `:ClaudeCodeSendText`, `:ClaudeCodeDiffAccept`, `:ClaudeCodeDiffDeny`, `:ClaudeCodeCloseAllDiffs` and `:ClaudeCodeSelectModel` commands. Use the `:Claudinho` subcommands.
- The `native`, `external` and `none` terminal providers and custom table providers: Claude always runs in a Neovim terminal, in the Claude window. The extra arguments for `claude` in the old commands (`:ClaudeCode --resume`) are gone too.
- `require("claudinho").start()`, `.stop()`, `.default_queue()` and `.process_mention_queue()`, the `ClaudinhoShutdown` autocmd and the plugin-wide server state (`state.server`, `state.port`, `state.auth_token`).
- Config keys, each ignored and reported as removed: `terminal.provider`, `terminal.provider_opts`, `terminal.external_terminal_cmd`, `terminal.split_side` (use `window.layout`), `terminal.split_width_percentage` (use `window.right.width`), `terminal.diff_split_width_percentage` (use `window.right.diff_width`), `terminal.auto_close`, `terminal.show_native_term_exit_tip`, `auto_start` and `terminal.auto_start`.
- The working-directory options `cwd`, `git_repo_cwd`, `cwd_provider` and their `terminal.*` forms, and the `claudinho.cwd` module.

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

[Unreleased]: https://github.com/pedrohrb7/claudinho.nvim/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/pedrohrb7/claudinho.nvim/releases/tag/v0.2.0
[0.1.0]: https://github.com/pedrohrb7/claudinho.nvim/releases/tag/v0.1.0
