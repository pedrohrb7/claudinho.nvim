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
