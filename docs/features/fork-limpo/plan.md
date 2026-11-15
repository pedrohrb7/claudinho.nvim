# Fase 0 · Fork limpo

- **Date:** 2026-11-12
- **Status:** Approved
- **Spec:** [spec.md](spec.md)

## Goal

O repo vira o Claudinho.nvim, um projeto próprio, sem vínculo com o upstream. Do claudecode.nvim ficam o código, os testes e o mínimo de ferramental para rodá-los, além de `PROTOCOL.md` e `ARCHITECTURE.md` como referência técnica. O namespace passa a ser `claudinho`, o snacks e as opções legadas saem, e a versão mínima do Neovim sobe para 0.12. A versão recomeça em `0.1.0`, e o git recomeça com um commit inicial só com o que fica. O comportamento do plugin não muda, exceto pelo que esta fase renomeia ou remove de propósito.

Critérios de sucesso:

| Critério                                      | Como medir                                                                                                                                        |
| --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| Nenhum resto do nome antigo fora das exceções | `rg -i claudecode` no repo encontra só as exceções da regra 6                                                                                     |
| O plugin novo carrega e o antigo não existe   | `require("claudinho").setup({})` funciona; `require("claudecode")` falha com módulo não encontrado                                                |
| Snacks e opções legadas fora do código        | `rg -i snacks lua/ plugin/ tests/` sem resultado; nenhuma das chaves da regra 15 no código                                                        |
| O repo tem só o que fica                      | A árvore bate com a tabela da regra 18; nenhum caminho da regra 19 existe                                                                         |
| Testes verdes                                 | `mise run all` verde localmente; o workflow de CI que fica passa no primeiro push; só saem os testes das funções removidas (regra 27)             |
| Docs do fork                                  | `README.md` (pt-BR) e `README.en.md` (inglês) com o mesmo conteúdo e links cruzados; `CLAUDE.md` curto; `CHANGELOG.md` novo com a entrada `0.1.0` |
| Versão                                        | `VERSION` igual a `0.1.0`, e `require("claudinho").version` igual                                                                                 |
| Neovim mínimo 0.12                            | Loader, health check e matriz do CI em 0.12 (regras 43 a 45); num Neovim 0.11 o plugin não carrega e mostra a mensagem da regra 2                 |
| Git recomeçado, só com autorização            | Depois do fluxo da regra 40: `git log` com um commit só, e o remoto sem branches nem tags do upstream                                             |

## Context

A Fase 0 é a primeira do roadmap do `docs/PRD.md` e a pré-condição do plano da [UI base](../base-ui/plan.md), que parte de `lua/claudinho/` sem snacks. Hoje o repo é o upstream inteiro: 356 commits de histórico, `lua/claudecode/` (44 arquivos), 148 arquivos de teste, release-please e Communique, skills de verificação com modelos TLA+, scripts e fixtures de reprodução de issues e várias docs do upstream.

Decisões que este plano segue:

- **PRD (atualizado e aprovado em 2026-11-12):** hard fork, namespace `claudinho`, API nova sem compatibilidade com o upstream, zero dependências, Neovim mínimo 0.12, ponto de partida no commit `d123707`.
- **Revisão de 2026-11-12, primeira rodada:**
  - fronteiras do rename com a UI base aceitas;
  - mensagens, código e testes em inglês;
  - `README.md` em pt-BR e um README em inglês;
  - `LICENSE` com o copyright da Coder e a linha do autor do fork.
- **Revisão de 2026-11-12, mudança de direção, que substitui a rodada anterior em versão, ferramental e docs:**
  - desvincular totalmente do upstream e manter só o código e os testes;
  - ferramental de teste enxuto;
  - docs reduzidas a `PROTOCOL.md` e `ARCHITECTURE.md`;
  - sem skills de verificação nem TLA+;
  - `VERSION` em `0.1.0`, `CHANGELOG.md` novo e git recomeçado.
- **Revisão de 2026-11-12, aprovação:**
  - as oito Open questions decididas (ver Open questions), já escritas como regras;
  - Neovim mínimo 0.12, que substitui o 0.8.0 do upstream (regras 2 e 43 a 45);
  - plano aprovado pelo usuário.

Fronteira com a UI base:

| Item                                      | Fase 0                                      | UI base                                 |
| ----------------------------------------- | ------------------------------------------- | --------------------------------------- |
| Comandos `:ClaudeCode*`                   | Ficam como estão                            | Viram subcomandos de `:Claudinho`       |
| Providers `external` e `none`             | Ficam como estão                            | Removidos                               |
| Opções `terminal.*` (exceto as do snacks) | Ficam como estão                            | Removidas                               |
| `ideName` do lock file                    | Continua `"Neovim"`                         | Ganha o número da aba                   |
| Janela flutuante do terminal              | Some com o snacks; o `native` não tem float | Layout `float`                          |
| Rótulos e mensagens novas                 | -                                           | Em inglês (adendo de idioma da UI base) |

## Scope

**In scope:**

- Rename de `lua/claudecode/`, `plugin/` e de todo identificador do plugin para `claudinho`, incluindo os que o usuário vê (eventos, highlights, variáveis, filetype, health).
- Remoção do snacks: provider, `snacks_win_opts`, leitura do snacks picker e explorer, fixtures e testes.
- Remoção das opções legadas de diff e do `queue_timeout`, com aviso para configs que ainda as usam.
- Redução do repo ao que fica (regras 18 e 19): código, testes, ferramental de teste enxuto, fixtures de explorer e `repro`, `PROTOCOL.md` e `ARCHITECTURE.md`.
- Docs do fork: `README.md`, `README.en.md`, `CLAUDE.md` curto, `CHANGELOG.md` novo, `LICENSE`.
- `VERSION` em `0.1.0` e o esquema de versão daqui em diante.
- Neovim mínimo 0.12 no loader, no health check e no CI (regras 43 a 45).
- O fluxo de recomeço do git e do remoto no GitHub, executado só com autorização explícita do usuário no momento (regras 38 a 42).

**Out of scope:**

- Qualquer mudança de comportamento além das remoções listadas: comandos, terminal, diff, seleção e servidor funcionam como hoje.
- Tudo o que a UI base faz (tabela acima).
- A estrutura definitiva das docs técnicas: o usuário organiza depois. `PROTOCOL.md` e `ARCHITECTURE.md` só trocam caminhos e nomes.
- Remover o código que só existe para versões do Neovim anteriores a 0.12 (ex.: o fallback para `get_active_clients`): o comportamento fica igual, e as fases que reescrevem cada área limpam o que tocarem.
- As integrações de explorer (nvim-tree, neo-tree, oil, mini.files, netrw), a decisão que segue em aberto no PRD: ficam como estão.
- Editar o `docs/PRD.md`: ele já foi atualizado em 2026-11-12 com as decisões deste plano.

## Business rules

### Namespace e identificadores

1. Os módulos ficam em `lua/claudinho/` e são carregados por `require("claudinho")` e `require("claudinho.<módulo>")`. Não existe módulo `claudecode` nem shim de compatibilidade.
2. O loader é `plugin/claudinho.lua`. A mensagem de versão mínima diz `Claudinho requires Neovim >= 0.12` (regra 43).
3. Todo identificador do plugin troca de nome:

| Tipo                                              | Antes                                                                                    | Depois                                                                                |
| ------------------------------------------------- | ---------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| Variáveis globais                                 | `vim.g.loaded_claudecode`, `vim.g.claudecode_auto_setup`, `vim.g.claudecode_user_config` | `vim.g.loaded_claudinho`, `vim.g.claudinho_auto_setup`, `vim.g.claudinho_user_config` |
| Variáveis de buffer                               | `vim.b.claudecode_*`                                                                     | `vim.b.claudinho_*`                                                                   |
| Augroups                                          | `ClaudeCode*` (ex.: `ClaudeCodeSelection`)                                               | `Claudinho*` (ex.: `ClaudinhoSelection`)                                              |
| Highlights                                        | `ClaudeCodeInlineDiffAdd`, `...Delete`, `...AddSign`, `...DeleteSign`                    | `ClaudinhoInlineDiffAdd`, `...Delete`, `...AddSign`, `...DeleteSign`                  |
| Eventos `User`                                    | `ClaudeCodeSendComplete`, `ClaudeCodeDiffOpened`, `ClaudeCodeDiffClosed`                 | `ClaudinhoSendComplete`, `ClaudinhoDiffOpened`, `ClaudinhoDiffClosed`                 |
| Filetype do terminal                              | `claudecode`                                                                             | `claudinho`                                                                           |
| Health check                                      | `:checkhealth claudecode`                                                                | `:checkhealth claudinho`                                                              |
| Prefixo do log e títulos de notificação           | `[ClaudeCode]`, `ClaudeCode ...`                                                         | `[Claudinho]`, `Claudinho ...`                                                        |
| Nome do servidor no `initialize` do MCP           | `claudecode-neovim`                                                                      | `claudinho-nvim` (regra 5)                                                            |
| Ids internos (nomes de terminal, sessão, buffers) | `claudecode_*`                                                                           | `claudinho_*`                                                                         |
| Tipos LuaLS                                       | `ClaudeCode*`                                                                            | `Claudinho*`                                                                          |
| Variáveis de ambiente dos testes e fixtures       | `CLAUDECODE_*`                                                                           | `CLAUDINHO_*`                                                                         |
| Config de fixture                                 | `dev-claudecode.lua`                                                                     | `dev-claudinho.lua`                                                                   |

