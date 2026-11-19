# Perfis de aba: `:Claudinho new <perfil>` com perfis nomeados no `setup`

- **Date:** 2026-11-19
- **Status:** Draft
- **Spec:** [spec.md](spec.md) <!-- quando existir -->
- **Decisões do usuário (2026-11-19):** opção 2 de duas: perfis nomeados no `setup` (`profiles = { review = { model = "sonnet", effort = "medium", mode = "plan" } }`) e `:Claudinho new review` abre uma aba configurada pelo perfil. A opção 1 é a [aba-com-opcoes](../aba-com-opcoes/plan.md) (Draft), base desta feature. Valem dela, sem reabrir: opções só no `new`; uma opção do `new` vence a mesma opção do `terminal_cmd` só naquela aba, e o plugin a tira do argv; o `tab-restart` reaplica as opções da abertura, mesmo depois de trocas na TUI; opção ou valor inválido (inclusive `--effort` desconhecido) é recusado antes de criar a aba; sem prompt inicial; `bypassPermissions` e `dontAsk` sem confirmação, com um aviso que sempre aparece (também no restart).
- **Revisão 2026-11-19:** o usuário decidiu quatro das oito perguntas abertas: o perfil tem `model`, `effort`, `mode` e `args`, sem `env`, diretório nem layout (regras 3 a 5); não há perfil padrão, e o `terminal_cmd` continua o padrão de toda aba (regra 34); o nome do perfil aparece só no lugar de `Claude <n>`, até o Claude dar o título dele (regra 25); abrir abas no início do Neovim fica fora (regra 36). As outras quatro seguem a recomendação, porque decorrem de decisões já tomadas na aba-com-opcoes, e o usuário pode revê-las ao validar este Draft: perfil inválido no `setup` fica desligado, com erro sempre visível, e o resto da config funciona (regras 8 a 10); o `tab-restart` reaplica as opções guardadas na abertura, não o perfil atual (regras 28 e 29); uma opção de lista digitada substitui a mesma opção do perfil (regra 18); os adendos na aba-com-opcoes e na base-ui entram na entrega desta feature (regra 37).

## Goal

Dar um nome a um conjunto de opções do `claude` usado com frequência e abrir uma aba com ele numa palavra: `:Claudinho new review`. O perfil vive na config, é conferido cedo (no `setup` e no `:checkhealth`) e de novo na abertura, combina com as opções digitadas no `new` (a digitada vence), e uma aba aberta com um perfil se comporta exatamente como uma aba aberta com as mesmas opções digitadas.

Critérios de sucesso, todos verificáveis na máquina do usuário (Claude Code 2.1.328 ou a versão instalada na entrega, registrada no log):

| Critério                       | Como medir                                                                                                                                                                                                                                                        |
| ------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Aba pelo perfil                | Com `profiles = { review = { model = "sonnet", effort = "medium", mode = "plan" } }`, `:Claudinho new review` abre uma aba nova; o primeiro status mostra o Sonnet e `medium`, e o modo mostra `plan`                                                             |
| Digitada vence o perfil        | `:Claudinho new review --effort high` abre com `high`; o comando da aba tem um `--effort` só                                                                                                                                                                      |
| Perfil vence o `terminal_cmd`  | Com `terminal_cmd = "claude --model opus"`, `new review` abre no Sonnet, sem `--model opus` no comando da aba; `new` sem perfil continua no Opus                                                                                                                  |
| Perfil com `args`              | `profiles.docs = { args = { "--append-system-prompt", "be brief" } }`: `new docs` abre com a opção e o valor como uma palavra só                                                                                                                                  |
| Completion                     | `:Claudinho new <Tab>` lista os perfis válidos em ordem alfabética, depois as opções; `new r<Tab>` filtra; depois de `new review `, lista as opções (inclusive `--model`)                                                                                         |
| Perfil inválido no `setup`     | Com `notify = false`, `profiles.review = { efort = "high" }` mostra um erro de config que nomeia o perfil e a chave; o resto da config e os outros perfis funcionam; `new review` é recusado com o mesmo motivo e não deixa aba, servidor, lock file nem settings |
| Valor inválido na abertura     | `profiles.review = { effort = "foo" }`: `new review` é recusado antes da aba, com um erro que nomeia o perfil; `:checkhealth claudinho` mostra o mesmo erro sem abrir aba                                                                                         |
| Restart guarda o perfil aberto | Uma aba aberta com `review`; o usuário muda o perfil (ou o remove) e chama o `setup` de novo; a aba termina; `tab-restart` volta com as opções da abertura, sem erro                                                                                              |
| Avisos de segurança            | Com `notify = false`, um perfil com `mode = "bypassPermissions"` mostra o aviso da regra 26 da aba-com-opcoes na abertura e no `tab-restart`; `new <esse perfil> --permission-mode plan` não mostra                                                               |
| Título                         | Logo depois de `new review`, enquanto o Claude não dá um título próprio, a barra mostra `1 review`; com o título do Claude, mostra o título dele                                                                                                                  |
| Nada muda sem perfil           | Sem `profiles`, ou com `new` sem perfil, `toggle`, `open`, `focus`, o `+` da barra, `<leader>an` e `select-model`: comportamento da aba-com-opcoes, sem diferença                                                                                                 |
| Entrega fechada                | `mise run all` verde, README (pt e en) atualizado, adendos na [base-ui](../base-ui/plan.md) e na [aba-com-opcoes](../aba-com-opcoes/plan.md), nenhuma entrada nova em `docs/backlog/` e a release da próxima minor (`mise run release minor`)                     |

