# Implementation log - fork-limpo

<!-- Written by /implement only, append-only. One "Run" section per /implement run and one block per task, filled from the agents' YAML reports. The stack agents read this file before coding and follow the decisions recorded here; never re-decide something already logged without a scope request. -->

## Run 2026-11-14

Mode: `--step` (pause after each task). At the start of the run the working tree had two changes that are not from this feature: `docs/prototype/base-ui.md` (reformat) and `mise.lock` (from `mise install`; Task 2 regenerates it). The user chose to continue with them in the tree.

### Task 1 - Linha de base de testes e cobertura (done)

- **Files:** none in the repo. The unit run wrote the untracked `luacov.report.out` and `luacov.stats.out`.
- **Decisions:**
  - Baseline on `HEAD` `548981e` (upstream code at `d123707` plus the planning docs), Neovim 0.12.3 from mise.
  - `BUSTED_SEED=12345`, with `CI=true`: `BUSTED_SEED=12345 CI=true mise run test` (shuffled order, 837.63 s).
  - `check`: 0 warnings, 0 errors in 185 files.
  - `unit`: 1767 successes, 0 failures, 0 errors, 28 pending. The pending tests are conditional: the `tests/integration/*_spec.lua` files mark themselves `pending("needs a real Neovim")` under busted, and a few `tests/lockfile_test.lua` cases skip when the host cannot make a FIFO or a socket or runs as root.
  - `format`: green (438 files, 0 changed). A first run failed because `docs/prototype/base-ui.md` changed during the run; the rerun passed.
  - `integration` (Neovim 0.12.3, plenary at `~/.local/share/nvim/site/pack/vendor/start/plenary.nvim`, SHA `74b06c6c75e4eeb3108ec01852001636d85a932b`): 30 files run, 30 passed, 0 failed, 0 timed out; 535 tests passed, 0 failed, 0 errors (plenary does not report pending). The stderr lines about "Diff setup failed" come from `diff_window_sizes_spec.lua`, which triggers an autocmd error on purpose. The real cache folder was left alone. The repo symlink that CI creates in the pack folder was not needed.
  - Coverage (luacov, `scripts/coverage-summary.sh luacov.report.out "$PWD"`): total 85.78% (6360 hits, 1054 missed). `plugin/` has no entries in `luacov.report.out`, so it has no coverage data.

    | File                                           | Hits | Missed |      % |
    | ---------------------------------------------- | ---: | -----: | -----: |
    | lua/claudecode/config.lua                      |  114 |      7 |  94.21 |
    | lua/claudecode/cwd.lua                         |   41 |     10 |  80.39 |
    | lua/claudecode/diff.lua                        | 1024 |     81 |  92.67 |
    | lua/claudecode/diff_inline.lua                 |  277 |     45 |  86.02 |
    | lua/claudecode/health.lua                      |   64 |     12 |  84.21 |
    | lua/claudecode/init.lua                        |  520 |    248 |  67.71 |
    | lua/claudecode/integrations.lua                |  190 |     91 |  67.62 |
    | lua/claudecode/lockfile.lua                    |  117 |     27 |  81.25 |
    | lua/claudecode/logger.lua                      |   76 |     16 |  82.61 |
    | lua/claudecode/selection.lua                   |  557 |     59 |  90.42 |
    | lua/claudecode/server/client.lua               |  234 |      9 |  96.30 |
    | lua/claudecode/server/frame.lua                |  124 |      6 |  95.38 |
    | lua/claudecode/server/handshake.lua            |   74 |     17 |  81.32 |
    | lua/claudecode/server/init.lua                 |  195 |     26 |  88.24 |
    | lua/claudecode/server/mock.lua                 |   73 |     44 |  62.39 |
    | lua/claudecode/server/tcp.lua                  |  258 |     18 |  93.48 |
    | lua/claudecode/server/utils.lua                |  178 |     31 |  85.17 |
    | lua/claudecode/terminal.lua                    |  287 |     83 |  77.57 |
    | lua/claudecode/terminal/external.lua           |   83 |     11 |  88.30 |
    | lua/claudecode/terminal/native.lua             |  254 |     14 |  94.78 |
    | lua/claudecode/terminal/none.lua               |   13 |      2 |  86.67 |
    | lua/claudecode/terminal/owned.lua              |   41 |      0 | 100.00 |
    | lua/claudecode/terminal/paste_fix.lua          |   75 |      1 |  98.68 |
    | lua/claudecode/terminal/snacks.lua             |  404 |     49 |  89.18 |
    | lua/claudecode/tools/check_document_dirty.lua  |   36 |      0 | 100.00 |
    | lua/claudecode/tools/close_all_diff_tabs.lua   |   15 |      0 | 100.00 |
    | lua/claudecode/tools/close_tab.lua             |   23 |      1 |  95.83 |
    | lua/claudecode/tools/get_current_selection.lua |   49 |      1 |  98.00 |
    | lua/claudecode/tools/get_diagnostics.lua       |   72 |      2 |  97.30 |
    | lua/claudecode/tools/get_latest_selection.lua  |   25 |      0 | 100.00 |
    | lua/claudecode/tools/get_open_editors.lua      |   58 |      4 |  93.55 |
    | lua/claudecode/tools/get_workspace_folders.lua |   22 |      0 | 100.00 |
    | lua/claudecode/tools/init.lua                  |   92 |     10 |  90.20 |
    | lua/claudecode/tools/open_diff.lua             |   43 |      0 | 100.00 |
    | lua/claudecode/tools/open_file.lua             |  334 |     13 |  96.25 |
    | lua/claudecode/tools/save_document.lua         |   48 |      0 | 100.00 |
    | lua/claudecode/utils.lua                       |  136 |      5 |  96.45 |
    | lua/claudecode/visual_commands.lua             |  134 |    111 |  54.69 |

- **Assumptions:** none.
- **Approved scope:** the user approved cloning plenary.nvim into `~/.local/share/nvim/site/pack/vendor/start/plenary.nvim` at the CI SHA (outside the repo; the commands of `test.yml`). Adding it to the `nvim-teste` config would not work: the integration runner starts Neovim with `-u tests/minimal_init.lua`, which only looks in that `vendor/start` path.
- **Migrations / env vars:** none.
- **Docs pending:** none.

