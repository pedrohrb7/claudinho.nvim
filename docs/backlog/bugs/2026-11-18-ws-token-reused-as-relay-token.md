# Token do WebSocket é o mesmo token das rotas POST de relay (CLAUDINHO_TOKEN)

- **Status:** Open
- **Reported:** 2026-11-18
- **Severity:** low
- **Environment:** local
- **Source:** agent run: base-ui, review, security-reviewer
- **Related:** feature base-ui; `lua/claudinho/session.lua`, `lua/claudinho/server/tcp.lua`, `lua/claudinho/server/handshake.lua`

## Evidence

`lua/claudinho/session.lua:79-80`, `lua/claudinho/server/tcp.lua:223-224`, `lua/claudinho/server/handshake.lua:64`. Não reproduzido (achado de revisão de código).

## Steps to reproduce

1. Dentro de uma sessão do claude, um processo filho (comando do Bash tool, servidor MCP ou hook) lê `CLAUDINHO_PORT` e `CLAUDINHO_TOKEN`.
2. Conecta em `ws://127.0.0.1:$CLAUDINHO_PORT` com esse token.
3. Chama ferramentas MCP (openDiff, saveDocument, seleções).

## Expected behavior

O token das rotas HTTP de relay não autentica o WebSocket; o token do WebSocket fica só no lock file.

## Actual behavior

O mesmo token vale nos dois lugares, então qualquer processo filho do claude pode dirigir as ferramentas MCP.

## Root cause

Provável: o job do claude recebe o token do WebSocket em `CLAUDINHO_TOKEN` e as rotas de relay o reutilizam.

## Fix

Não corrigido.
