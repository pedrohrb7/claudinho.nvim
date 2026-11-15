# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Claudinho.nvim is a hard fork of [claudecode.nvim](https://github.com/coder/claudecode.nvim), taken at [commit d123707](https://github.com/coder/claudecode.nvim/commit/d1237072eb7c55f97b2d3c44b7971546edad0238). The upstream history is not carried over.

## [Unreleased]

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
