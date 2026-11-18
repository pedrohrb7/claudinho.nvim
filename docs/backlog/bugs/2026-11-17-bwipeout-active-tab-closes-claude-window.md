# `:bwipeout!` da aba ativa com aba vizinha deixa a janela do Claude fechada

- **Status:** Open
- **Reported:** 2026-11-17
- **Severity:** medium
- **Environment:** local, Neovim da mise
- **Source:** agent run: found during the review of the E937 fix (fix-bug run); pre-existing, not caused by that fix
- **Related:** feature base-ui, plan rule 44 (closing a tab makes the next higher tab active, else the next lower, and the window stays open while tabs remain); close path from the BufDelete/BufWipeout handler in `lua/claudinho/sessions.lua`; see also [E937](2026-11-17-bufwipeout-e937-on-claude-exit.md)

## Evidence

Observed in review of the E937 fix; no command output recorded. Code path: `setup_autocmds` handler in `lua/claudinho/sessions.lua` calling `M.close(n)`.

- Visto de novo / caso relacionado, NÃO VERIFICADO (2026-11-18, review, code-reviewer): `BufWipeout` da aba ativa com vizinha que tem diffs em espera executa close -> set_active -> open_pending -> open_diff_blocking (cria splits e buffers) dentro do autocmd de BufWipeout; o Neovim pode recusar mudanças de layout ali (estilo E1159). Evidência: `lua/claudinho/sessions.lua:519-523`. Precisa de reprodução.

## Steps to reproduce

1. Open two Claude tabs.
2. With the second (active) tab shown, run `:bwipeout!` on its terminal buffer.

## Expected behavior

The tab closes and the Claude window shows the neighbour tab (plan rule 44).

## Actual behavior

The tab closes, but the Claude window ends up closed instead of showing the neighbour tab.

## Root cause

Not diagnosed yet.

## Fix

Not fixed yet.
