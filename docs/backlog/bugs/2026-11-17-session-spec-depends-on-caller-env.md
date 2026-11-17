# Teste session_spec depende do ambiente de quem o executa (CLAUDINHO_PORT herdado)

- **Status:** Open
- **Reported:** 2026-11-17
- **Severity:** medium
- **Environment:** local (Neovim 0.12.3), shell com `CLAUDINHO_PORT=36464` herdado
- **Source:** agent run: base-ui, Task 23 (gate final), test-runner
- **Related:** `docs/features/base-ui/`; `scripts/run_integration_tests_individually.sh`; `tests/integration/session_spec.lua`

## Evidence

- `tests/integration/session_spec.lua:84`, teste "session gives the process the port and the token of its own tab, and not vim.env", falha em `assert.is_nil(vim.env.CLAUDINHO_PORT)` quando o runner roda a partir de um shell que já tem `CLAUDINHO_PORT` definido (valor herdado 36464, por exemplo ao rodar a suíte de uma sessão do Claude Code dentro de um Neovim com claudinho).
- Com as variáveis `CLAUDINHO_*` e `CLAUDE_CODE_SSE_PORT` removidas do ambiente, o arquivo passa (9 passaram, 0 falhas, 0 erros).
- Não é causado pela Task 23 (arquivos não alterados).

## Steps to reproduce

1. Em um shell com `CLAUDINHO_PORT=36464` exportado, rodar `./scripts/run_integration_tests_individually.sh` (ou o arquivo `session_spec.lua` com o ambiente do runner).
2. Ver a falha em `session_spec.lua:84`.

## Expected behavior

O resultado não depende do ambiente do chamador: o runner (ou o spec) isola as variáveis `CLAUDINHO_*` e `CLAUDE_CODE_SSE_PORT`.

## Actual behavior

A asserção `assert.is_nil(vim.env.CLAUDINHO_PORT)` falha porque o valor é herdado do shell.

## Root cause

Provável: o runner não limpa as variáveis `CLAUDINHO_*` e `CLAUDE_CODE_SSE_PORT` do ambiente, e o spec assume que `vim.env.CLAUDINHO_PORT` começa vazio. Direção: o runner faz `unset` delas, ou o spec limpa/restaura as variáveis em `before_each`/`after_each`.

## Fix

Não corrigido.
