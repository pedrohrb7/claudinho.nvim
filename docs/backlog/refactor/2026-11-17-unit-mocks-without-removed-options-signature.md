# Unit mocks of config.without_removed_options out of sync with the real signature

- **Status:** Proposed
- **Opened:** 2026-11-17
- **Scope:** `tests/unit/send_command_spec.lua`, `focus_after_send_spec.lua`, `send_complete_event_spec.lua`, `add_command_spec.lua`, `tree_send_visual_spec.lua`, `tree_buffer_classification_spec.lua`, `conflict_spec.lua`
- **Source:** agent run: base-ui, task 13, lua agent

## Motivation

Os mocks não espelham mais a função real, então os testes podem passar mesmo se o uso do segundo retorno quebrar.

## Current state

Os mocks de `config.without_removed_options` retornam um só valor e ainda definem `auto_start`; a função real agora retorna `(config, found)`. Os testes passam. Evidência: `rg -n without_removed_options tests/unit`.

## Proposed change

Fazer os mocks retornarem `(config, found)` e remover `auto_start`.

## Risks

Baixo: só mocks de teste.

## Out of scope

Mudanças de comportamento do plugin.
