# Regra 30: seleção mais recente não é reenviada a aba nova ou reiniciada

- **Status:** Open
- **Reported:** 2026-11-18
- **Severity:** medium
- **Environment:** local
- **Source:** agent run: base-ui, review, code-reviewer; o usuário decidiu registrar para depois
- **Related:** feature base-ui, plan rule 30; `lua/claudinho/sessions.lua`, `lua/claudinho/mention_queue.lua`

## Evidence

`lua/claudinho/sessions.lua:169-182`; `lua/claudinho/mention_queue.lua` (`on_open` só descarrega a fila de menções). Não reproduzido.

## Steps to reproduce

1. Tenha uma seleção ativa no editor.
2. Crie ou reinicie uma aba do Claude (ela ainda não conectou).
3. A aba vira ativa.

## Expected behavior

A seleção mais recente chega ao Claude da aba nova assim que ele conecta (se a regra 30 cobrir abas novas).

## Actual behavior

O reenvio ocorre ao ativar a aba, quando o Claude ainda não conectou: o broadcast não alcança ninguém e nada reenvia no handshake.

## Root cause

Provável: `set_active` reenvia a seleção antes da conexão; `on_open` não reenvia.

## Fix

Não corrigido.

Questão aberta (usuário): a regra 30 cobre abas novas/reiniciadas? Se sim, `on_open` também deve reenviar a seleção mais recente.