## Context

A [aba-com-opcoes](../aba-com-opcoes/plan.md) dá ao `new` as opções do `claude`, mas quem usa sempre as mesmas combinações (uma aba de revisão em `plan` no Sonnet, uma de trabalho no Opus) digita a linha inteira a cada aba. Aquele plano deixou a porta aberta: a primeira palavra depois de `new` ficou reservada para o nome de um perfil (regra 4 dele), e as opções de abertura de uma aba são uma lista de argumentos que um perfil pode gerar (Context dele). Esta feature começa depois que a aba-com-opcoes fechar (ordem do roadmap no [PRD](../../PRD.md)): quase todo o comportamento vem de lá.

O que já existe no código e nos planos:

| Fato                                                                                                                                                                                                     | Consequência                                                                                              |
| -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| `config.lua`: as chaves antigas são conferidas com `assert` (o `setup` falha); as chaves da base-ui (`window`, `keymaps`, `notify`) caem no padrão com um erro que nomeia a chave (`normalize_new_keys`) | `profiles` segue o modelo da base-ui: erro sempre visível, o resto da config funciona                     |
| O `setup` pode ser chamado de novo (recarregar a config) e troca a config que as abas novas leem (`config.current()` em `sessions.new`)                                                                  | Um perfil mudado vale para as abas novas; as abertas ficam com o que guardaram (regra 28)                 |
| O `setup` não inicia nada (regra 2 da base-ui) e `terminal.auto_start` foi removido (regra 71 da base-ui)                                                                                                | Abrir abas no início do Neovim fica fora                                                                  |
| A barra mostra `Claude <n>` quando o título do terminal é vazio ou genérico (regra 11 da base-ui, `ui/tabbar.lua` `clean_title`)                                                                         | Lugar para o nome do perfil sem gastar largura                                                            |
| aba-com-opcoes: validação pelo `claude --help` lido uma vez por sessão do Neovim, só quando precisa; validação reduzida sem ele (regras 9 a 16)                                                          | O `setup` não pode rodar o `claude`: só a forma do perfil é conferida nele, os valores na abertura        |
| aba-com-opcoes: o `terminal_cmd` perde cada opção que o `new` dá, em qualquer forma (regra 5); as opções de abertura são guardadas em memória e reaplicadas no `tab-restart` (regras 30 a 34)            | Um perfil vira uma camada entre o `terminal_cmd` e as opções digitadas, com a mesma regra de substituição |
| aba-com-opcoes: a statusline mostra só o que o Claude informa (regra 21) e as opções não aparecem na barra nem na statusline (Out of scope)                                                              | O nome do perfil não entra na statusline; na barra, só no lugar do `Claude <n>` (regra 25)                |
| `:checkhealth claudinho` vai reportar a leitura do `claude --help` (regra 15 da aba-com-opcoes)                                                                                                          | Lugar para conferir os valores dos perfis sem abrir aba                                                   |

## Scope

**In scope:**

- A chave `profiles` no `setup`: nomes, as chaves `model`, `effort`, `mode` e `args`, e a conferência da forma no `setup`.
- `:Claudinho new <perfil> [opções]`, com a precedência opção digitada > perfil > `terminal_cmd`.
- Validação das opções do perfil na abertura, com as regras da aba-com-opcoes.
- Nome do perfil no título da aba no lugar de `Claude <n>`.
- Opções de abertura de uma aba de perfil guardadas na abertura e reaplicadas no `tab-restart`, mesmo depois de o perfil mudar ou sumir da config.
- Completion dos nomes de perfil.
- Perfis no `:checkhealth claudinho`.
- Adendo na [base-ui](../base-ui/plan.md) (regras 11, 64, 68 e 70) e na [aba-com-opcoes](../aba-com-opcoes/plan.md) (regras 4, 5, 11, 26, 28, 30 e 38), na entrega (regra 37).
- README (pt e en): a chave `profiles` com exemplo, a precedência, o restart, o `:checkhealth`, um exemplo de atalho do usuário para um perfil; `CHANGELOG.md`.
- Testes, com fixtures de `claude --help` reais e configs com perfis válidos e inválidos.

**Out of scope:**

