# Comentário de ClaudinhoSendCompleteData aponta para seção e tag desatualizadas

- **Status:** Proposed
- **Opened:** 2026-11-15
- **Source:** agent run: fork-limpo, task 9, docs-writer
- **Scope:** `lua/claudinho/types.lua` (linhas ~64-73)

## Motivation

O comentário leva o leitor a uma seção que não existe com esse nome no README principal e cita um nome de comando que vai mudar.

## Current state

O comentário de `ClaudinhoSendCompleteData` manda ler a seção "Events" do README. Essa seção se chama "Eventos" em `README.md` (pt-BR) e "Events" em `README.en.md`. O campo `context` ainda cita a tag "ClaudeCodeSend", nome de comando que a feature base-ui vai substituir por `:Claudinho`.

## Proposed change

Apontar o comentário para a seção "Events" de `README.en.md` (comentários de código são em inglês). Rever a tag de exemplo quando a base-ui renomear os comandos.

## Risks

Nenhum relevante (só comentário).

## Out of scope

Renomear os comandos (feature base-ui).
