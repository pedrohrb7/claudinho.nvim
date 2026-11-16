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