- Perfil padrão (usado por `new` sem perfil, `toggle`, `+` e envios): o `terminal_cmd` já é o padrão de toda aba (regra 34, decisão do usuário).
- Abrir várias abas configuradas no início do Neovim: o `setup` não inicia nada (regra 2 da base-ui) e `terminal.auto_start` foi removido de propósito (regra 71 da base-ui); quem quiser pode chamar `:Claudinho new <perfil>` num autocmd da própria config (regra 36, decisão do usuário).
- Variáveis de ambiente por perfil (o `env` da config vale para todas as abas), diretório por perfil (a aba sempre inicia no `getcwd()`, regra 93 da base-ui) e layout por perfil (uma janela por Neovim, regras 16 e 85 da base-ui) (decisão do usuário).
- Perfis em `toggle`, `open`, `focus`, `select-model`, no `+` da barra, nos envios e no preset de atalhos; subcomando novo para listar ou editar perfis; escolha de perfil por um seletor (`vim.ui.select`).
- Herança entre perfis (`extends`) e perfis fora do `setup` (arquivo próprio, por projeto).
- Nome do perfil na statusline.
- Reaplicar no `tab-restart` o perfil como está na config depois de mudado (regra 28).
- Uma API Lua pública para abrir aba com perfil.

## Business rules

Os textos que o plugin mostra saem em inglês (adendo de idioma da base-ui); o formato fica aqui e o texto final na spec. As regras da [aba-com-opcoes](../aba-com-opcoes/plan.md) valem como estão, salvo onde este plano diz o contrário (tabela da regra 37).

### O perfil na config

1. A config ganha a chave `profiles`: uma tabela de nome para perfil. Sem a chave, ou com ela vazia, não há perfis e nada muda.
2. Nome de perfil: começa com uma letra ou um dígito ASCII, seguido de letras, dígitos, `-` ou `_` (ex.: `review`, `quick-fix`, `opus_1m`). Maiúsculas contam: `Review` e `review` são dois perfis. Um nome nunca começa com `-`, para não ser lido como opção.
3. Um perfil é uma tabela com estas chaves, todas opcionais:

| Chave    | Tipo             | Vira                                                           |
| -------- | ---------------- | -------------------------------------------------------------- |
| `model`  | string           | `--model <valor>`                                              |
| `effort` | string           | `--effort <valor>`                                             |
| `mode`   | string           | `--permission-mode <valor>`                                    |
| `args`   | lista de strings | as palavras como estão, uma palavra do argv por item, na ordem |

4. As opções do perfil ficam nesta ordem: `model`, `effort`, `mode`, depois `args`. Os valores chegam ao `claude` como escritos, sem shell e sem separar por espaços: `args = { "--append-system-prompt", "be brief" }` é uma opção com um valor, e `model = "opus[1m]"` chega como está.
5. `args` aceita o mesmo que o `new` aceita digitado (regras 2, 3 e 6 da aba-com-opcoes): opções que o `claude` instalado declara, nas formas `--opção valor` e `--opção=valor`, menos as reservadas. Serve para o que as três chaves não cobrem (ex.: `--add-dir`, `--append-system-prompt`, `--agent`).
6. Um perfil vazio (`{}`) é válido: abre a aba sem opções de perfil, com o nome dele no título (regra 25).

### Conferência no `setup`

7. O `setup` confere a forma de cada perfil sem rodar o `claude` (o `setup` não inicia nada, regra 2 da base-ui):
   - o nome segue a regra 2 e o perfil é uma tabela;
   - só as chaves da regra 3 (uma chave a mais, ex.: `efort`, é falha, não é ignorada);
   - `model`, `effort` e `mode` são strings não vazias que não começam com `-` (a aba-com-opcoes recusa uma opção seguida de outra no lugar do valor, regra 11 dela);
   - `args` é uma lista, sem buracos, de strings não vazias, e começa com uma opção (palavra com `-`), não com uma palavra solta;
   - `args` não tem opção reservada (regra 6 da aba-com-opcoes) na forma longa, curta ou com `=`;
   - `args` não repete o que uma chave já dá: `--model` com `model`, `--effort` com `effort`, `--permission-mode` ou `--dangerously-skip-permissions` com `mode`, na forma longa, com ou sem `=`. A mesma repetição por nome curto ou alias, que só o `--help` revela, é recusada na abertura (regra 15).
8. Um perfil com qualquer falha da regra 7 fica desligado por inteiro: nunca é usado em parte. O resto da config e os outros perfis funcionam.
9. Cada falha gera um erro de config que nomeia o perfil, a chave e o motivo (ex.: `[Claudinho] profiles.review.efort is not a valid key; profile 'review' is disabled`). É erro de config: sempre aparece, com `notify` ligado ou desligado (regras 82 e 88 da base-ui), uma vez por chamada do `setup`.
10. `profiles` que não é uma tabela: erro de config, nenhum perfil, o resto funciona.
11. O que depende do `claude` instalado (opção desconhecida, valor de `effort` ou `mode` fora das escolhas, quantas palavras cada opção de `args` leva, palavra solta no meio de `args`) não é conferido no `setup`: é conferido na abertura (regra 14) e no `:checkhealth` (regra 30).

### Abrir com um perfil

