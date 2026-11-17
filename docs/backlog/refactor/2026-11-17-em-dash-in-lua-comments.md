# Em dash in pre-existing Lua comments

- **Status:** Proposed
- **Opened:** 2026-11-17
- **Scope:** `lua/claudinho/tools/open_file.lua:603`, `lua/claudinho/terminal/paste_fix.lua:133`
- **Source:** agent run: base-ui, task 12, lua agent

## Motivation

O projeto proíbe o em dash, e a Verification (Task 21) da spec base-ui o procura em `lua/`. Sem a correção, a verificação final não fica limpa.

## Current state

Dois comentários antigos usam o caractere em dash nos arquivos listados.

## Proposed change

Trocar o em dash por "-" nos dois comentários, antes da Task 21 da spec base-ui.

## Risks

Baixo: só comentários.

## Out of scope

Mudanças de comportamento do plugin.
