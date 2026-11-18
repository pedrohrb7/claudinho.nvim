# Conexão HTTP ("POST ") sem autenticação, sem prazo ocioso e sem limite esgota descritores

- **Status:** Open
- **Reported:** 2026-11-18
- **Severity:** low
- **Environment:** local
- **Source:** agent run: base-ui, review, security-reviewer
- **Related:** feature base-ui; `lua/claudinho/server/tcp.lua`, `lua/claudinho/server/http.lua`

## Evidence

`lua/claudinho/server/tcp.lua:218-224`, `lua/claudinho/server/http.lua:82-89`. Não reproduzido (achado de revisão de código).

## Steps to reproduce

1. Um processo local abre muitas conexões TCP na porta do servidor.
2. Em cada uma envia só os bytes `POST ` e fica em silêncio.

## Expected behavior

Conexão HTTP que não completa a requisição em ~2 s é fechada, e `http_clients` tem teto.

## Actual behavior

A conexão sai de `clients` antes da autenticação, sem prazo e sem teto; milhares de sockets silenciosos podem esgotar os descritores do Neovim.

## Root cause

Não diagnosticada ainda.

## Fix

Não corrigido.

Ideia de correção: fechar o cliente HTTP que não terminou a requisição em ~2 s e limitar `http_clients`.