4. Os eventos, variáveis e highlights antigos deixam de existir, sem alias e sem aviso: um autocmd do usuário em `ClaudeCodeDiffOpened` simplesmente não dispara mais. O README documenta a troca (regra 33).
5. O nome do servidor no `initialize` só muda depois de verificado que o Claude não depende dele: `/ide` conecta, as tools respondem e o diff abre com um `claude` real. Se depender, o nome fica `claudecode-neovim`, e a spec registra o motivo.
6. Continuam com o nome antigo, de propósito:
   - os comandos `:ClaudeCode*` e as descrições deles (a UI base os troca);
   - o que é do protocolo do Claude Code e não do plugin: `~/.claude/ide/`, `CLAUDE_CODE_SSE_PORT`, `ENABLE_IDE_INTEGRATION`, o header `x-claude-code-ide-authorization` e o `ideName = "Neovim"`;
   - a atribuição ao upstream no README e no `LICENSE`, com o link para `coder/claudecode.nvim`.
7. Com o claudecode.nvim já carregado no mesmo Neovim (`vim.g.loaded_claudecode`), o Claudinho não carrega e mostra um aviso único dizendo que os dois não rodam juntos. Os dois registrariam os mesmos `:ClaudeCode*` e escreveriam lock files iguais.

### Snacks

8. `terminal/snacks.lua` sai. O provider `auto` passa a escolher sempre o `native`.
9. Uma config com `terminal.provider = "snacks"` usa o `native` e mostra um aviso único que nomeia a chave. O `setup` não falha.
10. `snacks_win_opts` deixa de existir. Uma config que ainda a usa recebe um aviso único que nomeia a chave, e o resto da config funciona.
11. A leitura do snacks picker e do snacks explorer em `integrations.lua` sai. Num buffer desses, os comandos de envio se comportam como em qualquer buffer de explorer não suportado hoje.
12. O caminho do diff que escondia o float do snacks sai. O diff com o terminal `native` continua igual.
13. O health check deixa de citar o snacks.
14. Saem as fixtures `snacks-explorer` e `snacks-picker`. A fixture `netrw` perde o `snacks.lua` e passa a usar o terminal `native`.

### Opções legadas

15. Saem dos defaults, dos tipos e da validação: `diff_opts.vertical_split`, `diff_opts.open_in_current_tab`, `diff_opts.auto_close_on_accept`, `diff_opts.show_diff_stats` e `queue_timeout`.
16. Uma config que ainda define uma dessas chaves recebe um aviso único por chave, com a substituição quando ela existe. O `setup` não falha, nem com um valor de tipo errado.

| Chave removida                                                                 | Aviso aponta para                        |
| ------------------------------------------------------------------------------ | ---------------------------------------- |
| `diff_opts.vertical_split`                                                     | `diff_opts.layout`                       |
| `diff_opts.open_in_current_tab`                                                | `diff_opts.open_in_new_tab`              |
| `diff_opts.auto_close_on_accept`, `diff_opts.show_diff_stats`, `queue_timeout` | Sem substituto; a chave não tinha efeito |

17. Os avisos das regras 9, 10 e 16 saem no `setup`, em inglês, um por chave e por sessão do Neovim.