12. `:Claudinho new <perfil> [opções]`: a primeira palavra depois de `new` que não começa com `-` é o nome de um perfil (a posição que a regra 4 da aba-com-opcoes reservou). Só a primeira: um nome em outra posição é uma palavra solta, recusada pela regra 4 da aba-com-opcoes.
13. Recusas antes de criar qualquer coisa (regra 9 da aba-com-opcoes), sempre visíveis (regra 16 da aba-com-opcoes):

| Situação                                                       | Erro                                                                                                     |
| -------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| Perfil que não existe                                          | `[Claudinho] new: unknown profile 'foo'. Profiles: quick, review` (sem perfis: `No profiles configured`) |
| Perfil desligado no `setup` (regra 8)                          | `[Claudinho] new: profile 'review' is disabled: <motivo do erro do setup>`                               |
| Nome de perfil depois de uma opção (`new --model opus review`) | `[Claudinho] new: 'review' is not an option (a profile goes right after new)`                            |

14. As opções do perfil passam pela mesma validação das digitadas (regras 9 a 16 da aba-com-opcoes), contra o `claude --help` instalado, no mesmo passo. Qualquer falha, do perfil ou das digitadas, recusa o comando inteiro. Um erro que vem do perfil nomeia o perfil: `[Claudinho] new: profile 'review': option '--effort <level>' argument 'foo' is invalid. Allowed choices are ...`.
15. Dentro do perfil, uma opção dada por uma chave e de novo em `args` por nome curto ou alias também é recusada aqui, como na regra 7: `[Claudinho] new: profile 'review': --model is given twice`.
16. Sem o `claude --help` (regra 15 da aba-com-opcoes), o perfil passa pela mesma validação reduzida; o resto vai ao `claude`, e a regra 18 da aba-com-opcoes desfaz uma aba que não inicia.

### Precedência: opção digitada > perfil > `terminal_cmd`

17. O comando da aba tem três camadas, da mais fraca à mais forte: o `terminal_cmd`, as opções do perfil e as opções digitadas no `new`. Uma opção de uma camada tira a mesma opção de todas as camadas abaixo, com o valor, em qualquer forma, como a regra 5 da aba-com-opcoes faz com o `terminal_cmd`: forma longa, curta, aliases, com `=`, e `--permission-mode` e `--dangerously-skip-permissions` contando como a mesma opção.
18. Vale também para opções de lista: `new docs --add-dir ../b` com um perfil que dá `--add-dir ../a` abre só com `../b`, como a aba-com-opcoes já faz entre o `new` e o `terminal_cmd`.
19. Dentro de uma camada, as repetições seguem a regra 5 da aba-com-opcoes: opção de valor único, vale a última; opção de lista e opção sem valor, todas, como escritas.
20. As opções de abertura da aba (regra 30 da aba-com-opcoes) são as opções do perfil que sobraram, na ordem da regra 4, seguidas das digitadas, na ordem digitada. O comando da aba é o da regra 5 da aba-com-opcoes com elas: o `terminal_cmd` sem as opções de abertura, o `--settings` do plugin, as opções de abertura.
21. Sem o `claude --help`, a remoção entre camadas segue o limite da regra 5 da aba-com-opcoes: vale para `--model`, `--effort`, `--permission-mode` e `--dangerously-skip-permissions`; as outras opções repetidas vão como estão.
22. A config não muda: o `terminal_cmd` e o perfil continuam iguais para as outras abas.

### A aba aberta com um perfil

23. Uma aba aberta com um perfil, mesmo vazio, é uma aba aberta com opções: valem as regras 17 a 20 (partida; a aba some se o `claude` sai antes de ficar pronta, com o prefixo `new`) e 30 a 34 (`tab-restart`) da aba-com-opcoes.
24. A aba guarda, só em memória e enquanto existe, o nome do perfil e as opções de abertura montadas na abertura (regra 20). Fechar a aba as descarta, como na regra 30 da aba-com-opcoes.
25. Título: quando a barra mostraria `Claude <n>` (título vazio ou genérico, regra 11 da base-ui), ela mostra o nome do perfil: `1 review`. Um título real do Claude substitui o nome, como substitui `Claude <n>`, e o nome segue o corte da regra 12 da base-ui. Mensagens, avisos e o nome no `/ide` continuam com `Claude <n>` e `Neovim (Claudinho <n>)`.
26. A statusline não muda: mostra só o que o Claude informa (regra 21 da aba-com-opcoes). O nome do perfil não aparece nela, e o plugin nunca preenche modelo, esforço ou modo a partir do perfil.
27. Avisos: o aviso da regra 26 da aba-com-opcoes considera as opções de abertura depois da precedência (regra 17), venham do perfil ou digitadas. Um perfil com `mode = "bypassPermissions"`, `mode = "dontAsk"` ou `--dangerously-skip-permissions` em `args` gera o aviso na abertura e em cada `tab-restart`; `new <esse perfil> --permission-mode plan` não gera, porque a digitada venceu.

### `tab-restart`