### Task 2 - Remover o que é só do upstream e recomeçar a versão (done)

- **Files:**
  - Deleted (`rm`, unstaged): `DEVELOPMENT.md`, `AGENTS.md`, `STORY.md`, `CHANGELOG.md`, `lua/README.md`, `lua/claudecode/README.md`, `lua/claudecode/server/README.md`, `lua/claudecode/terminal/README.md`, `lua/claudecode/tools/README.md`, `plugin/README.md`, `release-please-config.json`, `.release-please-manifest.json`, `communique.toml`, `reviewfixer.yaml`, `dev-config.lua`, `.devcontainer/`, `.agents/`, `.github/ISSUE_TEMPLATE/`, `.github/workflows/{release-please,release-notes,issue-triage,pr-title}.yaml`, `fixtures/issue-*`, `fixtures/cursor-toggle-repro/`, `fixtures/paste-repro/`, `fixtures/remote-diff/`, and in `scripts/`: `README.md`, `tla/`, `fixtures/`, `package*.json`, `release-please-*` and `run-release-please.sh`, `test-release-please-runner.js`, `repro_issue_*`. 213 paths in all.
  - `scripts/` keeps only `coverage-summary.sh`, `run_integration_tests_individually.sh` and `manual_test_helper.lua`.
  - `.github/workflows/test.yml`: release tooling steps, the #238 gate and the `covered-lock` job removed (`Required` already depended only on the kept jobs).
  - `fixtures/{netrw,nvim-tree,oil,mini-files}/lua/plugins/dev-claudecode.lua`: symlinks to `dev-config.lua` replaced by regular files with its content.
  - `mise.toml`: removed `communique`, `websocat`, `jq`, the `reviewfix` task and the static-proof step of `check`; `fzf` kept (used by `fixtures/bin`), with a comment. `mise.lock` regenerated with `mise lock -p linux-x64,macos-arm64` (no network blocker).
  - `.gitignore`: removed `/scripts/node_modules/`.
  - `VERSION`: `0.4.0` -> `0.1.0`; `lua/claudecode/init.lua`: version comment no longer cites release-please.
  - `tests/unit/version_spec.lua`, `tests/unit/diff_reject_on_quit_spec.lua`, `tests/unit/mention_queue_spec.lua`: comments no longer cite removed files or the verify model (rule 22).
- **Decisions:**
  - The fixture `dev-claudecode.lua` copies had their two symlink-instruction comment lines replaced with a neutral line; the rest is the old content, renamed in Task 5.
  - The Task 1 `luacov.*.out` outputs were deleted (gitignored).
  - Checks (test-runner): `check` 0 warnings / 0 errors in 185 files; `unit` (`BUSTED_SEED=12345 CI=true`) 1767 successes / 0 failures / 0 errors / 28 pending, identical to Task 1; `format-check` green (250 files, 0 changed). Coverage was not measured in this run (`luacov -r summary` failed in the runner); the done criteria do not require it, and Task 13 measures it.
  - `treefmt` prints `appears to have been removed from the filesystem` warnings for the deleted files still in the git index. They are harmless and go away when the deletions are staged or the git history restarts (Task 14).
- **Assumptions:** the `test.yml` comment on the Neovim matrix and the plenary symlink step to `claudecode.nvim` stay for Tasks 5 and 6.
- **Approved scope:** none.
- **Migrations / env vars:** none.
- **Docs pending:** none.

### Task 3 - Chaves legadas removidas, com aviso (done)

- **Files:**
  - `lua/claudecode/config.lua`: `removed_options` (five rows) and `without_removed_options`; `queue_timeout` and the legacy asserts and mapping in `apply` removed.
  - `lua/claudecode/init.lua`: `setup` calls `config.without_removed_options(opts)` first and passes the copy on.
  - `lua/claudecode/types.lua`: `queue_timeout` field removed.
  - `tests/mocks/vim.lua`: `notify_once` added (dedups through `vim._notified_once`, calls `vim.notify`).
  - `tests/unit/config_spec.lua`, `tests/unit/command_args_spec.lua`: removed keys dropped from the fixtures; the `command_args_spec` config stub gets `without_removed_options`.
  - New: `tests/unit/removed_options_spec.lua`, `tests/integration/removed_options_spec.lua` (pending under busted).
  - `tests/unit/{claudecode_send_text_command,claudecode_add_command,tree_buffer_classification,tree_send_visual,claudecode_send_command,send_complete_event,focus_after_send}_spec.lua`: the `claudecode.config` stub gets `without_removed_options = function(o) return o end` (approved scope).
  - `fixtures/{netrw,nvim-tree,oil,mini-files}/lua/plugins/dev-claudecode.lua`: commented `queue_timeout` line removed.
- **Decisions:**
  - Task 4 adds its two rows to `config.removed_options` (`terminal.snacks_win_opts`; `terminal.provider` with value `snacks` and `replace_with` `native`). The row shape already supports `value` and `replace_with`, and a unit test covers that path.
  - `without_removed_options` shallow-copies the top level, `diff_opts` and `terminal`, so the user's table is not mutated; a non-table argument returns `{}`.
  - Specs that assert warnings reset `vim._notified_once`.
  - A single integration file must run with the runner's `VIMINIT`, `CLAUDECODE_MINIMAL_INIT` and temp `XDG_STATE_HOME`/`XDG_CONFIG_HOME`; a plain `PlenaryBustedFile` loads the claudecode.nvim installed in the user's own Neovim instead of the repo.
  - Checks (test-runner): `check` 0 warnings / 0 errors in 187 files; `unit` (`BUSTED_SEED=12345 CI=true`) 1790 successes / 0 failures / 0 errors / 29 pending (+23 new `removed_options_spec` cases, +1 pending for the new integration spec; no existing case removed); `format-check` green; `tests/integration/removed_options_spec.lua` passes on Neovim 0.12.3 with the runner's command and env. The full integration script was not rerun.
  - The removed key names still appear in `README.md` and `CLAUDE.md`; Tasks 9 and 10 rewrite them.