### O que fica e o que sai

18. Fica no repo:

| Grupo                         | Caminhos                                                                                                                                          |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| Código                        | `lua/claudinho/` (sem os READMEs internos), `plugin/claudinho.lua`                                                                                |
| Testes                        | `tests/` (menos os da regra 27)                                                                                                                   |
| Scripts que o CI que fica usa | `scripts/coverage-summary.sh`, `scripts/run_integration_tests_individually.sh`, `scripts/manual_test_helper.lua`                                  |
| Ferramental de teste          | `mise.toml`, `mise.lock`, `.busted`, `.luacheckrc`, `.luacov`, `.stylua.toml`, `treefmt.toml`, `.github/workflows/test.yml` (regra 20)            |
| Fixtures                      | `fixtures/netrw/`, `fixtures/nvim-tree/`, `fixtures/oil/`, `fixtures/mini-files/`, `fixtures/repro/`, `fixtures/bin/`, `fixtures/nvim-aliases.sh` |
| Git                           | `.gitignore`, `.gitattributes`                                                                                                                    |
| Referência técnica            | `PROTOCOL.md`, `ARCHITECTURE.md` (regra 35)                                                                                                       |
| Docs do fork                  | `README.md`, `README.en.md`, `CLAUDE.md`, `CHANGELOG.md`, `LICENSE`, `VERSION`, `docs/`                                                           |
| Ferramental de agentes        | `.claude/` (hook de format que roda quando um agente edita o repo)                                                                                |

19. Sai do repo:

| Grupo                | Caminhos                                                                                                                                                                                                                                                                                                                                                  |
| -------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Docs do upstream     | `DEVELOPMENT.md`, `AGENTS.md`, `STORY.md`, o `CHANGELOG.md` atual, `lua/README.md`, `lua/claudecode/README.md`, `lua/claudecode/server/README.md`, `lua/claudecode/terminal/README.md`, `lua/claudecode/tools/README.md`, `plugin/README.md`, `scripts/README.md`                                                                                         |
| Release              | `.github/workflows/release-please.yaml`, `.github/workflows/release-notes.yaml`, `release-please-config.json`, `.release-please-manifest.json`, `communique.toml`, `scripts/release-please-runner.js`, `scripts/run-release-please.sh`, `scripts/test-release-please-runner.js`, `scripts/fixtures/`, `scripts/package.json`, `scripts/package-lock.json` |
| Projeto upstream     | `reviewfixer.yaml`, `.github/workflows/issue-triage.yaml`, `.github/workflows/pr-title.yaml`, `.github/ISSUE_TEMPLATE/`, `.devcontainer/`, `dev-config.lua`                                                                                                                                                                                               |
| Verificação          | `.agents/` (skills `verify-*`, com os `covered.lock` e os modelos TLA+), `scripts/tla/`                                                                                                                                                                                                                                                                   |
| Reprodução de issues | `scripts/repro_issue_*` (incluindo `repro_issue_70_probe.lua`), `fixtures/issue-*`, `fixtures/cursor-toggle-repro/`, `fixtures/paste-repro/`, `fixtures/remote-diff/`                                                                                                                                                                                     |
| Snacks               | `lua/claudecode/terminal/snacks.lua`, `fixtures/snacks-explorer/`, `fixtures/snacks-picker/`, `fixtures/netrw/lua/plugins/snacks.lua`                                                                                                                                                                                                                     |

20. O `test.yml` fica com o que roda format, lint e testes:
    - **`unit-tests`:** sai a instalação e o teste do `release-please-runner`; ficam setup, luacheck, testes, format-check e o resumo de cobertura;
    - **`integration-tests`:** sai o passo `repro_issue_238.lua`; ficam as duas rodadas de integração (com a matriz da regra 45), a checagem da pasta de cache e o `manual_test_helper.lua`;
    - **`covered-lock`:** sai inteiro;
    - **`Required`:** passa a depender só dos jobs que ficam.
21. O `mise.toml` perde:
    - a ferramenta `communique` e a task `reviewfix`;
    - o passo das provas estáticas da skill de verificação na task `check`;
    - as ferramentas que só o que saiu usava. Uma ferramenta só sai quando nada que fica a usa: `fzf` fica, porque o `fixtures/bin` usa. Para `websocat`, `jq`, `node`, `prettier`, `actionlint` e `zizmor`, a spec confere caso a caso, por exemplo se o `prettier` do `treefmt.toml` precisa do `node`.
