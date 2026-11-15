# Onde paramos

Atualizado em 2026-11-14.

## Feito

- `docs/PRD.md`: atualizado e aprovado em 2026-11-12. Visão, decisões e roadmap, incluindo o ponto de partida no commit `d123707`, Neovim mínimo 0.12, o ciclo de ponta a ponta por feature, sessões por aba, comando `:Claudinho` e o nome/namespace `claudinho`.
- `docs/prototype/base-ui.md`: protótipo da UI base.
- `docs/features/`: scaffold (Index e `_template/`), mais a linha `- docs layout: features` no `CLAUDE.md`.
- `docs/features/fork-limpo/plan.md`: **Approved**. As oito Open questions foram decididas (`PROTOCOL.md` e `ARCHITECTURE.md` na raiz; 2 a 7 com a recomendação; PRD atualizado), e o Neovim mínimo 0.12 entrou no escopo (loader, health check e matriz do CI).
- `docs/features/fork-limpo/spec.md`: **Approved** em 2026-11-14. 14 tasks, da linha de base de testes ao recomeço do git. Decisões da revisão:
  - linha do `LICENSE`: `Copyright (c) 2026 pedrohrb7`, abaixo do aviso da Coder;
  - os filetypes do snacks em `diff.lua` (`snacks_picker_list`, `snacks_layout_box`) ficam, com as exceções do `rg -i snacks` listadas na spec;
  - a Task 13 exige a integração verde localmente no Neovim 0.12.3 e no 0.12.0;
  - a matriz do CI passa a `["stable", "v0.12.0"]`.
- `docs/features/base-ui/plan.md`: **Approved**, com dois adendos: idioma (textos visíveis do plugin em inglês) e Neovim mínimo 0.12.
- Agente de stack Lua: `lua` (`~/.claude/agents/lua.md`); a spec foi ajustada para esse nome em 2026-11-14.
- Ambiente local: plenary.nvim instalado em `~/.local/share/nvim/site/pack/vendor/start/plenary.nvim`, no SHA do CI (`74b06c6c75e4eeb3108ec01852001636d85a932b`).

## Pendente antes do `/implement` do fork-limpo

1. `mise install` completo: o download do `lua@5.5.0` em lua.org falhou por rede em 2026-11-12, e o `mise run all` precisa dele.

## Próximos passos

1. `/implement fork-limpo`, de ponta a ponta, terminando no recomeço do git (Task 14, só pelo usuário, com autorização a cada passo).
2. Só então a spec da base-ui.

## Lembretes

- O recomeço do git e qualquer commit ou push só acontecem com autorização explícita no momento.
- O `LICENSE` fica (MIT exige manter o aviso de copyright da Coder).
