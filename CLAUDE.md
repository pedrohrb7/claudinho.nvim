# CLAUDE.md

Context for Claude Code when working in this repository.

## Vision

claudinho.nvim is a clean fork of claudecode.nvim: a pure Lua Neovim plugin, with no dependencies, that speaks the same WebSocket MCP protocol as Anthropic's official IDE extensions. Claude Code CLI finds Neovim through a lock file in `~/.claude/ide/`, then calls the plugin's tools (open files, diffs, selections, diagnostics). Each Neovim tab runs its own Claude session (its own server, lock file and `claude` process), shown in a Claude window with a tab bar, status line and the layouts (`right`, `left`, `bottom`, `float`, `tab`).

- Requires Neovim >= 0.12.
- claudecode.nvim installed alongside is only a warning: both plugins run (`conflict.lua`; the warning shows once per session and only with `notify = true`), and removing claudecode.nvim is recommended.
- The MCP server name is `claudinho-nvim`. There is one command, `:Claudinho <subcommand>`; the `:ClaudeCode*` commands and the terminal providers are gone.
- `docs/PRD.md` has the product decisions; `PROTOCOL.md` and `ARCHITECTURE.md` describe the protocol and the design.

## Commands

The toolchain comes from [mise](https://mise.jdx.dev) (`mise.toml`). `mise run <task>` works without activating mise in the shell.

- `mise install` - install Neovim, LuaJIT, formatters and the other tools
- `mise run setup` - build the busted, luacheck and luacov rocks into `./.luarocks`
- `mise run check` - syntax check plus luacheck (0 warnings)
- `mise run test` - busted with coverage, shuffled order (`BUSTED_SEED=<n>` fixes the order)
- `mise run format` - treefmt over the whole tree
- `mise run format-check` - treefmt without writing (CI)
- `mise run all` - format, check and test; run it before every commit
- `mise run release <major|minor|patch> [--dry-run]` - bump `VERSION` and `CHANGELOG.md`, commit and tag; never pushes

## Structure

- `plugin/claudinho.lua` - loader: version check, load guard, optional auto setup (`vim.g.claudinho_auto_setup`)
- `lua/claudinho/` - the plugin; modules derived from claudecode.nvim start with an `-- Origin:` line
  - `init.lua`, `config.lua`, `conflict.lua`, `health.lua`, `notify.lua`
  - `commands.lua` - the `:Claudinho` command, its completion and the optional key preset
  - `sessions.lua` - registry of the per-tab sessions, active tab, routing, autocmds (`ExitPre`, then `VimLeavePre`)
  - `session.lua` - one session: server, lock file, settings and `claude` process (all-or-nothing start, restart, close order); the job gets its env vars only in its env and starts from argv, not a shell
  - `session_settings.lua`, `sources/relay.lua`, `sources/session_data.lua` - the per-session settings file, the relay script (always exits 0) and the parsing of the status line and hook JSON
  - `mention_queue.lua` - @-mention queue, one per server instance
  - `server/` - WebSocket server, one instance per session (`new`, `for_client`, `drain`; TCP, handshake, frames, clients, `http.lua` for the `POST /claudinho/*` routes, `mock.lua`)
  - `tools/` - MCP tools
  - `ui/` - `window.lua` (layouts, winbar, statusline), `tabbar.lua` and `status.lua` (pure functions)
  - `terminal.lua` - facade over the active tab's terminal; `terminal/paste_fix.lua` - streamed-paste shim
  - `diff.lua`, `diff_inline.lua`, `selection.lua`, `lockfile.lua`, `integrations.lua`, `visual_commands.lua`
- `tests/` - `unit/`, `integration/`, `mocks/`, `helpers/`, plus `minimal_init.lua` and `busted_setup.lua`
- `fixtures/` - Neovim configs per file explorer (`netrw`, `nvim-tree`, `oil`, `mini-files`); `source fixtures/nvim-aliases.sh` then `vv <config>`
- `scripts/` - test runner and helper scripts
- `docs/` - Portuguese project docs (`docs/features/<slug>/` holds plan, spec and log)

## Testing

Tests use busted, in files named `*_spec.lua` or `*_test.lua`. Run one file with `mise exec -- busted tests/unit/<file>_spec.lua`.

- The unit run takes about 10 to 14 minutes. Give it a timeout of at least 15 minutes.
- Integration specs in `tests/integration/` are pending under busted ("needs a real Neovim"). They run in a real Neovim through plenary.
- To run a single integration file, use the runner's environment: `VIMINIT`, `CLAUDINHO_MINIMAL_INIT` and temporary `XDG_STATE_HOME`/`XDG_CONFIG_HOME` (see `scripts/run_integration_tests_individually.sh`). A plain `PlenaryBustedFile` loads whatever plugin is installed in your own Neovim instead of the repo.

## Test suites

| Suite         | Command                                                                             | When                                                                                       |
| ------------- | ----------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| `check`       | `mise run check`                                                                    | Always (syntax and luacheck, 0 warnings)                                                   |
| `unit`        | `mise run test` (busted with coverage, random order; `BUSTED_SEED` fixes the order) | Always                                                                                     |
| `format`      | `mise run format-check`                                                             | Always                                                                                     |
| `integration` | `./scripts/run_integration_tests_individually.sh` (plenary, real Neovim)            | Always on the mise Neovim (0.12.3); on demand on 0.12.0 (`mise exec neovim@0.12.0 -- ...`) |
| `all`         | `mise run all`                                                                      | Final gate                                                                                 |

Local `integration` uses plenary installed at `~/.local/share/nvim/site/pack/vendor/start/plenary.nvim`, pinned to the same SHA as CI (`74b06c6c75e4eeb3108ec01852001636d85a932b`). If that folder is missing, `tests/minimal_init.lua` clones plenary without pinning a version; in that case, reinstall at the CI SHA before comparing results.

## Language

- Messages, code, comments, tests and `README.en.md` are in English.
- `README.md` and everything under `docs/` are in Portuguese.
- Never use the em dash; use "-".

## Version

During a feature, add changes under `## [Unreleased]` in `CHANGELOG.md`. When a feature closes (its spec set to Implemented), the closing step runs `mise run release minor` (before 1.0; a fix between features: `patch`; `1.0.0` is the user's decision, once the plugin is stable in daily use). `scripts/release.sh` needs a clean tree on `main`, a valid `VERSION`, at least one entry under Unreleased and no existing tag. It then turns Unreleased into `## [X.Y.Z] - <today>`, updates the links, writes `VERSION`, commits `chore(release): X.Y.Z` and creates the annotated tag `vX.Y.Z`. It never pushes: the user runs the `git push origin main vX.Y.Z` it prints. Use `--dry-run` to preview. `lua/claudinho/init.lua` reads `M.version` from `VERSION`; do not hardcode the number elsewhere.

## Workflow

- docs layout: features