22. Comentários de código e de teste que citam arquivos removidos (ex.: `diff_reject_on_quit_spec.lua` cita `scripts/repro_issue_238.lua`) são reescritos sem a referência. O teste continua.

### Versão e CHANGELOG

23. O `VERSION` recomeça em `0.1.0`, e o `init.lua` continua lendo a versão dele.
24. A versão sobe à mão, sem ferramenta, no mesmo PR que fecha uma feature: o `VERSION` e uma entrada nova no `CHANGELOG.md`. Antes da 1.0, cada feature fechada sobe o minor (`0.2.0`, `0.3.0`...) e cada correção entre features sobe o patch. A `1.0.0` é decisão do usuário, quando o plugin estiver estável no uso diário. A tag `vX.Y.Z` é criada à mão, com autorização do usuário no momento.
25. O `CHANGELOG.md` nasce novo, no formato Keep a Changelog, com uma linha que diz que o Claudinho.nvim é um hard fork do claudecode.nvim (com link para o commit de origem, regra 37) e a entrada `0.1.0` com o que a Fase 0 renomeou e removeu (seções Changed e Removed). Não leva nada do histórico do upstream.
26. O CHANGELOG fica em inglês, como o código.

### Testes

27. Só saem os testes das funções removidas: os specs do snacks (`tests/unit/terminal/snacks_*_spec.lua`, `tests/unit/snacks_picker_integration_spec.lua`) e os das opções legadas (ex.: `tests/integration/diff_legacy_swap_spec.lua`). Os testes que só citam o snacks ao lado de outro provider perdem só esses casos. Nenhum teste é desligado ou marcado como pendente.
28. Cada aviso das regras 7, 9, 10 e 16 ganha um teste, e a checagem de versão das regras 43 e 44 também.
29. A spec registra o número de testes e a cobertura antes e depois, para mostrar que só caiu o que saiu.
30. A verificação final tem duas partes:
    - **automática:** `mise run all`;
    - **manual, feita pelo usuário com um roteiro da spec:** uma sessão real em que o `claude` conecta por `/ide`, um `openDiff` é aceito e um `@`-mention é enviado.

### Documentação

31. O `README.md` fica em português e o `README.en.md` em inglês, com o mesmo conteúdo. A primeira linha de cada um aponta para o outro (`English version: README.en.md` / `Versão em português: README.md`).
32. Os dois descrevem o Claudinho.nvim no estado da Fase 0: o que é e de onde vem (regra 37), instalação com `vim.pack` e `require("claudinho")`, config, comandos (ainda `:ClaudeCode*`, com uma nota de que eles mudam na próxima fase), eventos, health check e requisitos (Neovim >= 0.12). São escritos do zero, curtos; nada do README do upstream é copiado sem revisão.
33. Os dois READMEs têm uma seção "Vindo do claudecode.nvim" / "Coming from claudecode.nvim" com a tabela da regra 3, as chaves removidas (regras 10 e 15) e o aviso de que os dois plugins não rodam juntos.
34. O `CLAUDE.md` é reescrito curto para o fork, em inglês:
    - visão do projeto;
    - comandos do `mise`;
    - estrutura de pastas;
    - como rodar os testes;
    - regra de idioma: mensagens, código, testes e `README.en.md` em inglês; `README.md` e `docs/` em português;
    - regra de versão (regra 24);
    - a seção `## Workflow` com `- docs layout: features`.
35. `PROTOCOL.md` e `ARCHITECTURE.md` ficam como referência técnica do upstream. Trocam só caminhos e nomes (regra 3) e ganham no topo uma nota curta de que descrevem o upstream e podem divergir do que o fork constrói. Continuam na raiz até o usuário estruturar as docs técnicas (decidido em 2026-11-12).
36. O `LICENSE` mantém o aviso MIT da Coder Technologies Inc. e ganha abaixo a linha de copyright do autor do fork, com o ano de 2026.
37. A origem citada no README e no CHANGELOG é o commit do upstream cujo código o commit inicial contém: hoje é `d123707`, o `HEAD` atual, o mesmo que o `docs/PRD.md` registra como ponto de partida. O link aponta para esse commit em `coder/claudecode.nvim`.

