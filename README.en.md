Versão em português: README.md

# Claudinho

Claudinho (`claudinho.nvim`) connects Neovim to Claude Code through a local WebSocket server that speaks the MCP protocol of Anthropic's official IDE extensions. Written in pure Lua, with no dependencies.

It is a hard fork of [claudecode.nvim](https://github.com/coder/claudecode.nvim), taken from commit [`d123707`](https://github.com/coder/claudecode.nvim/commit/d1237072eb7c55f97b2d3c44b7971546edad0238). The git history restarts here; credit to the original project lives in this link and in `LICENSE`.

Claude runs in Neovim's terminal, in a single window with tabs: each tab is a `claude` session with its own server and its own lock file. Everything is done with the `:Claudinho <subcommand>` command.

## Requirements

- Neovim >= 0.12
- The `claude` CLI ([Claude Code](https://docs.anthropic.com/en/docs/claude-code)) installed and on your `PATH`

## Installation

With the `vim.pack` of Neovim 0.12:

```lua
vim.pack.add({ "https://github.com/pedrohrb7/claudinho.nvim" })

require("claudinho").setup({})
```

`setup()` starts nothing: no server and no lock file exist until you open a tab. If claudecode.nvim is installed, both plugins run, but removing it is recommended (see [Coming from claudecode.nvim](#coming-from-claudecodenvim)).

To check the install, run `:checkhealth claudinho`.

## Quick start

1. `:Claudinho` opens the Claude window and creates tab 1. With the window visible, the same command hides it (it is `toggle`). Hiding never ends the session.
2. `:Claudinho new` opens another tab, `:Claudinho tab 2` goes to tab 2 and `:Claudinho tab-close` ends the active tab.
3. In visual mode, `:Claudinho send` sends the selection to Claude. In a file tree (netrw, nvim-tree, neo-tree, oil.nvim, mini.files), `:Claudinho tree-add` adds the file under the cursor. `:Claudinho add %` adds the current buffer.
4. When Claude proposes an edit, the diff opens in Neovim. `:Claudinho diff-accept` accepts it and `:Claudinho diff-deny` rejects it.

The plugin defines no keymaps by default. There is an optional preset (see [Keymaps](#keymaps)); to map just one, for example sending the selection:

```lua
vim.keymap.set("x", "<leader>as", ":Claudinho send<cr>", { desc = "Send to Claude" })
```

With lazy.nvim, the same mapping goes in `keys`, with `mode = "x"`:

```lua
{ "<leader>as", ":Claudinho send<cr>", mode = "x", desc = "Send to Claude" }
```

## Commands

`:Claudinho` with no subcommand is the same as `:Claudinho toggle`. The command completes the subcommands, the tab numbers (for `tab`, `tab-close` and `tab-restart`) and files (for `add`). An unknown subcommand shows an error with the list of valid ones.

| Subcommand                 | What it does                                                                                                                                                             |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `toggle`                   | Hides the window if it is visible; otherwise shows it. With no tabs, creates tab 1                                                                                       |
| `open`                     | Shows the window and focuses the terminal (already visible: only focuses). With no tabs, creates tab 1                                                                   |
| `hide`                     | Hides the window. The session keeps running                                                                                                                              |
| `focus`                    | Shows and focuses the window; with it focused, hides it. With no tabs, creates tab 1                                                                                     |
| `new`                      | Creates a new tab, with the lowest free number, in Neovim's current directory (`:pwd`)                                                                                   |
| `tab <n>`                  | Activates tab `n` and shows the window                                                                                                                                   |
| `tab-next`, `tab-prev`     | Activate the next or the previous tab (they wrap around)                                                                                                                 |
| `tab-close [n]`            | Ends tab `n`, or the active one without a number: rejects its diffs, ends the process and removes the lock file. Asks no confirmation                                    |
| `tab-restart <n>`          | Reopens Claude in an ended tab, with the same number and in the same directory, resuming the conversation (`--resume`) when it is known. On a running tab, it only warns |
| `kill-all`                 | Ends every tab, rejects every diff and closes the window. Asks no confirmation                                                                                           |
| `send`                     | Sends the visual selection (or the files selected in the tree) as an @-mention to the active tab                                                                         |
| `add {file} [start] [end]` | Adds a file (and, optionally, a line range) to the context of the active tab                                                                                             |
| `tree-add`                 | Adds the file (or the selected files) of the tree to the context                                                                                                         |
| `send-text {text}`         | Types the text in the terminal of the active tab and submits it. `:Claudinho! send-text {text}` or `send-text! {text}` only inserts it, without submitting               |
| `diff-accept`, `diff-deny` | Accept or reject the diff of the current window                                                                                                                          |
| `close-all-diffs`          | Closes the diffs Claudinho itself opened, in every tab; requests waiting for a tab to be activated are rejected                                                          |
| `select-model`             | Picks a model (the `models` list). With a running tab, sends `/model <value>` to it; with no tabs, creates tab 1 with `claude --model <value>`                           |

`send`, `add` and `tree-add` with no tab create tab 1 and deliver the @-mention once it connects. With the active tab ended, they reply `Claude <n> has exited; run :Claudinho tab-restart <n>` and send nothing. Sends go to the active tab only: the other tabs receive nothing from the editor.

## Tabs, winbar and statusline

The Claude window shows the terminal of the active tab. Switching tabs only changes what the window shows: the tab that leaves keeps running, connected to its own server.

The winbar of the window is the tab bar, in every layout: `<n> <title>` for each tab, separated by `│`, and a `+` at the end.

- The title is what Claude gives the terminal, without the status symbol at the start (`✳`, spinners). An empty or generic title (`claude`, `Claude Code`, the configured command) becomes `Claude <n>`. Past `window.tab_title_max` columns, the title is cut with `…`.
- A left click on a tab activates it; a click on `+` opens a new tab. With no room for all tabs, the bar shows the active tab, the `+` and the neighbours that fit, with `‹` and `›` for what is left out. The number and the marks are never cut.
- `● diff`: the tab has a diff waiting for activation. A diff requested by a background tab does not open; it opens, in arrival order, when you activate the tab.
- `[exited]`: the process of the tab ended. The tab stays in the bar with its final output visible, and no tab closes by itself. Use `:Claudinho tab-restart <n>` to reopen it or `:Claudinho tab-close <n>` to remove it.
- Highlight groups (they only set defaults, so you can override them): `ClaudinhoTabActive` (links to `TabLineSel`), `ClaudinhoTab` (`TabLine`), `ClaudinhoTabMark` (`WarningMsg`), `ClaudinhoTabExited` (`Comment`), `ClaudinhoTabNew` (`TabLine`) and `ClaudinhoTabFill` (`TabLineFill`).

The statusline of the window shows the status of the active tab, drawn by Neovim: the model with its version, the effort and the mode, separated by `·` (for example `Opus 5.5 · high · plan`). An item with no data is left out; with no data at all, the statusline is empty. The Claude TUI does not repeat the status.

| Item   | Where it comes from                                                                                                                                                                                                                               |
| ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Model  | The model name Claude reports; the version, when missing from the name, comes from the id (`claude-opus-5-5` becomes `Opus 5.5`)                                                                                                                  |
| Effort | The `effort.level` Claude reports (`low`, `medium`, `high`, `xhigh`, `max`), as it comes                                                                                                                                                          |
| Mode   | `permission_mode` of the last hook of the session: `default` and `manual` show `manual`; `plan`, `auto`, `accept edits` (`acceptEdits`), `don't ask` (`dontAsk`) and `bypass permissions` (`bypassPermissions`); any other value shows as it came |

To get this, each tab starts with `claude --settings <file>`, a temporary file generated for it alone, with the statusline and three hooks (`SessionStart`, `UserPromptSubmit` and `Stop`) that pass the data on to Neovim. The hooks only observe: they never block anything. Your user and project settings still apply, and the plugin hooks add to yours; only `statusLine` is overridden. The plugin never writes to `~/.claude/settings.json`, to `~/.claude.json` or to the project's `.claude/`, and it deletes the tab's file when the tab closes.

Leaving Neovim is the same as `kill-all`, with no questions: pending diffs are rejected, tabs end and lock files go away.

## Layouts

`window.layout` sets where the Claude window sits. The default is `right`. The layout comes from the configuration only: to change it, change the config and restart Neovim.

| Layout   | Where it sits                                                            | Size (config, default)                   |
| -------- | ------------------------------------------------------------------------ | ---------------------------------------- |
| `right`  | Vertical split on the right edge, full height, beside every editor split | Width, `window.right.width` = 0.30       |
| `left`   | Vertical split on the left edge, full height, beside every editor split  | Width, `window.left.width` = 0.30        |
| `bottom` | Horizontal split on the bottom edge, full width                          | Height, `window.bottom.height` = 0.30    |
| `float`  | Centered floating window                                                 | `window.float.width` and `height` = 0.80 |
| `tab`    | A Neovim tab of its own, with the window filling the whole tab           | -                                        |

- Every size is a fraction in (0, 1) of the editor width (or height). The sizes of `right` and `left` are independent: with the `left` layout only those of `window.left` count, with `right` only those of `window.right`. Both tables are validated whatever layout is in use.
- `window.right.diff_width` and `window.left.diff_width` (default `nil`) are the window width while a diff is open. With `nil`, the normal width applies. Each one applies only to the layout on its own side.
- `left` is the mirror of `right`. With a file explorer (nvim-tree, `:Lexplore`) also on the left edge, the column order follows whichever opened last, and the diff opens in the editor area, not next to the explorer.
- With `float`, the window hides when a diff opens, so it does not cover it, and comes back with `toggle`, `open` or `focus`. The border uses `'winborder'` when it is not empty, otherwise `"rounded"`.
- Closing the window with Neovim commands (`:q`, `<C-w>c`) is the same as hiding it. `:q` on the last editor window closes the Claude window first and Neovim exits.
- An invalid layout value falls back to `"right"`, with an error message listing the valid ones: `right, left, bottom, float, tab`.

## Configuration

The values below are the real defaults (`lua/claudinho/config.lua`). You only need to pass what you want to change.

```lua
require("claudinho").setup({
  port_range = { min = 10000, max = 65535 },
  terminal_cmd = nil,        -- the Claude command; nil uses "claude"
  env = {},                  -- extra environment variables for the terminal (strings)
  log_level = "info",        -- "trace" | "debug" | "info" | "warn" | "error"
  track_selection = true,
  focus_after_send = false,  -- focus the terminal after an accepted send
  visual_demotion_delay_ms = 50,
  connection_wait_delay = 600,   -- ms to wait after the connection before sending queued @-mentions
  connection_timeout = 10000,    -- ms for Claude to connect before the queue fails with an error

  window = {
    layout = "right",        -- "right" | "left" | "bottom" | "float" | "tab"
    right = {
      width = 0.30,          -- fraction of the editor width, in (0, 1)
      diff_width = nil,      -- nil or a fraction in (0, 1): width while a diff is open
    },
    left = {
      width = 0.30,          -- as right.width, with the "left" layout
      diff_width = nil,      -- as right.diff_width, with the "left" layout
    },
    bottom = { height = 0.30 },
    float = { width = 0.80, height = 0.80 },
    tab_title_max = 24,      -- longest title in the winbar, in columns
  },

  keymaps = { preset = false },  -- true maps the preset (see Keymaps)
  notify = false,                -- informative notifications (errors and replies always show)

  diff_opts = {
    layout = "vertical",              -- "vertical" | "horizontal" | "unified"
    open_in_new_tab = false,
    keep_terminal_focus = false,      -- gives focus back to the terminal when the diff opens
    hide_terminal_in_new_tab = false, -- with open_in_new_tab, does not show the terminal in the new tab
    on_new_file_reject = "keep_empty", -- "keep_empty" | "close_window"
    auto_resize_terminal = true,      -- false = you control the width through ClaudinhoDiffOpened/Closed
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
    auto_insert = true,        -- enters terminal mode when focusing a running tab
    fix_streamed_paste = "auto", -- true | false | "auto"
  },
})
```

Notes:

- Invalid new values (`window.*`, `keymaps.preset`, `notify`) do not break `setup()`: the value goes back to the default and an error message names the key, the value received and the value used. The older keys (`port_range`, `diff_opts`, `models` and others) still raise an error in `setup()` when invalid.
- Claude always runs in Neovim's terminal, in the window of `window.layout`. There are no other terminal providers.
- A new tab always starts in Neovim's current directory (`:pwd`, the one of the current window). No option changes that.
- `terminal_cmd` may have arguments (`"claude --verbose"`); its first word must be an executable, otherwise the tab is not created and an error shows.
- `terminal.auto_insert` and `terminal.fix_streamed_paste` are the only keys of `terminal`; they are read as they come, without going into the defaults.
- `diff_opts.auto_resize_terminal` applies to the `right` and `left` layouts: the plugin resizes the Claude window during the diff (using `diff_width`, or the normal width) and restores it on close.
- With `vim.g.claudinho_auto_setup = { ... }` set before the `plugin/` files run, Claudinho runs `setup()` by itself with that table.

## Keymaps

No keymap is created by default. With `keymaps = { preset = true }`, `setup()` maps the subcommands with the `<leader>a` prefix:

| Key                          | Mode | Command                                          |
| ---------------------------- | ---- | ------------------------------------------------ |
| `<leader>ac`                 | n    | `:Claudinho toggle`                              |
| `<leader>af`                 | n    | `:Claudinho focus`                               |
| `<leader>an`                 | n    | `:Claudinho new`                                 |
| `<leader>al`, `<leader>ah`   | n    | `:Claudinho tab-next`, `:Claudinho tab-prev`     |
| `<leader>a1` to `<leader>a9` | n    | `:Claudinho tab 1` to `:Claudinho tab 9`         |
| `<leader>ax`                 | n    | `:Claudinho tab-close`                           |
| `<leader>am`                 | n    | `:Claudinho select-model`                        |
| `<leader>ab`                 | n    | `:Claudinho add %` (the current buffer)          |
| `<leader>as`                 | x    | `:Claudinho send` (the visual selection)         |
| `<leader>aa`, `<leader>ad`   | n    | `:Claudinho diff-accept`, `:Claudinho diff-deny` |

The preset never overrides a mapping of yours: a key that is already mapped is left out, with an informative notice (see [Notifications](#notifications)).

## Notifications

Claudinho splits its messages into three classes:

- Errors (missing Claude command, a port or lock file that fails, an invalid subcommand or argument, an invalid config value) always show.
- Replies to a command that did not do what was asked (`No Claude tabs open`, `Claude <n> is still running`, a send to an ended tab) also always show.
- Informative notices show only with `notify = true`: a pending diff on a background tab (`Claude <n>: pending diff for <file>`), `Claude <n> exited`, removed keys, an installed claudecode.nvim and preset keys that are already mapped. With `notify = false`, the state stays visible: the `● diff` and `[exited]` marks in the tab bar and `:checkhealth claudinho`.

The texts are in English, as plugin messages.

## Limitations

- The mode shows only after the first prompt of the session, and changes at the next prompt or end of turn: Claude does not report it to the statusline.
- With the plugin statusline, the Claude TUI hides footer hints such as `esc to interrupt`.
- The status stays empty while the folder has no accepted trust in Claude, and also with `disableAllHooks` or `allowManagedHooksOnly` in the settings. Tabs work the same, only without the status.
- With `laststatus=3`, the statusline of the Claude window only shows while it is focused; with `laststatus=0`, never.
- Reloading the plugin modules with open tabs is not supported: the in-memory state is lost and the old tabs only close with Neovim.
- The token of each tab sits in the environment of the Claude process and its children (`CLAUDINHO_TOKEN`), the same boundary as the lock file, which your user already reads.

## CLI connection and `/ide`

Each tab has its own lock file in `~/.claude/ide/`, with `ideName = "Neovim (Claudinho <n>)"`, and its process is born already connected to the server of its own tab. Inside a tab, `/ide` lists only the tabs of the same Neovim.

A claude opened outside Neovim stays isolated: the plugin does not change its configuration nor touch lock files it did not create.

- **Automatic connection.** With `autoConnectIde` on in the Claude settings, with `--ide`, or with `CLAUDE_CODE_AUTO_CONNECT_IDE=1`, a claude opened outside Neovim may connect by itself to a tab, when that tab's folder is the only one, among the lock files, that contains the folder of the external claude. The plugin accepts this behavior and does not try to prevent it. To avoid it, open the external claude with `CLAUDE_CODE_AUTO_CONNECT_IDE=0` or keep `autoConnectIde` off (the CLI default). Without those options, an external claude only connects through an explicit `/ide` of yours.
- **Connected external session.** An external claude connected to a tab, by itself or through `/ide`, becomes a client of that tab: it receives the selection while the tab is active, diffs follow the rules of the tab, and closing the tab disconnects it without ending it.
- **Two Neovims.** In a claude opened outside Neovim, two Neovims with tabs of the same number show up in `/ide` with the same name, and the CLI shows the folder of each to tell them apart. If both are in the same folder, the lines look the same. Inside a tab the case does not occur, as said above.

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

`:checkhealth claudinho` checks the Neovim version, `setup()`, the `claude` CLI and the tabs: with no tabs, an informative line; per tab, the port, the number of clients and the lock file (with an error if the lock file is gone), or the exit code of an ended tab. It also shows, as warnings, an installed claudecode.nvim and every removed key your config still has (`Removed config key: <key>`), even with `notify = false`.

## Coming from claudecode.nvim

### Both plugins run, but removing claudecode.nvim is recommended

Claudinho no longer disables itself when claudecode.nvim is present: both load and work. But Claudinho replaces claudecode.nvim, and keeping both only brings confusion. Remove claudecode.nvim from your config (and from `vim.pack` or your plugin manager).

With `notify = true`, Claudinho warns once per session:

```
[Claudinho] claudecode.nvim is also installed. Both plugins run, but Claudinho replaces it: remove claudecode.nvim.
```

`:checkhealth claudinho` always shows the warning. Detection applies when `vim.g.loaded_claudecode` is set or when `lua/claudecode/init.lua` is on the runtimepath.

After the git history restart, anyone who installed an earlier version should remove the plugin and install it again instead of updating.

### What changed

| Surface                      | claudecode.nvim                                                          | Claudinho                                                                           |
| ---------------------------- | ------------------------------------------------------------------------ | ----------------------------------------------------------------------------------- |
| Module                       | `require("claudecode")`, `require("claudecode.<m>")`                     | `require("claudinho")`, `require("claudinho.<m>")`; the old one does not exist      |
| Loader                       | `plugin/claudecode.lua`, Neovim >= 0.8.0                                 | `plugin/claudinho.lua`, Neovim >= 0.12                                              |
| `vim.g`                      | `loaded_claudecode`, `claudecode_auto_setup`                             | `loaded_claudinho`, `claudinho_auto_setup`                                          |
| Commands                     | `:ClaudeCode*` (17 commands)                                             | `:Claudinho <subcommand>` (see the table below)                                     |
| Server                       | One server per Neovim, started in `setup()` (`auto_start`)               | None in `setup()`; one server per tab                                               |
| Lock file                    | `~/.claude/ide/<port>.lock`, `ideName = "Neovim"`                        | One per tab, `ideName = "Neovim (Claudinho <n>)"`                                   |
| Terminal                     | Providers `auto`, `native`, `snacks`, `external`, `none` and a table     | Only Neovim's terminal, in a single window with tabs                                |
| Side and size                | `terminal.split_side`, `terminal.split_width_percentage`                 | `window.layout` and the sizes in `window.*`                                         |
| `User` events                | `ClaudeCodeSendComplete`, `ClaudeCodeDiffOpened`, `ClaudeCodeDiffClosed` | `ClaudinhoSendComplete`, `ClaudinhoDiffOpened`, `ClaudinhoDiffClosed` (same `data`) |
| Highlights                   | `ClaudeCodeInlineDiff{Add,Delete,AddSign,DeleteSign}`                    | `ClaudinhoInlineDiff{...}`, same defaults                                           |
| Terminal filetype and health | `claudecode` / `:checkhealth claudecode`                                 | `claudinho` / `:checkhealth claudinho`                                              |
| Log and notifications        | `[ClaudeCode]`, `ClaudeCode ...`                                         | `[Claudinho]`, `Claudinho ...`                                                      |
| MCP `initialize`             | `serverInfo.name = "claudecode-neovim"`                                  | `"claudinho-nvim"`                                                                  |
| Auth header, CLI env         | `x-claude-code-ide-authorization`, `CLAUDE_CODE_SSE_PORT`                | Same                                                                                |

The `vim.g.claudecode_*` config variables (for example `claudecode_auto_setup`) are ignored, without a warning. Use `vim.g.claudinho_*`.

### Commands

| claudecode.nvim                       | Claudinho                                                                    |
| ------------------------------------- | ---------------------------------------------------------------------------- |
| `:ClaudeCode [args]`                  | `:Claudinho toggle`                                                          |
| `:ClaudeCodeOpen`                     | `:Claudinho open`                                                            |
| `:ClaudeCodeFocus`                    | `:Claudinho focus`                                                           |
| `:ClaudeCodeClose`                    | `:Claudinho tab-close` (the active tab)                                      |
| `:ClaudeCodeSend`                     | `:Claudinho send`                                                            |
| `:ClaudeCodeTreeAdd`                  | `:Claudinho tree-add`                                                        |
| `:ClaudeCodeAdd {file} [start] [end]` | `:Claudinho add {file} [start] [end]`                                        |
| `:ClaudeCodeSendText[!] {text}`       | `:Claudinho send-text[!] {text}`                                             |
| `:ClaudeCodeDiffAccept`               | `:Claudinho diff-accept`                                                     |
| `:ClaudeCodeDiffDeny`                 | `:Claudinho diff-deny`                                                       |
| `:ClaudeCodeCloseAllDiffs`            | `:Claudinho close-all-diffs`                                                 |
| `:ClaudeCodeSelectModel`              | `:Claudinho select-model`                                                    |
| `:ClaudeCodeStart`, `Stop`, `Status`  | No replacement: the session lifecycle is the tab's (`new`, `tab-close`, ...) |
| (did not exist)                       | `new`, `hide`, `tab`, `tab-next`, `tab-prev`, `tab-restart`, `kill-all`      |

The `:ClaudeCode*` commands no longer exist. The `snacks`, `external` and `none` providers, and the table provider, are gone too.

### Removed options

The plugin ignores these keys and the rest of the configuration works. The warning names the key and what replaces it, shows once per key and per session, and only with `notify = true`; `:checkhealth claudinho` always lists them.

| Key                                                                                    | Use instead                                                                     |
| -------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| `diff_opts.vertical_split`                                                             | `diff_opts.layout`                                                              |
| `diff_opts.open_in_current_tab`                                                        | `diff_opts.open_in_new_tab` (the value is the inverse)                          |
| `diff_opts.auto_close_on_accept`, `diff_opts.show_diff_stats`, `queue_timeout`         | Nothing: they already had no effect                                             |
| `terminal.provider` (any value, including `"snacks"`)                                  | Nothing: Claude always runs in Neovim's terminal, in the `window.layout` window |
| `terminal.provider_opts`, `terminal.external_terminal_cmd`, `terminal.snacks_win_opts` | Nothing: external terminals are no longer supported                             |
| `terminal.split_side`                                                                  | `window.layout`                                                                 |
| `terminal.split_width_percentage`                                                      | `window.right.width` (or `window.left.width`, see below)                        |
| `terminal.diff_split_width_percentage`                                                 | `window.right.diff_width` (or `window.left.diff_width`)                         |
| `terminal.auto_close`                                                                  | Nothing: no tab closes by itself; use `:Claudinho tab-close`                    |
| `terminal.show_native_term_exit_tip`                                                   | Nothing                                                                         |
| `auto_start`, `terminal.auto_start`                                                    | Nothing: `setup()` starts nothing; each tab starts its own server               |
| `terminal.cwd`, `terminal.git_repo_cwd`, `terminal.cwd_provider`                       | Nothing: a new tab starts in Neovim's current directory (`:pwd`)                |
| `cwd`, `git_repo_cwd`, `cwd_provider` (at the top of the config)                       | Nothing: same as the three above                                                |

Anyone who needed a fixed directory for Claude should change Neovim's directory (`:cd`) before opening the tab.

### If you used `terminal.split_side = "left"`

The default in claudecode.nvim was the right side; anyone who chose `"left"` now has the `left` layout. The warning for `terminal.split_width_percentage` mentions `window.right.*`, the common case: with the `left` layout, the sizes live in `window.left`.

```lua
-- before
terminal = {
  split_side = "left",
  split_width_percentage = 0.30,
  diff_split_width_percentage = 0.45,
}

-- after
window = {
  layout = "left",
  left = { width = 0.30, diff_width = 0.45 },
}
```
