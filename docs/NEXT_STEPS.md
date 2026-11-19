# Onde paramos

Atualizado em 2026-11-19.

## Feito

- `docs/PRD.md`: visão, decisões e roadmap (aprovado em 2026-11-12, atualizado com as features novas). Ponto de partida no commit `d123707`, Neovim mínimo 0.12, sessões por aba, comando `:Claudinho`, namespace `claudinho`. Cada feature fecha o ciclo inteiro (plano, spec, implementação, release) antes da próxima.
- `docs/prototype/base-ui.md`: protótipo da UI base.
- `docs/features/`: scaffold (Index e `_template/`) e a linha `- docs layout: features` no `CLAUDE.md`.
- Agente de stack Lua: `lua` (`~/.claude/agents/lua.md`).
- Ambiente local: plenary.nvim em `~/.local/share/nvim/site/pack/vendor/start/plenary.nvim`, no SHA do CI (`74b06c6c75e4eeb3108ec01852001636d85a932b`).
- Remoto: `main` (`8bf79de`) e `develop` (`d998d35`) estão iguais ao `origin`, então o force-push antigo de `main`, `develop` e `v0.1.0` está feito.
- Proveniência do código (requisito do usuário de 2026-11-15): coberta pela base-ui (Tasks 16, 17, 19 e 20). O commit `dfe71e6` pôs a linha `-- Origin:` em 38 módulos; a atribuição está no README, no `CHANGELOG.md` e no `LICENSE`, e as notas do upstream em `PROTOCOL.md` e `ARCHITECTURE.md`.

## Fork limpo: Implemented (2026-11-15), release 0.1.0

Plano e spec Implemented, 14 tasks (detalhe em `docs/features/fork-limpo/log.md`): namespace `claudinho`, opções do snacks e legadas removidas, Neovim mínimo 0.12, servidor MCP `claudinho-nvim`, READMEs pt/en, `CHANGELOG.md` e linha no `LICENSE`. O git recomeçou num commit raiz (`64f1422`), com backup em `~/backups/claudecode-history.bundle`. Tag `v0.1.0`.

## UI base: Implemented (2026-11-18), release `v0.2.0`

Plano e spec Implemented, todas as tasks feitas, incluindo a Task 23 (layout `left`); detalhe em `docs/features/base-ui/log.md`. O usuário rodou o roteiro manual (19 passos mais as cinco checagens das rodadas de revisão) em 2026-11-18, sem problemas. Release `v0.2.0` no commit `1370f7b chore(release): 0.2.0`.

Gate final (Neovim 0.12.3, `BUSTED_SEED=12345`):

- `format` sem mudanças; `check` 0 warnings em 217 arquivos;
- `unit` 1992 / 0 / 0 / 39;
- `integration` 616 / 0 / 0 em 41 arquivos, no 0.12.3 e no 0.12.0;
- cobertura 90,14% (antes 86,22%).

O plano da base-ui recebeu adendos das features seguintes: status-interativo (2026-11-18) e aba-com-opcoes (2026-11-19).

## Features planejadas (2026-11-18 e 2026-11-19)

Ordem do roadmap do `docs/PRD.md`: 3 status-interativo, 4 aba-com-opcoes, 5 perfis-de-aba, 6 Diff, 7 Painel de informações, 8 Envio de contexto e mouse.

- [status-interativo](features/status-interativo/plan.md): plano **Approved**, spec **Draft** (escrita em 2026-11-19, inclui limites de uso, regras 39 a 58). Próximo passo: o usuário revisa e aprova a spec; depois `/implement`.
- [aba-com-opcoes](features/aba-com-opcoes/plan.md): plano **Draft**. As perguntas abertas foram decididas pelo usuário em 2026-11-19 (regras 32, 13 e 4). Falta o usuário aprovar o plano; depois a spec.
- [perfis-de-aba](features/perfis-de-aba/plan.md): plano **Draft**, PRD atualizado. Das oito perguntas, quatro foram decididas pelo usuário (regras 3 a 5, 34, 25 e 36 no plano) e quatro pela recomendação (regras 8 a 10, 28, 29, 18 e 37), que o usuário ainda pode rever ao validar o Draft. Falta o usuário aprovar o plano; depois a spec.

## Backlog

Bugs ([índice](backlog/bugs/README.md)): 10 entradas, 9 abertas e 1 corrigida (E937 em BufWipeout ao sair do Claude).

- medium: teste `claude_stub` "is the first PATH entry" falha no runner completo;
- medium: `session_spec` depende do ambiente de quem executa (`CLAUDINHO_PORT` herdado);
- medium: `:bwipeout!` da aba ativa com aba vizinha deixa a janela do Claude fechada;
- medium: regra 30, seleção mais recente não é reenviada a aba nova ou reiniciada;
- low: diff unified não redimensiona a janela do Claude para `diff_width`;
- low: token do WebSocket é o mesmo das rotas POST de relay;
- low: conexão HTTP sem autenticação, sem prazo ocioso e sem limite esgota descritores;
- low: Esc após `:Claudinho send` pode chegar à TUI do Claude (não verificado);
- low: QuitPre fecha a janela do Claude antes da checagem de alterações (E37).

Refactors ([índice](backlog/refactor/README.md)): 5 entradas, todas `Proposed`, nenhuma fechada.

- doc comment de `ClaudinhoSendCompleteData`: seção do README e tag desatualizadas;
- travessões em comentários Lua antigos;
- restos de opções removidas no setup de testes e em comentários;
- mocks unitários de `config.without_removed_options` fora de sincronia com a assinatura real;
- `PROTOCOL.md` e `ARCHITECTURE.md` ainda citam comandos de diff removidos.

## Pendente (a confirmar pelo usuário)

Não dá para verificar pelo repositório:

1. Confirmar o resultado do CI nos pushes de `main` e `develop`.
2. Ajustar as regras de branch que exigiam `covered-lock` e `pr-title`.
3. Reinstalar o plugin na config do Neovim (o clone antigo do `vim.pack` não avança pro `main` reescrito).

## Próximos passos

1. Revisar e aprovar a spec do status-interativo; depois `/implement`.
2. Aprovar o plano do aba-com-opcoes e, em seguida, o do perfis-de-aba (e especificar cada um quando chegar a vez).
3. Depois de cada feature fechar, rodar `mise run release minor`; o push fica com o usuário.

## Lembretes

- Commits e pushes só com autorização explícita no momento.
- O `LICENSE` fica (MIT exige manter o aviso de copyright da Coder).