28. `tab-restart` reaplica as opções de abertura guardadas (regra 24), não o perfil como está na config: mudar, desligar ou remover o perfil num novo `setup` não muda o restart de uma aba que já existe, e o restart não confere o perfil de novo (regra 33 da aba-com-opcoes). O `terminal_cmd` é o da config atual, como na regra 31 da aba-com-opcoes.
29. Para usar o perfil mudado, o usuário abre outra aba com `new <perfil>`. A aba reiniciada mantém o nome do perfil no título (regra 25), mesmo que ele não exista mais na config.

### `:checkhealth`

30. `:checkhealth claudinho` lista os perfis, sem abrir aba: ok; desligado no `setup`, como erro, com o motivo da regra 9; ou com uma opção ou valor recusado pelo `claude --help` instalado, como erro, com a mensagem da regra 14. Sem o `--help`, um aviso diz que os valores dos perfis não foram conferidos. Sem perfis, uma linha informativa.

### Completion

31. Depois de `:Claudinho new `, a completion lista os nomes dos perfis válidos, em ordem alfabética, e depois as opções da regra 38 da aba-com-opcoes. Perfis desligados (regra 8) não são listados.
32. Os nomes de perfil só aparecem na primeira posição. Depois de um perfil, a completion é a das opções (regras 38 a 43 da aba-com-opcoes), inclusive `--model`, `--effort` e `--permission-mode` que o perfil já dá, porque a digitada vence o perfil.
33. Listar os nomes não depende do `claude --help`, e filtra pelo prefixo digitado, como os outros subcomandos (regra 68 da base-ui).

### Outras entradas

34. Não há perfil padrão. `new` sem perfil, `toggle`, `open` e `focus` sem abas, o `+` da barra, `<leader>an`, `select-model` e os envios que criam a aba 1 abrem como na aba-com-opcoes (regras 35 e 36 dela), com o `terminal_cmd`.
35. Nenhum subcomando novo e nenhuma tecla nova no preset. Um atalho para um perfil é do usuário (ex.: `vim.keymap.set("n", "<leader>ar", "<cmd>Claudinho new review<cr>")`), e o README mostra o exemplo.
36. O `setup` continua sem abrir aba (regra 2 da base-ui), com ou sem perfis.

### Relação com as regras da aba-com-opcoes e da base-ui

37. Quando esta feature for entregue, estas regras passam a valer como abaixo; na entrega, um adendo datado na aba-com-opcoes e outro na base-ui apontam para cá. A aba-com-opcoes é Draft e, pela convenção do projeto, um Draft é revisado no lugar, sem adendo; como ela fecha antes desta feature e já reservou a primeira posição para os perfis, nada nela fica errado até lá:

| Plano e regra                                        | O que muda                                                                                                                                 | Regra nova aqui |
| ---------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ | --------------- |
| aba-com-opcoes 4 (só opções)                         | A primeira palavra depois de `new` que não começa com `-` é um nome de perfil                                                              | 12              |
| aba-com-opcoes 11 (recusas)                          | A palavra na primeira posição deixa de ser `'hello' is not an option` e passa a ser `unknown profile 'hello'`; entram as recusas de perfil | 13 a 15         |
| aba-com-opcoes 26 e 28 (avisos)                      | "As opções do `new`" passam a ser as opções de abertura: as do perfil e as digitadas, depois da precedência                                | 27              |
| aba-com-opcoes 5 e 30 (comando e opções de abertura) | Entre o `terminal_cmd` e as digitadas entra a camada do perfil, com a mesma regra de substituição                                          | 17 a 20         |
| aba-com-opcoes 38 (completion)                       | Depois de `new `, os nomes dos perfis vêm antes das opções                                                                                 | 31 a 33         |
| base-ui 11 (título)                                  | Numa aba de perfil, o título vazio ou genérico mostra o nome do perfil em vez de `Claude <n>`                                              | 25              |
| base-ui 64 (subcomandos)                             | A linha `new [opções]` passa a ser `new [perfil] [opções]`                                                                                 | 12              |
| base-ui 68 (completion)                              | Nomes de perfil depois de `new`                                                                                                            | 31              |
| base-ui 70 (config)                                  | A config ganha `profiles`                                                                                                                  | 1 a 11          |

## Edge cases

