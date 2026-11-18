# QuitPre fecha a janela do Claude antes da checagem de alterações (E37)

- **Status:** Open
- **Reported:** 2026-11-18
- **Severity:** low
- **Environment:** local
- **Source:** agent run: base-ui, review, code-reviewer (re-review); pré-existente
- **Related:** feature base-ui; `lua/claudinho/ui/window.lua`

## Evidence

`lua/claudinho/ui/window.lua:499-508`. Não reproduzido (revisão de código).

## Steps to reproduce

1. Deixe só uma janela de editor, com buffer modificado, e a janela do Claude aberta.
2. Rode `:q`.

## Expected behavior

O `:q` cancelado por E37 mantém a janela do Claude visível.

## Actual behavior

O `:q` é cancelado (E37), mas a janela do Claude já foi fechada; a aba continua rodando, oculta.

## Root cause

Provável: o handler de QuitPre fecha a janela antes de o Neovim checar alterações.

## Fix

Não corrigido.
