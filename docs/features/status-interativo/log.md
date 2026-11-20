# Implementation log - status-interativo

<!-- Written by /implement only, append-only. One "Run" section per /implement run and one block per task, filled from the agents' YAML reports. The stack agents read this file before coding and follow the decisions recorded here; never re-decide something already logged without a scope request. -->

## Run 2026-11-20

Mode: no `--step` (pause only on blockers, scope requests, user tasks and questions). No commit until Task 16 (spec, Implementation order). Spec approved by the user on 2026-11-20.

### Task 1 - Linha de base de testes e cobertura (done)

- **Files:** none in the repo (`luacov.stats.out` rewritten by the run, gitignored).
- **Decisions:**
  - Baseline on `HEAD` `a7f6b5a`, Neovim 0.12.3 from mise, `BUSTED_SEED=12345 CI=true`.
  - `check`: 0 warnings, 0 errors in 217 files. `format-check`: pass (308 files, 0 changed).
  - `unit`: 1992 successes, 0 failures, 0 errors, 39 pending (integration specs), 735.7 s.
  - `integration` (0.12.3): 41 files, 614 passed, 2 failed, 0 errors. Both failures come from the environment the check ran in (inside a Claude Code shell), not from the code:
    - `tests/integration/claude_stub_spec.lua:14` "the stub claude on PATH is the first PATH entry": expected `/mnt/data/workspaces/claudinho.nvim/tests/bin`, got `/home/phrb/workspaces/claudinho.nvim/tests/bin` (the repo is reached through two paths, the test compares unresolved paths).
    - `tests/integration/session_spec.lua` "session gives the process the port and the token of its own tab, and not vim.env": `vim.env.CLAUDE_CODE_SSE_PORT` is `38525`, inherited from the Claude Code shell (confirmed: the shell has `CLAUDE_CODE_SSE_PORT=38525`).
      These are the comparison baseline for later gates; reported as out of scope (test isolation from the ambient environment).
  - `claude --version`: 2.1.329 (Claude Code). The spec measured 2.1.328; fixtures stay under `tests/fixtures/tui/2.1.328/` for the measured screens (Task 2), new captures go under the installed version (Task 3).
  - Coverage total 90.20%. Per file (%): commands 81.37, config 99.66, conflict 94.12, diff 98.90, diff_inline 87.16, health 98.92, init 91.10, integrations 65.18, lockfile 83.11, logger 89.47, mention_queue 98.10, notify 100, selection 93.00, server/client 97.28, server/frame 96.95, server/handshake 85.11, server/http 95.83, server/init 93.55, server/mock 66.94, server/tcp 96.68, server/utils 86.60, session 98.87, session_settings 89.13, sessions 98.26, sources/relay 59.68, sources/session_data 95.24, terminal 100, terminal/paste_fix 97.37, tools/check_document_dirty 100, tools/close_all_diff_tabs 100, tools/close_tab 96.15, tools/get_current_selection 98.18, tools/get_diagnostics 97.56, tools/get_latest_selection 100, tools/get_open_editors 95.52, tools/get_workspace_folders 100, tools/init 90.48, tools/open_diff 100, tools/open_file 97.30, tools/save_document 100, ui/status 100, ui/tabbar 98.73, ui/window 43.30 (most of it is covered by integration specs, not by the unit run), utils 95.74, visual_commands 55.82.

### Task 5 - Limites de uso e modo vim no JSON da statusline (done)

- **Files:** `lua/claudinho/sources/session_data.lua`, `lua/claudinho/types.lua`, `tests/unit/sources/session_data_spec.lua`, `tests/fixtures/claude/statusline_rate_limits_both.json`, `statusline_rate_limits_one.json`, `statusline_rate_limits_empty.json`, `statusline_rate_limits_wrong_types.json`, `statusline_vim_normal.json`.
- **Decisions:**
  - `ClaudinhoUsageWindow` (`{ used, resets_at? }`) and `ClaudinhoRateLimits` are declared in `types.lua` (spec section 0). `ClaudinhoStatuslineData` stays in `session_data.lua`, where it already lived, with the new `rate_limits` and `vim_mode` fields; later tasks reference these class names.
  - `rate_limits(t)` returns nil for a non-table, an array, or an empty table without the `vim.empty_dict()` metatable (compared with `getmetatable(vim.empty_dict())`); it returns `{}` for a marked empty dict or when no window is usable. A window with a valid `used_percentage` and a bad `resets_at` is kept, without `resets_at`.
  - The old `statusline_wrong_types` case still gives `{}` (absent keys do not appear).
- **Assumptions:** the busted decoder (`tests/busted_setup.lua`) does not mark empty objects, so `statusline_rate_limits_empty.json` gives nil in the unit run; the `{}` result is tested with a stubbed `vim.empty_dict`. Real Neovim marks `{}`, so the fixture gives `{}` there.
- **Checks:** `session_data_spec` 39 successes, 0 failures; `check` 0 warnings; treefmt on the touched files clean.

### Task 2 - Fixtures de tela medidas e script de captura (done)