| Situação                                                                                        | Comportamento esperado                                                                                                                                       |
| ----------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Sem `profiles` na config                                                                        | Tudo como na aba-com-opcoes; `new hello` responde `unknown profile 'hello'. No profiles configured` (regra 13)                                               |
| `new review` com `review` válido                                                                | Aba aberta com as opções do perfil; título `review` até o Claude dar o dele                                                                                  |
| `new review --effort high`, o perfil com `effort = "medium"`                                    | `high`: a digitada tira a do perfil (regra 17); o comando tem um `--effort` só                                                                               |
| `new review --model sonnet --model opus`                                                        | `opus`: na camada digitada vale a última (regra 19), e ela vence o perfil                                                                                    |
| `new --model opus review`                                                                       | Recusado: o nome do perfil precisa vir logo depois de `new` (regra 13)                                                                                       |
| `new review docs`                                                                               | Recusado: `docs` é palavra solta (regra 12); não existe combinar dois perfis                                                                                 |
| `new Review` com só `review` na config                                                          | Recusado: `unknown profile 'Review'`, com a lista dos perfis (regras 2 e 13)                                                                                 |
| `new foo` sem perfil `foo`                                                                      | Recusado; a mensagem lista os perfis válidos (regra 13)                                                                                                      |
| Perfil com chave a mais (`efort = "high"`)                                                      | Erro de config no `setup`; o perfil fica desligado; `new review` repete o motivo (regras 8, 9 e 13)                                                          |
| Perfil com nome inválido (`["my profile"]`, `["-x"]`, chave numérica de uma lista)              | Erro de config no `setup`; esse perfil não existe; os outros funcionam (regra 8)                                                                             |
| `profiles = "review"` (não tabela)                                                              | Erro de config; nenhum perfil; o resto da config funciona (regra 10)                                                                                         |
| `model = ""` ou `model = 1`                                                                     | Erro de config no `setup`; perfil desligado (regra 7)                                                                                                        |
| `model = "--version"`                                                                           | Erro de config no `setup`: valor que começa com `-` (regra 7)                                                                                                |
| `effort = "foo"` ou `mode = "foo"`                                                              | O `setup` aceita a forma; `new` recusa antes da aba, nomeando o perfil (regra 14); o `:checkhealth` mostra o erro (regra 30)                                 |
| `effort = "ultracode"` ou `mode = "default"`                                                    | Aceitos, pelas escolhas da regra 12 da aba-com-opcoes                                                                                                        |
| `model = "nao-existe"`                                                                          | Aceito: o valor de `--model` não é conferido (regra 14 da aba-com-opcoes); o Claude erra no primeiro pedido, na TUI                                          |
| `args = { "--resume", "abc" }`                                                                  | Erro de config no `setup`: opção reservada (regra 7)                                                                                                         |
| `args = { "hello" }`                                                                            | Erro de config no `setup`: `args` começa com palavra solta (regra 7)                                                                                         |
| `args = { "--verbose", "hello" }`                                                               | O `setup` aceita a forma; `new` recusa `hello` como palavra solta, pelo tipo de valor do `--help` (regras 11 e 14)                                           |
| `args = { "--foo" }`                                                                            | `new` recusa: opção desconhecida, nomeando o perfil (regra 14)                                                                                               |
| `model = "sonnet"` e `args = { "--model=opus" }`                                                | Erro de config no `setup`: a mesma opção duas vezes (regra 7)                                                                                                |
| `mode = "plan"` e `args = { "--dangerously-skip-permissions" }`                                 | Erro de config no `setup`: as duas definem o modo (regra 7)                                                                                                  |
| `model` e a mesma opção em `args` por nome curto ou alias                                       | `new` recusa: `--model is given twice` (regra 15)                                                                                                            |
| `args = { "--append-system-prompt", "be brief" }`                                               | Uma opção com um valor; nenhuma aspa necessária (regra 4)                                                                                                    |
| `args = { "--add-dir", "../a", "../b" }`                                                        | Lista com dois valores, como o `claude` lê (tipo do `--help`)                                                                                                |
| Perfil com `--add-dir ../a` e `new docs --add-dir ../b`                                         | Só `../b` (regra 18)                                                                                                                                         |
| `terminal_cmd = "claude --model opus --verbose"` e `new review` (perfil com `model`)            | O comando da aba fica `claude --verbose --settings <arquivo> --model sonnet ...` (regras 17 e 20)                                                            |
| `terminal_cmd` com `--dangerously-skip-permissions` e `new review` (perfil com `mode = "plan"`) | Inicia em `plan`, sem aviso: a opção do perfil tira as duas do `terminal_cmd`                                                                                |
| Perfil vazio `{}`                                                                               | Abre como `new` sem opções, mas com o título do perfil e as regras de aba com opções (regras 6 e 23)                                                         |
| Perfil com `mode = "bypassPermissions"`                                                         | Aviso na abertura e em cada restart; o diálogo de aceite do Claude na primeira vez continua (regra 27; regras 26 a 29 da aba-com-opcoes)                     |
| Perfil com `mode = "bypassPermissions"` e `new yolo --permission-mode plan`                     | `plan`, sem aviso (regra 27)                                                                                                                                 |
| Perfil com `mode = "auto"` sem o auto disponível                                                | O Claude inicia em Manual; o status mostra `manual` (regra 22 da aba-com-opcoes)                                                                             |
| O `claude` recusa uma opção do perfil só ao iniciar                                             | A aba some, sem sobras, com a saída do Claude (regra 18 da aba-com-opcoes)                                                                                   |
| `claude --help` ilegível                                                                        | Validação reduzida também para o perfil (regra 16); o `:checkhealth` avisa que os valores não foram conferidos (regra 30)                                    |
| `new review` duas vezes                                                                         | Duas abas independentes, ambas com o título `review` até o Claude dar o dele; os números as distinguem                                                       |
| O usuário muda `review` e chama o `setup` de novo                                               | Abas novas usam o perfil novo; abas abertas e o restart delas ficam com as opções da abertura (regra 28)                                                     |
| O usuário remove `review` e chama o `setup` de novo                                             | `new review` passa a responder `unknown profile`; o `tab-restart` das abas abertas com ele funciona como antes e o título continua `review` (regras 28 e 29) |
| O usuário desliga `review` (forma inválida) num novo `setup`                                    | Igual à linha anterior, com `new review` respondendo `is disabled` (regra 13)                                                                                |
| `terminal_cmd` mudou entre a abertura e o restart                                               | O restart usa o `terminal_cmd` novo, sem as opções de abertura (regra 28)                                                                                    |
| `tab-restart` de aba de perfil sem `session_id`                                                 | Conversa nova com as mesmas opções de abertura e a resposta de hoje (regra 31 da aba-com-opcoes)                                                             |
| Usuário troca modelo ou modo na TUI e a aba de perfil termina                                   | `tab-restart` volta às opções da abertura (regra 32 da aba-com-opcoes)                                                                                       |
| Perfil com `args = { "--name", "rev" }`                                                         | Aceito e reaplicado no restart; o título continua vindo do terminal, com o nome do perfil só no lugar de `Claude <n>` (regra 25)                             |
| Nome de perfil igual a um subcomando (`toggle`) ou a `default`                                  | Aceito: o nome só é lido depois de `new`; não há nome reservado                                                                                              |
| `select-model` sem abas                                                                         | Como hoje: aba 1 com `--model <valor>`, sem perfil (regra 34)                                                                                                |
| `env` da config com `ANTHROPIC_MODEL` e perfil com `model`                                      | O `--model` do perfil vence a variável                                                                                                                       |
| `vim.g.claudinho_auto_setup` com `profiles`                                                     | Conferência igual à do `setup` (regras 7 a 10)                                                                                                               |
| Completion com muitos perfis                                                                    | Todos os válidos, em ordem alfabética, antes das opções; o prefixo filtra (regras 31 e 33)                                                                   |