### Recomeço do git e do remoto

38. O recomeço do git, qualquer commit, push, troca ou remoção de branch e tag e qualquer mudança no repositório do GitHub só acontecem com autorização explícita do usuário, dada no momento de cada passo. Nenhum agente executa esses passos por conta própria.
39. Pronto antes do recomeço:
    - todas as regras de 1 a 37 e de 43 a 45 aplicadas na árvore de trabalho;
    - `mise run all` verde;
    - a verificação manual da regra 30 feita;
    - a árvore final revisada pelo usuário: lista de arquivos e diff contra o `HEAD` atual.
40. Fluxo:

| Passo                    | O que acontece                                                                                                                                                                                                            | Autorização                       |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------- |
| 1. Backup                | Um `git bundle` com todo o histórico atual, guardado fora do repo, num caminho que o usuário escolhe                                                                                                                      | Do usuário, no momento            |
| 2. Histórico novo        | Um branch órfão com a árvore final e um commit só (ex.: `chore: initial commit of claudinho.nvim 0.1.0`). Esse branch vira o `main` local, e o histórico antigo sai do repo local                                         | Do usuário, no momento            |
| 3. Desvincular no GitHub | Se o repositório do GitHub é um fork de `coder/claudecode.nvim`, ele sai da rede de forks: "Leave fork network" nas Settings, ou apagar e recriar o repositório com o mesmo nome. Se não é um fork, este passo não existe | Do usuário, que executa no GitHub |
| 4. Push                  | O `main` novo vai para o remoto com push forçado; os branches e as tags do upstream no remoto são apagados                                                                                                                | Do usuário, no momento            |
| 5. Depois                | O CI roda no commit novo e precisa passar; as regras de branch do GitHub que exigiam checks removidos (`covered-lock`, `pr-title`) são ajustadas pelo usuário                                                             | Do usuário                        |

41. O que se perde, e o usuário confirma antes do passo 2:
    - os 356 commits do upstream no repo: `git log`, `git blame` e `git bisect` sobre o código herdado;
    - as tags e os branches do upstream no remoto;
    - o vínculo de fork no GitHub: o rótulo "forked from", o compare e os PRs para o upstream;
    - ao sair da rede de forks ou recriar o repositório, as issues, os PRs, a wiki, as estrelas, os watchers e o histórico de Actions do repositório no GitHub. Leave fork network é permanente e só existe para forks públicos com menos de 1 GB;
    - as docs do upstream removidas pela regra 19, incluindo o `lua/claudecode/README.md`.

    Nada disso some de fato: o histórico fica no bundle do passo 1, e o upstream continua público em `coder/claudecode.nvim`.

42. A config do Neovim do usuário que instala o fork por `vim.pack` tem um clone com o histórico antigo, que não avança para o `main` reescrito. O README e o fluxo dizem para remover e instalar o plugin de novo depois do passo 4.

### Versão mínima do Neovim

As regras desta seção vêm depois das outras para não renumerar as referências; elas valem como parte do namespace (regra 2) e do ferramental de teste (regras 20 e 21).

43. A versão mínima do Neovim é 0.12, como decidido no `docs/PRD.md`. O loader `plugin/claudinho.lua` confere `nvim-0.12`; numa versão anterior, mostra a mensagem da regra 2 e para ali: nenhum comando, autocmd, servidor ou lock file é criado.
44. O health check confere a mesma versão: `:checkhealth claudinho` mostra OK com `Neovim >= 0.12` e erro com `Neovim >= 0.12 is required` numa versão anterior.
45. A matriz do job `integration-tests` do `test.yml` passa da versão estável mais a 0.8.0 para a estável mais a mínima 0.12 (ex.: `["stable", "v0.12.0"]`; a spec confirma a tag exata da release). O `mise.toml` continua fixando o Neovim 0.12.3 para os testes locais.

## Edge cases