- **Assumptions:** none.
- **Approved scope:** the seven unit specs above, to add the `without_removed_options` identity stub (`init.setup` now calls it).
- **Migrations / env vars:** none.
- **Docs pending:** `README.md` (legacy aliases text around lines 400-401, and a note on the removed keys and their warnings) and `CLAUDE.md` (Diff Options, legacy aliases line); both rewritten in Tasks 9 and 10.

### Task 4 - Remover o snacks (done)

- **Files:**
  - Deleted (`rm`): `lua/claudecode/terminal/snacks.lua`; `tests/unit/terminal/snacks_{spec,close,failed_start,reload,toggle,unfocused_show}_spec.lua` (`snacks_spec.lua` included); `tests/unit/snacks_picker_integration_spec.lua`; `tests/integration/diff_terminal_float_spec.lua`, `tests/integration/diff_terminal_float_reload_spec.lua`; `fixtures/snacks-explorer/`, `fixtures/snacks-picker/`, `fixtures/netrw/lua/plugins/snacks.lua`.
  - `lua/claudecode/terminal.lua`: no `snacks` provider, `snacks_win_opts` or `M.hide_float`; in `get_provider()`, `auto` shares the `native` branch.
  - `lua/claudecode/terminal/native.lua`: `stop_snacks_terminal` and its two calls removed. `terminal/owned.lua`: `SNACKS_MARK`, `stop_buffer`, `stop_other` removed. `terminal/external.lua`, `utils.lua`: comments only.
  - `lua/claudecode/integrations.lua`: the `snacks_picker_list` branch and `_get_snacks_picker_selection` removed. `lua/claudecode/init.lua`: `snacks_picker_list` out of the tree filetypes; the SendText description says native provider only.
  - `lua/claudecode/diff.lua`: `hide_terminal_float_for_diff`, `terminal_windows` and both calls removed; the sidebar filetypes `snacks_picker_list`/`snacks_layout_box` kept (allowed exception).
  - `lua/claudecode/health.lua`: `auto` reports `Terminal provider 'auto': native terminal`. `lua/claudecode/types.lua`: `snacks` out of the provider alias, `snacks_win_opts` and `hide_float?` removed.
  - `lua/claudecode/config.lua`: the two `removed_options` rows (`terminal.snacks_win_opts`; `terminal.provider = "snacks"`, replaced by `native`).
  - Tests changed: `tests/unit/terminal_spec.lua` (the snacks mock now stands in for `claudecode.terminal.native`; `hide_float` block out; 3 new cases), `native_terminal_toggle_spec.lua` (block "a Claude that the snacks provider started" out), `health_spec.lua` (snacks error case swapped for the auto/native case), `tree_buffer_classification_spec.lua` (+2 `snacks_picker_list` cases), `removed_options_spec.lua` unit (+6) and integration (7 keys, 7 warnings), `diff_new_tab_mode_spec.lua` (`snacks_auto_insert` -> `auto_insert_on_bufenter`), and only snacks lines or comments in `command_args_spec.lua`, `terminal/send_text_spec.lua`, `terminal/none_provider_spec.lua`, `diff_inline_spec.lua`, `diff_keep_terminal_focus_float_spec.lua`.
  - `fixtures/{netrw,nvim-tree,oil,mini-files}/lua/plugins/dev-claudecode.lua`: provider comment lists `"auto" (native), "native", "external", or "none"`; `snacks_win_opts` line removed.
- **Decisions:**
  - `terminal_spec`: the 4 cases of the "With Snacks available" block were kept, migrated to the test provider as "when setup rejects a provider value", because they test the invalid-value warning and the kept provider, which still exist (rule 27). The spec's Testing table lists the block as leaving; this is a deliberate deviation shown to the user.
  - A `snacks_picker_list` buffer falls through to "Not in a supported tree buffer".
  - Fix round 1 (quality-fixer): the first implementation dropped the `auto` branch of `get_provider()`, so the default provider fell into the final `else` and logged `Invalid provider type: string` on each call; `tests/integration/diff_close_save_spec.lua` failed 7 cases. `auto` now shares the `native` branch. The spec gave 77/0/0 at the Task 2 and Task 3 commits, so only Task 4 introduced it. The full integration script now runs in every task gate.
  - Count reconciliation (busted TAP per file, HEAD vs working tree): 1790 -> 1606 = -160 (the six snacks provider specs: 12 + 7 + 10 + 98 + 13 + 20) - 18 (picker spec) - 13 (`native_terminal_toggle_spec` snacks block) - 1 (`terminal_spec`: -4 `hide_float`, +3 new) + 2 (`tree_buffer_classification_spec`) + 6 (`removed_options_spec`). Every case that left is in "Testes que saem". The spec's approximate counts there are low (about 123 for the provider specs; real 160; the toggle block is 13, not 10), because several specs generate cases in loops. Pending 29 -> 27: the two deleted integration specs.
  - Checks (test-runner, after the fix): `check` 0 warnings / 0 errors in 177 files; `unit` (`BUSTED_SEED=12345 CI=true`) 1606 / 0 / 0 / 27; `format-check` green (226 files, 0 changed); `integration` (Neovim 0.12.3) 29 files, 505 passed, 0 failed, 0 errors.
  - `rg -i snacks lua/ plugin/ tests/` only shows the allowed exceptions: `diff.lua` sidebar filetypes (two lists), the `config.lua` removed-options rows, `removed_options_spec` (unit and integration), `diff_find_main_editor_window_spec`, `tree_buffer_classification_spec` and the "snacks provider is gone" cases in `terminal_spec`.
- **Assumptions:** keeping the 4 migrated "With Snacks available" cases (see Decisions); the user can ask for them to go.
- **Approved scope:** none.
- **Migrations / env vars:** none.
- **Docs pending:** `README.md` still documents snacks (dependencies, `snacks_win_opts`, floating window, filetype and `<C-z>` notes, picker usage, augroup list); `CLAUDE.md` mentions snacks; `ARCHITECTURE.md` shows the snacks provider. Tasks 9, 10 and 12.
- **Manual checks:** `vv netrw` opens with no snacks plugin and `:ClaudeCode` opens the native terminal; Verificação step 9 covers the two snacks warnings.