## Approach

### A config

```lua
require("claudinho").setup({
  profiles = {
    review = { model = "sonnet", effort = "medium", mode = "plan" },
    deep = { model = "opus[1m]", effort = "max" },
    docs = { args = { "--append-system-prompt", "Answer in Portuguese.", "--add-dir", "../shared" } },
  },
})
```

`:Claudinho new review`, `:Claudinho new deep --permission-mode acceptEdits`, `:Claudinho new docs --model haiku`.

### Montagem do comando da aba

| Camada (mais fraca primeiro) | Exemplo                                                                                     | O que acontece                                                                             |
| ---------------------------- | ------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| `terminal_cmd`               | `claude --model opus --verbose`                                                             | Perde toda opção que as camadas de cima dão (`--model opus` sai, `--verbose` fica)         |
| Perfil `review`              | `--model sonnet --effort medium --permission-mode plan`                                     | Perde toda opção que a camada digitada dá (`--effort medium` sai)                          |
| Digitadas                    | `--effort high`                                                                             | Ficam todas                                                                                |
| Resultado                    | `claude --verbose --settings <arquivo> --model sonnet --permission-mode plan --effort high` | Opções de abertura guardadas na aba: `--model sonnet --permission-mode plan --effort high` |

### Fluxos

| Fluxo                           | Passos                                                                                                                                                                                                       |
| ------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Configurar                      | `setup({ profiles = ... })` -> conferência da forma, sem rodar o `claude` -> erros de config para os perfis com falha -> os outros ficam disponíveis                                                         |
| Abrir com perfil                | `:Claudinho new review [opções]` -> o perfil existe e está ligado -> leitura do `claude --help` (só a primeira vez) -> validação do perfil e das digitadas -> precedência -> aba nova como na aba-com-opcoes |
| Perfil inexistente ou desligado | `new foo` -> erro com a lista dos perfis, ou com o motivo do `setup`; nada é criado                                                                                                                          |
| Valor inválido no perfil        | `new review` -> validação recusa -> erro que nomeia o perfil; nada é criado                                                                                                                                  |
| Reiniciar                       | Processo termina -> `[exited]` -> `tab-restart <n>` -> `claude --resume=<id>` + as opções de abertura guardadas, sem reler o perfil -> aviso de novo se o modo for `bypassPermissions` ou `dontAsk`          |
| Mudar um perfil                 | Editar a config -> `setup` de novo -> abas novas com o perfil novo; as abertas inalteradas                                                                                                                   |
| Conferir sem abrir aba          | `:checkhealth claudinho` -> cada perfil: ok, desligado ou valor recusado                                                                                                                                     |
| Completion                      | `:Claudinho new <Tab>` -> perfis, depois opções -> `new review <Tab>` -> opções                                                                                                                              |

### Estados