| Situação                                                                                            | Comportamento esperado                                                                                                                           |
| --------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| A config do usuário chama `require("claudecode")`                                                   | Erro de módulo não encontrado do Lua; o README explica a troca                                                                                   |
| `vim.g.claudecode_user_config` ou `vim.g.claudecode_auto_setup` definidos                           | Ignorados, sem aviso; o README lista os nomes novos                                                                                              |
| Um autocmd do usuário em `ClaudeCodeDiffOpened`, `ClaudeCodeDiffClosed` ou `ClaudeCodeSendComplete` | Não dispara mais; o README lista os nomes novos                                                                                                  |
| Highlights `ClaudeCodeInlineDiff*` customizados                                                     | Não se aplicam mais; os novos usam os mesmos defaults                                                                                            |
| claudecode.nvim e Claudinho instalados juntos                                                       | Regra 7: o Claudinho não carrega e avisa                                                                                                         |
| Claudinho carregado antes do claudecode.nvim                                                        | O Claudinho carrega; o claudecode.nvim registra os mesmos `:ClaudeCode*` por cima. O README diz para remover o claudecode.nvim antes             |
| `terminal.provider = "snacks"` com `snacks_win_opts` de janela flutuante                            | Avisos das regras 9 e 10; o terminal abre como split `native` até a UI base trazer o `float`                                                     |
| Chave legada com valor de tipo errado (ex.: `vertical_split = "sim"`)                               | Só o aviso da regra 16, sem erro                                                                                                                 |
| Num picker ou explorer do snacks, o usuário roda `:ClaudeCodeTreeAdd` ou `:ClaudeCodeSend`          | O mesmo resultado de hoje num explorer não suportado (regra 11)                                                                                  |
| Fixture removida chamada por `vv <nome>`                                                            | O `list-configs` não a mostra, e o `vv` dá o erro de config inexistente de hoje                                                                  |
| O `claude` depende do nome `claudecode-neovim`                                                      | Regra 5: o nome antigo fica, com o motivo registrado na spec                                                                                     |
| O usuário não autoriza o recomeço do git                                                            | Valem as regras 1 a 37 e 43 a 45; a feature fecha quando o fluxo da regra 40 rodar ou o usuário decidir não rodá-lo, e a spec registra a decisão |
| O repositório do GitHub não pode sair da rede de forks (privado ou maior que 1 GB)                  | Passo 3 pela outra via: apagar e recriar com o mesmo nome, com as perdas da regra 41                                                             |
| Algum outro clone do repo (outra máquina) tem o histórico antigo                                    | O primeiro `pull` falha por histórico divergente; o clone é descartado e refeito                                                                 |
| Neovim 0.11 ou anterior                                                                             | Regra 43: a mensagem `Claudinho requires Neovim >= 0.12` e nada mais; o README lista o requisito                                                 |
| Teste ou comentário que cita o comportamento do Neovim 0.8 a 0.11                                   | O teste continua e passa na 0.12; a spec decide caso a caso se o comentário ainda vale                                                           |

## Approach

Esta fase não cria tela nem fluxo novo de uso. Os estados de UI (loading, vazio, erro, sucesso, permissão negada, offline) continuam os de hoje para o terminal, o diff e o envio. O que muda para quem usa e para quem mantém:

| Área                      | Antes                                                               | Depois                                                                                                             |
| ------------------------- | ------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| Instalação                | `coder/claudecode.nvim`, `require("claudecode")`                    | `pedrohrb7/claudinho.nvim`, `require("claudinho")`                                                                 |
| Terminal                  | `auto`, `native`, `snacks`, `external`, `none`                      | `auto` (= `native`), `native`, `external`, `none`                                                                  |
| Config                    | Opções legadas aceitas em silêncio                                  | Aviso por chave removida                                                                                           |
| Integração em user config | Eventos, highlights e `vim.g` com `ClaudeCode`/`claudecode`         | Com `Claudinho`/`claudinho`                                                                                        |
| Docs                      | README do upstream e sete docs de desenvolvimento                   | `README.md` (pt-BR), `README.en.md`, `CLAUDE.md` curto, `PROTOCOL.md` e `ARCHITECTURE.md` de referência, e `docs/` |
| CI                        | Testes, TLA+, release-please, release notes, PR title, issue triage | Format, lint e testes                                                                                              |
| Versão                    | `0.4.0`, release-please a cada push                                 | `0.1.0`, à mão no fechamento de cada feature                                                                       |
| Neovim mínimo             | 0.8.0 no loader, no health check e no CI                            | 0.12 nos três                                                                                                      |
| Git                       | Histórico e vínculo de fork do upstream                             | Um commit inicial, sem vínculo                                                                                     |

