# Diff unified nao redimensiona a janela do Claude para diff_width

- **Status:** Open
- **Reported:** 2026-11-17
- **Severity:** low
- **Environment:** local
- **Source:** agent run: base-ui, task 23, agent lua
- **Related:** docs/features/base-ui/

## Evidence

Spec temporario (layout `right`): abrir o terminal, `wincmd p`, `open_diff` com `diff_opts.layout = "unified"`. O terminal ficou com 48 colunas em vez de 32 (`window.right.diff_width`). Codigo relacionado: `lua/claudinho/diff.lua` (`resize_terminal_for_diff`, caminho unified em torno de `diff_data.layout == "unified"`).

## Steps to reproduce

1. Configurar `diff_opts.layout = "unified"` e ter uma janela de editor aberta.
2. Abrir o terminal do Claude e voltar ao editor (`wincmd p`).
3. Abrir um diff.

## Expected behavior

A janela do Claude passa a `window.right.diff_width` (ou `window.left.diff_width`).

## Actual behavior

A janela mantem a largura anterior (48 em vez de 32). Ocorre tambem com layout `right`, entao e anterior a Task 23.

## Root cause

Nao diagnosticado ainda.

## Fix

Nao diagnosticado ainda.