### Task 5 - Rename para claudinho (done)

- **Files:**
  - Moved (`mv`, unstaged, so git shows `D` plus `??`): `lua/claudecode/` -> `lua/claudinho/`; `plugin/claudecode.lua` -> `plugin/claudinho.lua`; `tests/unit/claudecode_{add_command,send_command,send_text_command}_spec.lua` -> `tests/unit/{add_command,send_command,send_text_command}_spec.lua`; `fixtures/{netrw,nvim-tree,oil,mini-files}/lua/plugins/dev-claudecode.lua` -> `dev-claudinho.lua`.
  - Rules a-e of spec section 4 applied with one `perl -pi` pass (rule d as `(?<!coder/)claudecode(?!-neovim)`) over `lua/`, `plugin/`, `tests/`, the fixtures, `fixtures/bin/repro`, `fixtures/nvim-aliases.sh`, `scripts/manual_test_helper.lua`, `scripts/run_integration_tests_individually.sh`, `.luacov` (`^lua/claudinho/`), `.luacheckrc` (line 1 comment), `mise.toml` (header), `.github/workflows/test.yml` (pack symlink `.../start/claudinho.nvim`).
  - Fixture lazy specs: `dir = vim.fn.fnamemodify(vim.fn.stdpath("config"), ":h:h")`, `name = "claudinho.nvim"`; the "Thomas's personal config" header rewritten. `fixtures/bin/repro` uses `${TMPDIR}/claudinho.nvim-repro`.
  - New: `tests/unit/namespace_spec.lua` (4 cases: `claudinho` loads, `claudecode` is nil, `setup` is a function, version matches `VERSION`). `tests/unit/diff_inline_spec.lua`: +1 case (the four `ClaudinhoInlineDiff*` groups keep their values and `default = true`).
- **Decisions:**
  - `serverInfo.name` stays `claudecode-neovim` (`lua/claudinho/server/init.lua:333`) until Task 8.
  - `Claudecode Integration` in `tests/integration/basic_spec.lua` became `Claudinho Integration` (a case the rules did not list).
  - `ClaudeCodeSendComplete` became `ClaudinhoSendComplete` through rule e, as designed.
  - Step f, `ClaudeCode` changed to `Claudinho`: `plugin/claudinho.lua:12` (comment) and `:26` (load-failure message); the `ClaudeCode:` message prefix in `lua/claudinho/terminal.lua:179` and `diff.lua:569,572`; `tools/init.lua:71` title `Claudinho Tool Registration`; `logger.lua` `[Claudinho] ` (42, 83), comment (52), `Claudinho Logger:` (33), titles `Claudinho Error`/`Warning` (114, 116); `diff_inline.lua:397` assert message; `ClaudeCode.nvim` header comments in `visual_commands.lua`, `types.lua`, `cwd.lua`, `integrations.lua`; `fixtures/repro/init.lua:45,59`; `tests/unit/init_spec.lua:398,444`; `[ClaudeCode]` in `logger_spec`, `log_lines_spec`, `tool_log_lines_spec` (pattern `^%[Claudinho%]`).
  - Step f, `ClaudeCode` kept (the `:ClaudeCode` command): `lua/claudinho/init.lua:1147` (`nvim_create_user_command`), `:1203` (command list message), `:1298` (`vim.cmd("ClaudeCode ...")`); `health.lua:127` (`:ClaudeCode` hint); the `cmd` lists and `<cmd>ClaudeCode...` keys of the four fixture `dev-claudinho.lua`; `fixtures/repro/example/README.md:46`; tests in `init_spec.lua` (command describes, `call.vals[1] == "ClaudeCode"`, `ClaudeCode --model ...`, line 739 message), `command_args_spec.lua` (unit and integration) and the `start("ClaudeCode ...")` calls. `rg -w ClaudeCode lua plugin tests fixtures scripts`: 61 lines.
  - Log-line cut expectations recalculated (`[Claudinho] ` is 12 chars, was 13): `logger_spec.lua:165` -> `"[Claudinho] ERROR: Accept error: EMFILE: too ma..."`; `logger_spec.lua:180` -> `"[Claudinho] Closed client_7: no reply for 61s, ..."`. The other cases only needed the prefix; the cut logic is unchanged.
  - Old-name criterion (`rg -i claudecode` outside `docs/`): only `:ClaudeCode*` command names, `claudecode-neovim` (protected), `namespace_spec.lua:9-10` (exception d), and the upstream issue URLs in `paste_fix.lua:5`, `diff_new_tab_strand_spec.lua:4`, `diff_terminal_only_window_spec.lua:4`, which the spec keeps. `CLAUDE.md` still has about 40 old-name lines (Task 10).
  - Checks (test-runner): `check` 0 warnings / 0 errors in 178 files; `unit` (`BUSTED_SEED=12345 CI=true`) 1611 / 0 / 0 / 27 (1606 + 4 + 1, as expected); `format-check` green (the first `treefmt --ci` run reported 1 changed and failed, the rerun 0 changed with no file different on disk; recorded as flaky); `integration` (Neovim 0.12.3) 29 files, 505 passed, 0 failed, 0 errors. Coverage: 75 entries under `lua/claudinho/`, 0 under `lua/claudecode/`, total 85.46% (5867 lines, 998 missed). `rg -i snacks lua/ plugin/ tests/` still only shows the allowed files.
- **Assumptions:** `fixtures/repro/example/README.md` was in scope (under `fixtures/repro/**`) and keeps `:ClaudeCode`; header comments say `Claudinho.nvim` (rule f).
- **Approved scope:** none.
- **Migrations / env vars:** `CLAUDINHO_MINIMAL_INIT` and `CLAUDINHO_INTEGRATION_TEST` replace `CLAUDECODE_*` (test runner only).
- **Docs pending:** `README.md`, `CLAUDE.md`, `PROTOCOL.md`, `ARCHITECTURE.md` still use the old name (Tasks 9, 10, 12); the health check now prints `claudinho.nvim <version> is set up`, so the README should say `:checkhealth claudinho`.
- **Manual checks:** `vv netrw`, `vv oil`, `vv nvim-tree`, `vv mini-files` load the local checkout as `claudinho.nvim` and `:ClaudeCode` opens the native terminal; `repro` creates `${TMPDIR}/claudinho.nvim-repro`; `:checkhealth claudinho` works.