A ordem de trabalho fica para a spec, com duas restrições de produto. A suíte fica verde ao fim de cada passo (rename, snacks, opções legadas, remoções, docs), para uma regressão apontar o passo que a causou. E o recomeço do git é sempre o último passo.

## Risks & mitigations

| Risco                                                                                                                 | Impacto                                    | Mitigação                                                                                                               |
| --------------------------------------------------------------------------------------------------------------------- | ------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------- |
| Um nome antigo escapa do rename num caminho sem teste                                                                 | Erro em tempo de execução para o usuário   | Critério do `rg -i claudecode` com as exceções da regra 6; suíte completa; sessão real da regra 30                      |
| O Claude depende do nome do servidor no `initialize`                                                                  | `/ide` ou as tools param                   | Regra 5: verificar antes e manter o nome antigo se preciso                                                              |
| Sem as skills de verificação e o TLA+, regressões de diff, seleção e fila de @-mentions que os modelos pegavam passam | Bugs sutis nessas áreas                    | Os testes de unidade e integração dessas áreas ficam todos; as fases que reescrevem cada área trazem os próprios testes |
| Sem o `lua/claudecode/README.md`, o comportamento detalhado de diff e terminal só fica nos testes e no código         | A Fase 2 começa com menos referência       | O texto continua no bundle e no upstream público, no commit da regra 37; `PROTOCOL.md` e `ARCHITECTURE.md` ficam        |
| Sem histórico compartilhado, portar correções do upstream vira trabalho manual (sem `cherry-pick` nem `merge-base`)   | Correções de protocolo chegam com atraso   | Comparar à mão com o upstream a partir do commit da regra 37, só para `server/` e `tools/`                              |
| O recomeço do git é irreversível no remoto                                                                            | Perda de histórico, issues e PRs no GitHub | Regras 38 a 41: backup antes, autorização a cada passo, perdas confirmadas pelo usuário                                 |
| Regras de branch do GitHub exigem checks removidos                                                                    | PRs bloqueados depois do recomeço          | Passo 5 da regra 40                                                                                                     |
| Quem usava o float do snacks perde a janela flutuante até a UI base                                                   | Mudança visível no uso diário              | Aviso da regra 9; nota no README; a UI base é a próxima fase                                                            |
| Os comandos `:ClaudeCode*` num plugin chamado Claudinho confundem durante a transição                                 | Dúvida de quem lê o README                 | Nota nos dois READMEs (regra 32) de que os comandos mudam na UI base                                                    |
| Algum teste depende de um comportamento que mudou entre o Neovim 0.8 e o 0.12                                         | Teste vermelho no job da versão mínima     | A suíte local já roda no 0.12.3; a spec roda a matriz nova antes do recomeço do git (regra 39)                          |

## Open questions

Nenhuma em aberto. Todas decididas pelo usuário em 2026-11-12:

1. **Onde ficam `PROTOCOL.md` e `ARCHITECTURE.md`:** na raiz, até o usuário estruturar as docs técnicas (regra 35).
2. **Idioma do CHANGELOG:** inglês, como o código (regra 26).
3. **Claudinho com o claudecode.nvim carregado:** não carrega e avisa (regra 7).
4. **Variáveis `vim.g.claudecode_*` antigas:** ignoradas sem aviso, documentadas no README (casos de borda).
5. **`.claude/`:** fica, como ferramenta de quem desenvolve o fork com o Claude (regra 18).
6. **Backup do histórico:** `git bundle` fora do repo antes de recomeçar (regra 40, passo 1).
7. **Via de desvínculo no GitHub:** "Leave fork network" quando o repositório for elegível; senão, apagar e recriar com o mesmo nome (regra 40, passo 3).
8. **O que deixava de valer no `docs/PRD.md`:** o PRD foi atualizado e aprovado em 2026-11-12 (ponto de partida `d123707`, docs do upstream que ficam, riscos, itens da Fase 0 e primeiros passos), antes da spec.

Decidido na mesma revisão, fora da lista acima: Neovim mínimo 0.12 (regras 2 e 43 a 45).
