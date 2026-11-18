# PROTOCOL.md e ARCHITECTURE.md ainda citam comandos de diff removidos

- **Status:** Proposed
- **Opened:** 2026-11-18
- **Scope:** `PROTOCOL.md` (linhas 248 e 481), `ARCHITECTURE.md` (linhas 118-119)

## Motivation

Parágrafos herdados do upstream ainda nomeiam `:ClaudeCodeCloseAllDiffs`, `:ClaudeCodeDiffAccept` e `:ClaudeCodeDiffDeny`, comandos removidos. Leitores podem se confundir.

## Current state

Mantidos de propósito pelo limite da spec (na Task 20 só a nota e a seção nova mudaram). Fonte: Task 20, docs-writer, feature base-ui.

## Proposed change

Atualizar os parágrafos para os comandos atuais ou marcá-los como upstream. Precisa de decisão sobre o escopo (spec ou pedido ao docs-writer).

## Risks

Perder a rastreabilidade com o protocolo upstream se os parágrafos forem apagados.

## Out of scope

Reescrever o resto de PROTOCOL.md e ARCHITECTURE.md.