### Task 6 - Neovim mínimo 0.12 (done)

- **Files:**
  - `plugin/claudinho.lua`: the guard is `has("nvim-0.12")`, with `Claudinho requires Neovim >= 0.12` through `nvim_err_writeln`; after `vim.g.loaded_claudinho` only the Task 7 placeholder comment for the conflict guard.
  - `lua/claudinho/health.lua`: `check_neovim` reports `Neovim >= 0.12` or `Neovim >= 0.12 is required`, from `has("nvim-0.12")`.
  - `tests/mocks/vim.lua`: `has` returns 1 for `"nvim-0.12"` (was `"nvim-0.8.0"`); every other feature still 0.
  - `tests/unit/health_spec.lua`: +2 cases (ok when `has("nvim-0.12") == 1`, error when 0).
  - New: `tests/unit/plugin_loader_spec.lua` (5 cases: below 0.12 writes the error and stops; 0.12 sets `loaded_claudinho`; a second source is a no-op; `claudinho_auto_setup` schedules `setup` with the table; `claudecode_auto_setup` alone does nothing and does not warn).
  - `.github/workflows/test.yml`: matrix `["stable", "v0.12.0"]`; matrix comment "v0.12.0 is the minimum that plugin/claudinho.lua and the health check support." (the 0.8 binary-version line removed); plenary pin comment says "dropping the minimum Neovim the matrix runs".
- **Decisions:**
  - Loader step 3 is only the spec's placeholder comment; the conflict logic is Task 7.
  - The `report_*` fallback in `health.lua` and its comment stay; the 0.8-0.11 comments outside these files stay, per the table in spec section 5.
  - `plugin_loader_spec` loads the loader per case, with `package.preload["claudinho"]` and `vim.g`, `vim.fn.has`, `nvim_err_writeln`, `defer_fn` and `notify` replaced and restored in `after_each`.
  - Checks (test-runner): `check` 0 warnings / 0 errors in 179 files; `format-check` green; `actionlint` and `zizmor` on `test.yml` green; `unit` (`BUSTED_SEED=12345 CI=true`) 1618 / 0 / 0 / 27 (1611 + 5 + 2); `integration` (Neovim 0.12.3) 29 files, 505 passed, 0 failed, 0 errors.
  - Gate policy from here (user, 2026-11-15): Tasks 7 and 8 run the full gate; the docs-only Tasks 9-12 run only format; Task 13 runs the final full gate.
- **Assumptions:** none.
- **Approved scope:** none.
- **Migrations / env vars:** none.
- **Docs pending:** `README.md` still says Neovim >= 0.8 (Tasks 9 and 10).
- **Manual checks:** none (the CI `v0.12.0` matrix leg runs only on GitHub).

### Task 7 - Guarda contra o claudecode.nvim carregado (done)

- **Files:**
  - New: `lua/claudinho/conflict.lua` (`M.MESSAGE` and `M.check()`: `vim.g.loaded_claudecode` set -> `vim.notify_once` at WARN and `true`; a stub without `vim.g` -> `false`).
  - `plugin/claudinho.lua`: the Task 6 placeholder became `if require("claudinho.conflict").check() then return end`, after `vim.g.loaded_claudinho` is set (no auto-setup, no `require("claudinho")`).
  - `lua/claudinho/init.lua`: `setup()` calls `conflict.check()` first and returns `M` on conflict, with no config, terminal, server, commands or autocmds (`state.initialized` stays `false`).
  - New: `tests/unit/conflict_spec.lua` (5 cases: check false, true and warns once, no `vim.g`; setup with conflict does nothing; setup without conflict runs).
  - `tests/unit/plugin_loader_spec.lua`: +2 cases (warns once and does not defer or load; a new `source` does not repeat the warning); resets `vim._notified_once`; records `notify`.
  - New: `tests/integration/loader_spec.lua` (child `nvim -l <script>` sources the plugin: with the conflict one message and no `:ClaudeCodeStart`; without it `:ClaudeCodeStart` exists); pending under busted.
- **Decisions:**
  - `loader_spec` runs the child with `-l <temp script>` and reads stdout, for a clean message count.
  - The "sets up normally" case of `conflict_spec` only asserts the conflict message is absent, because the setup path emits other notifications.
  - `init.setup` returns `M` on conflict, so a lazy.nvim caller gets a module that does nothing.
  - Checks (test-runner): `check` 0 warnings / 0 errors in 182 files; `format-check` green (231 files, 0 changed); `unit` (`BUSTED_SEED=12345 CI=true`) 1625 / 0 / 0 / 28 (1618 + 5 + 2, +1 pending for `loader_spec`); `integration` (Neovim 0.12.3) 30 files, 507 passed, 0 failed, 0 errors. The runner started the unit suite twice at once; the main session had it kill the duplicate, and the counts come from the run that was kept (logged in the dotfiles refactor entry `2026-11-15-test-runner-long-suite-background-wait.md`).
- **Assumptions:** none.
- **Approved scope:** none.
- **Migrations / env vars:** none.
- **Docs pending:** `README.md` must say to remove claudecode.nvim, because Claudinho disables itself with a warning when both are loaded (Tasks 9 and 10).
- **Manual checks:** with claudecode.nvim loaded too, starting Neovim shows one `[Claudinho] claudecode.nvim is also loaded...` warning, and Claudinho starts no server or terminal.

### Task 8 - Nome do servidor MCP, com verificação real (done)

- **Files:**
  - `lua/claudinho/server/init.lua`: `serverInfo.name` `"claudecode-neovim"` -> `"claudinho-nvim"` (line 333).
  - `tests/unit/server_spec.lua`: +1 case asserting `serverInfo.name == "claudinho-nvim"` and `serverInfo.version == require("claudinho").version:string()`.
