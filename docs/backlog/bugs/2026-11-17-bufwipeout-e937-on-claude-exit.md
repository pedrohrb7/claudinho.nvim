# E937 em BufWipeout ao sair do Claude com Ctrl+C duas vezes

- **Status:** In progress
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

Not diagnosed yet. Pistas, nao verificadas: o erro indica um autocmd de `BufWipeout` apagando um buffer de terminal ainda em uso (exibido numa janela). Candidatos no plugin (grep `BufWipeout`, `TermClose`, `nvim_buf_delete`): o handler de `BufDelete`/`BufWipeout` em `lua/claudinho/sessions.lua:508` (chama `M.close`, que apaga o buffer em `lua/claudinho/session.lua:460`), `lua/claudinho/diff.lua:865` e `:1285`, e `lua/claudinho/diff_inline.lua:475`. Tambem pode ser um autocmd da config do usuario. Precisa de reproducao antes de diagnosticar.

## Fix

Not fixed yet.
