# Aba com opções: `:Claudinho new` com as opções do `claude`

- **Date:** 2026-11-19
- **Status:** Draft
- **Spec:** [spec.md](spec.md) <!-- quando existir -->
- **Decisões do usuário (2026-11-19):** abrir uma aba já configurada (`:Claudinho new --model sonnet --effort medium --permission-mode plan`), com completion; aceitar só as opções válidas, como o `claude` no terminal (regras 1 a 16); uma opção dada no `new` vence a mesma opção do `terminal_cmd` só naquela aba, e o plugin tira a repetida do comando (regra 5); `tab-restart` mantém as opções da abertura (regras 30 a 35); `bypassPermissions` e `dontAsk` abrem sem confirmação, com um aviso (regras 25 a 29). Perfis nomeados ficam para uma feature seguinte.
- **Revisão 2026-11-19:** o usuário decidiu as três perguntas abertas, todas como recomendado: o `tab-restart` reaplica as opções da abertura mesmo depois de uma troca na TUI (regra 32); `--effort` desconhecido é recusado antes da aba (regra 13); sem prompt inicial nem palavras soltas no `new` (regra 4). Confirmado também: só o `new` ganha opções; `toggle`, `open`, `focus` e `select-model` não mudam (regras 35 a 37).

## Goal

Abrir uma aba do Claude já com o modelo, o esforço, o modo de permissão ou qualquer outra opção do `claude`, num comando só, em vez de abrir a aba e trocar cada coisa dentro da TUI. Cada aba guarda as opções com que abriu e as reaplica no `tab-restart`. Uma opção inválida nunca deixa uma aba quebrada ou pela metade.

Critérios de sucesso, todos verificáveis na máquina do usuário (Claude Code 2.1.328 ou a versão instalada na entrega, registrada no log):

| Critério                                | Como medir                                                                                                                                                                                                                                                                   |
| --------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Aba configurada                         | `:Claudinho new --model sonnet --effort medium --permission-mode plan` abre uma aba nova; o primeiro status mostra o Sonnet e `medium`, e o modo mostra `plan` (pela leitura do rodapé do [status-interativo](../status-interativo/plan.md), ou no primeiro hook antes dela) |
| Abas independentes                      | Duas abas abertas com opções diferentes mostram, cada uma, o próprio modelo, esforço e modo ao serem ativadas                                                                                                                                                                |
| Completion                              | `:Claudinho new <Tab>` lista `--model`, `--effort` e `--permission-mode` primeiro; `--model <Tab>` lista os `value` de `models` da config; `--effort <Tab>` e `--permission-mode <Tab>` listam os valores do `claude` instalado                                              |
| Inválido não abre aba                   | `--permission-mode foo`, `--effort foo`, `--foo`, `--model` sem valor, uma palavra solta (`new hello`) e uma opção reservada (`--resume x`): nenhuma aba, nenhum servidor, lock file em `~/.claude/ide/` nem arquivo de settings sobra, e um erro diz o que estava errado    |
| Recusa na partida não deixa aba         | Uma opção que só o `claude` recusa ao iniciar (a spec escolhe um caso real medido): a aba some, sem sobras, e o erro mostra a mensagem do próprio `claude`                                                                                                                   |
| Restart mantém as opções                | Numa aba aberta com `--model sonnet --effort medium --permission-mode plan`, o processo é encerrado e `tab-restart` retoma a conversa com o mesmo modelo, esforço e modo, mesmo depois de uma troca feita na TUI                                                             |
| Avisos de segurança                     | Com `notify = false`, `new --permission-mode bypassPermissions`, `new --dangerously-skip-permissions` e `new --permission-mode dontAsk` abrem a aba e mostram o aviso da regra 26; o `tab-restart` dessas abas mostra o aviso de novo                                        |
| Opções do `new` vencem o `terminal_cmd` | Com `terminal_cmd = "claude --model opus"`, `new --model sonnet` abre no Sonnet, e o comando dessa aba não tem `--model opus` (nem com `--model=opus`); uma aba aberta sem opções continua com o `terminal_cmd` inteiro                                                      |
| Nada muda sem opções                    | `new` sem opções, `toggle`, `open`, `focus`, o `+` da barra e `<leader>an` abrem a aba como hoje                                                                                                                                                                             |
| Entrega fechada                         | `mise run all` verde, README (pt e en) atualizado, adendo na [base-ui](../base-ui/plan.md), nenhuma entrada nova em `docs/backlog/` e a release da próxima minor (`mise run release minor`)                                                                                  |

## Context

Cada aba já é um processo `claude` próprio (`session.lua`), então modelo, esforço e modo já são independentes por aba. Hoje o único jeito de mudá-los é dentro da TUI de cada aba, depois que ela abre.

O que já existe:

| Fato                                                                                                                                                                        | Consequência                                                                                                             |
| --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| `:Claudinho new` não recebe argumentos (`commands.lua`, `handlers.new` -> `sessions.new()`)                                                                                 | O comando ganha opções sem mudar o caso sem opções                                                                       |
| `sessions.new(extra_args)` já aceita argumentos extras; o `select-model` sem abas usa isso com `--model <valor>`                                                            | O caminho até o `claude` já existe                                                                                       |
| `session.start` monta o argv sem shell: `terminal_cmd` + `--settings <arquivo>` + os extras                                                                                 | `opus[1m]` chega ao `claude` como foi digitado; uma opção dada no `new` precisa sair do argv do `terminal_cmd` (regra 5) |
| `tab-restart` reabre com `--resume=<session_id>` e mais nada (`session.lua`, `restart`)                                                                                     | Hoje uma aba reiniciada perde o esforço e um `bypassPermissions` da abertura                                             |
| `claude --help` (2.1.328) lista todas as opções, com o tipo de valor (`<valor>`, `[valor]`, `<valores...>`) e, no `--permission-mode`, as escolhas; roda em cerca de 0,15 s | O plugin pode saber quais opções o `claude` instalado aceita, sem lista fixa no código                                   |

O que foi medido com o `claude` 2.1.328, sem abrir sessão:

