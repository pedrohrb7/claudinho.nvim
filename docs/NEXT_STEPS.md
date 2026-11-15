# Onde paramos

Atualizado em 2026-11-15.

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

## Fork limpo: completo (2026-11-15)

Tasks 1-14 feitas (detalhe em `docs/features/fork-limpo/log.md`):

- renomeado pro namespace `claudinho`;
- opções do snacks e legadas removidas, com aviso;
- Neovim mínimo 0.12;
- guarda contra o claudecode.nvim, com detecção por runtimepath;
- servidor MCP `claudinho-nvim`;
- READMEs pt/en, `CLAUDE.md`, `CHANGELOG.md` 0.1.0 e linha no `LICENSE`.

Gate final: unit 1630/0/0/28, integração 508 no 0.12.3 e no 0.12.0, cobertura 86,22%.

Git recomeçado (Task 14, fechada pelo usuário em 2026-11-15 com o push de `892bacc`, CI em andamento): novo commit raiz `64f1422`, backup em `~/backups/claudecode-history.bundle`, saída da rede de forks do GitHub, remoto só com `main`.

## Pendente (follow-ups do usuário)

1. Confirmar o resultado do CI em `892bacc`.
2. Ajustar as regras de branch que exigiam `covered-lock` e `pr-title`.
3. Reinstalar o plugin na config do Neovim (o clone antigo do `vim.pack` não avança pro `main` reescrito).
4. Tag `v0.1.0`, só com autorização do usuário (o `CHANGELOG.md` linka pra ela).

## Próximos passos

1. Spec da base-ui (`docs/features/base-ui/plan.md` está Approved, ainda sem spec).
2. Requisito do usuário (2026-11-15): quando a base-ui trocar todo `:ClaudeCode*` por `:Claudinho`, manter registro de onde o código veio: atribuição no README, `CHANGELOG.md` e `LICENSE`; as notas do upstream em `PROTOCOL.md` e `ARCHITECTURE.md`; e uma linha de proveniência em cada módulo reescrito.

## Lembretes

- O recomeço do git e qualquer commit ou push só acontecem com autorização explícita no momento.
- O `LICENSE` fica (MIT exige manter o aviso de copyright da Coder).
