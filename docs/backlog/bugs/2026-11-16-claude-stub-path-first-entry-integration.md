# Teste de integração claude_stub "is the first PATH entry" falha no runner completo

- **Status:** Open
- **Reported:** 2026-11-16
- **Severity:** medium
- **Environment:** local (Neovim 0.12.3, mise 2026.10.17 em `/usr/bin/mise`)
- **Source:** agent run: base-ui, Task 5 gate, test-runner
- **Related:** `docs/features/base-ui/`; `tests/minimal_init.lua`; `scripts/run_integration_tests_individually.sh`

## Evidence

- `tests/integration/claude_stub_spec.lua:13` ("is the first PATH entry") afirma que o diretório de `tests/bin/claude` é igual à primeira entrada de `vim.env.PATH`. `tests/minimal_init.lua` prepende `tests/bin` ao PATH, uma única vez.
- `mise exec -- ./scripts/run_integration_tests_individually.sh`: 3 de 3 execuções completas em 2026-11-16 falharam (525 passaram, 1 falhou), inclusive uma em `HEAD` (`19c7974`) sem alterações na working tree.
- O mesmo comando por arquivo do runner (mesmos VIMINIT, CLAUDINHO_MINIMAL_INIT e diretórios XDG temporários), isolado, passa 4 de 4, com e sem `mise exec`.
- Passou no runner completo nos gates das Tasks 1-4 do base-ui em 2026-11-15 (526 passaram).
- O runner guarda só o final da saída: o valor de PATH da asserção que falhou não foi capturado.
- Mudou entre os dois dias: mise reinstalado, `mise install --locked` e `mise run setup` refeitos, plenary reinstalado no SHA do CI (74b06c6c75e4eeb3108ec01852001636d85a932b). Sob `mise exec`, o PATH começa com `.luarocks/bin`, `fixtures/bin` e os diretórios de instalação do mise.
- `claude_stub_spec.lua` ordena primeiro em `tests/integration` (provavelmente o primeiro arquivo executado; inferido, não observado).

## Steps to reproduce

1. `mise exec -- ./scripts/run_integration_tests_individually.sh` (Neovim 0.12.3).
2. Ver o resumo: 1 falha em `claude_stub_spec.lua` "is the first PATH entry".

## Expected behavior

O teste passa: a primeira entrada de `vim.env.PATH` é o diretório de `tests/bin`.

## Actual behavior

Falha no runner completo (3 de 3); passa isolado (4 de 4). Não é causado por mudança de feature; o gate de integração local fica vermelho. Status no CI desconhecido.

## Root cause

Não diagnosticado. Próximo passo sugerido: rodar o runner completo sem truncar a saída e imprimir o PATH dentro do teste que falha.

## Fix

Não corrigido.