| Entrada                     | O que o `claude` faz                                                                                                                                                     |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `--permission-mode foo`     | Sai com código 1: `error: option '--permission-mode <mode>' argument 'foo' is invalid. Allowed choices are acceptEdits, auto, bypassPermissions, manual, dontAsk, plan.` |
| `--permission-mode default` | Aceita (alias documentado de `manual`)                                                                                                                                   |
| `--effort foo`              | Não recusa: `Warning: Unknown --effort value 'foo' - ignoring it and using the default effort. Valid values: low, medium, high, xhigh, max.` e segue                     |
| `--effort ultracode`        | Aceita sem aviso, embora o `--help` não liste (a [referência do CLI](https://code.claude.com/docs/en/cli-reference) documenta)                                           |
| `--foo`                     | Sai com código 1: `error: unknown option '--foo'`                                                                                                                        |
| `--model nao-existe`        | Não recusa: avisa que não conhece o modelo e segue (aceita IDs de gateway e modelos novos)                                                                               |
| `--model --version`         | Lê `--version` como o nome do modelo                                                                                                                                     |
| `--foo --version`           | Mostra a versão e sai com 0: o `claude` não tem um modo de "só validar" as opções                                                                                        |

Da documentação do Claude Code:

- [Sessões](https://code.claude.com/docs/en/sessions): `--resume` restaura o modelo e o modo de permissão da conversa, exceto `bypassPermissions`, e `--permission-mode` passado no resume substitui o modo restaurado. Flags como `--add-dir`, `--mcp-config` e `--plugin-dir` não são restauradas e precisam ser passadas de novo.
- [Referência do CLI](https://code.claude.com/docs/en/cli-reference): `--effort` vale só para a sessão e não persiste; `--model` vence o `model` dos settings e o `ANTHROPIC_MODEL`; `--permission-mode` vence o `defaultMode` dos settings; `--dangerously-skip-permissions` equivale a `--permission-mode bypassPermissions`.
- [Modos de permissão](https://code.claude.com/docs/en/permission-modes): na primeira vez com `bypassPermissions`, o próprio Claude mostra um diálogo de aceite (recusar encerra o Claude); `dontAsk` nega toda ação que pediria permissão; `--permission-mode auto` sem o auto disponível inicia em Manual, sem erro.

Relação com a feature seguinte (perfis nomeados, fora do escopo): um perfil vai ser um nome para um conjunto de opções (`profiles = { review = { model = "sonnet", effort = "medium", mode = "plan" } }`, `:Claudinho new review`). Este plano não bloqueia isso: a primeira palavra depois de `new` que não é opção fica reservada (regra 4), e as opções de abertura de uma aba (regra 30) são uma lista de argumentos do `claude` que um perfil pode gerar.

## Scope

**In scope:**

- `:Claudinho new [opções]`, com as opções que o `claude` instalado declara, menos as reservadas.
- Validação antes de criar a aba, a partir do `claude --help` instalado, e a remoção completa da aba quando o `claude` recusa uma opção ao iniciar.
- Completion de nomes de opções e dos valores de `--model`, `--effort` e `--permission-mode`.
- Opções de abertura guardadas por aba e reaplicadas no `tab-restart`.
- Aviso ao abrir ou reiniciar uma aba em `bypassPermissions` ou `dontAsk`.
- Adendo na [base-ui](../base-ui/plan.md) apontando a mudança das regras 4, 41, 64 e 68.
- README (pt e en): o `new` com opções, a completion, as opções reservadas, os avisos e o `tab-restart`; `CHANGELOG.md`.
- Testes, com fixtures de saídas reais do `claude --help`.

**Out of scope:**

- Perfis nomeados na config e `:Claudinho new <perfil>`, e abrir várias abas configuradas no início (feature seguinte).
- Opções em `toggle`, `open`, `focus`, `select-model`, no `+` da barra, nos envios (`send`, `add`, `tree-add`, `send-text`) e no preset de atalhos.
- Prompt inicial (`claude "pergunta"`) e retomar uma conversa antiga numa aba nova (`--resume`, `--continue`).
- Opções padrão para toda aba nova na config (já existe o `terminal_cmd`).
- Mudar opções de uma aba que já está rodando, ou editar as opções de abertura guardadas.
- Mostrar as opções na barra de abas ou na statusline.
- Completion de valores de outras opções (caminhos de `--add-dir`, nomes de agentes etc.).
- Uma API Lua pública para abrir aba com opções.

## Business rules

Os textos que o plugin mostra saem em inglês (adendo de idioma da base-ui). Os textos dos avisos da regra 26 são os finais; as outras mensagens têm o formato definido aqui e o texto final na spec.

### Opções aceitas

1. `:Claudinho new [opções]` abre uma aba nova (regra 4 da base-ui) com o `claude` iniciado com essas opções. Sem opções, `new` é exatamente o de hoje.
2. Opções válidas são as que o `claude` instalado declara no `claude --help`: nomes longos, curtos e aliases (ex.: `--allowed-tools` e `--allowedTools`), cada uma com o tipo de valor que declara (sem valor, valor obrigatório, valor opcional, lista de valores). As opções reservadas da regra 6 ficam de fora.
3. As duas formas do `claude` valem: `--model sonnet` e `--model=sonnet`. As palavras são separadas como numa linha de comando de shell, com aspas agrupando (`--append-system-prompt "be brief"`), como no `terminal_cmd`. Nenhum shell roda: colchetes, `*` e `$` chegam ao `claude` como digitados (`opus[1m]`).
4. Só opções e os valores delas. Uma palavra que não é opção nem valor de uma opção (ex.: `new hello`, ou um prompt inicial do `claude`) é recusada. A primeira posição depois de `new` fica reservada para o nome de um perfil, na feature seguinte.
5. O `terminal_cmd` é o padrão de toda aba; as opções do `new` valem por cima dele, só naquela aba. O comando da aba é montado assim, sem depender de como o `claude` trata uma opção repetida (comportamento não documentado):
   - antes de montar o comando, o plugin tira do argv do `terminal_cmd` cada ocorrência de toda opção dada no `new`, com o valor dela, em qualquer forma: `--model opus`, `--model=opus`, o nome curto e os aliases que o `claude --help` declara para a mesma opção (ex.: `--allowedTools` e `--allowed-tools`);
   - quantas palavras saem com a opção segue o tipo de valor que o `--help` declara (regra 2): sem valor, só a opção; valor obrigatório, a opção e a palavra seguinte; valor opcional, a seguinte quando não começa com `-`; lista, as seguintes até a próxima que começa com `-`;
   - `--permission-mode` e `--dangerously-skip-permissions` contam como a mesma opção (as duas definem o modo inicial): uma delas no `new` tira as duas do `terminal_cmd`;
   - o resto do `terminal_cmd` fica, na mesma ordem: o programa, as opções que o `new` não deu e os valores delas;
   - depois vêm o `--settings` do plugin e as opções do `new`, na ordem digitada;
   - o `terminal_cmd` da config não muda: as outras abas, e as abertas sem opções, continuam com ele inteiro (um perfil, na feature seguinte, vale do mesmo jeito: por cima do `terminal_cmd`, só na aba);
   - uma opção de valor único repetida no próprio `new` (ex.: `--model sonnet --model opus`) vai só uma vez: o plugin manda a última ocorrência e tira as anteriores. Opções de lista (`--add-dir a --add-dir b`, como o `--help` mostra para `--plugin-dir`) e opções sem valor vão todas, como digitadas.
   - sem o `claude --help` (regra 15), a remoção e a deduplicação valem para `--model`, `--effort`, `--permission-mode` e `--dangerously-skip-permissions`, nas formas `--opção valor` e `--opção=valor`; as outras opções repetidas vão como estão.
6. Opções reservadas, recusadas antes de criar a aba, na forma longa, curta, alias ou com `=`:

| Opções                                                                                          | Por quê                                                             |
| ----------------------------------------------------------------------------------------------- | ------------------------------------------------------------------- |
| `--settings`                                                                                    | O plugin passa o arquivo de settings da sessão (statusline e hooks) |
| `--ide`                                                                                         | A aba já se conecta ao próprio servidor                             |
| `-r`/`--resume`, `-c`/`--continue`, `--fork-session`, `--from-pr`, `--teleport`, `--session-id` | `new` sempre abre uma conversa nova; a retomada é do `tab-restart`  |
| `-p`/`--print`                                                                                  | Não abre a TUI: responde e sai                                      |
| `--bg`/`--background`, `--desktop`, `--cloud`, `--environment`, `--tmux`                        | A sessão roda fora do terminal da aba                               |
| `-h`/`--help`, `-v`/`--version`                                                                 | Imprimem e saem                                                     |

7. Uma opção que o `claude` instalado não declara, mas que vira reservada numa versão nova por ser do mesmo tipo (um novo modo de rodar fora do terminal, por exemplo), passa ao `claude` até a lista da regra 6 ser atualizada; a regra 18 garante que uma aba que não inicia não sobra.
8. Abrir com opções segue o resto da regra 4 da base-ui: o menor número livre, o diretório atual do Neovim, a aba vira a ativa e a janela aparece com o terminal em foco.

### Validação antes de criar a aba

9. Antes de criar qualquer coisa (servidor, lock file, settings, buffer, processo), o plugin confere as opções contra o `claude --help` instalado. Qualquer falha recusa o comando inteiro: nenhuma aba é criada e um erro aparece.
10. O plugin lê o `claude --help` uma vez por sessão do Neovim, na primeira vez que precisa (completion depois de `new` ou um `new` com opções), com o mesmo comando do `terminal_cmd`. A leitura nunca trava o Neovim de forma perceptível.
11. Recusas da validação, no formato das mensagens do `claude` (texto final na spec):

| Situação                                                                  | Erro                                                                                                    |
| ------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| Opção que o `claude` não declara                                          | `[Claudinho] new: unknown option '--foo'`                                                               |
| Opção reservada (regra 6)                                                 | `[Claudinho] new: --resume can't be used with new (<motivo da tabela>)`                                 |
| Palavra solta (regra 4)                                                   | `[Claudinho] new: 'hello' is not an option`                                                             |
| Opção de valor obrigatório sem valor, ou seguida de outra opção           | `[Claudinho] new: option '--model <model>' argument missing`                                            |
| Valor fora das escolhas que o `--help` declara (ex.: `--permission-mode`) | `[Claudinho] new: option '--permission-mode <mode>' argument 'foo' is invalid. Allowed choices are ...` |
| Nível de esforço desconhecido                                             | `[Claudinho] new: option '--effort <level>' argument 'foo' is invalid. Allowed choices are ...`         |
| Opção sem valor recebendo valor com `=` (ex.: `--verbose=1`)              | `[Claudinho] new: option '--verbose' takes no value`                                                    |

12. Valores válidos de `--permission-mode`: as escolhas do `--help` mais `default` (alias documentado de `manual`). Valores válidos de `--effort`: os níveis listados no `--help` mais os que o `claude` instalado aceita sem aviso e a referência do CLI documenta (`ultracode` no 2.1.328; a spec confirma na versão da entrega). Outros valores (de `--model` e das demais opções) são do `claude`: a regra 18 cobre a recusa.
13. `--effort` com um nível desconhecido é recusado, embora o `claude` só avise e siga com o esforço padrão: o usuário pediu um esforço, e abrir com outro seria aceitar uma opção inválida (decisão do usuário).
14. O valor de `--model` não é conferido: o `claude` aceita aliases, nomes completos e IDs de gateway, e segue com um modelo que não conhece. Só a falta do valor é recusada (regra 11), porque o `claude` leria a opção seguinte como o nome do modelo.
15. Sem o `claude --help` (saída que o plugin não reconhece, ou o comando falhou): a validação fica só com o que não depende dele (opções reservadas, palavra solta na primeira posição, valor ausente em `--model`, `--effort` e `--permission-mode`), o resto vai ao `claude`, e a regra 18 cobre a recusa. A falha da leitura aparece uma vez como aviso informativo (só com `notify` ligado, regra 81 da base-ui) e no `:checkhealth claudinho`. Com o `claude` ausente, vale o erro de hoje de comando que não existe.
16. Erros de validação sempre aparecem, com `notify` ligado ou desligado (regra 82 da base-ui).

### Início da aba

17. Passada a validação, a aba abre como na regra 4 da base-ui, com o terminal à mostra: a TUI do `claude` aparece normalmente, inclusive os diálogos do próprio Claude (confiança da pasta, aceite do `bypassPermissions`), que o plugin nunca responde.
18. Se o `claude` de uma aba aberta com opções termina antes de a sessão ficar pronta (sinal de pronto definido na spec; nunca só um tempo limite), a aba some por completo: número livre de novo, sem servidor, lock file, settings nem buffer, e a ativa volta a ser a anterior (sem outras abas, a janela fecha). Um erro mostra o que o `claude` imprimiu: `[Claudinho] new: claude did not start: <últimas linhas da saída do claude>` (sem saída: `exited with code <n>`). Vale para qualquer motivo, inclusive o usuário recusar o aceite do `bypassPermissions`.
19. Uma aba aberta sem opções que termina na partida continua como hoje (`[exited]`, regra 40 da base-ui).
20. Depois de pronta, uma aba aberta com opções segue as regras de qualquer aba: se o processo terminar, fica `[exited]` (regra 40 da base-ui).

### Status

21. A statusline mostra só o que o Claude informa: modelo e esforço vêm do JSON da statusline (regras 48 e 49 da base-ui), e o modo vem dos hooks e da leitura do rodapé (regra 50 da base-ui e regra 29 do status-interativo). O plugin nunca preenche o status a partir das opções digitadas.
22. Até o primeiro dado chegar, o status fica como em qualquer aba nova (regra 51 da base-ui). Se o Claude ajustar uma opção (ex.: `--permission-mode auto` sem o auto disponível inicia em Manual), o status mostra o que o Claude reportou.
23. Um modelo ou esforço que o Claude não reconhece aparece como o Claude reportar (regras 48, 49 e 54 da base-ui), sem erro do plugin.
24. As abas são independentes: as opções de uma aba nunca mudam o status, o processo ou o restart de outra.

### Modos sem confirmação

25. `--permission-mode bypassPermissions`, `--dangerously-skip-permissions` e `--permission-mode dontAsk` abrem a aba sem pedir confirmação ao usuário.
26. Ao abrir a aba (`new` ou `tab-restart`) com uma dessas opções valendo (regra 5: a última vence), o plugin mostra um aviso, nível warning:

| Opção que vale                                                            | Aviso                                                                          |
| ------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| `--permission-mode bypassPermissions` ou `--dangerously-skip-permissions` | `Claude <n> started in bypassPermissions mode: every tool runs without asking` |
| `--permission-mode dontAsk`                                               | `Claude <n> started in dontAsk mode: every tool that would ask is denied`      |

27. O aviso sempre aparece, com `notify` ligado ou desligado: é um aviso de segurança em resposta a um comando do usuário (como a regra 85 da base-ui). Aparece uma vez por início, logo depois de a aba ser criada, e de novo a cada `tab-restart` dessa aba (o modo volta a valer). Se o início falhar (regra 18), o erro vem depois do aviso.
28. Só as opções do `new` contam. Um `bypassPermissions` vindo do `terminal_cmd`, do `defaultMode` dos settings ou de um Shift+Tab na TUI não gera aviso do plugin. `--allow-dangerously-skip-permissions` sozinho não gera aviso: a aba não inicia em `bypassPermissions`.
29. O diálogo de aceite do próprio Claude na primeira vez com `bypassPermissions` continua como é; o plugin não o responde nem o substitui.

### `tab-restart`

30. As opções de abertura de uma aba são as que o `new` recebeu, depois da validação, na ordem digitada. Ficam só em memória, enquanto a aba existe; nada vai para disco. Fechar a aba (`tab-close`, `kill-all`, saída do Neovim) as descarta.
31. `tab-restart <n>` reabre o `claude` com o `--resume=<session_id>` de hoje (regra 41 da base-ui) mais as opções de abertura, iguais, montados pela regra 5: o `terminal_cmd` da config sem as opções de abertura, o `--settings`, o `--resume` e as opções de abertura. Sem `session_id` conhecido, abre uma conversa nova com as mesmas opções (regra 43 da base-ui).
32. As opções de abertura valem por cima do que mudou dentro da TUI desde a abertura: uma aba aberta com `--model sonnet` em que o usuário trocou para o Opus pelo `/model` volta no Sonnet. O que não foi passado na abertura segue a restauração do próprio Claude (modelo e modo da conversa, exceto `bypassPermissions`), como hoje (decisão do usuário: as opções da abertura são previsíveis e não dependem de traduzir o status de volta para um valor de opção).
33. O restart não lê o `claude --help` de novo nem revalida as opções: elas já passaram na abertura.
34. Se o `claude` reiniciado termina antes de ficar pronto (ex.: o `claude` foi atualizado e não aceita mais uma opção), a aba volta a `[exited]`, guarda as opções e mostra o erro da regra 18 com o prefixo `tab-restart`. A aba não some: ela tem uma conversa que o usuário pode querer retomar.
35. O `select-model` não muda: sem abas, cria a aba 1 com `--model <valor>` como hoje (regra 15 do status-interativo), e essa aba não tem opções de abertura; o `tab-restart` dela é o de hoje (o Claude restaura o modelo da conversa).

### Outras entradas

36. `toggle`, `open` e `focus` sem abas, o `+` da barra, `<leader>an` do preset e os envios que criam a aba 1 continuam abrindo a aba sem opções, como hoje.
37. Os subcomandos que já existem não ganham opções; argumentos novos neles seguem as regras atuais de cada um.

### Completion

38. Depois de `:Claudinho new `, a completion lista os nomes longos das opções válidas (regra 2), sem as reservadas: `--model`, `--effort` e `--permission-mode` primeiro, depois as outras na ordem do `--help`. Nomes curtos e aliases são aceitos quando digitados, mas não são listados. `--model`, `--effort` e `--permission-mode` já presentes na linha não são listados de novo.
39. Depois de `--model ` (ou `--model=`), a completion lista o `value` de cada item de `models` da config, na ordem da config, sem repetidos (ex.: `opus`, `opus[1m]`, `sonnet`, `sonnet[1m]`, `haiku`, `default`). Um valor com espaço não é listado. Um modelo fora da lista continua aceito (regra 14).
40. Depois de `--effort ` e `--permission-mode ` (ou com `=`), a completion lista os valores válidos da regra 12, na ordem do `--help` (`default` não é listado, `manual` sim; `ultracode` vem por último).
41. Outras opções não têm completion de valor.
42. Sem o `claude --help` (regra 15), a completion lista só `--model`, `--effort` e `--permission-mode`, com os valores do Claude Code 2.1.328 medidos neste plano.
43. A completion filtra pelo prefixo digitado, como a dos outros subcomandos (regra 68 da base-ui).

## Edge cases

| Situação                                                                                    | Comportamento esperado                                                                                                                                                                                            |
| ------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `new` sem opções                                                                            | Como hoje (regra 1); a aba não tem opções de abertura                                                                                                                                                             |
| `new --model`                                                                               | Recusado: argumento ausente (regras 11 e 14); nenhuma aba                                                                                                                                                         |
| `new --model --effort high`                                                                 | Recusado: `--model` sem valor; o `--effort` não vira nome de modelo                                                                                                                                               |
| `new --effort foo`                                                                          | Recusado antes da aba (regra 13), embora o `claude` só avisasse                                                                                                                                                   |
| `new --permission-mode default`                                                             | Aceito (regra 12)                                                                                                                                                                                                 |
| `new --permission-mode Plan` (maiúscula diferente)                                          | Recusado: os valores são comparados como o `claude` compara, sem ignorar maiúsculas                                                                                                                               |
| `new --model nao-existe`                                                                    | A aba abre; o `claude` segue com o modelo pedido e erra no primeiro pedido à API, na própria TUI (regra 14)                                                                                                       |
| `new hello` ou `new --model sonnet hello`                                                   | Recusado: palavra solta (regra 4)                                                                                                                                                                                 |
| `new --resume abc` ou `new -c`                                                              | Recusado: opção reservada (regra 6)                                                                                                                                                                               |
| `new --settings '{"x":1}'`                                                                  | Recusado: opção reservada                                                                                                                                                                                         |
| `new --foo`                                                                                 | Recusado: opção desconhecida (regra 11)                                                                                                                                                                           |
| Opção escondida que o `claude` aceita mas não lista no `--help`                             | Recusada como desconhecida: válida é o que o `claude` declara (regra 2)                                                                                                                                           |
| `--model sonnet --model opus`                                                               | Vale `opus`: o plugin manda só a última (regra 5); a completion não lista `--model` de novo                                                                                                                       |
| `terminal_cmd = "claude --model opus"` e `new --model sonnet`                               | Sonnet: `--model opus` sai do comando dessa aba (regra 5); as outras abas seguem com ele                                                                                                                          |
| `terminal_cmd = "claude --model=opus --verbose"` e `new --model sonnet`                     | O comando da aba fica `claude --verbose --settings <arquivo> --model sonnet`: sai o `--model=opus`, o `--verbose` fica (regra 5)                                                                                  |
| `terminal_cmd` com `--dangerously-skip-permissions` e `new --permission-mode plan`          | Inicia em `plan`: as duas opções contam como a mesma e o `--dangerously-skip-permissions` sai do comando dessa aba (regra 5); sem aviso                                                                           |
| `terminal_cmd` com `--add-dir ../a` e `new --add-dir ../b`                                  | Só `../b` nessa aba: a opção do `new` vence, mesmo sendo de lista (regra 5)                                                                                                                                       |
| `terminal_cmd` com `--model opus` e `tab-restart` de uma aba aberta com `--model sonnet`    | Sonnet: o restart monta o comando pela regra 5 (regra 31)                                                                                                                                                         |
| `terminal_cmd` com `--permission-mode bypassPermissions` e `new` sem opções                 | Abre como hoje, sem aviso (regra 28)                                                                                                                                                                              |
| `env` da config com `ANTHROPIC_MODEL` e `new --model sonnet`                                | Sonnet: `--model` vence a variável                                                                                                                                                                                |
| `--add-dir a b` (opção de lista)                                                            | `a` e `b` são valores do `--add-dir`, como no `claude`; o tipo vem do `--help` (regra 2)                                                                                                                          |
| `--append-system-prompt "be brief"`                                                         | Aceito; as aspas agrupam (regra 3)                                                                                                                                                                                |
| Valor com espaço sem aspas                                                                  | Vira duas palavras; a segunda é recusada como palavra solta se a opção só aceita um valor                                                                                                                         |
| Opção que o `claude` só recusa ao iniciar                                                   | A aba some, com a saída do `claude` no erro (regra 18)                                                                                                                                                            |
| `--permission-mode bypassPermissions` pela primeira vez na máquina                          | Aviso do plugin (regra 26), depois o diálogo do Claude. Aceitar: a aba segue. Recusar: o Claude sai antes de ficar pronto e a aba some (regra 18)                                                                 |
| `--permission-mode bypassPermissions` rodando como root ou com política que bloqueia o modo | O que o Claude fizer: se sair na partida, regra 18; se iniciar em outro modo, o status mostra o modo real (regra 22)                                                                                              |
| `--permission-mode auto` sem o auto disponível                                              | O Claude inicia em Manual sem erro; o status mostra `manual` (regra 22)                                                                                                                                           |
| `--permission-mode dontAsk`                                                                 | Aviso da regra 26; a aba segue; o Claude nega o que pediria permissão                                                                                                                                             |
| `--worktree nome`                                                                           | Aceito; o Claude trabalha na worktree. No `tab-restart`, a opção vai de novo; se o Claude recusar, regra 34                                                                                                       |
| `--bare` ou `--safe-mode`                                                                   | Aceitos; o Claude desliga hooks e a statusline pode não rodar: o status fica parcial ou vazio, como com `disableAllHooks` (edge case do status-interativo). A spec confirma que a aba conecta ao próprio servidor |
| `-n nome` / `--name nome`                                                                   | Aceito e reaplicado no `tab-restart`. O título na barra continua vindo do terminal (regra 10 da base-ui)                                                                                                          |
| Usuário troca modelo, esforço ou modo na TUI e depois a aba termina                         | `tab-restart` volta às opções da abertura (regra 32)                                                                                                                                                              |
| Aba sem opções de abertura reiniciada                                                       | Como hoje                                                                                                                                                                                                         |
| `tab-restart` de aba com opções e sem `session_id`                                          | Conversa nova com as mesmas opções e a resposta de hoje (regra 31)                                                                                                                                                |
| `tab-restart` de aba `bypassPermissions` ou `dontAsk`                                       | O aviso aparece de novo (regra 27); o modo volta a valer porque a opção é reaplicada (o Claude sozinho não restauraria o `bypassPermissions`)                                                                     |
| O `claude` foi atualizado entre a abertura e o restart, e mudou uma opção                   | Restart sem revalidar (regra 33); se o Claude recusar, a aba fica `[exited]` com o erro (regra 34)                                                                                                                |
| `claude --help` muda de formato numa versão nova                                            | Regra 15: validação reduzida, o Claude decide o resto, a regra 18 evita aba pela metade; completion com os valores de 2.1.328                                                                                     |
| `terminal_cmd` aponta para um wrapper que não responde `--help` como o `claude`             | Igual à linha anterior                                                                                                                                                                                            |
| Completion de `--model` com `models` só com valores de espaço                               | Nada a listar; o valor digitado é aceito                                                                                                                                                                          |
| `select-model` sem abas e depois `tab-restart` dessa aba                                    | Como hoje: sem opções de abertura; o Claude restaura o modelo da conversa (regra 35)                                                                                                                              |
| Usuário fecha a aba (`tab-close`) enquanto ela inicia                                       | Como hoje: a aba fecha; nenhum erro da regra 18                                                                                                                                                                   |
| `kill-all` ou saída do Neovim                                                               | Como hoje; as opções de abertura somem com as abas                                                                                                                                                                |

## Approach

### Fluxos

| Fluxo                      | Passos                                                                                                                                                                                                                                                                        |
| -------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Abrir aba configurada      | `:Claudinho new --model sonnet --effort medium --permission-mode plan` -> leitura do `claude --help` (só na primeira vez) -> validação -> aba nova, janela e foco no terminal -> o Claude abre -> primeiro status com modelo e esforço -> modo pela leitura do rodapé ou hook |
| Opção inválida             | `new` com opção ou valor inválido -> validação recusa -> erro; nada é criado                                                                                                                                                                                                  |
| O Claude recusa ao iniciar | Validação passa -> aba abre -> o Claude termina antes de ficar pronto -> a aba some sem sobras -> erro com a saída do Claude                                                                                                                                                  |
| Modo sem confirmação       | `new --permission-mode bypassPermissions` -> validação -> aba nova -> aviso -> diálogo do Claude na primeira vez na máquina -> sessão                                                                                                                                         |
| Reiniciar                  | Processo da aba termina -> `[exited]` -> `:Claudinho tab-restart <n>` -> `claude --resume=<id>` + opções de abertura -> aviso de novo se for `bypassPermissions` ou `dontAsk`                                                                                                 |
| Completion                 | `:Claudinho new <Tab>` -> nomes de opções (os três primeiros) -> `--model <Tab>` -> valores de `models` -> `--effort <Tab>` -> níveis -> `--permission-mode <Tab>` -> modos                                                                                                   |

### Estados

| Estado                                                             | O que o usuário vê                                                                               |
| ------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------ |
| Carregando (primeira completion ou primeiro `new` com opções)      | Um atraso curto, uma vez por sessão do Neovim, enquanto o `claude --help` é lido                 |
| Vazio (`new` sem opções)                                           | A aba de hoje                                                                                    |
| Aba iniciando                                                      | A TUI do Claude abrindo; status vazio até o primeiro dado (regra 22)                             |
| Sucesso                                                            | A aba com o status do Claude refletindo as opções (ex.: `Sonnet <versão> · medium · plan`)       |
| Erro de validação                                                  | Nenhuma aba; um erro com a opção e o motivo (regra 11)                                           |
| Erro na partida                                                    | A aba aparece e some; um erro com a saída do Claude (regra 18)                                   |
| Permissão negada (política bloqueia `bypassPermissions` ou `auto`) | O que o Claude decidir: sai (erro na partida) ou inicia em outro modo, que o status mostra       |
| Offline                                                            | Nenhuma diferença: a validação e a completion são locais; a TUI mostra os próprios erros de rede |
| `claude --help` ilegível                                           | Validação reduzida e completion só dos três (regras 15 e 42); aviso informativo e `:checkhealth` |

### O que o plugin faz (nível de produto)

- Lê o `claude --help` uma vez por sessão do Neovim e guarda as opções, os tipos de valor e as escolhas.
- Confere as opções do `new` antes de criar qualquer coisa; só depois cria a aba pelo caminho de hoje, com o comando da regra 5: o `terminal_cmd` sem as opções que o `new` deu, o `--settings` e as opções do `new`.
- Acompanha a partida de uma aba aberta com opções até ela ficar pronta; se o Claude terminar antes, desfaz tudo e mostra a saída dele.
- Guarda as opções de abertura na aba, em memória, e as reaplica no `tab-restart`.
- Mostra os avisos da regra 26 na abertura e em cada restart.
- O servidor da aba, os settings da sessão, os hooks e a statusline não mudam.

### Documentação

- README (pt e en): `new [opções]` na tabela de comandos, com o exemplo do Goal; a completion; a lista de opções reservadas e por quê; os avisos de `bypassPermissions` e `dontAsk`; o `tab-restart` que reaplica as opções e vence as trocas feitas na TUI; a opção do `new` que vence a mesma opção do `terminal_cmd` só naquela aba (regra 5).
- Adendo na base-ui (regras 4, 41, 64, 68), como o status-interativo fez, e `CHANGELOG.md`.

## Risks & mitigations

| Risco                                                                                                                       | Impacto                                                        | Mitigação                                                                                                                                                                                                            |
| --------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| O formato do `claude --help` muda                                                                                           | Validação e completion param de reconhecer opções              | Regra 15 (validação reduzida, nunca recusa tudo por não ler o help) e regra 18 (nenhuma aba pela metade); fixtures do `--help` real por versão nos testes; aviso no `:checkhealth`                                   |
| O `--help` não lista valores que o Claude aceita (`ultracode`, `default`)                                                   | Um valor válido recusado                                       | Regra 12 acrescenta os valores documentados e medidos; a spec confere na versão da entrega; um valor novo entra numa versão seguinte                                                                                 |
| Uma versão nova do Claude cria outra opção que roda fora do terminal ou retoma conversa                                     | Aba que inicia e some, ou que não conecta                      | Regra 18 desfaz a aba; a lista da regra 6 é revista a cada atualização do Claude medida                                                                                                                              |
| O sinal de "pronto" chega antes de um diálogo do Claude que pode encerrar a sessão                                          | Uma recusa no diálogo deixa uma aba `[exited]` em vez de sumir | A spec escolhe o sinal medindo a partida com o diálogo de confiança e o de `bypassPermissions`; o pior caso é o comportamento de hoje (`[exited]` com `tab-restart`)                                                 |
| O restart reaplica uma opção que não faz sentido repetir (`--worktree`, `--name`)                                           | Restart que falha ou faz algo inesperado                       | Regra 34 mantém a aba e mostra o erro do Claude; a spec testa `--worktree` e `--name` no restart                                                                                                                     |
| As opções de abertura vencem uma troca feita na TUI no restart                                                              | O usuário perde o modelo ou modo que escolheu depois           | Comportamento decidido (regra 32), documentado no README; decisão do usuário                                                                                                                                         |
| Um aviso de segurança que aparece a cada restart incomoda                                                                   | Ruído                                                          | Só para `bypassPermissions` e `dontAsk`, uma vez por início; decisão do usuário de avisar                                                                                                                            |
| A remoção do `terminal_cmd` lê mal o tipo de valor de uma opção (ex.: valor opcional seguido de uma palavra que não é dele) | Sai uma palavra a mais ou a menos do `terminal_cmd`            | Regra 5 segue o tipo declarado no `--help`, como o `claude` lê; testes com `terminal_cmd` nas formas com espaço, com `=`, nome curto, alias e lista; sem o `--help`, a regra 5 limita a remoção às opções conhecidas |
| Ler o `--help` atrasa a primeira completion                                                                                 | Pausa perceptível no `<Tab>`                                   | Cerca de 0,15 s medido, uma vez por sessão; a spec mede no Neovim e, se passar do perceptível, lê antes (ex.: no primeiro `:Claudinho`)                                                                              |

## Open questions

Nenhuma em aberto. As três perguntas foram decididas pelo usuário em 2026-11-19 e estão nas regras: restart depois de uma troca na TUI (regra 32), `--effort` desconhecido (regra 13) e prompt inicial (regra 4).
