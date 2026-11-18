# Implementation log - base-ui

<!-- Written by /implement only, append-only. One "Run" section per /implement run and one block per task, filled from the agents' YAML reports. The stack agents read this file before coding and follow the decisions recorded here; never re-decide something already logged without a scope request. -->

## Run 2026-11-15

Mode: `--step` (pause after each task; commit each task with the user's approval; the user pushes). Gate policy carried over from fork-limpo: code tasks run `check`, the full `unit`, `format` and the full `integration`; docs-only tasks run only `format`; Task 21 runs the final gate. Long suites run through the harness background with a timeout of at least 1200 s, one run at a time.

### Task 1 - Linha de base de testes e cobertura (done)

- **Files:** none in the repo. `luacov.report.out` and `luacov.stats.out` regenerated (gitignored).
- **Decisions:**
  - Baseline on `HEAD` `8933efd` (code identical to `c8f5329`, release task; later commits are docs), Neovim 0.12.3 from mise, `BUSTED_SEED=12345 CI=true`.
  - `check`: 0 warnings, 0 errors in 183 files.
  - `unit`: 1639 successes, 0 failures, 0 errors, 28 pending (the integration specs, which need a real Neovim), 619.16 s.
  - `integration` (Neovim 0.12.3): 30 files, 508 passed, 0 failed, 0 errors.
  - `claude --version`: 2.1.325 (Claude Code).
  - Coverage (luacov, `scripts/coverage-summary.sh luacov.report.out "$PWD"`): total 86.22%. Per file (%):

    | File                 |     % | File                            |      % |
    | -------------------- | ----: | ------------------------------- | -----: |
    | config.lua           | 96.55 | terminal/external.lua           |  88.30 |
    | conflict.lua         | 93.75 | terminal/native.lua             |  91.57 |
    | cwd.lua              | 80.39 | terminal/none.lua               |  86.67 |
    | diff.lua             | 92.79 | terminal/owned.lua              | 100.00 |
    | diff_inline.lua      | 86.02 | terminal/paste_fix.lua          |  98.68 |
    | health.lua           | 94.94 | tools/check_document_dirty.lua  | 100.00 |
    | init.lua             | 73.05 | tools/close_all_diff_tabs.lua   | 100.00 |
    | integrations.lua     | 63.01 | tools/close_tab.lua             |  95.83 |
    | lockfile.lua         | 81.25 | tools/get_current_selection.lua |  98.00 |
    | logger.lua           | 88.17 | tools/get_diagnostics.lua       |  97.30 |
    | selection.lua        | 90.42 | tools/get_latest_selection.lua  | 100.00 |
    | server/client.lua    | 96.30 | tools/get_open_editors.lua      |  93.55 |
    | server/frame.lua     | 95.38 | tools/get_workspace_folders.lua | 100.00 |
    | server/handshake.lua | 81.32 | tools/init.lua                  |  90.20 |
    | server/init.lua      | 88.24 | tools/open_diff.lua             | 100.00 |
    | server/mock.lua      | 62.39 | tools/open_file.lua             |  96.25 |
    | server/tcp.lua       | 93.48 | tools/save_document.lua         | 100.00 |
    | server/utils.lua     | 85.17 | utils.lua                       |  96.45 |
    | terminal.lua         | 78.51 | visual_commands.lua             |  54.69 |
    |                      |       | plugin/claudinho.lua            |  93.33 |

    All paths under `lua/claudinho/` except the last. The summary script prints percentages only.

- **Assumptions:** none.
- **Approved scope:** none.
- **Migrations / env vars:** none.
- **Docs pending:** none.

### Task 2 - Servidor por instância (done)

- **Files:**
  - `lua/claudinho/server/init.lua`: instance API (`M.new`, `M.for_client`, `Server:start/stop/drain/broadcast/send/send_response/get_status`); handlers closed over the instance; per-instance `stop()`; a default instance behind the module-level functions; `M.state` is a view of the default instance.
  - `lua/claudinho/server/tcp.lua`: `create_server` takes a 4th argument `server_id`, kept as `server.id`; `_handle_new_connection` sets `client.server_id`.
  - `lua/claudinho/server/client.lua`: `server_id` in the `WebSocketClient` annotation.
  - New: `tests/unit/server/instances_spec.lua` (11 cases: ids/ports/tokens, isolated broadcast, `server_id` and `for_client`, per-instance stop, deferred answer through the owning instance, default instance); `tests/integration/server_instances_spec.lua` (5 real-socket cases, pending under busted); `tests/helpers/ws_client.lua` (WebSocket client for real-Neovim specs: connect with token, send, `next_message`, close; a wrong token makes connect raise).
- **Decisions:**
  - Module-level `M.start`, `M.stop`, `M.broadcast`, `M.send`, `M.send_response`, `M.get_status`, `M.state`, `M.register_handlers` and `M._handle_*` delegate to a default instance built on first use, so single-session callers are unchanged until later tasks move them. On the default instance, `send`, `send_response`, `broadcast`, `_handle_message` and `_handle_request` are fields that forward to the module functions, so existing specs that replace them still work. Later tasks call instance methods directly on non-default instances.
  - `M.state` maps `server` to the instance's `tcp` and `port`, `auth_token`, `handlers` one to one; writes to those keys go to the instance (existing specs that set `state.server = {}` still work). The instance field is `tcp`, as in the spec; `M.state.server` is only a compatibility alias.
  - The default `on_open` (queued mention processing) applies only when `opts.on_open` is nil; an instance with its own `on_open` replaces it. `on_disconnect` adds the callback after the existing diff cleanup.
  - `stop()` calls `diff.close_diffs_for_client(client.id, "server stopping")` for each handshaken client of the instance, and no longer calls `close_pending_diffs` (guard: `package.loaded["claudinho.diff"]`).
  - Running instances live in a module-local `running` table from start to stop; `for_client` returns nil for a stopped instance.
  - `tools.setup(self)` is still called on start; `tools/init.lua` is unchanged (`tools.M.server` is written but never read).
  - `drain(timeout_ms)` uses `vim.wait` with a 10 ms poll, default 1000 ms.
  - Checks (test-runner): `check` 0 warnings / 0 errors in 186 files; `format-check` green; `unit` (`BUSTED_SEED=12345 CI=true`) 1650 / 0 / 0 / 29 (607 s; +11 `instances_spec`, +1 pending `server_instances_spec`); `integration` (Neovim 0.12.3) 31 files, 513 passed, 0 failed, 0 errors. Existing server specs pass with no protocol assertion changed.
- **Assumptions:** the default `drain` timeout of 1000 ms; the integration spec uses ports 20000-40000.
- **Approved scope:** none.
- **Migrations / env vars:** none.
- **Docs pending:** `ARCHITECTURE.md` and `CLAUDE.md` (Tasks 18 and 20): the server instance API (`M.new`, `for_client`, `drain`), `client.server_id`, the per-instance stop.

### Task 3 - Rotas HTTP de status e hooks (done)

- **Files:**
  - New `lua/claudinho/server/http.lua`: POST parser and router; answers 204/400/401/404/413, closes the socket after the write, then calls `on_post(kind, body)` inside a `pcall`. Exports `M.TOKEN_HEADER` (`x-claudinho-token`), `MAX_HEADER_BYTES` (8192, counting the final CRLFCRLF), `MAX_BODY_BYTES` (1 MiB) and `create_response`.
  - `lua/claudinho/server/client.lua`: `process_data` takes an 8th argument `on_http`; a request line starting with `POST ` sets `client.mode = "http"` and hands the buffer to `on_http` before the handshake. `M.write` (raw write); `mode`/`http` annotations.
  - `lua/claudinho/server/tcp.lua`: `create_server` accepts `callbacks.on_post` and keeps `server.http_clients`; on the first POST bytes the client moves from `clients` to `http_clients`; `_disconnect_client` and `stop_server` clean `http_clients` (stop closes their sockets).
  - `lua/claudinho/server/init.lua`: the tcp callbacks gain `on_post`, forwarding to `self.on_post` (`opts.on_post` of `M.new`).
  - New `tests/unit/server/http_spec.lua` (23 cases: routes, token, limits, a POST client outside `clients`); `tests/unit/server/handshake_spec.lua` +4 (a POST is not a WebSocket endpoint; a POST skips the handshake when `on_http` is set; a GET with `on_http` still upgrades); new `tests/integration/server_http_spec.lua` (4 real-socket cases, pending under busted); new `tests/helpers/http_post.lua` (raw POST over `vim.uv`: `build`, `send`, `post`; returns status, raw bytes, closed flag, elapsed ms).
- **Decisions:**
  - Without `on_http` a POST still goes down the handshake path and gets the old 404, so the WebSocket protocol and its callers are unchanged.
  - The first 1-4 bytes of a connection wait until the verb is known (a prefix of `POST ` returns early); fewer than 5 bytes of anything else are decided on the next read.
  - Check order once the headers arrive: 404 (path or method), 401 (token), 400 (`Content-Length` missing or not a number), 413 (over 1 MiB). It answers without reading the body. Chunked bodies are not supported: the relay (Task 4) must always send `Content-Length`. Bytes after the declared body are ignored (no keep-alive).
  - POST clients live in `server.http_clients`, so ping, broadcast, `get_status` and `on_disconnect` never see them.
  - The 204 goes out before `on_post` runs, inside the libuv callback: the session (Task 8) must wrap its handler in `vim.schedule`.
  - A server without a token (`auth_token` nil) accepts POSTs without a token check, like the WebSocket path; real sessions always have one.
  - Checks (test-runner): `check` 0 warnings / 0 errors in 190 files; `format-check` green; `unit` (`BUSTED_SEED=12345 CI=true`) 1677 / 0 / 0 / 30 (622 s); `integration` (Neovim 0.12.3 through `mise exec`) 32 files, 517 passed, 0 failed, 0 errors. The agent expected 1678, but `http_spec` has 23 cases, not 24 (counted by the main session with busted TAP: `http_spec` 23, `handshake_spec` 18 -> 22); no test was lost. The runner's note that the integration ran on 0.12.6 came from the system `nvim` it queried outside mise; the script runs mise's 0.12.3.
- **Assumptions:** chunked bodies unsupported; no keep-alive.
- **Approved scope:** none.
- **Migrations / env vars:** none.
- **Docs pending:** `PROTOCOL.md` and `ARCHITECTURE.md` (Task 20): the two POST routes, the `X-Claudinho-Token` header, status codes and limits, `client.mode = "http"`, `server.http_clients`, `on_post`. `CLAUDE.md` (Task 18): `server/http.lua` in the server module list.
- **Review note:** security-relevant (a new local HTTP endpoint with token auth); include `security-reviewer` in the end-of-feature review.

### Task 4 - Lock file por aba, settings da sessão e relay (done)

- **Files:**
  - `lua/claudinho/lockfile.lua`: `create(port, token, opts)` takes `opts.ide_name` (default `"Neovim"`) and `opts.workspace_folders` (default `get_workspace_folders()`); `get_workspace_folders(cwd)` puts the tab folder first, then the LSP folders, without duplicates.
  - `lua/claudinho/types.lua`: `ClaudinhoLockfileOpts`.
  - New `lua/claudinho/session_settings.lua`: `relay_path()` (absolute, from the module's own source path), `build(progpath, relay)` (pure table builder), `write(session)` (sets `session.settings_path`, returns the path or nil and an error; file mode 0600, opened with `wx`), `remove(session)` (clears `settings_path`; deletes only a path ending in `.claudinho-<n>.json`, never anything else under `~/.claude`).
  - New `lua/claudinho/sources/relay.lua`: `parse_port`, `build_request`, `main(kind, deps)` and the `nvim -l` entry point.
  - Tests: `tests/lockfile_test.lua` +4 (33 -> 37); new `tests/unit/session_settings_spec.lua` (12); new `tests/unit/sources/relay_spec.lua` (11); new `tests/integration/relay_spec.lua` (9, pending under busted; real `nvim --clean -l` child processes against a real server instance, including an empty PATH, a dead port, a server that never answers and a wrong token).
- **Decisions:**
  - `relay.main(kind, deps)` takes optional `deps` (`getenv`, `read_stdin`, `write_stdout`, `send`) so unit specs run it with no network or stdio. Exit code is always 0; everything runs inside `pcall`.
  - The relay reads stdin and writes the statusline newline before checking the port; without a valid port nothing is sent. It sends `Content-Length`, `X-Claudinho-Token`, `Content-Type: application/json` and `Connection: close`, and waits up to `relay.TIMEOUT_MS = 500` for the answer or the close.
  - The settings unit spec fakes `vim.uv` and `vim.json` (the busted mock has neither); the 0600 mode is asserted on the `fs_open` call.
  - Relay time: average 11.4 ms (agent run) and 11.6 ms (gate run) over 10 child-process runs, round trip included, on Neovim 0.12.3 (F4 measured 9.7 to 12.1 ms). Every run under 2000 ms.
  - Checks (test-runner): `check` 0 warnings / 0 errors in 195 files; `format-check` green; `unit` (`BUSTED_SEED=12345 CI=true`) 1704 / 0 / 0 / 31 (635 s); `integration` (Neovim 0.12.3 through `mise exec`) 33 files, 526 passed, 0 failed, 0 errors.
- **Assumptions:** the settings file name uses `session.number` (the `ClaudinhoSession` annotation of section 6); a missing token still sends the POST without the header (the server answers 401, which the relay ignores).
- **Approved scope:** none.
- **Migrations / env vars:** `CLAUDINHO_PORT` and `CLAUDINHO_TOKEN`, read by the relay; the session sets them in the tab process (Task 8).
- **Docs pending:** `ARCHITECTURE.md` and `PROTOCOL.md` (Task 20): per-tab lock file fields, the settings file, the relay script and its exit-0 contract. `CLAUDE.md` (Task 18): `session_settings.lua` and `sources/relay.lua` in the structure list.

## Run 2026-11-16

Mode: `--step`, same gate policy as the 2026-11-15 run. The run state `.claude/runs/base-ui.json` was missing and was recreated from this log (Tasks 1-4 done). Toolchain reinstalled by the user before the gate (mise, `mise install --locked`, `mise run setup`, plenary at the CI SHA).

### Task 5 - Dados da sessão, status e barra de abas (funções puras) (done)

- **Files:**
  - New `lua/claudinho/sources/session_data.lua`: `decode`, `from_statusline`, `from_hook`, `model_label` (pure).
  - New `lua/claudinho/ui/status.lua`: `text(data)`, `MODES`, `mode_label`; items joined with `" · "`, `%` escaped.
  - New `lua/claudinho/ui/tabbar.lua`: `clean_title`, `marks`, `label`, `layout`, `render`, `setup_highlights`, `click`, `install_click_handler`.
  - New `tests/unit/sources/session_data_spec.lua` (22), `tests/unit/ui/status_spec.lua` (12), `tests/unit/ui/tabbar_spec.lua` (36); new `tests/fixtures/claude/*.json` (13: 9 statusline, 4 hook).
- **Decisions:**
  - Tab info shape for the tab bar: `{ number, title, diff, exited }`, title already clean or nil. Task 10 passes `b:term_title` through `clean_title(title, { cmd = config.terminal_cmd })`.
  - `render(tabs, active, width, max)` takes everything as arguments (not `render(win)`). `layout` returns items `{ kind = tab|sep|new|more_left|more_right, text, number, active, tab, limit }`. Task 10 computes the width and wires `winbar = %!v:lua...`.
  - The click global is installed by `tabbar.install_click_handler()` (`_G.ClaudinhoTabClick = M.click`). Task 10 must call it and `tabbar.setup_highlights()`.
  - `M.click` lazy-requires `claudinho.sessions` and calls `sessions.new()` or `sessions.activate(n)`; `sessions.lua` comes in Task 9, the spec stubs it through `package.loaded`.
  - Cells are `" <label> "`, with the box bar between all items and before `+`. Overflow arrows are the items `" ‹ "` and `" › "`. Overflow fallback neighbours use limit 0 and are added right first, then left.
  - `status.text` takes `{ model, effort, mode }` with the raw `permission_mode`; the display mapping lives in `status`. `from_hook` returns the raw `permission_mode` as `mode`.
  - `decode` treats a table with `[1] ~= nil` as an array (nil); an empty table counts as an object.
  - The modules use their own trim (the busted vim mock has no `vim.trim`/`vim.list_extend`); the spec fakes `vim.json.decode`. The mock's `strdisplaywidth` counts code points, so wide-character truncation is not covered by unit tests (manual check at Task 10). Glyphs are literal UTF-8, not `\u{}` escapes (Lua 5.1).
  - Fix round 1 (quality-fixer): `status_spec` registered `it` inside a `pairs()` loop, rejected by the test-order helper; now an ordered array with `ipairs`.
  - Checks (test-runner): `check` 0 warnings / 0 errors in 201 files; `format-check` green; `unit` (`BUSTED_SEED=12345 CI=true`) 1774 / 0 / 0 / 31 (648 s); `integration` (Neovim 0.12.3 through `mise exec`) 33 files, 525 passed, 1 failed: `tests/integration/claude_stub_spec.lua` ("is the first PATH entry"). It fails on `HEAD` without the Task 5 changes too (proved with the changes stashed) and passes in isolation (4 of 4); registered as a pre-existing bug in `docs/backlog/bugs/2026-11-16-claude-stub-path-first-entry-integration.md` (medium), with the user's approval to close the task.
- **Assumptions:** `clean_title` drops the first token only when it has no ASCII letter or digit (so a non-ASCII first word, such as CJK, is dropped too); the generic command check compares the whole command, its first token and that token's basename, case-insensitive; the marks are `" ● diff"` and `" [exited]"` (the spec's English text wins over rule 14's `[encerrada]`).
- **Approved scope:** none.
- **Migrations / env vars:** none.
- **Docs pending:** `ARCHITECTURE.md` (Task 20): `sources/session_data.lua`, `ui/status.lua`, `ui/tabbar.lua` and their pure-function contract.
- **Manual checks (Task 10):** winbar clicks (left button on a tab and on `+`; other buttons ignored; `mouse=` disables clicks); light and dark colorschemes (groups link to `TabLineSel`, `TabLine`, `WarningMsg`, `Comment`, `TabLineFill`); a narrow window (shrink to numbers, then the `‹ ›` arrows keeping the active tab and `+`); a window narrower than the active tab plus `+`; CJK titles.

### Task 6 - Config nova e notificações (done)

- **Files:**
  - `lua/claudinho/config.lua`: new defaults `window`, `keymaps` and `notify`; public `normalize_new_keys`, run only by `apply`, falls back to the default with the exact error through `notify.error` (no assert). `validate()` is unchanged; no old key changes.
  - New `lua/claudinho/notify.lua`: `info` (only when the plugin state has `config.notify == true`, once through `notify_once`, optional level override), `reply` (WARN), `error` (ERROR); title `Claudinho`.
  - `lua/claudinho/types.lua`: `ClaudinhoConfig` gains `window`, `keymaps`, `notify`; new `ClaudinhoWindowConfig` and `ClaudinhoKeymapsConfig`.
  - Tests: `tests/unit/config_spec.lua` (new defaults, valid values, each invalid key as an `ipairs` array, a non-table `window`; 30), `tests/config_test.lua` (+2: defaults and fallback), new `tests/unit/notify_spec.lua` (8). `tests/mocks/vim.lua` unchanged.
  - `docs/backlog/bugs/README.md`: Index table aligned by treefmt (the row added after the Task 5 gate went into `2568f84` unformatted).
- **Decisions:**
  - `notify.info` reads the plugin state without loading the plugin: `package.loaded["claudinho"].state.config.notify == true`; plugin not loaded or no config means off.
  - `config.lua` requires `claudinho.notify` lazily inside `normalize_new_keys` (no require cycle).
  - Error value text: strings quoted, others through `tostring`; "using <default>" is the default's `tostring` (`0.3`, `0.8`, `24`, `false`, and `nil` for `diff_width`). A non-table `window`, `right`, `bottom`, `float` or `keymaps` reports `<key> = <v> is not valid; using the default <key>.`
  - `window.tab_title_max` must be an integer >= 1.
  - Checks (test-runner): `check` 0 warnings / 0 errors in 203 files; `format-check` green after the backlog Index fix (299 traversed, 0 changed); `unit` (`BUSTED_SEED=12345 CI=true`) 1798 / 0 / 0 / 31 (636 s); `integration` (Neovim 0.12.3 through `mise exec`) 33 files, 525 passed, 1 failed: only the known `claude_stub_spec` bug (`docs/backlog/bugs/2026-11-16-claude-stub-path-first-entry-integration.md`).
- **Assumptions:** the spec gives the exact text only for the generic template; the formats for non-numeric and non-table values above are the agent's reading. An unset `diff_width` stays nil; an invalid explicit value reports "using nil.".
- **Approved scope:** none.
- **Migrations / env vars:** none.
- **Docs pending:** `README.md` and `README.en.md` (Task 17): the `window`, `keymaps` and `notify` keys and defaults. `CHANGELOG.md` Unreleased (Task 19): the new keys and `notify.lua`.

### Task 7 - Fila de @-mentions por instância (done)

- **Files:**
  - New `lua/claudinho/mention_queue.lua` (origin line first): the queue code moved out of `init.lua`; `Queue.new({ server, config, format_path? })` with `send`, `enqueue`, `on_open`, `flush`, `clear`, `is_connected`, `ready_in` (plus private `_format`, `_queue`, `_expire`, `_schedule_flush`, `_start_timer`, `_stop_timer`).
  - `lua/claudinho/init.lua`: the queue functions, `process_mention_queue` and `format_mention` removed; `M.default_queue()` returns a queue bound to the default server and is used for send, clear and `is_claude_connected`.
  - `lua/claudinho/server/init.lua`: the default `on_open` calls `default_queue():on_open()`.
  - `lua/claudinho/types.lua`: `mention_queue`, `mention_timer` and `connection_timer` removed from `ClaudinhoState`.
  - Tests: `tests/unit/mention_queue_spec.lua` (46 -> 49 cases: state reads through `default_queue()`, module added to the reload list, 3 new `Queue.new` cases with two isolated queues); `tests/unit/at_mention_edge_cases_spec.lua` (24, reads the queue through `default_queue()`).
- **Decisions:**
  - `Queue.new` takes an optional `format_path` (default identity). `init` passes `M._format_path_for_at_mention` dynamically, because `add_command_spec` stubs and asserts that function.
  - The default queue's server is an adapter that reads `M.state.server` on each call: `broadcast` forwards to `M.state.server.broadcast(...)`, `get_status` to `server/init`. Specs that replace `claudinho.state.server` with a mock keep working.
  - `default_queue()` refreshes `queue.config` from `M.state.config` on every call (setup and tests replace it).
  - `flush` no longer asserts that the server is up: a stopped server makes `broadcast` return false and the mention waits or expires; `stop()` still clears the queue.
  - `M.process_mention_queue` removed now (the spec lists it for removal in Task 12; only `server/init` called it).
  - `queue.mentions`, `queue.mention_timer` and `queue.connection_timer` replace the `M.state` fields.
  - Checks (test-runner): `check` 0 warnings / 0 errors in 204 files; `format-check` green (0 changed); `unit` (`BUSTED_SEED=12345 CI=true`) 1801 / 0 / 0 / 31 (674 s; +3, the new isolated-queue cases; no case lost); `integration` (Neovim 0.12.3 through `mise exec`) 33 files, 525 passed, 1 failed: only the known `claude_stub_spec` bug.
  - The agent ran `busted tests/unit/server` (whole directory, 266 successes) as a narrow check; the workflow hook logged it as a deviation.
- **Assumptions:** extra public methods beyond the spec's list (`enqueue`) are acceptable.
- **Approved scope:** none.
- **Migrations / env vars:** none.
- **Docs pending:** `ARCHITECTURE.md` and `CLAUDE.md` (Tasks 18 and 20): `mention_queue.lua` in the structure list; the queue is per server instance and `init` uses the default one until Task 12.

### Task 8 - Sessão: processo, servidor, lock file e settings (done)

- **Files:**
  - New `lua/claudinho/session.lua` (origin line first, upstream `terminal.lua`): `M.new(number, config, opts?)`, `M.start(s, extra_args?)`, `M.restart(s)`, `M.close(s, reason?)`; env building, `on_post` merge into `session.data`, process-exit handling, `TermEnter` guard. No command uses it yet.
  - `lua/claudinho/types.lua`: `ClaudinhoSession` and `ClaudinhoPendingDiff`.
  - Tests: new `tests/unit/session_spec.lua` (52, fakes for server, lockfile, settings, queue and the Neovim API); new `tests/integration/session_spec.lua` (9, real Neovim, pending under busted); new `tests/helpers/tab_env.lua` (private `CLAUDE_CONFIG_DIR`/`HOME`, an idle test command that writes its env to a file, an exit-code command, env reader, cleanup). `tests/mocks/vim.lua` unchanged.
- **Decisions:**
  - `start`/`restart` return `false` plus `"Cannot start Claude <n>: ..."` and never call `notify`; the caller (Task 9/12) shows it, so there is no double notification.
  - The job runs from an argv list (`utils.parse_command(base_cmd)` + `--settings <path>` + the parsed `extra_args`), not a shell string, which keeps bracketed aliases such as `opus[1m]` intact. `extra_args` is the spec's shell-escaped suffix with a leading space; `shell_split` reads it back.
  - The server is created with `on_open` and `on_post` only, both wrapped in `vim.schedule`; `on_disconnect` is left to the server's own diff cleanup.
  - Env built in `session.lua`: plugin vars (`CLAUDINHO_PORT`, `CLAUDINHO_TOKEN` and the others of section 6), then `config.env`, then the `no_proxy`/`NO_PROXY` loopback merge (copied from `terminal.lua`, rewritten in Task 12). `vim.env` is never touched.
  - Reports to `claudinho.sessions` go through `pcall(require)`: `on_change` when a POST changed data, `on_exit` when the process ends. A silent no-op until Task 9; Task 9 owns the "Claude <n> exited" notification.
  - Buffer unlisted (`nvim_create_buf(false, false)`), `bufhidden=hide`, `b:claudinho_session`, `filetype=claudinho`.
  - Process end (`handle_exit` through `vim.schedule`) is ignored while closing or when the job id is not `session.job`. It sets `state`/`exit_code`, clears the queue, empties `pending_diffs` and releases server, lock and settings; the buffer stays. A buffer-local `TermEnter` autocmd (group `ClaudinhoSession`) schedules `stopinsert` on an exited session.
  - `restart`: on success every window showing the old buffer gets the new one, and the old buffer is deleted after the new `jobstart`; on failure the session stays exited with its old buffer. `data` is kept; the new server's queue replaces the old one.
  - `close` order: reject waiting diffs (`coroutine.resume(co, "reject")`), `close_diffs_for_client` for each handshaken client (only if `claudinho.diff` is loaded), `server:drain(200)`, `queue:clear`, `jobstop` plus a wait for `TermClose` up to 1000 ms (skipped when `jobstop` returns 0), release (server stop, lock remove, settings remove), buffer delete.
  - Integration specs point `lockfile.lock_dir` at a temp folder (it is read once at module load).
  - Fix round (LuaLS warnings in the new file, no behavior change): `---@cast port integer` after the server start check; `server --[[@as ClaudinhoMentionServer]]` at the `Queue.new` call. `lua-language-server --check` (warning level) clean.
  - Checks (test-runner): `check` 0 warnings / 0 errors in 208 files; `format-check` green (0 changed); `unit` (`BUSTED_SEED=12345 CI=true`) 1853 / 0 / 0 / 32 (674 s; +52 and +1 pending); `integration` (Neovim 0.12.3 through `mise exec`) 34 files, 534 passed, 1 failed: only the known `claude_stub_spec` bug; `session_spec` 9/9.
- **Assumptions:** a pending diff's coroutine is resumed with the string `"reject"` (Task 11 must accept it); a never-started session starts in state `exited`, so `restart` on it starts it; "a mensagem certa sai" is the returned error text, not a notification.
- **Approved scope:** none.
- **Migrations / env vars:** `CLAUDINHO_PORT` and `CLAUDINHO_TOKEN` are now set in the tab job env (read by the relay since Task 4).
- **Docs pending:** `ARCHITECTURE.md` and `CLAUDE.md` (Tasks 18 and 20): `session.lua` in the structure list; lifecycle (all-or-nothing start, process exit, restart, close order); env vars only in the job env; job started from argv, not a shell. `CHANGELOG.md` Unreleased (Task 19): the per-tab session module (internal).
- **Manual checks (Task 10):** a key typed in an ended terminal, rechecked with a real window (the integration case only checks the buffer stays valid and the mode is not terminal).

### Task 9 - Abas: registro, aba ativa, roteamento e encerramento (done)

- **Files:**
  - New `lua/claudinho/sessions.lua`: registry `{ tabs, active, by_server }` with `new`, `activate`, `next`, `prev`, `close`, `restart`, `reject_all_pending`, `kill_all`, `active`, `for_client`, `on_change`, `on_exit`, `router`, `setup_autocmds` (not yet called by `init`; Task 12).
  - `lua/claudinho/selection.lua`: `resend_latest()`; `send_selection_update` returns the broadcast result; `is_claude_terminal_buffer` also accepts `b:claudinho_session`; `enable()` takes a server or a router. Current behavior unchanged (`init` does not pass the router yet).
  - `lua/claudinho/types.lua`: `ClaudinhoSelectionRouter`, `ClaudinhoSessionsState`.
  - Tests: new `tests/unit/sessions_spec.lua` (50, fakes for session, server, window, selection, diff, notify); `tests/selection_test.lua` (+6: router without server, `resend_latest` x4, `b:claudinho_session` x2); new `tests/integration/sessions_spec.lua` (7, real Neovim: three tabs with distinct port/token/lock; `kill_all` leaves 0 jobs and 0 lock files; router and `for_client`; a status POST reaches only its own tab; a wrong-tab token gets 401; close moves to the neighbour; `BufWipeout` closes the tab; `ExitPre`/`VimLeavePre`).
- **Decisions:**
  - Window contract for Task 10: `sessions.lua` calls `pcall(require, "claudinho.ui.window")`, then `window.show({ focus = true })` after `new`, `window.close()` when the last tab closes or on `kill_all`, and `window.refresh()` to redraw winbar and statusline; `refresh()` decides by itself whether the window is visible. Every call is guarded.
  - Messages: the sessions functions show their own messages (`notify.error` for a start/restart failure; `notify.reply` for "No Claude <n>", "tab-restart needs a tab number" and "Claude <n> is still running") and also return `false` plus the message. Task 12 must not notify the same text again.
  - `on_exit` shows `notify.info("Claude <n> exited")` only for registered sessions; `on_change` and `on_exit` ignore unregistered sessions.
  - `activate` resumes the tab's `pending_diffs` coroutines with `"open"` in arrival order, removing each first. It resends the selection (through `package.loaded["claudinho.selection"]`, only if loaded) only when the active tab actually changes. `new` also goes through `set_active`. `activate` does not show the window (only `new` does), as in the spec table.
  - `reject_all_pending(reason)` answers `"reject"` to the waiting diffs of every tab and leaves open diffs alone (Task 11 can call it from close-all-diffs). `kill_all` and the `ExitPre` callback also call `diff.close_pending_diffs(reason)` (only if `claudinho.diff` is loaded), then drain every server for `session.DRAIN_MS` (200 ms); `kill_all` then closes each session and the window, and is idempotent.
  - `sessions.new` reads the config from `package.loaded.claudinho.state.config` (fallback `config.defaults`) and passes a `format_path` that calls `claudinho._format_path_for_at_mention` when present.
  - `by_server` maps `server.id` to the tab number; re-registered after restart; removed on `on_exit` and `close`.
  - The `BufDelete`/`BufWipeout` callback finds the tab by `session.buf` and skips a tab with `closing = true`; `session.restart` swaps `s.buf` before deleting the old buffer, so restart does not close the tab.
  - `router.broadcast(method, params, on_written)` returns `server:broadcast(...)` only for the active tab when it is running and has a server, otherwise `false`.
  - Checks (test-runner): `check` 0 warnings / 0 errors in 211 files; `format-check` green (0 changed); `unit` (`BUSTED_SEED=12345 CI=true`) 1909 / 0 / 0 / 33 (655 s; +56, +1 pending); `integration` (Neovim 0.12.3 through `mise exec`) 35 files, 541 passed, 1 failed: only the known `claude_stub_spec` bug, whose first PATH entry this time showed `/home/phrb/workspaces/claudinho.nvim/tests/bin` (the second path of this checkout) instead of the `/mnt/data/...` path (added to the backlog entry).
- **Assumptions:** "No Claude <n>" and "tab-restart needs a tab number" are the agent's wording (the spec gives exact text only for "Claude <n> is still running" and "Claude <n> exited"); `activate` on a missing tab replies and returns `false`; the "on_post updates only its own tab" case lives in the integration spec.
- **Approved scope:** none.
- **Migrations / env vars:** none.
- **Docs pending:** `ARCHITECTURE.md` (Task 20): the `sessions.lua` registry, active tab, router, `setup_autocmds` (`ExitPre` then `VimLeavePre`), `for_client` through `server.id`, the `window.show/close/refresh` contract. `CLAUDE.md` (Task 18): `sessions.lua` in the structure list. `CHANGELOG.md` Unreleased (Task 19): internal tab registry; `selection.resend_latest`.
- **Manual checks (Task 10):** tab switching, redraw on `on_change`/`on_exit`, and a buffer wipe of a visible tab in a real window.
- **Out of scope:** luacheck on the file alone warns about an unused `context` argument at `tests/selection_test.lua:1041` (pre-existing; the project `check` is clean).

### Task 10 - Janela do Claude: layouts, winbar e statusline (done)

- **Files:**
  - New `lua/claudinho/ui/window.lua` (origin line first, upstream `lua/claudecode/terminal/native.lua`): layouts `right`, `bottom`, `float`, `tab` (invalid falls back to `right`); `show`, `hide`, `close`, `toggle`, `open`, `focus`, `ensure_visible`, `refresh`, `release`, `unlock`, `resize`, `update_title`, `setup`, `teardown`; pure `geometry()`.
  - `lua/claudinho/ui/tabbar.lua`: `render()` with no arguments reads the sessions registry, the drawn window's width (`vim.g.statusline_winid`) and `window.tab_title_max`; the pure path is unchanged.
  - `lua/claudinho/ui/status.lua`: `render()` = `text(sessions.active().data)`.
  - `lua/claudinho/sessions.lua`: `close()` calls `window.release(buf, neighbour buf)` before `session.close`; `restart()` calls `window.unlock()` first and redraws on failure; `kill_all()` calls `window.release` for the active buffer before closing the sessions (the `window.close` order is kept).
  - `lua/claudinho/types.lua`: `ClaudinhoWindowState`.
  - Tests: new `tests/unit/ui/window_geometry_spec.lua` (16: right, bottom, float centered with tabline/statusline/cmdheight, tab, unknown layout); `tests/unit/ui/status_spec.lua` (+2, `render`); new `tests/integration/window_spec.lua` (33, real Neovim: four layouts, toggle/open/hide/focus, `:q`, `<C-w>c`, `:tabclose`, tab switch, close, restart, title by OSC, `gt`, float and diff, `:q` on the last window in a child Neovim).
- **Decisions:**
  - Winbar and statusline are `%!v:lua.require'claudinho.ui.tabbar'.render()` and `%!v:lua.require'claudinho.ui.status'.render()`.
  - Splits open with `nvim_open_win({ split = "right"|"below", win = -1 })` (botright, focus unchanged). The tab layout uses `tabnew`, and its empty buffer is wiped (`bufhidden=wipe`).
  - Visibility is `nvim_win_is_valid(state.win)`; no `WinClosed` autocmd: a closed window is a hidden one, and the session stays.
  - `window.setup()` is idempotent and called lazily by `show()` and `refresh()` (so `TermRequest` is registered before the first title). It installs the click handler, links the highlights and registers `ColorScheme`, `VimResized`, `QuitPre`, `User ClaudinhoDiffOpened` and `TermRequest` in group `ClaudinhoWindow`; `teardown()` undoes it.
  - `winfixbuf` is on after every buffer set and off only during the plugin's own swap. `window.unlock()` serves `sessions.restart` (whose `set_buf` would otherwise be refused); `window.release()` frees the window before a buffer is deleted (tab close, `kill_all`).
  - `hide()` and `close()` open an empty tab first when the Claude window is the only non-float window of the only Neovim tab, so hiding never exits Neovim. In the `tab` layout, `hide` closes the Neovim tab.
  - `toggle`: window in the current Neovim tab means hide, otherwise show with focus (a window elsewhere moves here). `focus`: focused means hide, otherwise show with focus.
  - `ensure_visible()` does nothing while `hidden_by_diff` or when visible; otherwise shows without focus. Task 12/13 must point the diff's `ensure_visible` call at it.
  - Float: no border and no `style=minimal` (spec text); size from the editor area (`lines - cmdheight - tabline - statusline`). `right` and `bottom` use `floor(columns|lines * fraction)`. `diff_width` is not handled here (Task 13).
  - `startinsert` only with focus, a running session and `terminal.auto_insert ~= false`; the integration spec records `vim.cmd("startinsert")` calls instead of reading the mode (it takes effect after returning to the main loop).
  - `sessions.activate` still does not show the window; it redraws, and `refresh()` swaps the buffer and the status.
  - `nvim__redraw` in `pcall`, with a `redrawstatus!` fallback.
  - Checks (test-runner): `check` 0 warnings / 0 errors in 214 files; `format-check` green (0 changed); `unit` (`BUSTED_SEED=12345 CI=true`) 1927 / 0 / 0 / 34 (644 s; +18, +1 pending); `integration` (Neovim 0.12.3 through `mise exec`) 36 files, 574 passed, 1 failed: only the known `claude_stub_spec` bug.
  - Process note: while debugging, the agent ran a `mise exec` with `HOME=/tmp`, which left `/tmp/.local` and `/tmp/.cache` behind (cleanup left to the user).
- **Assumptions:** `toggle` from another Neovim tab (window visible elsewhere) brings the window to the current tab instead of hiding it; the float's height and its own winbar/statusline rows come from the editor area; the "key typed in an ended terminal" integration case only proves that `show(focus)` does not call `startinsert` for an exited tab (the real key behavior stays a manual check).
- **Approved scope:** none.
- **Migrations / env vars:** none.
- **Docs pending:** `ARCHITECTURE.md` (Task 20): `ui/window.lua` (layouts, state `{ win, tabpage, hidden_by_diff }`, the `show/hide/close/release/unlock/refresh` contract with sessions), the `TermRequest` title flow, `QuitPre`, `ClaudinhoDiffOpened` for the float, `winfixbuf`. `CLAUDE.md` (Task 18): `ui/window.lua`. `README.md` and `README.en.md` (Task 17): layouts, winbar, statusline, the `laststatus=3` and `laststatus=0` limitation, float without border. `CHANGELOG.md` Unreleased (Task 19): the Claude window with four layouts, tab bar in the winbar, status in the statusline.
- **Manual checks:**
  - Each `window.layout` (`right`, `bottom`, `float`, `tab`) through `:lua require('claudinho.sessions').new()` (until Task 12), then resize the terminal: the float stays centered at 80% with its statusline; light and dark colorschemes; `laststatus=3` (statusline only while focused) and `laststatus=0` (never).
  - Winbar: left click on a tab and on `+`; right and middle clicks ignored; `:set mouse=` disables clicks; shrink until titles become numbers and then `‹ ›` appear, keeping the active tab and `+`; a window narrower than the active tab plus `+`; a CJK title.
  - Colors: groups link to `TabLineSel`, `TabLine`, `WarningMsg`, `Comment`, `TabLineFill`, also after `:colorscheme <other>`.
  - Title: when Claude changes its terminal title, the tab name follows in the same redraw; a generic "Claude Code" title shows `Claude <n>`.
  - Several tabs: buffer, winbar and statusline change together; an ended tab keeps its last status and shows `[exited]`; after `/exit`, typing in the ended terminal does not enter terminal mode.
  - `:q` and `<C-w>c` on the Claude window hide it and the process keeps running; `:bwipeout` of a visible tab's buffer is refused by `winfixbuf` (confirm this is acceptable); `gt` to another tab then open moves the window there.
  - `:q` in the last editor window while Claude is open (`right` and `float`) leaves Neovim without a prompt and leaves no lock files in `~/.claude/ide`.
  - Float and diff: opening a diff hides the float; open/toggle/focus bring it back.

### Task 11 - Diff por aba (done)

- **Files:**
  - `lua/claudinho/sessions.lua`: new `gate_diff(client, params)` and a local `resume_waiting` helper; `reject_all_pending` now redraws the bar.
  - `lua/claudinho/tools/open_diff.lua`: calls `sessions.gate_diff` before `open_diff_blocking`; returns `diff.rejected_response` on `"reject"`.
  - `lua/claudinho/diff.lua`: new `M.rejected_response(tab_name)`; `_resolve_diff_as_rejected` uses it (same content).
  - Tests: new `tests/unit/diff_routing_spec.lua` (10: active and no-tab clients open at once; a background client waits, is marked and notified; opens in order on activation; reject answers `DIFF_REJECTED`; `reject_all_pending` across tabs; immediate resolve on open; tab exit drops with no answer); new `tests/integration/diff_routing_spec.lua` (4, two real tabs with one `ws_client` each: a background `openDiff` waits and opens on activation; accept/reject answers only the asking client; close-all rejects a waiting diff; `getOpenEditors` answers a background tab). Existing diff specs unchanged and green.
- **Decisions:**
  - `gate_diff` returns `"open"` or `"reject"` and yields only when the client's tab is not the active one; without a coroutine, with no owning tab, or with a closing tab it returns `"open"`.
  - The first yield makes the server register the call as deferred under `tostring(co)`. `resume_waiting` resumes waiting coroutines with `"open"` or `"reject"`; if the handler finishes on that resume (rejected, or a diff that resolved at once) it sends the response through `_G.claude_deferred_responses[tostring(co)]` with `tools.build_response`; if the handler yields again (diff open, waiting for the user), `diff.lua`'s resolution callback answers as before. A missing sender is ignored.
  - `session.close` still resumes with `"reject"` and sends nothing (the server stop drops the keys and the client is gone).
  - The pending entry's path and the notice use `params.new_file_path`; the notice is `notify.info("Claude <n>: pending diff for <path>")` with `fnamemodify(path, ":~:.")`, once per request.
  - `diff.lua` still knows nothing about tabs. The bar's diff mark already derives from `#s.pending_diffs`.
  - Rule 40 (process death discards pending diffs) was already in `session.lua`'s `handle_exit`.
  - Task 12 must call `sessions.reject_all_pending("user command")` from the new `:Claudinho close-all-diffs` (the old command in `init.lua` is not wired yet).
  - Checks (test-runner): `check` and `format-check` green; `unit` (`BUSTED_SEED=12345 CI=true`) 1937 / 0 / 0 / 35 (636 s; +10, +1 pending); `integration` (Neovim 0.12.3 through `mise exec`) 37 files, 578 passed, plus only the known `claude_stub_spec` failure.
- **Assumptions:** the pending entry's `path` is `new_file_path` (the spec does not say which).
- **Approved scope:** none.
- **Migrations / env vars:** none.
- **Docs pending:** `ARCHITECTURE.md` and `PROTOCOL.md` (Task 20): `openDiff` routing by tab (`gate_diff`, `pending_diffs`, a reject answers `DIFF_REJECTED` without a window), rules 31 to 36. `CHANGELOG.md` Unreleased (Task 19): diffs from a background tab wait until the tab is activated.
- **Manual checks:** with two tabs, a diff requested by tab 1 while tab 2 is active opens no window, tab 1 shows the diff mark, and with `notify = true` the notice appears once; switching to tab 1 opens it and clears the mark. Accept or reject it after switching to tab 2: the answer reaches only tab 1. A diff waiting in a background tab, then tab-close or close-all-diffs: rejected, no window, mark gone.

### Task 12 - Comando `:Claudinho` e fim dos `:ClaudeCode*` e dos providers (done)

- **Files:**
  - New `lua/claudinho/commands.lua` (origin line first): `:Claudinho` with 19 subcommands, completion (subcommands, tab numbers, files) and the 20-key `keymaps.preset`.
  - `lua/claudinho/init.lua`: `setup`, `send_at_mention`, `is_claude_connected`, `open_with_model`, `get_version` and the format/broadcast helpers on the active tab; `setup` starts no server and writes no lock file, enables the selection with `sessions.router`, calls `sessions.setup_autocmds()` and creates the command. `start`, `stop`, the default queue and the 15 `:ClaudeCode*` commands removed.
  - `lua/claudinho/terminal.lua`: facade over the active tab (`setup`, `get_active_terminal_bufnr`, `ensure_visible`, `open`, `send_to_terminal`). Deleted: `terminal/native.lua`, `external.lua`, `none.lua`, `owned.lua`; `terminal/paste_fix.lua` stays.
  - `lua/claudinho/sessions.lua`: `NO_TABS`, `exited_message(s)`; start/restart fallback texts. `lua/claudinho/session.lua`: every start/restart failure is `Could not start Claude <n>: <reason>` (spec messages table; the old "Cannot start ... the server did not start (...)" was 90 cells and would hit "Press ENTER").
  - `lua/claudinho/selection.lua`: no server check; send context `"Claudinho send"`. `lua/claudinho/health.lua`: one line per tab, the notifications-off line; provider and server checks removed. `lua/claudinho/types.lua`: provider interface and server state fields removed. `lua/claudinho/server/init.lua`: dead default `on_open` branch (called the removed `default_queue`) removed. `lua/claudinho/diff.lua`: comment only. `plugin/claudinho.lua`: comments only.
  - Fixtures (`fixtures/*/lua/plugins/dev-claudinho.lua`, `fixtures/repro/init.lua`, `fixtures/repro/example/README.md`) moved to `:Claudinho`. `CHANGELOG.md`: Unreleased Changed and Removed entries.
  - Tests: new `tests/helpers/active_tab.lua` (a fake active tab with a real mention queue); new `tests/unit/commands_spec.lua` (58), `keymaps_spec.lua` (11), `terminal_facade_spec.lua` (13). Ported with more cases: `init_spec` 19 -> 30, `send_text_command_spec` 4 -> 6, `add_command_spec` 33 -> 35, `terminal/send_text_spec` 18 -> 19, `health_spec` 13 -> 15. Ported with the same count: `send_command`, `tree_send_visual`, `tree_buffer_classification`, `send_complete_event`, `focus_after_send`, `at_mention_edge_cases`, `mention_queue`, `selection_test`, `diff_client_ownership`, `session_spec`, `sessions_spec`, `server/log_lines_spec` (its ports-in-use case now opens a tab). Comments and titles only: `diff_opened_handler_resolves_spec`, `diff_bulk_close_reentrancy_spec`, `visual_commands_select_mode_spec`. Integration ported: `diff_hand_over`, `select_mode_send`, `diff_close_save`, `diff_disconnect_window_lock`, `diff_window_sizes`, `selection_held`, `selection_visual_edit`, `diff_window_choice`, `loader` (only the "creates the commands" case: `:Claudinho` = 2, `:ClaudeCodeStart` = 0).
  - Deleted specs ("Testes que saem"), with their counts before deletion: `tests/unit/terminal_spec.lua` 64, `native_terminal_toggle_spec.lua` 88, `terminal/external_spec.lua` 20, `terminal/none_provider_spec.lua` 2, `focus_after_send_provider_warning_spec.lua` 9, unit `command_args_spec.lua` 9, integration `command_args_spec.lua` (1 pending under busted, 8 real cases). Unit: -192 successes, -1 pending.
- **Decisions:**
  - The spec text says 17 `:ClaudeCode*` and a 19-key preset; the explicit lists give 15 commands (`ClaudeCode`, `ClaudeCodeStart`, `Stop`, `Status`, `Send`, `TreeAdd`, `Add`, `Focus`, `Open`, `Close`, `SendText`, `DiffAccept`, `DiffDeny`, `CloseAllDiffs`, `SelectModel`) and 20 keys (`<leader>ac` toggle, `af` focus, `an` new, `al` tab-next, `ah` tab-prev, `a1`-`a9` tab 1-9, `ax` tab-close, `am` select-model, `ab` `add %`, `aa` diff-accept, `ad` diff-deny; visual `<leader>as` send). The implementation follows the lists.
  - `setup` keeps `conflict.check()` (Task 14 owns the warning) and the removed-options flow (Task 13).
  - `send_at_mention` with no tab calls `sessions.new()` and enqueues in the new tab. With an exited active tab it returns `false` plus `"Claude <n> has exited; run :Claudinho tab-restart <n>"` without notifying (the caller's `logger.error` shows it once); `send-text`, `select-model` and the facade use `notify.reply` for that text.
  - The connected-send path still goes through `M.is_claude_connected()` and `M._broadcast_at_mention()`, now on the active tab's queue (keeps the test seams).
  - The facade's `ensure_visible` calls `window.ensure_visible()`; `diff.lua` and `diff_inline.lua` are unchanged.
  - `tab`, `tab-next` and `tab-prev` call `window.show({ focus = false })` after the switch; `open` and `toggle` focus.
  - `close-all-diffs` adds `sessions.reject_all_pending("user command")` to the pending count; summaries use `notify.info`; warnings and "No Claude diffs to close" use `notify.reply`.
  - `add`, `send` and `tree-add` messages stay on the logger, renamed to "Claudinho add:" and so on; the "Added N files" summaries stay on the logger, not `notify.info`.
  - Preset keys the plugin mapped itself (same `desc`) are remapped on a second `setup` without a notice.
  - Hand-off to Task 13: with a real Claude window (`winfixwidth`, spec section 8) as the only window, the unified diff gets 40 columns instead of 53 (widths 48/70/40 vs 48/57/53). `tests/integration/diff_window_choice_spec.lua` "gives the diff a share of the screen when the Claude terminal is the only window" sets `winfixwidth = false` on the Claude window, with a comment; Task 13 (window sizes in the diff) must decide the real behavior and remove that workaround.
  - Checks (test-runner, after the fix rounds): `check` 0 warnings / 0 errors in 210 files; `format-check` green; `unit` (`BUSTED_SEED=12345 CI=true`) 1845 / 0 / 0 / 34 (678 s; 1937 + 82 new + 18 ported - 192 deleted; pending 35 - 1); `integration` (Neovim 0.12.3 through `mise exec`) 36 files, 570 passed (-8, the deleted `command_args_spec`), plus only the known `claude_stub_spec` failure. `rg -n 'ClaudeCode' lua plugin fixtures scripts`: no matches; `rg -n 'ClaudeCode' tests`: only `commands_spec.lua` (the 15 names asserted absent) and `loader_spec.lua`. `lua/claudinho/terminal/` holds only `paste_fix.lua`.
  - First gate: one unit error in `tests/unit/server/log_lines_spec.lua:175` (called `claudinho.start`), fixed by the approved port and the message change.
- **Assumptions:** see the 15/20 counts above.
- **Approved scope:** `tests/unit/diff_client_ownership_spec.lua`, `tests/integration/selection_held_spec.lua`, `tests/integration/selection_visual_edit_spec.lua`, `tests/integration/diff_window_choice_spec.lua`, `tests/integration/loader_spec.lua` (ports); `lua/claudinho/diff.lua`, `tests/unit/diff_opened_handler_resolves_spec.lua`, `tests/unit/diff_bulk_close_reentrancy_spec.lua`, `tests/unit/visual_commands_select_mode_spec.lua` (comments and titles); `lua/claudinho/server/init.lua` (dead branch); `tests/unit/server/log_lines_spec.lua` (port); `lua/claudinho/session.lua`, `tests/unit/session_spec.lua`, `tests/integration/session_spec.lua`, `tests/unit/sessions_spec.lua`, `tests/integration/sessions_spec.lua` (start-failure text to the spec). All approved by the user on 2026-11-16/17.
- **Migrations / env vars:** none.
- **Docs pending:** `README.md` and `README.en.md` (Task 17): subcommand table, preset keys, removed commands. `CLAUDE.md` (Task 18): `commands.lua`, the terminal facade and the `active_tab` helper. `ARCHITECTURE.md` and `PROTOCOL.md` (Task 20): `send_at_mention` routing, the facade, the provider removal.
- **Manual checks:**
  - `:Claudinho` with no tab starts Claude 1 and focuses the window; a second one hides it; `open`, `focus`, `hide` as in the spec table, also on a narrow terminal.
  - `:Claudinho tab 2` with no such tab and `:Claudinho tab-restart` with no number give the `[Claudinho]` error text; `:Claudinho layout` gives the unknown-subcommand error.
  - `keymaps = { preset = true }` with `<leader>ac` already mapped: that key stays yours, the other 19 work, the notice shows once with `notify = true`.
  - `:Claudinho send-text hi` submits; `:Claudinho! send-text hi` and `send-text! hi` only insert; with the tab ended: `Claude <n> has exited; run :Claudinho tab-restart <n>`.
  - `:Claudinho select-model` with no tab, a running tab and an ended tab.
  - A visual selection then `:'<,'>Claudinho send`, and `:Claudinho add %`, from a file buffer and a tree buffer.
  - `:checkhealth claudinho`: one line per tab, "No Claude tabs open" with none, the notify-off line.
  - Old `:ClaudeCode*` names give E492.
  - A tab that cannot start (command missing, every port in use) shows one line `Could not start Claude 1: <reason>` that fits the command line.
- **Out of scope:** em dashes in pre-existing comments at `lua/claudinho/tools/open_file.lua:603` and `lua/claudinho/terminal/paste_fix.lua:133` (the spec's Verification dash check covers `lua/`); to the backlog.

### Task 13 - Chaves removidas (terminal e diretório), cwd.lua e tamanhos da janela no diff (done)

- **Files:**
  - `lua/claudinho/config.lua`: the removed-keys table of section 4 (16 new rows, including the six directory keys; the old `terminal.provider = "snacks"` row is gone: `terminal.provider` is one row for any value); `without_removed_options(user_config, { notify })` returns `(config, found)` and warns only with `notify`; `auto_start`, the `terminal.provider` default and the `provider_opts` validation removed; `terminal` defaults to `{}`.
  - `lua/claudinho/init.lua`: `setup` passes `opts.notify == true` and keeps the found rows in `state.removed_found`; a comment about the removed directory keys reworded.
  - `lua/claudinho/diff.lua`: reads `window.right.width` and `window.right.diff_width` (`_resolve_split_width_percentage` kept as the test seam); resizes only for `window.layout = "right"`; after sizing a fixed-width (`winfixwidth`) Claude window in the current tab, for the `diff` phase, runs `wincmd =` so the other windows share the rest equally; a new-tab diff puts the Claude window on the right, or below (`split` + `wincmd J`) with `bottom`.
  - `lua/claudinho/health.lua`: one WARN per removed key from `state.removed_found` (the warning text without the `[Claudinho] ` prefix).
  - `lua/claudinho/types.lua`: provider, split, cwd and `auto_start` fields and aliases dropped (`ClaudinhoTerminalConfig` keeps `auto_insert` and `fix_streamed_paste`); `state.removed_found`.
  - Deleted: `lua/claudinho/cwd.lua`, `tests/unit/cwd_spec.lua` (5 cases), rule 95.
  - Tests (before -> after): `tests/unit/config_spec.lua` 30 -> 27 (the 3 `external_terminal_cmd` cases); `tests/config_test.lua` 5 -> 5; `tests/unit/removed_options_spec.lua` 29 -> 67 (16 new keys x 2, `notify` gating and found rows +4, `init.setup` +2); `tests/unit/health_spec.lua` 15 -> 17; `tests/unit/diff_auto_resize_events_spec.lua` 16 -> 21 (+2 layout, +3 fixed-width `wincmd =`); `tests/unit/diff_split_width_spec.lua` 6 -> 6 (`window.right.*`); `tests/integration/removed_options_spec.lua` 1 -> 2 (no warning without `notify`, found rows kept); `tests/integration/diff_window_choice_spec.lua` 14 -> 15 (bottom layout: Claude below the diff at full width); `tests/integration/diff_window_sizes_spec.lua` 24 -> 24. Stale `terminal` config values replaced, same counts: unit `diff_inline`, `diff_inline_quit`, `diff_keep_terminal_focus_float`, `diff_new_tab_insert_mode`, `diff_new_tab_terminal_handler`, `diff_inline_new_tab`, `diff_hide_terminal_new_tab`; integration `diff_accept_emptied_buffer`, `diff_accept_missing_final_newline`, `diff_accept_trailing_newlines`, `diff_close_save`, `diff_left_window`, `diff_quit_reject`, `diff_routing`.
  - `CHANGELOG.md`: Unreleased Changed (diff sizes, removed-key warnings, cwd) and Removed (keys, cwd module).
- **Decisions:**
  - Task 12 hand-off closed: the `winfixwidth = false` workaround in `diff_window_choice_spec` is gone (the case now asserts the Claude window keeps `winfixwidth`), and its assertion (diff at least `floor(columns/3) - 1`) is unchanged; the code fix is the `wincmd =` after sizing a fixed-width Claude window. The spec gives no widths; this is the agent's decision, to confirm with the user.
  - The removed-key notice uses `vim.notify_once` (title Claudinho, WARN), not `notify.info`, because `config.notify` is not applied yet at that point; it shows only with `notify = true`.
  - `terminal.provider` is one row without value; `snacks_win_opts` and the Phase 0 rows stay.
  - The new-tab terminal split follows `window.layout` only for `bottom` (horizontal below); `right`, `float` and `tab` use the vertical right split. Only `right` gets the diff resize.
  - `diff.setup` still accepts partial configs: a missing `window` means layout `right`, width 0.30.
  - The specs assert the exact messages of spec section 4.
  - Checks (test-runner): `check` 0 warnings / 0 errors in 208 files; `format-check` green; `unit` (`BUSTED_SEED=12345 CI=true`) 1882 / 0 / 0 / 34 (643 s; +37: -5 cwd, -3 config, +38 removed_options, +2 health, +5 auto_resize); `integration` (Neovim 0.12.3 through `mise exec`) 36 files, 572 passed (+2), plus only the known `claude_stub_spec` failure; `rg -n 'git_repo_cwd|cwd_provider' lua plugin` finds only the removed-key rows in `config.lua:137-154`.
- **Assumptions:** the `float` and `tab` layouts also get the vertical-right split in a new diff tab and no width resize ("only right" read literally); health shows the warning text without the `[Claudinho] ` prefix.
- **Approved scope:** none.
- **Migrations / env vars:** none.
- **Docs pending:** `README.md` and `README.en.md` (Task 17): removed terminal and directory keys with replacements, `window.right.width`/`diff_width`, "new tabs start in `:pwd`", the `notify` gating of the removed-key warnings, health lines. `ARCHITECTURE.md` and `CLAUDE.md` (Tasks 18 and 20): `cwd.lua` removed; the diff resizes only the `right` layout and equalizes after sizing a fixed-width window; `state.removed_found`.
- **Manual checks:**
  - `setup({ notify = true, terminal = { provider = "snacks", split_side = "left" }, cwd = "/tmp" })`: one `[Claudinho]` warning per key on the first setup, none on a second `setup()`; without `notify = true`, none.
  - `:checkhealth claudinho` with those keys: one WARN per key, with the "was removed and is ignored" text.
  - Layout `right`, a diff in the current tab with Claude as the only window (160+ columns): Claude gets `window.right.width` and the two diff windows are about equal; with `window.right.diff_width = 0.2` Claude shrinks to 20% while the diff is open and returns after accept or reject.
  - Layout `bottom`: the diff does not resize Claude; with `open_in_new_tab = true` Claude sits below the diff in the new tab at full width.
  - Layouts `float` and `tab`: a diff opens as before (the float hides while a diff is open).
  - A tab started after `:cd` elsewhere uses the new `:pwd`.
- **Out of scope:** `tests/minimal_init.lua:73` still passes the removed `auto_start = false` (harmless, warns only with `notify`) and `tests/selection_test.lua:2982` has a comment about `terminal.provider = "none"`; unit mocks in `send_command_spec`, `focus_after_send_spec`, `send_complete_event_spec`, `add_command_spec`, `tree_send_visual_spec`, `tree_buffer_classification_spec` and `conflict_spec` stub `without_removed_options` with one return value and `auto_start` (they pass but do not mirror the `(config, found)` signature). To the backlog.

### Task 14 - claudecode.nvim vira aviso (done)

- **Files:**
  - `lua/claudinho/conflict.lua`: `MESSAGE` is the section 4 text; `check()` replaced by `warn(notify_enabled)`, which returns `detected()` and calls `vim.notify_once(MESSAGE, WARN, { title = "Claudinho" })` only when `notify_enabled == true`.
  - `plugin/claudinho.lua`: no conflict check; the loader goes on to the auto-setup.
  - `lua/claudinho/init.lua`: `setup` calls `conflict.warn(opts.notify == true)` and continues.
  - `lua/claudinho/health.lua`: new `check_conflict()`, always run (with or without `setup()`): WARN `claudecode.nvim is loaded (g:loaded_claudecode is set)` or `claudecode.nvim is installed (lua/claudecode/init.lua is on the runtimepath)`, with the section 11 advice; the Phase 0 error branch removed from `check_setup`.
  - `CHANGELOG.md`: one Unreleased Changed entry.
  - Tests (before -> after): `tests/unit/conflict_spec.lua` 8 -> 10 (`warn` cases, silent without `notify`, setup continues); `tests/unit/plugin_loader_spec.lua` 7 -> 6 (the "warns once and stops" and "does not repeat" cases became one: the loader does not stop, shows no warning, goes on to the auto-setup); `tests/unit/health_spec.lua` 17 -> 18 (two WARN cases: `g:loaded_claudecode` without setup, runtimepath next to a healthy setup); `tests/unit/init_spec.lua` 30 -> 30 (conflict stub gains `warn`; "does nothing when claudecode.nvim is loaded" replaced by "sets up normally when claudecode.nvim is detected, passing the notify flag to the warning"); `tests/integration/loader_spec.lua` 3 -> 3 (`setup({ notify = true })`, "is also installed", `:Claudinho` = 2, `:ClaudeCodeStart` = 0, one warning, `init=true` in the runtimepath case).
- **Decisions:**
  - `conflict.warn` uses `vim.notify_once` with the flag from `setup` (not `notify.info`), because `config.notify` is not applied yet when `setup` runs (as the Task 13 removed-key warnings).
  - `check_conflict()` reads `vim.g.loaded_claudecode` first, so "loaded" wins over "installed" when both hold; `detected()` is unchanged.
  - Checks (test-runner): `check` 0 warnings / 0 errors in 208 files; `format-check` green; `unit` (`BUSTED_SEED=12345 CI=true`) 1884 / 0 / 0 / 34 (632 s; +2); `integration` (Neovim 0.12.3 through `mise exec`) 36 files, 572 passed, plus only the known `claude_stub_spec` failure.
- **Assumptions:** none.
- **Approved scope:** `tests/unit/init_spec.lua` (conflict stub and the refusal case), approved by the user on 2026-11-17.
- **Migrations / env vars:** none.
- **Docs pending:** `README.md` and `README.en.md` (Task 17): "Coming from claudecode.nvim" says both run and removing claudecode.nvim is recommended (rule 33). `CLAUDE.md` (Task 18): the Vision line "The plugin refuses to run when claudecode.nvim is loaded" is now wrong. `ARCHITECTURE.md` and `PROTOCOL.md` (Task 20): any mention of the Phase 0 refusal.
- **Manual checks:** with claudecode.nvim installed next to Claudinho, `:Claudinho` works and `:checkhealth claudinho` shows the WARN with the advice, with and without `setup()`; with `notify = true` the warning shows once per start, with `notify = false` none.

## Run 2026-11-17

Mode: tasks selected by the user (Task 23 only), same gate policy as the earlier runs. The run state `.claude/runs/base-ui.json` was missing and was created for this run. Toolchain reinstalled by the user before the checks (`mise install`, `mise run setup`, `base-devel` on Void Linux); plenary installed at the CI SHA with the user's approval.

### Task 23 - Layout `left` (done)

- **Files:**
  - `lua/claudinho/config.lua`: default `window.left = { width = 0.30, diff_width = nil }`, `"left"` in `VALID_LAYOUTS`; `window.right` and `window.left` validated by one shared loop, with the exact messages, under any layout.
  - `lua/claudinho/types.lua`: layout union gains `"left"`; new `window.left` field.
  - `lua/claudinho/ui/window.lua`: `LAYOUTS` gains `left`; `geometry("left")` from `window.left.width`; `open_window` splits to the left edge (`split = "left", win = -1`) with `winfixwidth`.
  - `lua/claudinho/diff.lua`: `sized_side()` reads `window.left` or `window.right`; the resize gate accepts `right` and `left`; the new-tab terminal uses `wincmd H` then `wincmd l` for `left`; comments updated.
  - `CHANGELOG.md`: Added entry for `left`; two Changed lines mention `left`.
  - `fixtures/{netrw,nvim-tree,oil,mini-files}/lua/plugins/dev-claudinho.lua`: the commented window block lists the five layouts and `window.left`.
  - Tests: `tests/unit/config_spec.lua` (43), `tests/config_test.lua` (6), `tests/unit/ui/window_geometry_spec.lua` (22), `tests/unit/diff_split_width_spec.lua` (10), `tests/unit/diff_auto_resize_events_spec.lua` (23), `tests/unit/diff_new_tab_terminal_handler_spec.lua` (9), `tests/integration/window_spec.lua` (39), `tests/integration/diff_window_choice_spec.lua` (21).
- **Decisions:**
  - Removed-key messages untouched; they still point to `window.right.*`.
  - The `left` diff-width integration cases use `diff_opts.layout = "vertical"`: a unified diff with an editor window present does not resize Claude, with `right` too (pre-existing, to the backlog).
  - `window_spec` checks full height through `winlayout` (Claude is the first leaf of a single top-level row) plus equal heights and the same row as the editor windows.
  - Fix round 1 (quality-fixer): `window_spec` nested `assert(window.win())` inside `nvim_win_get_width`; luassert's `assert` returns several values ("Expected 1 argument"). Now bound to a local first, like the rest of the file.
  - Checks (test-runner): `check` 0 warnings / 0 errors in 208 files; `format-check` green; the 6 unit files under busted green; `window_spec` 39 / 0 and `diff_window_choice_spec` 21 / 0 (Neovim 0.12.3 through `mise exec`, plenary 74b06c6).
- **Assumptions:** the new-tab `diff_width` test reads the terminal width at `floor(columns * 0.20)` after open.
- **Approved scope:** none.
- **Migrations / env vars:** none (new config keys `window.left.width`, `window.left.diff_width`).
- **Docs pending:** `README.md` and `README.en.md` (Task 17): layout `left`, `window.left.width`/`diff_width`, migration from `terminal.split_side = "left"`. `CLAUDE.md`, `ARCHITECTURE.md`, `PROTOCOL.md` (Tasks 18 and 20): `left` in the window and diff sections.
- **Manual checks:** `window.layout = "left"` with two vertical editor splits (column 0, full height, `floor(columns * 0.30)`, fixed width); nvim-tree fixture with the explorer opened before and after Claude, and hide + open; a diff with `window.left.diff_width` (shrinks, returns after accept or reject); `open_in_new_tab = true` (terminal on the left edge of the new tab); an invalid `window.left.*` under `right` and `left`.
- **Out of scope:** unified diff with an editor window present does not resize the Claude window to `diff_width` (also with `right`). To the backlog.
- **Review (code-reviewer):** ship; fixed in the same round: a geometry case "right ignores window.left.width", `resolve_split_width_percentage` local renamed to `side`, `sized_side` uses `window_layout()`, the `window.right`/`window.left` validation is a local function `normalize_side` (as section 15 says).
- **Final gate (test-runner):** `check` 0 / 0 in 208 files; `format-check` green; `unit` (`BUSTED_SEED=12345 CI=true`) 1917 / 0 / 0 / 34 (514 s); `integration` (Neovim 0.12.3) 36 files, 583 passed, 1 failed: `tests/integration/session_spec.lua:84`, which reads `CLAUDINHO_PORT` inherited from the caller's shell (passes 9 / 0 with the `CLAUDINHO_*` vars unset). Registered in `docs/backlog/bugs/2026-11-17-session-spec-depends-on-caller-env.md`. The known `claude_stub_spec` failure passed in this run.
- **Backlog:** `docs/backlog/bugs/2026-11-17-unified-diff-does-not-resize-claude-window.md` (low), `docs/backlog/bugs/2026-11-17-session-spec-depends-on-caller-env.md` (medium).

### Task 15 - Critérios de sucesso como testes de integração (done)

- **Files:**
  - `tests/helpers/criteria.lua`: shared helper; the real `require("claudinho").setup` with the stub by absolute path (`tests/bin/claude`), option `claude_dir_in_home`, tree/SHA snapshots and WebSocket message waiters.
  - `tests/helpers/criteria_exit_child.lua`: child Neovim script (three stub tabs, a pending diff, exit command driven by files).
  - `tests/integration/criteria_tabs_ws_spec.lua` (4): selection, current selection on tab switch, @-mention, external client drops with its tab.
  - `tests/integration/criteria_cycles_spec.lua` (4): 10 cycles each of hide/open, toggle, tab switching and layout changes (right, bottom, float, tab, left).
  - `tests/integration/criteria_exit_spec.lua` (3): `:qa`, `:wqa` and `:q` on the last window, in a child Neovim.
  - `tests/integration/criteria_isolation_spec.lua` (3): SHA of `HOME` and the project `.claude/` unchanged, a foreign lock kept, plugin env only in tab processes.
  - `lua/claudinho/sessions.lua`: the `ExitPre` handler in `setup_autocmds` also calls `jobstop` on every tab's job after rejecting the diffs; tabs stay registered and `VimLeavePre` is unchanged (approved scope, see below).
  - `tests/unit/sessions_spec.lua`: case "ExitPre stops the process of every tab with a job". `tests/integration/sessions_spec.lua`: case "ExitPre stops the processes of the tabs, so :wqa finds no running job".
- **Decisions:**
  - The specs never use a bare `claude`, so the `claude_stub` PATH bug cannot affect them; the child Neovim runs with `clear_env` and gets only `PATH`, `HOME`, `CLAUDE_CONFIG_DIR`, `TMPDIR`, `XDG_*` and `CLAUDINHO_*`.
  - Fresh `claudinho.*` modules per test and full teardown (`kill_all`, `selection.disable`, `window.teardown`, augroup).
  - The selection is triggered with `selection.update_selection()` after moving the cursor, not through the debounce autocmds.
  - `criteria_cycles` also cycles the layout: the plan criterion mentions layout, the spec table does not.
  - `criteria_isolation` puts `CLAUDE_CONFIG_DIR` at `HOME/.claude`, so the snapshot covers `settings.json`, `.claude.json`, `ide/` with a foreign lock (a living pid) and the project `.claude/`; it clears `CLAUDE_CODE_SSE_PORT`, `CLAUDINHO_PORT` and `CLAUDINHO_TOKEN` around each test (see the session-spec-depends-on-caller-env bug).
  - The `:wqa` scenario leaves a modified file buffer so `:wqa` has something to write; the check for 0 settings files looks in a private `TMPDIR`.
  - `ExitPre` stops the jobs but does not close the sessions: the existing case that `ExitPre` leaves sessions alive still holds. A late job-exit event may show a "Claude n exited" notice at exit (harmless).
- **Assumptions:** the half of the criterion about an external claude not connecting by itself needs the real CLI; it stays in manual scripts 10 and 18.
- **Approved scope:** `lua/claudinho/sessions.lua`, `tests/unit/sessions_spec.lua`, `tests/integration/sessions_spec.lua` (2026-11-17, user). Defect found by `criteria_exit_spec`: with a running tab, `:wqa` stopped with `E948: Job still running (add ! to end the job)` and Neovim stayed open (rule 46), because the tab jobs were killed only on `VimLeavePre`, after Neovim's own job check. Confirmed in plain Neovim 0.12.3: an `ExitPre` autocmd that calls `jobstop` makes the same `:wqa` exit 0.
- **Migrations / env vars:** none.
- **Docs pending:** `ARCHITECTURE.md` (Task 20): `ExitPre` rejects diffs and stops the tab processes, `VimLeavePre` closes the sessions. `CHANGELOG.md` Unreleased (Task 19): fix for `:wqa` with running Claude tabs (E948).
- **Manual checks:** `:wqa` in a real Neovim with 2 or more Claude tabs and a modified buffer: no E948, the buffer is written, no claude process or lock file left.
- **Out of scope:** none.
- **Checks (test-runner):** `check` 0 / 0 in 216 files; `format-check` green (296 files, 0 changed); `unit` 1927 / 0 / 0 / 39 (640 s); `integration` (Neovim 0.12.3) 601 passed, 1 failed: `tests/integration/claude_stub_spec.lua:14`, pre-existing and registered (`docs/backlog/bugs/2026-11-16-claude-stub-path-first-entry-integration.md`). Criteria times in isolation: cycles 0.3 s, exit 0.4 s, isolation 0.9 s, tabs_ws 3.4 s.

### Task 16 - Linhas de origem nos módulos (done)

- **Files:**
  - 34 modules under `lua/claudinho/` (`*.lua`, `server/`, `terminal/`, `tools/`) and `plugin/claudinho.lua`: one added first line each, `-- Origin: coder/claudecode.nvim@d1237072, <upstream path> (MIT, see LICENSE)`; `git diff --numstat` is 1 / 0 for every file. `commands.lua`, `mention_queue.lua`, `session.lua` and `ui/window.lua` already had the line from earlier tasks (38 tagged in all); the 9 new modules of section 13 have none.
  - `tests/unit/provenance_spec.lua` (new): checks the exact first line of the 38 tagged files, no line on the 9 new modules, and that every module under `lua/claudinho/` is in one of the two lists.
- **Decisions:** upstream paths taken from a local checkout of coder/claudecode.nvim (file names only); `terminal.lua` maps to `lua/claudecode/terminal.lua`, `terminal/paste_fix.lua` and the 12 `tools/*.lua` to the same relative path upstream, `plugin/claudinho.lua` to `plugin/claudecode.lua`.
- **Assumptions:** files that start with `---@brief [[` or `---@meta` (including `types.lua`) get the origin line above it, as section 13 says (first line).
- **Approved scope:** none.
- **Migrations / env vars:** none.
- **Docs pending:** none.
- **Manual checks:** none.
- **Out of scope:** none. A later new module under `lua/claudinho/` must be classified in the provenance lists, or `provenance_spec` fails.
- **Checks (test-runner):** `check` 0 / 0 in 217 files; `unit` 1975 / 0 / 0 / 39 (633 s); `integration` (Neovim 0.12.3) 601 passed, only the pre-existing `claude_stub_spec.lua:14` failed. `format-check` first failed on this log (an unquoted `claude_stub` in the Task 15 block, which prettier read as emphasis); fixed by the main session, then green twice.