- **Decisions:**
  - The version assertion uses the same source as the handler (`require("claudinho").version:string()`), so it does not hard-code `0.1.0`.
  - `rg -n claudecode-neovim lua tests` finds nothing after the change.
  - Real-`claude` check (spec manual script steps 1-6): the user ran it on 2026-11-15 with the new name and reported every step passed (`/ide` connects, tools respond, `openDiff` opens, accept and deny work). The new name stays; the section 7 fallback was not needed.
  - Checks (test-runner): `check` 0 warnings / 0 errors in 182 files; `format-check` green (231 files, 0 changed); `unit` (`BUSTED_SEED=12345 CI=true`) 1626 / 0 / 0 / 28 (1625 + 1), 597.6 s; `integration` (Neovim 0.12.3) 507 passed, 0 failed, 0 errors. The runner's first unit run was killed by its own `timeout 580` before the summary and a background-subshell rerun was denied by the permission classifier; with the user's approval it ran once through the harness's background execution with `timeout 1200`. A unit timeout must allow at least 15 minutes (Task 1 took 838 s).
  - Code committed as `14a87a9` before the manual check, at the user's request; the spec status and this block follow in the next commit.
- **Assumptions:** none.
- **Approved scope:** none.
- **Migrations / env vars:** none.
- **Docs pending:** `CHANGELOG.md` (Task 11) lists the MCP server name change under Changed.
- **Manual checks:** spec manual script steps 1-6, done by the user (passed).

### Task 9 - README.md e README.en.md (done)

- **Files:** `README.md` (rewritten from scratch in pt-BR, first line `English version: README.en.md`); `README.en.md` (new, English, first line `Versão em português: README.md`).
- **Decisions:**
  - Same sections in both: what it is and the hard-fork link (`d1237072`), requirements (Neovim >= 0.12, `claude` CLI), install (`vim.pack.add` + `setup`), quick start with the visual `<cmd>ClaudeCodeSend<cr>` mapping, the 15 `:ClaudeCode*` commands from `init.lua` (with the note that they become `:Claudinho*` in the next phase), config, events (`ClaudinhoSendComplete`, `ClaudinhoDiffOpened`, `ClaudinhoDiffClosed` and their `data`), `:checkhealth claudinho`, and "Vindo do claudecode.nvim" / "Coming from claudecode.nvim" (conflict warning, reinstall after the git restart, the contracts table, removed options and their warnings).
  - The config block mirrors `config.defaults` and `terminal.defaults` key by key; the removed-options table paraphrases `config.removed_options`.
  - The `open_in_current_tab` row says `open_in_new_tab` takes the inverse value; the warning itself only says "Use diff_opts.open_in_new_tab instead".
  - The MCP name row says `claudinho-nvim` only (Task 8 confirmed it).
  - The file-tree list for `:ClaudeCodeTreeAdd` is netrw, nvim-tree, neo-tree, oil.nvim, mini.files (netrw added after the main session checked `integrations.lua`).
  - Checks: `treefmt --ci README.md README.en.md` 0 changed; no em dash. Per the gate policy, no test run for docs-only tasks.
- **Assumptions:** the health summary comes from `health.lua`; the `external` fallback to `native` from `terminal.lua:150`; "the float arrives with the base UI, in a later phase" from the spec; "Claudinho loaded before claudecode.nvim loads normally" from spec section 6 (Task 7 only guards claudecode.nvim loaded first); `:ClaudeCodeSendText` is native-only from the command's `desc`.
- **Approved scope:** none.
- **Migrations / env vars:** none.
- **Docs pending:** none for the READMEs. Out of scope (for backlog-keeper at the end): the `ClaudinhoSendCompleteData` comment in `lua/claudinho/types.lua:64-73` points to README "Events", which is "Eventos" in `README.md`.

### Task 10 - CLAUDE.md curto (done)

- **Files:** `CLAUDE.md` (the upstream file replaced by a short English one, 72 lines).
- **Decisions:**
  - Sections: Vision, Commands, Structure, Testing, Test suites, Language, Version, Workflow (`- docs layout: features`).
  - `## Test suites` is the spec's "Suítes" table in English, with the plenary SHA note. `## Version` is the plan's rule 24 in English.
  - Testing records the 15-minute minimum unit timeout, the integration runner's env for a single file, and that integration specs are pending under busted.
  - Vision records the conflict with claudecode.nvim, the `claudinho-nvim` server name, and that commands keep the `ClaudeCode*` names.
  - Dropped the upstream material: release-please, snacks, the 0.8 minimum, the per-tool lists and the auth-testing walkthroughs.
  - Every cited path exists (checked by the main session); `CHANGELOG.md`, named in `## Version`, is created by Task 11. `mise install` is a mise command, not a task.
  - Checks: `treefmt --ci CLAUDE.md` 0 changed; no em dash.
- **Assumptions:** none beyond the log's earlier facts.
- **Approved scope:** none.
- **Migrations / env vars:** none.
- **Docs pending:** none.

### Task 11 - CHANGELOG.md novo e LICENSE (done)