- **Files:** `scripts/dump_tui_screen.lua`, `tests/fixtures/tui/2.1.328/{start_auto,start_no_suggestion,manual,accept_edits,plan,typed_text,multiline,slash_menu,empty_after_esc,ctrl_c,effort_picker,model_picker,bypass_accept}.txt`.
- **Decisions:**
  - The fixtures are built from the section 11 excerpts, as the spec asks; the mode lines come from F4. Rule lines are 80 columns of U+2500; the header item `● high · /effort` is right-aligned to column 78. Trailing spaces are trimmed except on the U+00A0 prompt lines (`empty_after_esc` keeps them). `multiline`, `slash_menu`, the pickers and `bypass_accept` are partial screens, as in the spec. 11 fixtures carry U+00A0 after `❯`; `bypass_accept`, `effort_picker` and `model_picker` correctly carry none.
  - Deviation from the spec's Done when: `:luafile` takes no arguments (checked on 0.12.3: `:luafile a.lua foo` gives E5112, "cannot open a.lua foo"). The script reads the name from the chunk argument (`:lua loadfile("scripts/dump_tui_screen.lua")("<name>")`) and, without one, asks for it with `vim.fn.input` (empty answer cancels). The header comment documents both ways.
  - The version comes from the x.y.z in `<terminal_cmd or claude> --version`; trailing blank lines of the buffer are dropped; an existing file is never overwritten; nothing is sent to the terminal.
- **Checks:** `check` 0 warnings; treefmt clean on the script and the fixtures; luacheck on the script clean. The script was not run (needs a real session); Task 3 exercises it.

### Task 6 - Valor único de uso e relógio de reset (done)

- **Files:** `lua/claudinho/usage.lua` (new), `tests/unit/usage_spec.lua` (new, 13 cases).
- **Decisions:**
  - `ClaudinhoUsageValue` (`{ five_hour?, seven_day? }`) is declared in `usage.lua`; `types.lua` unchanged (Task 5 already holds `ClaudinhoUsageWindow` and `ClaudinhoRateLimits`).
  - `update(nil)` returns false and keeps the value (an absent `rate_limits` does not change it); `update({})` clears the windows and returns true. `update` copies the windows; `changed` compares `used` and `resets_at` of each window.
  - `windows(now)` only filters, never mutates. The tick removes expired windows from `M.state.value`, schedules `require("claudinho.ui.window").refresh()` only when a window expired, and stops and closes the timer when no future reset is left. The timer is not armed when every `resets_at` is already past.
  - Test seams: `M.now()`, `M.new_timer()`, `M.TICK_MS = 500`. Nothing goes to log or disk (`usage.lua` does not require the logger).
  - Not wired yet: `usage.update` from `session.lua` and `usage.stop()` on `VimLeavePre` (Task 8).
- **Checks:** `usage_spec` 13 successes, 0 failures; `check` 0 warnings (219 files); treefmt clean on both files.

### Task 7 - Statusline: regiões, uso, cores e largura (done)

- **Files:** `lua/claudinho/ui/status.lua`, `tests/unit/ui/status_spec.lua` (40 cases).
- **Decisions:**
  - Added `items`, `percent`, `level`, `format_reset`, `layout`, `build`, `setup_highlights`, `MIN_GAP`, `DAYS`, `MONTHS`, `HIGHLIGHTS`, `CLICK_FUNC`. `M.text` is unchanged (base-ui cases still pass); `render` builds from the active tab, `usage.windows` and the window width (`vim.o.columns` with `laststatus=3`, otherwise `nvim_win_get_width(vim.g.statusline_winid or 0)`).
  - Left for Task 11 (its Files include `status.lua`): `M.click`, `install_click_handler`, `left_mode` and the `ModeChanged` autocmd. `M.CLICK_FUNC = "ClaudinhoStatusClick"` is already used in the left `%N@v:lua.ClaudinhoStatusClick@` regions; until Task 11 installs the handler, a click there would call an undefined global (temporary, no commit before Task 16). `window.lua` must call `status.setup_highlights()` (Task 11).
  - `layout(left_width, usage, width, now)` returns a list of `{ text, level }`. Variant 3 keeps the first present item without a time, so with only `7d` present it goes from variant 2 straight to nothing. A nil width means no limit; a nil `now` defaults to `os.time()`. Widths via `vim.fn.strdisplaywidth`.
  - Colored items are `%$Group$text%*`; the separator between usage items stays uncolored. Groups `ClaudinhoUsageWarn` and `ClaudinhoUsageError` link to theme groups.
  - `format_reset` uses no `%a`/`%b` (own `DAYS`/`MONTHS`), so it does not depend on the locale; tested with `TZ` switched through LuaJIT ffi (America/Sao_Paulo, America/New_York) and `LC_TIME` switched (only `en_US.utf8` and `C` exist on this machine).
- **Docs pending:** README pt/en (usage format, time formats, 80%/95% thresholds, highlight groups) - Task 13.
- **Checks:** `status_spec` 40 successes, 0 failures; `check` 0 warnings; treefmt clean.
