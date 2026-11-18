# E937 em BufWipeout ao sair do Claude com Ctrl+C duas vezes

- **Status:** Fixed
- **Reported:** 2026-11-17
- **Severity:** high
- **Environment:** local, Neovim do usuario (`~/.config/nvim`)
- **Source:** user report
- **Related:** feature base-ui (abas de sessao em `lua/claudinho/sessions.lua`)

## Evidence

Reported by the user. Texto da tela, literal:

```
Error in BufWipeout Autocommands for "*":
E937: Attempt to delete a buffer that is in use: term://~/.config/nvim//4738:/home/phrb/.local/bin/claude
Press ENTER or type command to continue
```

Relato adicional do usuario (2026-11-17, literal): "Esse erro que falei também me impede de fechar o nvim, ele entende como um arquivo que foi escrito mas que nao foi salvo".

Impacto: depois do E937 nao e possivel sair do Neovim normalmente. Hipotese, nao verificada: o buffer de terminal do `claude`, que o wipeout falho deixou vivo, e tratado como buffer com alteracoes nao salvas e bloqueia `:q`/`:qa`. A saida so se faz com `:qa!` (perde alteracoes de outros buffers, se houver).

Reproduzido (2026-11-17, sessao principal), em headless no Neovim 0.12.6 (`nvim --headless --clean`): `require("claudinho").setup({ terminal_cmd = <script que imprime e sai com 0 apos 1s> })`, `:Claudinho`, o terminal fica em modo terminal (`t`) enquanto o processo termina, depois uma tecla (`nvim_input("x")`) - o Neovim apaga (wipe) um buffer de terminal encerrado quando uma tecla e digitada em modo terminal. Saida:

```
Error in BufWipeout Autocommands for "*":
E937: Attempt to delete a buffer that is in use: term://<cwd>//<pid>:<cmd>
```

A config do usuario (`~/.config/nvim`) nao tem autocmd de `TermClose`/`BufWipeout` que apague buffers (so um `checktime` em `TermClose`), entao esta descartada como origem. Caminho provavel (a confirmar no diagnostico): o autocmd `BufDelete`/`BufWipeout` em `lua/claudinho/sessions.lua` (`setup_autocmds`) chama `M.close(n)` para o buffer que esta sendo apagado.

## Steps to reproduce

Como o usuario observou:

1. Abrir a janela do Claude com `:Claudinho` (abrir/alternar), na config propria `~/.config/nvim`.
2. Dentro do TUI do Claude, apertar Ctrl+C duas vezes para o processo `claude` sair.
3. A mensagem acima aparece, com o prompt "Press ENTER".
4. (Relato adicional, 2026-11-17) Depois do erro, tentar fechar o Neovim (`:q`/`:qa`): o Neovim recusa, tratando como se houvesse um arquivo modificado e nao salvo. O texto exato do erro de saida nao foi informado.

## Expected behavior

O Claude sai sem erro. Pelo plano, a aba nunca fecha sozinha: ela deve aparecer como encerrada (exited).

## Actual behavior

Erro E937 vindo de autocmds `BufWipeout` com padrao `"*"`, ao tentar apagar o buffer de terminal do `claude`, e um prompt hit-enter.

## Root cause

When the claude process ended while its terminal was in terminal mode, the next key made Neovim wipe the ended terminal buffer (Neovim closes an ended terminal on a key in terminal mode). The BufDelete/BufWipeout handler in `lua/claudinho/sessions.lua` (`setup_autocmds`) then called `M.close(n)`, and `session.close` (`lua/claudinho/session.lua`) deleted the same buffer again with `nvim_buf_delete` while Neovim was already wiping it: E937. Besides the error, the tab closed, against plan rules 39-40 (an ended tab stays, shown as exited). The leftover buffer from the failed wipe is what blocked `:q`.

## Fix

- (a) `guard_ended_terminal` in `session.lua` adds a `TermClose` autocmd that calls `stopinsert` when the ended terminal is the current buffer and in terminal mode, so the key no longer wipes the buffer.
- (b) `sessions.close(n, opts)` and `session.close(session, reason, opts)` take `{ buf_gone = true }` from the BufDelete/BufWipeout handler: the job stops with `jobstop` and no wait, and the buffer is not deleted again.

Changed files: `lua/claudinho/session.lua`, `lua/claudinho/sessions.lua`, `tests/unit/session_spec.lua`, `tests/unit/sessions_spec.lua`, `tests/integration/session_exit_key_spec.lua`, `tests/helpers/exit_key_child.lua`, `CHANGELOG.md`, `docs/features/base-ui/spec.md`. Commit e3f3563 plus working-tree follow-ups (review minors).

Regression tests: `tests/integration/session_exit_key_spec.lua` (child Neovim, helper `tests/helpers/exit_key_child.lua`), `tests/unit/sessions_spec.lua`, `tests/unit/session_spec.lua`.

Verification (2026-11-17): headless repro repeated on the mise Neovim: after the process ends the mode is "nt", the key does not wipe the buffer, the tab stays, no E937 in `:messages`, 0 modified buffers. Gate: check, format-check, unit (1926 ok) and integration (586 ok) green; the only integration failure is `tests/integration/claude_stub_spec.lua:14`, already registered as [2026-11-16-claude-stub-path-first-entry-integration.md](2026-11-16-claude-stub-path-first-entry-integration.md) (pre-existing, environmental). Pending: the user's manual check on their own config.