| Estado                                                                          | O que o usuário vê                                                                                                 |
| ------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| Carregando (primeiro `new` com perfil ou opções, primeira completion de opções) | Um atraso curto, uma vez por sessão do Neovim, enquanto o `claude --help` é lido (regra 10 da aba-com-opcoes)      |
| Vazio (sem perfis)                                                              | `new <Tab>` lista só as opções; `new foo` responde `No profiles configured`                                        |
| Aba iniciando                                                                   | Título `<perfil>` na barra; a TUI do Claude abrindo; status vazio até o primeiro dado                              |
| Sucesso                                                                         | A aba com o status do Claude refletindo as opções de abertura (ex.: `Sonnet <versão> · medium · plan`)             |
| Erro de config                                                                  | Erro no `setup` nomeando perfil, chave e motivo; o resto funciona                                                  |
| Erro na abertura                                                                | Nenhuma aba; erro com o perfil e o motivo                                                                          |
| Erro na partida                                                                 | A aba aparece e some; erro com a saída do Claude (regra 18 da aba-com-opcoes)                                      |
| Permissão negada (política bloqueia um modo)                                    | O que o Claude decidir, como na aba-com-opcoes: sai (erro na partida) ou inicia em outro modo, que o status mostra |
| Offline                                                                         | Nenhuma diferença: conferência, validação e completion são locais                                                  |

### O que o plugin faz (nível de produto)

- No `setup`, confere a forma de cada perfil e guarda os ligados; nunca roda o `claude` nem inicia nada.
- No `new`, troca o nome do perfil pelas opções dele, valida tudo como a aba-com-opcoes valida as digitadas, aplica a precedência e abre a aba pelo caminho da aba-com-opcoes.
- Guarda na aba o nome do perfil (para o título) e as opções de abertura (para o restart), em memória.
- No `:checkhealth`, confere os perfis contra o `claude --help` instalado.
- O servidor da aba, os settings da sessão, os hooks e a statusline não mudam.

### Documentação

- README (pt e en): a chave `profiles` com o exemplo acima, as chaves e o que cada uma vira; `new [perfil] [opções]` na tabela de comandos; a precedência opção digitada > perfil > `terminal_cmd`, inclusive para opções de lista; o `tab-restart` que usa as opções da abertura, não o perfil atual; o `:checkhealth`; um exemplo de atalho do usuário para um perfil.
- Adendos na base-ui e na aba-com-opcoes com a tabela da regra 37, e `CHANGELOG.md`.

## Risks & mitigations

| Risco                                                                                    | Impacto                                            | Mitigação                                                                                                                                                      |
| ---------------------------------------------------------------------------------------- | -------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Um valor inválido no perfil só aparece no primeiro `new` (o `setup` não roda o `claude`) | O usuário descobre o erro na hora de abrir a aba   | Regra 7 pega no `setup` tudo que não depende do `claude`; `:checkhealth` confere o resto sem abrir aba (regra 30); o erro do `new` nomeia o perfil (regra 14)  |
| Um erro de digitação numa chave (`efort`) passaria em silêncio                           | Aba aberta com o esforço errado                    | Chave a mais desliga o perfil com erro sempre visível (regras 7 a 9)                                                                                           |
| O restart com as opções antigas surpreende quem acabou de editar o perfil                | O usuário espera o perfil novo numa aba reiniciada | Decisão alinhada à regra 32 da aba-com-opcoes (a abertura é previsível); README explica; `new <perfil>` abre com o novo (regra 29)                             |
| `args` vira uma porta para opções reservadas                                             | Uma aba que não conecta ou não abre a TUI          | Regra 7 recusa as reservadas já no `setup`; a regra 18 da aba-com-opcoes desfaz uma aba que não inicia                                                         |
| Um perfil com `bypassPermissions` usado sem perceber (um atalho do usuário)              | Ferramentas rodam sem pedir                        | O aviso sempre aparece, na abertura e em cada restart (regra 27)                                                                                               |
| O nome do perfil no título confunde quando várias abas usam o mesmo perfil               | Duas abas `1 review` e `2 review`                  | O número da aba continua na frente; o título real do Claude substitui o nome (regra 25)                                                                        |
| A precedência entre três camadas é difícil de prever                                     | Opção esperada que não vale                        | Uma regra só, a da aba-com-opcoes, aplicada camada a camada (regra 17); tabela no README; testes com as formas longa, curta, alias, `=` e lista em cada camada |
| Mudança no formato do `claude --help`                                                    | Validação dos perfis reduzida                      | Regra 16 e a mitigação da aba-com-opcoes (validação reduzida, aba nunca pela metade, aviso no `:checkhealth`)                                                  |
| A aba-com-opcoes muda antes de ser entregue                                              | Regras daqui apontando para números que mudaram    | Esta feature começa depois que a aba-com-opcoes fecha; a spec confere os números citados contra o plano entregue                                               |

## Open questions

Nenhuma em aberto. As oito perguntas foram resolvidas em 2026-11-19 e estão nas regras: quatro pelo usuário (forma do perfil, regras 3 a 5; sem perfil padrão, regra 34; nome do perfil só no lugar de `Claude <n>`, regra 25; abas no início fora, regra 36) e quatro pela recomendação, que o usuário pode rever ao validar este Draft (perfil inválido no `setup` desligado, regras 8 a 10; restart com as opções da abertura, regras 28 e 29; opção de lista digitada substitui a do perfil, regra 18; adendos na entrega, regra 37).