- **Files:** `CHANGELOG.md` (new, English, Keep a Changelog, 34 lines); `LICENSE` (`Copyright (c) 2026 pedrohrb7` right below the Coder line, rest untouched).
- **Decisions:**
  - The hard-fork line names `d123707` and links the full hash `d1237072eb7c55f97b2d3c44b7971546edad0238`. No upstream history.
  - `0.1.0` is dated 2026-11-15 (the expected closing day; adjust in Task 13 if the feature closes later).
  - Changed: the rule 3 renames (module, loader, `vim.g`, events, highlights, filetype, health, log prefixes), what stays the same (`:ClaudeCode*` commands, lock file, auth header, `CLAUDE_CODE_SSE_PORT`), Neovim 0.12, `auto` = `native`, MCP server name `claudinho-nvim`, the removed-key warnings and the refusal to run with claudecode.nvim loaded.
  - Removed: the snacks provider with `snacks_win_opts` and `hide_float`, the snacks picker/explorer reading, and the five rule 15 keys, each with the replacement its warning names (checked against `config.removed_options`).
  - A `[0.1.0]` link points to `https://github.com/pedrohrb7/claudinho.nvim/releases/tag/v0.1.0`, which works once the tag exists (the tag is created by hand, with the user's authorization).
  - Checks: `treefmt --ci CHANGELOG.md LICENSE` 0 changed; no em dash.
- **Assumptions:** the release tag URL above.
- **Approved scope:** none.
- **Migrations / env vars:** none.
- **Docs pending:** none.

### Task 12 - Notas em PROTOCOL.md e ARCHITECTURE.md (done)

- **Files:** `PROTOCOL.md` (the upstream note at the top, before the H1; no rename needed); `ARCHITECTURE.md` (the note at the top, plus the rule 3 renames).
- **Decisions:**
  - The note is the spec's exact text: "This document describes the upstream claudecode.nvim at commit d123707 and may diverge from what Claudinho.nvim builds (for example, the snacks terminal provider was removed in 0.1.0)."
  - `ARCHITECTURE.md` renames: every `lua/claudecode/` -> `lua/claudinho/` (file citations and the tree heading), `ClaudeCodeDiffOpened` -> `ClaudinhoDiffOpened`, augroup `ClaudeCodeShutdown` -> `ClaudinhoShutdown`, cache dirs `claudecode_diffs`/`claudecode_diffs_fallback` -> `claudinho_diffs`/`claudinho_diffs_fallback`; each checked against the current code (`init.lua:519`, `diff.lua:537`).
  - What stays: the prose name claudecode.nvim (the files describe upstream), the `:ClaudeCodeDiffAccept`/`DiffDeny`/`CloseAllDiffs` commands, the `coder/claudecode.nvim` link, and the Claude CLI contracts (`CLAUDE_CODE_SSE_PORT`, `x-claude-code-ide-authorization`, the `claude-code` clientInfo). Neither file names `claudecode-neovim`. The snacks material was left as is.
  - Checks: `treefmt --ci PROTOCOL.md ARCHITECTURE.md` 0 changed; no `claudecode` identifier left outside the prose, command and link exceptions (checked by the main session).
- **Assumptions:** none.
- **Approved scope:** none.
- **Migrations / env vars:** none.
- **Docs pending:** none.

### Review (code-reviewer, range `548981e..1004a60`)

- **Verdict:** fix first. Tasks 3-6 and 8-12 met; Task 7 partial.
- **Findings and fixes:**
  - (major) `lua/claudinho/conflict.lua`: the guard only read `vim.g.loaded_claudecode`, which claudecode.nvim sets in its `plugin/` file, sourced after `init.lua`. With the README install (`vim.pack.add` + `setup()` in `init.lua`) Claudinho's `setup()` never saw claudecode.nvim and both ran (reproduced headless on 0.12.3). The user chose runtimepath detection (2026-11-15); the spec got the addendum "Adendo 2026-11-15 - detecção também pelo runtimepath" in section 6 (by specker). Fix (lua): new pure `conflict.detected()` (`vim.g.loaded_claudecode`, or `lua/claudecode/init.lua` on the runtimepath via `nvim_get_runtime_file`; a stub without it counts as no conflict); `conflict.check()` = `detected()` + one `vim.notify_once`. Any installed claudecode.nvim now disables Claudinho; a claudecode.nvim added to the runtimepath after Claudinho's `setup()` is still not detected.
  - (minor) `lua/claudinho/health.lua`: with the conflict, `:checkhealth claudinho` said "setup() has not been called"; it now reports `conflict.MESSAGE` as an error with the advice to remove claudecode.nvim (calls only `detected()`, so it never warns).
  - (minor) `vim.g.loaded_claudecode` disables Claudinho although the README said `vim.g.claudecode_*` are ignored: documented (docs-writer) - the `claudecode_*` config variables are ignored, `loaded_claudecode` counts as claudecode.nvim present.
  - (docs) `vim.g.claudinho_user_config` was listed as renamed but nothing reads it: dropped from `README.md`, `README.en.md` and `CHANGELOG.md`. The READMEs now describe the runtimepath detection, the remaining gap and the health error; the CHANGELOG conflict item says "installed or loaded".
  - (cosmetic) the four fixture `dev-claudinho.lua` had a duplicated header line: one kept. Found by the main session's criterion commands: `fixtures/repro/example/README.md` said `/tmp/claudecode.nvim-repro`; now `${TMPDIR:-/tmp}/claudinho.nvim-repro`, as in `fixtures/bin/repro`.
- **Tests added:** `conflict_spec` +3 (runtimepath hit, miss, stub without `nvim_get_runtime_file`), `health_spec` +1 (conflict report), `loader_spec` +1 (child Neovim with a fake claudecode on the runtimepath calls `setup()` from its init file: one warning, `state.initialized` false, no `:ClaudeCodeStart`). The reviewer's repro now shows the warning once and starts nothing.
- **Approved scope:** Task 7 extended to `lua/claudinho/health.lua`, `tests/unit/health_spec.lua`, the four fixture `dev-claudinho.lua` and `fixtures/repro/example/README.md` (review fixes, user decision on the guard). The README/CHANGELOG fixes went to docs-writer.
- **Not changed:** the reviewer's question on the fixture headers was answered by the fix above; no standards findings.

### Task 13 - Verificação final e medição (gate and measurement; manual script pending)

- **Gate (test-runner):** `mise run all` (`BUSTED_SEED=12345 CI=true`) exit 0 - `check` 0 warnings / 0 errors in 182 files, `format` 0 changed over 233 files. Its unit step ran before the review fixes landed (1626/0/0/28), so the unit suite and coverage were re-run on the fixed tree: **1630 / 0 / 0 / 28** (590.9 s). `integration` on Neovim 0.12.3: 30 files, **508** passed, 0 failed, 0 errors; on Neovim 0.12.0 (`mise exec neovim@0.12.0`, `NVIM v0.12.0`): 30 files, **508** passed, 0 failed, 0 errors (both already include the review's `loader_spec` case). Local plenary at `74b06c6c75e4eeb3108ec01852001636d85a932b`, the CI SHA.
- **Criterion commands (main session, read-only):** the old-name tokens outside `docs/` are only the allowed exceptions - `:ClaudeCode*` commands and their contexts (a), the attribution and "before" tables in README/CHANGELOG/PROTOCOL/ARCHITECTURE (b), `conflict.lua` and its tests (c), `namespace_spec`/`loader_spec`/`plugin_loader_spec` (d), plus the upstream issue links the spec keeps and the prose "fork of claudecode.nvim" in `CLAUDE.md`. `claudecode-neovim` appears only in the README/CHANGELOG "before" column (exception (e) does not apply: the new name stayed). `rg -i snacks lua/ plugin/ tests/` and the legacy keys: only the allowed files. No reference to removed files; no removed path exists; `VERSION` is `0.1.0`.
- **Before / after** (before = Task 1 baseline at `548981e`, Neovim 0.12.3, same seed):

  | Measure                             |   Before |    After | Explained by                                                                                                                                                                                                                                                                                                                                                                                                                         |
  | ----------------------------------- | -------: | -------: | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
  | unit successes                      |     1767 |     1630 | +23 Task 3 (`removed_options_spec`); -184 Task 4 (-160 snacks provider specs, -18 picker spec, -13 toggle block, -1 `terminal_spec`, +2 tree classification, +6 `removed_options_spec`); +5 Task 5 (`namespace_spec` 4, `diff_inline_spec` 1); +7 Task 6 (`plugin_loader_spec` 5, `health_spec` 2); +7 Task 7 (`conflict_spec` 5, `plugin_loader_spec` 2); +1 Task 8 (`server_spec`); +4 review (`conflict_spec` 3, `health_spec` 1) |
  | unit pending                        |       28 |       28 | +1 Task 3 (`removed_options_spec` integration), -2 Task 4 (two float specs deleted), +1 Task 7 (`loader_spec`)                                                                                                                                                                                                                                                                                                                       |
  | unit failures / errors              |    0 / 0 |    0 / 0 | -                                                                                                                                                                                                                                                                                                                                                                                                                                    |
  | integration files / passed (0.12.3) | 30 / 535 | 30 / 508 | Task 4 deleted `diff_terminal_float_spec` and `diff_terminal_float_reload_spec` and Task 3 added `removed_options_spec` (29 files, 505); Task 7 added `loader_spec` (30, 507); review +1 `loader_spec` case (508)                                                                                                                                                                                                                    |
  | integration on 0.12.0               |  not run | 30 / 508 | new minimum, on-demand suite                                                                                                                                                                                                                                                                                                                                                                                                         |
  | coverage total                      |   85.78% |   86.22% | snacks.lua (89.18%, 404 hits) removed; `health.lua`, `config.lua`, `logger.lua` and `init.lua` gained from the new specs                                                                                                                                                                                                                                                                                                             |

  Coverage per file that changed (before -> after, %): `config.lua` 94.21 -> 96.55; `conflict.lua` new -> 93.75; `health.lua` 84.21 -> 94.94; `init.lua` 67.71 -> 73.05; `integrations.lua` 67.62 -> 63.01 (the snacks picker branch, mostly covered, left; the rest is unchanged code); `logger.lua` 82.61 -> 88.17; `terminal.lua` 77.57 -> 78.51; `terminal/native.lua` 94.78 -> 91.57 (the covered `stop_snacks_terminal` left); `terminal/owned.lua` 100 -> 100 (41 -> 13 lines); `diff.lua` 92.67 -> 92.79; `terminal/snacks.lua` 89.18 -> removed. Every other file is unchanged. `plugin/claudinho.lua` now has coverage data (93.33%), which the baseline lacked.

- **Pending for Task 13 done:** the user runs the full manual script (spec "Roteiro manual do usuário", steps 1-12, rule 30) and reviews the tree and the diff against `HEAD` (rule 39).

### Task 14 - Recomeço do git e do remoto (steps 1-4 done; step 5 pending)

- **Who:** the user ran every step, with authorization at each one (rule 38); the main session prepared the commands and checked each result. Nothing was delegated.
- **Step 1, backup:** `~/backups/claudecode-history.bundle` (3.5 MB); `git bundle verify` reports a complete history, with `docs/fork-planning` at `8da00e5`, `main` at `d123707` and the two remote branches.
- **Step 2, new history:** the user confirmed the rule 41 losses; orphan branch, one commit `64f1422 chore: initial commit of claudinho.nvim 0.1.0`, whose tree (`608b725`) is identical to `8da00e5`'s (checked against the bundle); old local branches deleted, reflog expired, `gc`.
- **Step 3, GitHub:** the repository showed "forked from coder/claudecode.nvim"; the user used "Leave fork network" and the label is gone.
- **Step 4, push:** `git push --force origin main`, `docs/fork-planning` and any upstream tags deleted on the remote. `git ls-remote --heads --tags origin` lists only `refs/heads/main` at `64f1422`. The local clone has only `main`, `origin/main` and `origin/HEAD` at `64f1422`, 1 reachable commit, pack 632 KiB, no loose objects. A stale `origin/docs/fork-planning` ref was cleared by `git fetch --prune`.
- **Step 5, pending:** CI green on `64f1422`; branch rules that required `covered-lock` or `pr-title` adjusted; the plugin removed and installed again in the user's Neovim config (rule 42; the user is testing it in their test config). Task 14 is marked done once the user confirms these.
- **Spec addendum:** written by specker at the end of "Recomeço do git" (Verification).
- **Note:** commits after the restart (this log, the addendum, the closing of Tasks 13 and 14) land on top of `64f1422`.

### Task 13 - closed (done)

- **Manual script:** the user ran it in their Neovim test config after the review fixes and reported it passed (steps 1-6 had passed earlier, in Task 8, with the real `claude`); the tree and diff review (rule 39) was done in Task 14 step 2, where the new root commit's tree was checked identical to `8da00e5`.
- **Status:** Task 13 done on 2026-11-15. The spec stays `In progress` until Task 14 step 5 is confirmed.

### Task 14 - closed (done)

- **Step 4 follow-up:** the user pushed `892bacc` on top of `64f1422`; the CI was running when the user closed the task (2026-11-15), so its result is not recorded here.
- **Step 5:** closed by the user's decision with the CI run in progress. Branch rules that required `covered-lock`/`pr-title` and the plugin reinstall in the Neovim config (rule 42) are the user's own follow-ups.
- **Feature status:** every task (1-14) is done; spec and plan set to `Implemented`, and the Index updated.
