# Esc após `:Claudinho send` pode chegar à TUI do Claude (não verificado)

- **Status:** Open
- **Reported:** 2026-11-18
- **Severity:** low
- **Environment:** local
- **Source:** agent run: base-ui, review, code-reviewer
- **Related:** feature base-ui; `lua/claudinho/commands.lua`

## Evidence

`lua/claudinho/commands.lua:267-276`. NÃO VERIFICADO: precisa de reprodução antes de qualquer outra coisa. Pré-existente, movido sem alteração.

## Steps to reproduce

Hipótese, a confirmar:

1. Sem abas (o send cria uma via `sessions.new`) ou com `focus_after_send`, rode `:Claudinho send`.
2. O send foca a janela do Claude e entra em insert.
3. Observar se o `<Esc>` alimentado com modo 'i' chega à TUI.

## Expected behavior

O Esc só sai do insert do Neovim e não afeta o Claude.

## Actual behavior

Possível: o Esc chega à TUI e interrompe um turno ou dispensa o prompt de confiança da pasta. Não confirmado.

## Root cause

Não diagnosticada ainda.

## Fix

Não corrigido.
