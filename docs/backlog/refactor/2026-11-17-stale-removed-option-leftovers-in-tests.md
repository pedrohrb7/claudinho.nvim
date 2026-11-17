# Leftovers of removed options in test setup and comments

- **Status:** Proposed
- **Opened:** 2026-11-17
- **Scope:** `tests/minimal_init.lua:73`, `tests/selection_test.lua:2982`
- **Source:** agent run: base-ui, task 13, lua agent

## Motivation

Resíduos de opções removidas confundem a leitura e podem esconder erros de configuração.

## Current state

`tests/minimal_init.lua:73` ainda chama setup com a chave removida `auto_start = false` (inofensivo: avisos de chaves removidas só aparecem com `notify = true`). `tests/selection_test.lua:2982` tem um comentário desatualizado sobre `terminal.provider = "none"`.

## Proposed change

Remover a chave `auto_start` do setup e atualizar o comentário.

## Risks

Baixo: só configuração de teste e comentário.

## Out of scope

Mudanças de comportamento do plugin.
