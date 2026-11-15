# CLAUDE.md

Context for Claude Code when working in this repository.

## Vision

claudinho.nvim is a clean fork of claudecode.nvim: a pure Lua Neovim plugin, with no dependencies, that speaks the same WebSocket MCP protocol as Anthropic's official IDE extensions. Claude Code CLI finds Neovim through a lock file in `~/.claude/ide/`, then calls the plugin's tools (open files, diffs, selections, diagnostics). The terminal is Neovim's native one, or an external app, or none.

- Requires Neovim >= 0.12.
- The plugin refuses to run when claudecode.nvim is loaded (`g:loaded_claudecode`): both register the same `:ClaudeCode*` commands.
- The MCP server name is `claudinho-nvim`. Commands keep the `ClaudeCode*` names.
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

## Structure

- `plugin/claudinho.lua` - loader: version check, conflict check, optional auto setup
- `lua/claudinho/` - the plugin
  - `init.lua`, `config.lua`, `conflict.lua`, `health.lua`
  - `server/` - WebSocket server (TCP, handshake, frames, clients)
  - `tools/` - MCP tools
  - `terminal/` and `terminal.lua` - native, external and none providers
  - `diff.lua`, `diff_inline.lua`, `selection.lua`, `lockfile.lua`
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

The version is bumped by hand, with no tool, in the same PR that closes a feature: `VERSION` plus a new `CHANGELOG.md` entry. Before 1.0, each closed feature bumps the minor (`0.2.0`, `0.3.0`...) and each fix between features bumps the patch. `1.0.0` is the user's decision, once the plugin is stable in daily use. The `vX.Y.Z` tag is created by hand, only with the user's authorization at that moment. `lua/claudinho/init.lua` reads `M.version` from `VERSION`; do not hardcode the number elsewhere.

## Workflow

- docs layout: features
