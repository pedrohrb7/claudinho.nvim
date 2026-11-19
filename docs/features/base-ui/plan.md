# UI base: janela do Claude com abas de sessão

- **Date:** 2026-11-12
- **Status:** Implemented
- **Spec:** [spec.md](spec.md)
- **Addendum 2026-11-12:** rótulos e mensagens do plugin em inglês, pela decisão de idioma da Fase 0 ([fork-limpo](../fork-limpo/plan.md)). Ver [Addendum](#addendum-2026-11-12-idioma-da-interface).
- **Addendum 2026-11-12:** Neovim mínimo 0.12, decidido no `docs/PRD.md` e aplicado pela Fase 0 ([fork-limpo](../fork-limpo/plan.md)). Ver [Addendum](#addendum-2026-11-12-neovim-mínimo-012).
- **Addendum 2026-11-15:** registro da origem do código, o bloqueio do claudecode.nvim vira aviso, mecanismo das chaves removidas, release `0.2.0` na entrega, notificações informativas desligadas por padrão, layout só pela config (sai o `:Claudinho layout`) e esclarecimento sobre o que persiste entre reinícios. Ver [Addendum](#addendum-2026-11-15-origem-do-código-claudecodenvim-notificações-layout-e-release).
- **Addendum 2026-11-15 (2):** revisão da spec: errata da regra 85 repetida (a da seção 5 passa a ser a 89), `autoConnectIde` aceito e documentado, opções de diretório removidas, dois Neovims na mesma pasta documentados e o critério "nada muda fora das sessões do plugin" medido com o stub. Ver [Addendum](#addendum-2026-11-15-2-revisão-da-spec).
- **Addendum 2026-11-17:** layout `left`, espelho do `right`, com tamanhos próprios em `window.left` (`width`, `diff_width`), decidido pelo usuário dentro desta feature. Ver [Addendum](#addendum-2026-11-17-layout-left).
- **Addendum 2026-11-17 (2):** a janela do Claude fica sempre na borda do layout (`right`, `left` e `bottom`): quando outra janela toma a borda, o plugin a devolve, uma vez por mudança, sem opção para desligar. Ver [Addendum](#addendum-2026-11-17-2-janela-do-claude-sempre-na-borda).
- **Addendum 2026-11-18:** a feature [status-interativo](../status-interativo/plan.md) muda a regra 66 (`select-model` passa pela guarda da TUI) e acrescenta `select-effort` e `mode-next` à tabela da regra 64, valendo quando ela for entregue. Ver [Addendum](#addendum-2026-11-18-guarda-no-select-model-e-subcomandos-novos).

## Goal

Uma janela do Claude dentro do Neovim com várias sessões ao mesmo tempo, uma por aba numerada. Cada aba é isolada: a seleção, os @-mentions e os diffs chegam só à sessão certa. O status da sessão ativa (modelo, esforço, modo) fica sempre à vista, e toda a API passa pelo comando `:Claudinho`.

Critérios de sucesso, todos verificáveis na máquina do usuário:

| Critério                                                          | Como medir                                                                                                                                                      |
| ----------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Seleção e @-mentions chegam só à aba ativa                        | Com 3 abas, um cliente WebSocket em cada servidor: só o da aba ativa recebe `selection_changed` e `at_mentioned`                                                |
| Esconder, mostrar, trocar de aba e de layout nunca encerra sessão | 10 ciclos de cada: os PIDs dos `claude` das abas não mudam                                                                                                      |
| Cada aba aparece no `/ide` com o seu número                       | Num claude aberto fora do Neovim, `/ide` lista uma entrada por aba, cada uma com o número dela                                                                  |
| Sair do Neovim não deixa sobras                                   | Depois de `:qa` com 3 abas e um diff pendente: 0 processos `claude` do plugin, 0 lock files do plugin em `~/.claude/ide/`, nenhuma pergunta na saída            |
| Nada muda fora das sessões do plugin                              | `~/.claude/settings.json`, `~/.claude.json` e `.claude/` do projeto com o mesmo checksum antes e depois; um claude externo não se conecta sozinho a nenhuma aba |
| O status acompanha a aba ativa                                    | Ao trocar de aba, a statusline da janela mostra o status da nova aba no mesmo redraw                                                                            |
| Entrega fechada                                                   | `mise run all` verde, README atualizado, nenhuma entrada nova em `docs/backlog/`                                                                                |

## Context

O protótipo (`docs/prototype/base-ui.md`) desenha a janela: abas no topo, o container de mensagens, o campo de envio com o arquivo aberto entre `[ ]` e o status embaixo. Pelo Caminho A do PRD, o container e o campo de envio são a própria TUI do Claude num terminal do Neovim. O plugin desenha só o que fica em volta: a barra de abas (winbar) e o status (statusline da janela).

Hoje o upstream tem uma sessão só: um servidor, um lock file e um terminal, escolhido entre os providers `native`, `snacks`, `external` e `none`. O servidor e o lock file são estado global (`server/init.lua` guarda `state.port`; `terminal.lua` passa essa porta para o único terminal). Esta feature troca esse modelo por "uma sessão = uma aba", cada uma com o seu servidor.

**Pré-condição:** a Fase 0 do PRD (fork limpo) fecha antes, como entrega própria: namespace `claudinho` (`lua/claudinho/`), `terminal/snacks.lua` e as opções legadas removidos e testes verdes. Este plano parte desse estado.

Relação com o roadmap do PRD:

| Fase / área do PRD            | Item                                                                                  | Neste plano                                             |
| ----------------------------- | ------------------------------------------------------------------------------------- | ------------------------------------------------------- |
| 0 · Fork limpo                | Rename, remoção do snacks e das opções legadas                                        | Pré-condição, fora                                      |
| 1 · Janela do terminal        | Float, split e tab; esconder e mostrar sem matar o processo; `hide_float` para o diff | Dentro, completo                                        |
| 1 · Fundação                  | `events.lua`, `sources/ide_protocol.lua`, `ui/adapters`                               | Decisão técnica da spec: o plano não exige nem proíbe   |
| 3 · Painel de informações     | Modelo, esforço e modo da sessão; fontes hooks e statusline                           | Dentro, só o status e o `session_id`                    |
| 3 · Painel de informações     | Estado ao vivo, custo, % de contexto, arquivos editados, aviso quando o Claude para   | Fora                                                    |
| 5 · Comandos e atalhos        | Comando único com subcomandos, completion, preset opcional, fim dos `:ClaudeCode*`    | Dentro, completo                                        |
| 2 · Diff                      | Redesenho do diff (winbar de ações, aceite por hunk, fila)                            | Fora; aqui só o roteamento por aba e a marca "● diff"   |
| 4 · Envio de contexto e mouse | Redesenho do envio, menu `PopUp`, adapters de explorer                                | Fora; os comandos de envio são portados como estão hoje |

Decisões do PRD que este plano segue: hard fork, zero dependências, API nova sem compatibilidade com `:ClaudeCode*`, hooks e statusline por `claude --settings`.

## Scope

**In scope:**

- Abas de sessão: criar, trocar, fechar, reiniciar uma aba encerrada, encerrar todas; uma sessão (processo, servidor, porta, token, lock file) por aba.
- Janela do Claude com a barra de abas na winbar e os layouts `right` (padrão), `bottom`, `float` e `tab`, com troca de layout sem matar sessão.
- Roteamento por aba: seleção e @-mentions para a aba ativa; diff de aba em segundo plano esperando a ativação.
- Status na statusline da janela: modelo com versão, esforço e modo da aba ativa.
- Settings por sessão (`claude --settings`) com a statusLine e os hooks do plugin.
- Isolamento das sessões do Claude abertas fora do Neovim.
- Comando `:Claudinho` com todos os subcomandos, completion e preset opcional de atalhos; remoção de todos os `:ClaudeCode*` e dos providers `external` e `none`.
- Config da janela (layout, tamanhos, tamanho do nome, preset) e aviso para chaves removidas.
- Testes e docs (README, CLAUDE.md, PROTOCOL.md onde o lock file muda).

**Out of scope:**

- Retomar conversas antigas numa aba nova (`--resume` / `--continue` escolhidos pelo usuário). O único `--resume` deste plano é o do `tab-restart`, na mesma aba.
- Argumentos extras para o `claude` em `new`, `open` ou `toggle`.
- Botão X na aba e qualquer fechamento automático de aba.
- Redesenho do diff (Fase 2), do envio de contexto e do mouse (Fase 4), e o resto do painel de informações (Fase 3).
- Leitura do transcript `.jsonl`.
- Caminho B (UI nativa com o Claude headless).
- As decisões em aberto do PRD sobre a versão mínima do Neovim e as integrações de explorer: os explorers continuam como estão depois da Fase 0.
- Fixar as abas entre reinícios do Neovim: as abas morrem com o Neovim.

## Business rules

### Sessões e abas

1. Uma aba é uma sessão do Claude: um processo do Claude num terminal do Neovim, com servidor WebSocket, porta, token e lock file próprios. Nenhum desses itens é compartilhado entre abas.
2. Carregar o plugin (`setup`) não inicia servidor nem cria lock file. O primeiro servidor nasce com a primeira aba, e sem abas não existe nenhum.
3. A sessão de uma aba se conecta só ao servidor da própria aba. A porta e o token chegam ao processo por variável de ambiente, só no ambiente desse processo.
4. Uma aba nova (`+` na barra ou `:Claudinho new`) sempre inicia uma sessão nova com o comando do Claude da config (padrão `claude`, sem argumentos), no diretório atual do Neovim (`getcwd()` da janela atual) no momento da criação. A aba nova vira a ativa e aparece na janela, que abre se estiver escondida.
5. Cada aba recebe ao nascer um número inteiro, a partir de 1, que não muda enquanto ela existe. A aba nova recebe o menor número livre.
6. As abas aparecem na barra em ordem crescente de número.
7. O nome que a aba mostra na lista do `/ide` contém o número da aba (ex.: `Neovim (Claudinho 2)`). O formato exato fica para a spec, que confere como o `/ide` mostra o campo.
8. Mudar o diretório do Neovim (`:cd`) depois não muda nada nas abas existentes; só as novas usam o diretório novo.

### Nome e marcas da aba

9. O texto de uma aba na barra é `<número> <título>`, seguido das marcas de estado (ex.: `1 Fix login bug ● diff`).
10. O título é o título que o Claude dá ao terminal (`b:term_title`), sem o símbolo de status que o Claude põe no começo (ex.: `✳`, spinner), para a barra não piscar enquanto o Claude trabalha.
11. Um título vazio ou genérico vira `Claude <número>`. Genérico é um título que, já sem o símbolo, é igual a `Claude Code`, `claude`, ao comando configurado ou ao título padrão do terminal do Neovim (`term://...`).
12. O título é cortado no tamanho máximo da config (padrão 24 caracteres), com `…` no fim quando cortado. O número e as marcas nunca são cortados.
13. O nome acompanha o título: quando o Claude troca o título do terminal, a barra se atualiza.
14. Marcas: `● diff` enquanto a aba tem diff esperando a ativação (regra 31) e `[encerrada]` depois que o processo terminou (regra 40).
15. A aba ativa tem destaque visual próprio, diferente das outras. O `+` fica sempre no fim da barra.

### Janela e layouts

16. Existe uma janela do Claude por Neovim. Ela mostra o terminal da aba ativa e tem a barra de abas na winbar, em todos os layouts.
17. Layouts:

| Layout           | Onde fica                                                                                     | Tamanho (config, padrão) |
| ---------------- | --------------------------------------------------------------------------------------------- | ------------------------ |
| `right` (padrão) | Split vertical na borda direita, na altura toda da tela, ao lado de todos os splits do editor | Largura, 30% das colunas |
| `bottom`         | Split horizontal na borda de baixo, na largura toda                                           | Altura, 30% das linhas   |
| `float`          | Janela flutuante centralizada                                                                 | Largura e altura, 80%    |
| `tab`            | Aba do Neovim própria, com a janela ocupando a aba inteira                                    | -                        |

18. O layout padrão e os tamanhos vêm da config. `:Claudinho layout <nome>` troca o layout na hora, sem encerrar nenhuma sessão, e vale até sair do Neovim; o próximo início usa o padrão da config. Com a janela escondida, a troca só muda o layout usado na próxima vez que ela aparecer.
19. `:Claudinho toggle`: com a janela visível, esconde; escondida e com abas, mostra a aba ativa; sem abas, abre a janela e cria a aba 1 com sessão nova.
20. `:Claudinho open` só mostra (já visível: só foca). Sem abas, cria a aba 1 como o `toggle`.
21. `:Claudinho hide` só esconde; com a janela já escondida, não faz nada.
22. `:Claudinho focus` mantém o comportamento do `:ClaudeCodeFocus` de hoje: com a janela fora de foco ou escondida, mostra e foca; com ela em foco, esconde.
23. Esconder nunca encerra sessão. Fechar a janela do Claude com os comandos do Neovim (`:q`, `<C-w>c`) é o mesmo que esconder.
24. Mostrar a janela por `new`, `toggle`, `open` ou `focus` foca o terminal da aba ativa em modo terminal, como hoje.
25. No layout `float`, quando um diff abre, a janela do Claude se esconde para não cobrir o diff, e as sessões continuam; ela volta com `toggle`, `open` ou `focus`. Nos outros layouts, a relação entre o diff e a janela segue o comportamento de hoje.

### Troca de aba e roteamento

26. Troca de aba: clique com o botão esquerdo no texto da aba na winbar, `:Claudinho tab <número>`, `:Claudinho tab-next` e `:Claudinho tab-prev`. `tab-next` e `tab-prev` dão a volta (depois da última vem a primeira).
27. Trocar de aba só troca o terminal mostrado na janela. A aba que sai continua rodando e conectada ao próprio servidor.
28. A aba ativa é a que a janela mostra; com a janela escondida, é a última que esteve à mostra. Com pelo menos uma aba, sempre existe uma aba ativa.
29. A seleção (`selection_changed`) e os @-mentions (`send`, `add`, `tree-add`, `send-text`) vão só para a aba ativa. As outras abas não recebem nada do editor.
30. Ao virar ativa, a aba recebe a seleção atual do editor, para não ficar com uma seleção velha.
31. Um diff (`openDiff`) pedido por uma aba em segundo plano não abre. A aba ganha a marca `● diff`, e uma notificação curta avisa uma vez por pedido (ex.: `Claude 2: diff pendente em src/login.lua`). Quando o usuário ativa a aba, os diffs pendentes dela abrem na ordem em que chegaram e a marca some.
32. Um diff pedido pela aba ativa abre na hora, como hoje.
33. A resposta a um diff (aceitar, rejeitar, `diff-accept`, `diff-deny`, salvar) sempre vai para a aba que pediu o diff, mesmo com outra aba ativa.
34. Um diff aberto da aba 1 continua aberto quando o usuário troca para a aba 2, e a resposta dele vai para a aba 1.
35. `:Claudinho close-all-diffs` atua nos diffs de todas as abas. Os diffs que esperam a ativação também são rejeitados, e as marcas `● diff` somem.
36. As outras tools MCP (`openFile`, `getDiagnostics`, `getOpenEditors` etc.) respondem a qualquer aba, ativa ou não, como hoje.
37. O que chega pelos hooks e pela statusline de uma sessão só atualiza a aba dessa sessão.

### Encerramento e reinício

38. `:Claudinho tab-close [número]` fecha a aba indicada, ou a ativa sem argumento: rejeita os diffs pendentes dela, encerra o processo, para o servidor, remove o lock file e tira a aba da barra. Não pede confirmação.
39. Nenhuma aba fecha sozinha: nem quando o processo termina, nem por uma tecla no terminal encerrado, nem ao esconder a janela.
40. Quando o processo de uma aba termina, por qualquer motivo ou código de saída, sem `tab-close`:
    - a aba continua na barra, com a saída final visível e a marca `[encerrada]`;
    - os diffs pendentes dela fecham sem resposta, e a marca `● diff` some;
    - o servidor para e o lock file é removido, então a aba some do `/ide`;
    - uma tecla no terminal encerrado não fecha o buffer;
    - uma notificação curta avisa `Claude <número> encerrou`.
41. `:Claudinho tab-restart <número>` vale só para aba encerrada. Ele reabre o Claude na mesma aba, com o mesmo número e no mesmo lugar da barra, com `claude --resume <session_id>`, no diretório em que a aba foi criada. O `session_id` é o último recebido da aba pelos hooks ou pela statusline. A aba ganha servidor, porta e lock file novos, com o mesmo número, e a marca `[encerrada]` some.
42. `tab-restart` numa aba que está rodando avisa que ela está rodando e não muda nada.
43. `tab-restart` numa aba sem `session_id` conhecido abre uma sessão nova na mesma aba e avisa que a conversa anterior não pôde ser retomada.
44. Depois que a aba ativa fecha, a ativa passa a ser a vizinha de número maior, ou a de número menor quando não há maior. Quando a última aba fecha, a janela fecha e o estado volta a "sem abas".
45. `:Claudinho kill-all` rejeita todos os diffs pendentes (abertos e esperando a ativação), encerra todas as sessões, para todos os servidores, remove todos os lock files do plugin e fecha todas as abas e a janela. Não pede confirmação.
46. Sair do Neovim faz o mesmo que o `kill-all`, sem perguntar nada. Os terminais das abas não bloqueiam a saída (nenhum erro de "job still running"), e os diffs pendentes são rejeitados antes de as sessões terminarem.

### Status

47. A statusline da janela do Claude mostra o status da aba ativa, desenhado pelo Neovim, nesta ordem: modelo com versão, esforço e modo, separados por `·` (ex.: `Opus 5.5 · high · plano`).
48. Modelo: o `model.display_name` do JSON da statusline do Claude. Quando o nome não traz a versão, ela vem do `model.id` (ex.: `claude-opus-5-5` vira `Opus 5.5`).
49. Esforço: o `effort.level` do JSON da statusline, como vem (`low`, `medium`, `high`, `xhigh`, `max`). Sem o campo, o esforço fica fora do status.
50. Modo: o `permission_mode` do último hook da sessão que trouxe o campo, mostrado assim:

| `permission_mode`   | Mostrado          |
| ------------------- | ----------------- |
| `default`           | `manual`          |
| `plan`              | `plano`           |
| `auto`              | `auto`            |
| `acceptEdits`       | `aceitar edições` |
| `dontAsk`           | `não perguntar`   |
| `bypassPermissions` | `sem permissões`  |
| outro valor         | o valor como veio |

51. Um item sem dado fica fora do status, sem separador sobrando; sem nenhum dado, a statusline da janela fica vazia.
52. Trocar de aba troca o status no mesmo redraw. Uma aba encerrada mantém o último status que teve.
53. A TUI do Claude não repete o status: o script de statusline do plugin repassa o JSON ao Neovim e imprime uma linha vazia.
54. Campos ausentes, campos novos e eventos desconhecidos no JSON da statusline ou dos hooks nunca geram erro; o que falta só fica fora do status.

### Settings da sessão, hooks e statusline

55. Cada sessão do plugin inicia com `claude --settings <arquivo>`, um arquivo gerado pelo plugin só para ela, com a `statusLine` e os hooks do plugin.
56. Os settings do usuário e do projeto continuam valendo (agents, permissões, hooks, modelo etc.). Os hooks do plugin se somam aos do usuário, e só a `statusLine` é sobreposta.
57. O plugin nunca escreve em `~/.claude/settings.json`, `~/.claude.json` nem em `.claude/` do projeto. O arquivo gerado para uma sessão é apagado quando a aba fecha ou o Neovim sai.
58. Os hooks e a statusline do plugin só observam: nunca bloqueiam nem mudam uma decisão do Claude, sempre terminam com sucesso e sem saída para o Claude, mesmo com o Neovim inacessível, e nunca atrasam a sessão de forma perceptível.
59. A porta e o token do servidor da aba chegam aos scripts por variável de ambiente. O servidor da aba só aceita esses dados com o token dela.
60. Os scripts não exigem nada além do Neovim e do Claude instalados (nenhum `jq`, `curl`, `python`), seguindo a regra de zero dependências.

### Sessões do Claude fora do Neovim

61. Um claude aberto fora do Neovim continua isolado e nada muda nele. O plugin não altera a config global do Claude, não encerra processo que não iniciou e não remove lock file que não criou.
62. Uma sessão externa nunca se conecta sozinha ao servidor de uma aba; só um `/ide` explícito do usuário conecta. As variáveis de ambiente das sessões (porta, token, `CLAUDE_CODE_SSE_PORT` etc.) existem só no processo de cada aba, nunca no ambiente do próprio Neovim: um `:terminal` comum ou um `:!claude` não as herda.
63. Uma sessão externa conectada pelo `/ide` à aba N passa a ser cliente da aba N: recebe a seleção quando N está ativa, e os diffs dela seguem as regras da aba N. Fechar ou encerrar a aba N desconecta essa sessão, sem encerrá-la.

### Comandos

64. Toda a API é `:Claudinho <subcomando>`. Nenhum `:ClaudeCode*` existe mais, e os providers `external` e `none` são removidos.

| Subcomando                          | O que faz                                                               | Antes                                           |
| ----------------------------------- | ----------------------------------------------------------------------- | ----------------------------------------------- |
| `toggle`                            | Regra 19                                                                | `:ClaudeCode`                                   |
| `open` / `hide`                     | Regras 20 e 21                                                          | `:ClaudeCodeOpen` / -                           |
| `focus`                             | Regra 22                                                                | `:ClaudeCodeFocus`                              |
| `new`                               | Regra 4                                                                 | -                                               |
| `tab <n>` / `tab-next` / `tab-prev` | Regra 26                                                                | -                                               |
| `tab-close [n]`                     | Regra 38                                                                | `:ClaudeCodeClose`                              |
| `tab-restart <n>`                   | Regras 41 a 43                                                          | -                                               |
| `kill-all`                          | Regra 45                                                                | -                                               |
| `layout <nome>`                     | Regra 18; sem nome, mostra o layout atual                               | -                                               |
| `send` (com range)                  | Envia a seleção visual como @-mention, como hoje, para a aba ativa      | `:ClaudeCodeSend`                               |
| `add <arquivo> [início] [fim]`      | Adiciona arquivo ou trecho, como hoje, à aba ativa                      | `:ClaudeCodeAdd`                                |
| `tree-add`                          | Adiciona os arquivos selecionados no explorer, como hoje, à aba ativa   | `:ClaudeCodeTreeAdd`                            |
| `send-text <texto>`                 | Envia texto ao terminal da aba ativa, como hoje (`!` insere sem enviar) | `:ClaudeCodeSendText`                           |
| `diff-accept` / `diff-deny`         | Aceita ou rejeita o diff da janela atual, como hoje; regra 33           | `:ClaudeCodeDiffAccept` / `:ClaudeCodeDiffDeny` |
| `close-all-diffs`                   | Como hoje, em todas as abas; regra 35                                   | `:ClaudeCodeCloseAllDiffs`                      |
| `select-model`                      | Regra 66                                                                | `:ClaudeCodeSelectModel`                        |

`:ClaudeCodeStart`, `:ClaudeCodeStop` e `:ClaudeCodeStatus` somem sem substituto: o ciclo da sessão passa a ser o da aba.

65. Os subcomandos portados mantêm o comportamento de hoje, só mirando a aba ativa. Um envio sem nenhuma aba cria a aba 1 e entrega quando ela conectar, como hoje o envio abre o terminal e põe o @-mention na fila. Um envio para uma aba que ainda não conectou espera na fila dessa aba.
66. `select-model` abre a escolha de modelo da config. Com uma aba ativa rodando, envia `/model <valor>` à TUI dela; sem abas, cria a aba 1 com `claude --model <valor>`.
67. `:Claudinho` sem subcomando é o mesmo que `toggle`. Um subcomando desconhecido mostra um erro com a lista dos válidos.
68. O comando tem completion: subcomandos, números das abas existentes (em `tab`, `tab-close`, `tab-restart`) e nomes de layout.
69. Nenhum atalho é criado por padrão. A config tem um preset opcional, desligado por padrão, que mapeia os subcomandos com o prefixo `<leader>a` do README do upstream: `ac` toggle, `af` focus, `an` new, `al`/`ah` tab-next/tab-prev, `a1` a `a9` tab 1 a 9, `ax` tab-close, `am` select-model, `ab` add do buffer atual, `as` send (visual), `aa`/`ad` diff-accept/diff-deny. O preset nunca sobrescreve um mapeamento que já existe na mesma tecla; essa tecla fica de fora, com um aviso.

### Configuração

70. A config da janela expõe: layout padrão, tamanhos por layout, tamanho máximo do nome da aba e o preset de atalhos. O comando do Claude, as variáveis de ambiente extras e a lista de modelos continuam configuráveis como hoje.
71. As opções do terminal antigo (`provider`, `provider_opts`, `external_terminal_cmd`, `split_side`, `split_width_percentage`, `auto_start`) deixam de existir. Uma config que ainda usa uma chave removida gera um aviso único que nomeia a chave e diz o que a substitui, e o resto da config funciona.

## Edge cases

| Situação                                                                                                   | Comportamento esperado                                                                                                                                                                                                                                                                                                 |
| ---------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| O comando do Claude não existe ou falha ao iniciar                                                         | Nenhuma aba é criada; um erro mostra o comando que falhou; não sobra servidor, lock file nem arquivo de settings                                                                                                                                                                                                       |
| O servidor da aba não consegue porta, ou o lock file não pode ser escrito (`~/.claude/ide/` sem permissão) | Igual ao anterior, com o motivo no erro                                                                                                                                                                                                                                                                                |
| `tab <n>` ou `tab-close <n>` com número inexistente                                                        | Erro com a lista das abas existentes; nada muda                                                                                                                                                                                                                                                                        |
| `tab-next`/`tab-prev` com uma aba só                                                                       | Nada muda                                                                                                                                                                                                                                                                                                              |
| `tab`, `tab-next`, `tab-prev`, `tab-close`, `hide` sem nenhuma aba                                         | Aviso "nenhuma aba aberta"; nada muda                                                                                                                                                                                                                                                                                  |
| `tab-restart` sem número                                                                                   | Erro de uso; o número é obrigatório                                                                                                                                                                                                                                                                                    |
| `layout` com nome inválido                                                                                 | Erro com os nomes válidos                                                                                                                                                                                                                                                                                              |
| `layout` com o layout atual                                                                                | Nada muda                                                                                                                                                                                                                                                                                                              |
| `send`, `add` ou `send-text` com a aba ativa encerrada                                                     | Nada é enviado; um aviso sugere `:Claudinho tab-restart <n>`                                                                                                                                                                                                                                                           |
| Vários diffs de uma aba em segundo plano                                                                   | Uma marca `● diff` só; uma notificação por pedido; ao ativar, todos abrem na ordem de chegada                                                                                                                                                                                                                          |
| A aba com diff esperando é fechada antes de ser ativada                                                    | Os diffs são rejeitados (regra 38) e não abrem                                                                                                                                                                                                                                                                         |
| O processo de uma aba morre com um diff dela aberto                                                        | O diff fecha sem resposta (regra 40)                                                                                                                                                                                                                                                                                   |
| O usuário apaga o buffer de uma aba (`:bdelete`, `:bwipeout`)                                              | Mesmo efeito que `tab-close` daquela aba.                                                                                                                                                                                                                                                                              |
| O usuário abre o buffer de uma aba em outra janela                                                         | O plugin não impede; a aba ativa continua sendo a da janela do Claude                                                                                                                                                                                                                                                  |
| `:q` na última janela do editor, sobrando só a do Claude                                                   | É a saída do Neovim: regra 46                                                                                                                                                                                                                                                                                          |
| Troca de aba do Neovim (`gt`) com layout `right` ou `bottom`                                               | A janela do Claude fica na aba do Neovim onde estava; `toggle`/`open` em outra aba do Neovim leva a janela para lá.                                                                                                                                                                                                    |
| A barra de abas não cabe na largura da janela                                                              | Os títulos encolhem até sobrar só o número; o `+` e a aba ativa ficam sempre visíveis.                                                                                                                                                                                                                                 |
| Mouse desligado no Neovim (`mouse=`)                                                                       | Cliques na barra não fazem nada; os comandos continuam funcionando                                                                                                                                                                                                                                                     |
| O usuário roda `/clear` na TUI                                                                             | O Claude gera um `session_id` novo; o `tab-restart` usa o último recebido                                                                                                                                                                                                                                              |
| O usuário roda `/cd` na TUI                                                                                | O `tab-restart` retoma no diretório em que a aba foi criada; a spec confere se o `--resume` acha a sessão nesse caso                                                                                                                                                                                                   |
| Dois Neovims abertos, cada um com uma aba 1                                                                | O `/ide` lista as duas; a spec confere como o `/ide` as distingue e acrescenta ao nome o que faltar (ex.: a pasta)                                                                                                                                                                                                     |
| `disableAllHooks` ligado pelo usuário                                                                      | Sem hooks e sem statusline custom: o status fica vazio e o `tab-restart` não tem `session_id` (regra 43); as abas funcionam                                                                                                                                                                                            |
| `allowManagedHooksOnly` ligado pela organização                                                            | Os hooks do plugin não rodam: o modo fica fora do status; modelo e esforço continuam pela statusline                                                                                                                                                                                                                   |
| Sessão externa com `autoConnectIde` ligado em `~/.claude.json`                                             | Não pode se conectar sozinha a nenhuma aba (regra 62). A spec verifica se o Claude se conecta sozinho a um lock file do Neovim com essa opção; se sim, ela define como o lock file fica fora da conexão automática sem sair da lista do `/ide`. Se isso não for possível, a spec volta ao usuário antes de implementar |
| Neovim morto à força (crash, `kill -9`)                                                                    | As sessões perdem o terminal e terminam; lock files podem sobrar. A spec confere se o Claude ignora lock files de PID morto e, se não ignorar, define a limpeza no próximo início                                                                                                                                      |

## Approach

### A janela

```text
 1 Fix login bug ● diff │ 2 Claude 2 │ 3 Refactor [encerrada] │ +     <- winbar: abas clicáveis
 ┌──────────────────────────────────────────────────────────────┐
 │ TUI do Claude da aba ativa (mensagens)                       │
 │ ...                                                          │
 │ > campo de envio  [src/login.lua]                            │   <- comportamento atual da TUI
 └──────────────────────────────────────────────────────────────┘
 Opus 5.5 · high · plano                                             <- statusline da janela
```

### Estados

| Estado                        | O que o usuário vê                                                                                                                       |
| ----------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| Sem abas                      | Nenhuma janela. `toggle`, `open`, `new` ou um envio criam a aba 1                                                                        |
| Aba iniciando                 | A aba já está na barra como `Claude <n>`; o terminal mostra a abertura do Claude; status vazio até o primeiro JSON                       |
| Aba rodando                   | Título do Claude na aba; status preenchido conforme os dados chegam                                                                      |
| Aba em segundo plano com diff | `● diff` na aba e uma notificação curta                                                                                                  |
| Aba encerrada                 | `[encerrada]` na aba, saída final visível, último status mantido                                                                         |
| Erro ao criar aba             | Nenhuma aba nova; notificação de erro com o motivo                                                                                       |
| Permissão negada              | Hooks bloqueados por política: o status perde o modo (ou tudo, com `disableAllHooks`); `~/.claude/ide/` sem escrita: erro ao criar a aba |
| Offline                       | Sem efeito no plugin: a TUI mostra os próprios erros de rede, e a aba segue rodando                                                      |
| Janela escondida              | Sessões rodando; seleção e envios vão para a última aba mostrada; diffs da aba ativa abrem normalmente                                   |

### Fluxos

| Fluxo                 | Passos                                                                                                                                                  |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Primeira sessão       | `:Claudinho toggle` -> abre a janela no layout padrão -> cria a aba 1 -> foca o terminal                                                                |
| Mais uma sessão       | Clique no `+` ou `:Claudinho new` -> aba N no fim da barra, ativa e focada; as outras seguem rodando                                                    |
| Trocar de aba         | Clique na aba ou `:Claudinho tab 2` -> a janela mostra a aba 2 -> o status troca -> seleção e envios passam a ir para a 2 -> diffs pendentes da 2 abrem |
| Diff em segundo plano | A aba 3 pede um diff -> `● diff` + notificação -> o usuário ativa a 3 -> o diff abre -> a resposta vai para a 3                                         |
| Sessão terminou       | `/exit` na TUI ou crash -> `[encerrada]` + notificação -> `:Claudinho tab-restart 3` -> a mesma conversa volta na aba 3                                 |
| Trocar layout         | `:Claudinho layout float` -> a janela muda de lugar com a mesma aba -> nenhum processo reinicia                                                         |
| Encerrar tudo         | `:Claudinho kill-all` ou `:qa` -> diffs rejeitados -> sessões encerradas -> lock files removidos -> sem abas                                            |

### O que o servidor e as fontes fazem (nível de produto)

- Um servidor por aba, com a autenticação de hoje, e um lock file por aba, com o número da aba no nome mostrado pelo `/ide`.
- O servidor da aba recebe três coisas: as conexões do Claude (protocolo IDE, como hoje), o JSON da statusline e os eventos dos hooks da sessão, estes dois só com o token da aba.
- O plugin guarda, por aba: o último `session_id`, o modelo, o esforço e o modo. Nada é gravado em disco além do lock file e do arquivo de settings da sessão.

## Risks & mitigations

| Risco                                                                                                              | Impacto                                                                                                                         | Mitigação                                                                                                                                                     |
| ------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `autoConnectIde` (em `~/.claude.json`) faz uma sessão externa se conectar sozinha a uma aba                        | Quebra o isolamento que o usuário exigiu (regras 61 e 62)                                                                       | A spec testa o caso com a opção ligada e define como manter o lock file fora da conexão automática; sem solução, para e volta ao usuário antes de implementar |
| `permission_mode` só chega em alguns hooks, e a statusline não traz o modo                                         | O modo pode ficar desatualizado entre a troca na TUI (shift+tab) e o próximo hook que traga o campo, e fica fora até o primeiro | Mostrar o último valor recebido; a spec escolhe os eventos de hook que mais cedo trazem o campo; registrar a limitação no README                              |
| `disableAllHooks` ou `allowManagedHooksOnly` desligam os hooks (e, no primeiro caso, a statusline) do plugin       | Status parcial ou vazio; `tab-restart` sem `session_id`                                                                         | Abas e roteamento não dependem dos hooks; regras 43 e 51; caso descrito no README                                                                             |
| Com uma statusline configurada, mesmo vazia, a TUI esconde dicas do rodapé (`esc to interrupt`, `? for shortcuts`) | O usuário perde essas dicas nas sessões do plugin                                                                               | Consequência aceita da decisão 11; registrar no README                                                                                                        |
| O CLI muda `--settings`, os campos da statusline ou os hooks                                                       | Status ou `tab-restart` param de funcionar                                                                                      | Regra 54; testes com fixtures do JSON real; nada de produto depende de campo novo                                                                             |
| O título do terminal muda de formato                                                                               | Nomes de aba estranhos                                                                                                          | Regra 11 cai em `Claude <n>`; fixtures de títulos reais nos testes                                                                                            |
| Terminais rodando bloqueiam o `:qa`                                                                                | Viola a regra 46                                                                                                                | A spec cobre `:qa`, `:q` na última janela e `:wqa` com abas rodando, em teste de integração                                                                   |
| Vários servidores e processos ao mesmo tempo                                                                       | Uso de memória e portas                                                                                                         | Um servidor só nasce com a aba e morre com ela (regras 2 e 38); sem limite artificial                                                                         |
| Tirar o estado global do servidor e do terminal                                                                    | Regressões no protocolo, que hoje funciona                                                                                      | Manter os testes de `server/`, `lockfile` e tools verdes durante a troca; testes de integração com duas abas e um cliente por servidor                        |
| `--resume` não acha a sessão (diretório diferente, histórico apagado)                                              | `tab-restart` falha                                                                                                             | A TUI mostra o erro na própria aba; a aba fica rodando ou encerrada conforme o processo, e o usuário pode fechar e abrir outra                                |

## Open questions

Nenhuma em aberto. As oito perguntas da revisão de 2026-11-12 foram decididas com as recomendações, já escritas como regras: 5 (número da aba), 10 (título sem o símbolo de status), 20 (`open` sem abas), 30 (seleção ao ativar), 34 (diff aberto ao trocar de aba), 36 (`openFile` em segundo plano), 43 (`tab-restart` sem `session_id`), 44 (aba ativa depois de fechar), 66 (`select-model`), 67 (`:Claudinho` sem subcomando), 69 (teclas do preset) e os casos de borda de `:bdelete`, aba do Neovim e barra que não cabe.

## Addendum 2026-11-12: idioma da interface

Origem: decisão de idioma da Fase 0 ([fork-limpo](../fork-limpo/plan.md)): mensagens do plugin, código e testes em inglês. Este adendo troca só o texto que o plugin mostra; nenhuma regra muda de comportamento. Onde as regras, os casos de borda, o esboço e os fluxos acima citam um texto em português, vale o texto em inglês desta tabela. Toda mensagem, aviso ou erro do plugin que este plano descreve sem texto literal também sai em inglês.

| Onde                                                     | Antes (texto mostrado)                        | Agora                                                   |
| -------------------------------------------------------- | --------------------------------------------- | ------------------------------------------------------- |
| Marca de aba encerrada (regras 14 e 40, esboço, estados) | `[encerrada]`                                 | `[exited]`                                              |
| Notificação de diff em segundo plano (regra 31)          | `Claude 2: diff pendente em src/login.lua`    | `Claude 2: pending diff for src/login.lua`              |
| Notificação de processo encerrado (regra 40)             | `Claude <número> encerrou`                    | `Claude <n> exited`                                     |
| Modo `default` (regra 50)                                | `manual`                                      | `manual`                                                |
| Modo `plan`                                              | `plano`                                       | `plan`                                                  |
| Modo `auto`                                              | `auto`                                        | `auto`                                                  |
| Modo `acceptEdits`                                       | `aceitar edições`                             | `accept edits`                                          |
| Modo `dontAsk`                                           | `não perguntar`                               | `don't ask`                                             |
| Modo `bypassPermissions`                                 | `sem permissões`                              | `bypass permissions`                                    |
| Exemplo de status (regra 47)                             | `Opus 5.5 · high · plano`                     | `Opus 5.5 · high · plan`                                |
| Comando sem abas (casos de borda)                        | "nenhuma aba aberta"                          | `No Claude tabs open`                                   |
| `tab-restart` numa aba rodando (regra 42)                | aviso de que a aba está rodando               | `Claude <n> is still running`                           |
| `tab-restart` sem `session_id` (regra 43)                | aviso de que a conversa não pôde ser retomada | `Claude <n>: no session to resume, started a new one`   |
| Envio para aba encerrada (casos de borda)                | aviso sugerindo `tab-restart`                 | `Claude <n> has exited; run :Claudinho tab-restart <n>` |

Os textos que já estavam em inglês não mudam: `Claude <n>`, `● diff`, `+`, os nomes de subcomandos e layouts, `Neovim (Claudinho 2)`. A redação final das mensagens sem texto literal fica para a spec, em inglês.

## Addendum 2026-11-12: Neovim mínimo 0.12

Origem: decisão do `docs/PRD.md` (atualizado e aprovado em 2026-11-12), aplicada pela Fase 0 ([fork-limpo](../fork-limpo/plan.md), regras 2 e 43 a 45): o loader, o health check e o CI passam a exigir Neovim 0.12. Nenhuma regra deste plano muda de comportamento.

- A versão mínima do Neovim deixa de ser decisão em aberto. No item de **Out of scope** sobre as decisões em aberto do PRD, vale agora só a parte das integrações de explorer, que continuam como estão depois da Fase 0.
- A UI base parte de um plugin que já só carrega no Neovim 0.12 ou mais novo, então a spec pode usar as APIs de janela e winbar dessa versão sem fallback para versões anteriores.

## Addendum 2026-11-15: origem do código, claudecode.nvim, notificações, layout e release

Origem: a Fase 0 ([fork-limpo](../fork-limpo/plan.md)) está Implemented, na versão `0.1.0` ([spec](../fork-limpo/spec.md), [log](../fork-limpo/log.md)), e o usuário tomou seis decisões em 2026-11-15. As regras abaixo continuam a numeração do plano; cada item diz qual parte aprovada acima ele complementa ou muda. O texto aprovado acima não foi reescrito: onde ele e este adendo divergem, vale este adendo.

### 1. Origem do código

Complementa o item "Testes e docs" do **Scope** e o critério "Entrega fechada" (ver o item 4).

72. Ao trocar os `:ClaudeCode*` por `:Claudinho` e reescrever módulos, a feature mantém o registro de onde o código veio:
    - a atribuição ao upstream (hard fork de `coder/claudecode.nvim` no commit `d1237072`) continua em `README.md`, `README.en.md`, `CHANGELOG.md` e no `LICENSE` (aviso MIT da Coder);
    - as notas do upstream no topo de `PROTOCOL.md` e `ARCHITECTURE.md` continuam, atualizadas onde esta feature muda o que elas descrevem (por exemplo, um servidor e um lock file por aba);
    - todo módulo reescrito ou derivado de um arquivo do upstream leva no cabeçalho uma linha curta de origem que nomeia o arquivo do upstream de onde vem (ex.: derivado de `lua/claudecode/terminal.lua`). Módulo novo, sem arquivo de origem, não leva a linha. O texto exato, em inglês, fica para a spec.

O item "Testes e docs" do **Scope** passa a incluir também `README.en.md`, `ARCHITECTURE.md`, `CHANGELOG.md` e as linhas de origem nos módulos.

### 2. claudecode.nvim instalado junto

Muda a regra 7 da Fase 0 ([fork-limpo](../fork-limpo/plan.md)), hoje cumprida por `lua/claudinho/conflict.lua`: o Claudinho se recusa a rodar quando o claudecode.nvim está carregado ou no runtimepath, porque os dois registram os mesmos `:ClaudeCode*`. Complementa a regra 64 deste plano.

Depois desta feature nada colide mais: os comandos são `:Claudinho` contra `:ClaudeCode*`, os identificadores já foram renomeados na Fase 0, servidores, portas e lock files são separados, as variáveis de ambiente existem só em cada processo (regra 62) e os registros de diff são separados. O que sobra é incômodo, não conflito: duas entradas parecidas no `/ide`, a seleção acompanhada duas vezes e duas formas de abrir o Claude. Decisão do usuário (opção B): a recusa vira aviso.

73. Com o claudecode.nvim detectado, os dois plugins rodam. O Claudinho carrega e funciona normalmente, e mostra um aviso por sessão do Neovim dizendo que o claudecode.nvim está instalado e sugerindo removê-lo.
74. `:checkhealth claudinho` mostra o claudecode.nvim detectado como aviso (warning), não como erro.
75. A detecção é a da Fase 0: `vim.g.loaded_claudecode` definido ou `lua/claudecode/init.lua` no runtimepath.
76. Até esta feature ser entregue, a recusa da Fase 0 continua valendo; ela só muda junto com a troca dos comandos para `:Claudinho`.

O texto exato do aviso e do health check, em inglês, fica para a spec. A seção "Coming from claudecode.nvim" / "Vindo do claudecode.nvim" dos dois READMEs (regra 33 da Fase 0) troca "os dois não rodam juntos" por "os dois rodam, mas o recomendado é remover o claudecode.nvim".

| Situação                                                                           | Comportamento esperado                                                                                                         |
| ---------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| claudecode.nvim no runtimepath mas não carregado (lazy-load)                       | Conta como detectado (regra 75): aviso e health check como warning; o Claudinho roda                                           |
| Os dois plugins ativos, `/ide` num claude aberto fora do Neovim                    | Lista as entradas do claudecode.nvim e as do Claudinho (`Neovim (Claudinho <n>)`, regra 7); nenhuma conecta sozinha (regra 62) |
| Preset de atalhos ligado e o usuário já mapeou `<leader>a*` para o claudecode.nvim | Regra 69: o preset não sobrescreve essas teclas e avisa                                                                        |

### 3. Chaves removidas do terminal

Diz como a regra 71 é cumprida; nenhum comportamento muda.

77. A regra 71 reusa o mecanismo de chaves removidas da Fase 0 (`config.removed_options` em `lua/claudinho/config.lua`: um aviso `vim.notify_once` por chave, nomeando o substituto, e o `setup` continua funcionando). Esta feature só acrescenta à tabela as chaves que remove: `terminal.provider`, `terminal.provider_opts`, `terminal.external_terminal_cmd`, `terminal.split_side`, `terminal.split_width_percentage`, `terminal.auto_start` e as demais que a spec remover. A linha atual de `terminal.provider = "snacks"` passa a ser coberta pela de `terminal.provider`; a spec decide como as duas convivem.

### 4. Release na entrega

Muda o critério "Entrega fechada" do **Goal**. Segue o passo de release criado em 2026-11-15 (`mise run release minor`, ver a seção "Version" do `CLAUDE.md`).

78. Durante a feature, cada mudança visível para o usuário entra em `## [Unreleased]` no `CHANGELOG.md`.
79. A feature fecha com o passo de release: `mise run release minor` transforma o Unreleased em `## [0.2.0]`, grava `0.2.0` no `VERSION`, faz o commit `chore(release): 0.2.0` e cria a tag `v0.2.0`. O push fica com o usuário.

O critério "Entrega fechada" passa a ser:

| Critério        | Como medir                                                                                                                                                                                                                                                                           |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Entrega fechada | `mise run all` verde, README atualizado, nenhuma entrada nova em `docs/backlog/`, origem do código registrada (regra 72) e release feito (regra 79): `VERSION` em `0.2.0`, `CHANGELOG.md` com `## [0.2.0]` e o Unreleased vazio, commit `chore(release): 0.2.0` e tag local `v0.2.0` |

### 5. Notificações informativas desligadas por padrão

Muda as regras 31, 40, 69, 71, 73 e 77 no ponto em que elas mostram uma notificação: essa notificação passa a depender da opção abaixo. Nenhum outro comportamento dessas regras muda.

80. Uma opção nova da config (nome na spec, ex.: `notify`), desligada por padrão, controla toda notificação informativa do plugin. Desligada, nenhuma aparece; ligada, cada uma se comporta como o plano descreve.
81. São informativas: o aviso de diff em segundo plano (regra 31), `Claude <n> exited` (regra 40), os avisos de chave removida (regras 71 e 77, incluindo os que a Fase 0 já emite), o aviso de claudecode.nvim instalado (regras 73 a 76), o aviso de tecla do preset já mapeada (regra 69) e qualquer outra notificação informativa que a spec acrescentar. As respostas a um comando do usuário da regra 89 não são informativas.
82. Erros sempre aparecem, com a opção ligada ou desligada, porque sem eles uma ação falharia em silêncio: o comando do Claude ausente ou que falha ao iniciar, falha de porta ou de lock file, subcomando ou argumentos inválidos, os casos de borda que dizem "erro", o layout inválido na config (regra 88) e as respostas da regra 89.
83. Com a opção desligada, o estado continua visível sem notificação: as marcas `● diff` e `[exited]` na barra de abas, e o `:checkhealth claudinho`, que reporta como aviso (warning) as chaves removidas presentes na config do usuário e o claudecode.nvim instalado.
84. Consequência: no padrão, o aviso de claudecode.nvim instalado (regra 73) e os avisos de chave removida só aparecem no `:checkhealth claudinho`. Os avisos da Fase 0 continuam aparecendo na `0.1.0` até esta feature ser entregue.
85. Um aviso que responde a um comando do usuário que não fez o que ele pediu sempre aparece, como os erros, com a opção da regra 80 ligada ou desligada: `tab-restart` numa aba rodando (regra 42), `tab-restart` sem `session_id` que abre uma sessão nova (regra 43), `No Claude tabs open` e o envio para uma aba encerrada (casos de borda), e qualquer outro aviso desse tipo que a spec acrescentar. Ele só aparece em resposta a uma ação do usuário, e sem ele o comando falharia ou mudaria de efeito em silêncio.

### 6. Layout só pela config

Muda as regras 18, 64 e 68, o **Scope**, os casos de borda, o fluxo "Trocar layout" e um critério de sucesso do **Goal**.

85. O layout da janela vem só da config: o padrão `right` e os tamanhos por layout da regra 17. Trocar de layout é mudar a config e reiniciar o Neovim. A troca em tempo de execução da regra 18 deixa de existir.
86. O subcomando `:Claudinho layout` é removido. Saem com ele: a linha `layout <nome>` da tabela de comandos (regra 64), os nomes de layout na completion (regra 68, que fica com os subcomandos e os números das abas), os casos de borda "`layout` com nome inválido" e "`layout` com o layout atual", o fluxo "Trocar layout" e, no item de janela do **Scope**, "com troca de layout sem matar sessão". `:Claudinho layout` passa a ser um subcomando desconhecido (regra 67).
87. O critério de sucesso "Esconder, mostrar, trocar de aba e de layout nunca encerra sessão" passa a ser "Esconder, mostrar e trocar de aba nunca encerra sessão", medido do mesmo jeito: 10 ciclos de cada, com os PIDs dos `claude` das abas iguais.
88. Um valor de layout inválido na config cai em `right`, com uma mensagem de nível erro que nomeia o valor recebido e os válidos (é erro de config, então aparece mesmo com as notificações desligadas, regra 82). O resto da config funciona.

A regra 25 (no `float`, a janela se esconde quando um diff abre) continua valendo para quem escolhe `float` na config.

### 7. Esclarecimento: o que persiste entre reinícios

Não muda nenhuma regra. O preset de atalhos (regra 69) e o layout (regra 85) vêm só da config do usuário e são aplicados pelo `setup()` em todo início do Neovim, então persistem entre reinícios enquanto estiverem na config. Não existe mais escolha em tempo de execução que se perde ao sair; só as abas morrem com o Neovim, como o **Out of scope** já diz.

## Addendum 2026-11-15 (2): revisão da spec

Origem: a [spec](spec.md) (Draft) deixou cinco perguntas em **Open questions**, e o usuário decidiu todas em 2026-11-15, com as recomendações da spec. As regras novas continuam a numeração do plano, a partir da 90. O texto aprovado acima não foi reescrito: onde ele e este adendo divergem, vale este adendo. Depois deste adendo, o plano não tem pergunta em aberto.

### 1. Errata: duas regras 85

Corrige a numeração do adendo de 2026-11-15, que tem duas regras com o número 85 (spec, Open question 5). A numeração que vale é a que a spec já usa:

| Regra no texto acima                                              | Começa com                                                                      | Número que vale     |
| ----------------------------------------------------------------- | ------------------------------------------------------------------------------- | ------------------- |
| 85 da seção 5 ("Notificações informativas desligadas por padrão") | "Um aviso que responde a um comando do usuário que não fez o que ele pediu ..." | **89**              |
| 85 da seção 6 ("Layout só pela config")                           | "O layout da janela vem só da config ..."                                       | **85** (não muda)   |
| 86 a 88 da seção 6                                                | -                                                                               | 86 a 88 (não mudam) |

Nenhuma citação muda: "regra 89" nas regras 81 e 82 já é a regra das respostas a comandos do usuário, e "regra 85" na seção 7 já é a de layout. Não existe outra regra 89. O adendo de 2026-11-15 fica com as regras 72 a 89, cada número uma vez.

### 2. `autoConnectIde`: aceito e documentado

Muda a regra 62, o caso de borda de `autoConnectIde`, o risco de `autoConnectIde`, o caso de borda "Os dois plugins ativos" da seção 2 do adendo de 2026-11-15 e o critério de sucesso "Nada muda fora das sessões do plugin" (item 5). Spec, Open question 1, opção (a). Nada muda no código.

Fato conferido pela spec no Claude Code CLI 2.1.325 (fato F6): com `autoConnectIde` ligado em `~/.claude.json`, com `claude --ide` ou com `CLAUDE_CODE_AUTO_CONNECT_IDE=1`, um claude aberto fora do Neovim se conecta sozinho quando exatamente um lock file de `~/.claude/ide/` tem uma pasta que contém a cwd dele. O CLI não lê nenhum campo do lock file que tire a aba da conexão automática e a mantenha selecionável no `/ide`. `autoConnectIde` vem desligado por padrão no CLI.

90. A primeira frase da regra 62 ("uma sessão externa nunca se conecta sozinha ao servidor de uma aba") vale com a conexão automática do CLI desligada, que é o padrão: `autoConnectIde` desligado, sem `--ide` e sem `CLAUDE_CODE_AUTO_CONNECT_IDE=1`. Com uma dessas opções ligada pelo próprio usuário, um claude externo pode se conectar sozinho a uma aba quando a pasta dela é a única, entre os lock files de `~/.claude/ide/`, que contém a cwd dele. O plugin aceita esse comportamento e não tenta impedi-lo. O resto da regra 62 (as variáveis de ambiente só no processo de cada aba) não muda.
91. Uma sessão externa conectada sozinha pela regra 90 é cliente da aba como na regra 63: recebe a seleção quando a aba está ativa, os diffs dela seguem as regras da aba, e fechar ou encerrar a aba a desconecta sem encerrá-la.
92. Os dois READMEs explicam que, com `autoConnectIde`, `--ide` ou `CLAUDE_CODE_AUTO_CONNECT_IDE=1`, um claude aberto fora do Neovim pode se conectar sozinho a uma aba, e como evitar: `CLAUDE_CODE_AUTO_CONNECT_IDE=0` numa sessão, ou `autoConnectIde` desligado.

Casos de borda e risco que mudam:

| Situação                                                                                                         | Comportamento esperado                                                                                                                                                                                                                                  |
| ---------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Sessão externa com `autoConnectIde` ligado em `~/.claude.json` (ou `--ide`, ou `CLAUDE_CODE_AUTO_CONNECT_IDE=1`) | Substitui o caso do plano. Quando a pasta de exatamente uma aba contém a cwd dela, ela se conecta sozinha a essa aba (regra 90) e segue a regra 63 (regra 91). Em qualquer outro caso, só um `/ide` explícito conecta. Documentado no README (regra 92) |
| Os dois plugins ativos, `/ide` num claude aberto fora do Neovim                                                  | Substitui a parte "nenhuma conecta sozinha (regra 62)" da seção 2 do adendo de 2026-11-15 por "nenhuma conecta sozinha com a conexão automática desligada (regras 62 e 90)"                                                                             |

| Risco                                                                                                                   | Impacto                                                                                                                                          | Mitigação                                                                                                                       |
| ----------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------- |
| `autoConnectIde` (ou `--ide`, ou `CLAUDE_CODE_AUTO_CONNECT_IDE=1`) faz uma sessão externa se conectar sozinha a uma aba | Substitui o risco do plano. Só afeta quem ligou a opção, que existe para isso; com o padrão do CLI, o isolamento das regras 61 e 62 vale inteiro | Comportamento aceito (regra 90) e documentado no README com o jeito de desligar (regra 92); a sessão conectada segue a regra 63 |

### 3. Opções de diretório removidas

Complementa as regras 4, 71 e 77. Spec, Open question 2, opção (a).

93. As opções `terminal.cwd`, `terminal.git_repo_cwd` e `terminal.cwd_provider` e os aliases do topo `cwd`, `git_repo_cwd` e `cwd_provider` deixam de existir: uma aba nova sempre inicia no `getcwd()` da janela atual (regra 4), e nenhuma opção muda isso.
94. As seis chaves entram na tabela de chaves removidas das regras 71 e 77, com o aviso de sempre: nomeia a chave e diz o que a substitui (a aba nova inicia no diretório atual do Neovim, `:pwd`), e o resto da config funciona. O aviso é informativo (regra 81): aparece só com a opção `notify` da regra 80 ligada, e o `:checkhealth claudinho` sempre o mostra como aviso (regra 83).
95. O módulo `cwd.lua` sai, com os testes dele. Os READMEs tiram essas opções da config e as listam entre as chaves removidas.

### 4. Dois Neovims na mesma pasta

Resolve o caso de borda "Dois Neovims abertos, cada um com uma aba 1" e a parte da regra 7 que deixava o formato do nome para a spec conferir. Spec, Open question 3, opção (a).

Fato conferido pela spec (fato F5): o `/ide` usa o `ideName` do lock file como rótulo e, quando duas entradas disponíveis têm o mesmo nome, mostra as pastas de cada uma como descrição. Dentro de uma aba, o `/ide` lista só as abas do próprio Neovim.

96. O nome da aba no `/ide` continua `Neovim (Claudinho <n>)`, sem pasta nem PID acrescentados.
97. Os dois READMEs registram o caso: num claude aberto fora do Neovim, dois Neovims com abas de mesmo número mostram a pasta de cada uma no `/ide`, e na mesma pasta as duas linhas ficam iguais. Dentro de uma aba, o `/ide` lista só as abas do próprio Neovim, então lá elas não se confundem.

| Situação                                    | Comportamento esperado                                                                                                                                                                                                                                                                            |
| ------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Dois Neovims abertos, cada um com uma aba 1 | Substitui o caso do plano. No `/ide` de um claude externo, as duas aparecem como `Neovim (Claudinho 1)`, com a pasta de cada uma como descrição; na mesma pasta, as linhas ficam iguais, o que é aceito e documentado (regras 96 e 97). No `/ide` de uma aba, só aparecem as abas do mesmo Neovim |

### 5. Critério "Nada muda fora das sessões do plugin"

Muda esse critério de sucesso do **Goal**. Spec, Open question 4. A regra 57 não muda: o plugin continua sem escrever em nenhum dos três lugares. Só a medição muda, porque o próprio CLI regrava `~/.claude.json` a cada início (spec, fato F10), com ou sem o plugin.

| Critério                             | Como medir                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| ------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Nada muda fora das sessões do plugin | Testes automatizados com um `claude` stub provam que o plugin não escreve em `~/.claude/settings.json`, `~/.claude.json` nem em `.claude/` do projeto (mesmo checksum antes e depois de abrir, usar e fechar abas). Com o CLI real, o roteiro manual do usuário confere só os checksums de `~/.claude/settings.json` e de `.claude/` do projeto. Com a conexão automática do CLI desligada (padrão), um claude externo não se conecta sozinho a nenhuma aba (regras 62 e 90) |

## Addendum 2026-11-17: layout `left`

Origem: decisão do usuário em 2026-11-17, dentro desta feature (não é uma feature nova). As regras novas continuam a numeração do plano, a partir da 98. O texto aprovado acima não foi reescrito: onde ele e este adendo divergem, vale este adendo.

Muda a regra 17 (tabela de layouts), o item de janela do **Scope**, o caso de borda "Troca de aba do Neovim (`gt`) com layout `right` ou `bottom`" e a lista de layouts válidos da regra 88. Complementa as regras 25, 70 e 85 e acrescenta um critério de sucesso ao **Goal**. A regra 86 não muda: `:Claudinho layout` continua um subcomando desconhecido.

### 1. O layout

98. Existe um quinto layout, `left`: split vertical na borda esquerda, na altura toda da tela, ao lado de todos os splits do editor. É o espelho do `right`. O layout padrão continua `right`.

A tabela da regra 17 passa a ser:

| Layout           | Onde fica                                                                                      | Tamanho (config, padrão) |
| ---------------- | ---------------------------------------------------------------------------------------------- | ------------------------ |
| `right` (padrão) | Split vertical na borda direita, na altura toda da tela, ao lado de todos os splits do editor  | Largura, 30% das colunas |
| `left`           | Split vertical na borda esquerda, na altura toda da tela, ao lado de todos os splits do editor | Largura, 30% das colunas |
| `bottom`         | Split horizontal na borda de baixo, na largura toda                                            | Altura, 30% das linhas   |
| `float`          | Janela flutuante centralizada                                                                  | Largura e altura, 80%    |
| `tab`            | Aba do Neovim própria, com a janela ocupando a aba inteira                                     | -                        |

O item de janela do **Scope** passa a ser: "Janela do Claude com a barra de abas na winbar e os layouts `right` (padrão), `left`, `bottom`, `float` e `tab`" (sem a troca de layout, que a regra 86 já tirou).

### 2. Config

99. Os tamanhos do `left` ficam numa tabela própria da config, `window.left`, como cada layout tem a sua (regra 70):

| Chave                    | Padrão | O que é                                                                                           |
| ------------------------ | ------ | ------------------------------------------------------------------------------------------------- |
| `window.left.width`      | `0.30` | Largura da janela, como fração das colunas                                                        |
| `window.left.diff_width` | `nil`  | Largura da janela enquanto um diff está aberto, com as mesmas regras de `window.right.diff_width` |

100. `window.left` e `window.right` são independentes: com o layout `left` valem só os tamanhos de `window.left`, e com o `right`, só os de `window.right`. Um `window.left` com outro layout ativo fica guardado e não tem efeito, como um `window.bottom` com o layout `right`.
101. Um valor inválido em `window.left.width` ou `window.left.diff_width` cai no padrão da chave (`0.30` e `nil`), com uma mensagem de nível erro que nomeia a chave e o valor recebido, como as outras chaves da janela. É erro de config, então aparece mesmo com as notificações desligadas (regra 82), e vale qualquer que seja o layout ativo. O resto da config funciona.
102. `left` entra nos layouts válidos de `window.layout`. A mensagem de erro da regra 88 lista `left` entre os válidos, e um valor inválido continua caindo em `right`.

### 3. Diff com o layout `left`

103. Com o `left`, a relação entre o diff e a janela do Claude é a do `right`, espelhada, lendo `window.left` no lugar de `window.right`:
     - com `diff_opts.auto_resize_terminal` ligado (padrão), o plugin redimensiona a janela do Claude enquanto o diff está aberto e devolve a largura quando ele fecha, como faz no `right`; desligado, o plugin não mexe na largura;
     - com `diff_opts.open_in_new_tab`, a janela do Claude vai para a borda esquerda da aba nova do Neovim, no lugar da direita;
     - o diff abre na área do editor, nunca na janela do Claude, e a janela do Claude continua visível ao lado dele (a regra 25 só esconde a janela no `float`).

### Casos de borda

| Situação                                                                  | Comportamento esperado                                                                                                                                                                                                    |
| ------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Troca de aba do Neovim (`gt`) com layout `right`, `left` ou `bottom`      | Substitui o caso do plano, só acrescentando o `left`. A janela do Claude fica na aba do Neovim onde estava; `toggle`/`open` em outra aba do Neovim leva a janela para lá, na borda do layout                              |
| `left` com um explorer de arquivos já aberto na esquerda (ex.: nvim-tree) | Ao mostrar, a janela do Claude fica na borda esquerda, à esquerda do explorer, na altura toda; o plugin não move nem redimensiona o explorer                                                                              |
| Explorer aberto na esquerda com a janela do Claude já visível no `left`   | O explorer abre onde o próprio comando dele manda; o plugin não reposiciona a janela do Claude na hora, como no `right` com uma barra lateral aberta à direita. Ao esconder e mostrar de novo, ela volta à borda esquerda |
| `window.left.diff_width` inválido com o layout `right`                    | Erro nomeando a chave (regra 101); o valor cai em `nil` e nada muda no `right`                                                                                                                                            |

### Critério de sucesso

Acrescenta ao **Goal**:

| Critério                          | Como medir                                                                                                                                                                                                                                                                                                                        |
| --------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| O layout `left` espelha o `right` | Com `window.layout = "left"` e dois splits verticais no editor: a janela do Claude começa na primeira coluna, tem a altura toda do editor e a largura de `window.left.width`; com um diff aberto, a largura segue as regras do `right` (regra 103), e com `diff_opts.open_in_new_tab` a janela fica na borda esquerda da aba nova |

Os dois READMEs documentam o layout `left` e as chaves `window.left.width` e `window.left.diff_width`, e a mudança entra em `## [Unreleased]` no `CHANGELOG.md` (regra 78).

## Addendum 2026-11-17 (2): janela do Claude sempre na borda

Origem: relato e decisão do usuário em 2026-11-17, dentro desta feature. Com o neo-tree configurado na direita e o layout `right`, abrir o Claude dá `arquivo | neo-tree | Claude` (certo), mas fechar e reabrir o neo-tree dá `arquivo | Claude | neo-tree`, porque o neo-tree reabre na borda direita. Hoje o plano diz que o plugin não reposiciona a janela do Claude depois que outra janela toma a borda (só `hide` + `open` a devolve). Decisão do usuário: a janela do Claude fica sempre na borda, como a regra 17 promete ("na borda ... ao lado de todos os splits do editor"). As regras novas continuam a numeração do plano, a partir da 104. O texto aprovado acima não foi reescrito: onde ele e este adendo divergem, vale este adendo.

Muda o caso de borda "Explorer aberto na esquerda com a janela do Claude já visível no `left`" do adendo de 2026-11-17 (layout `left`), incluindo a comparação com o `right` que ele faz. Complementa as regras 17, 23, 25, 98 e 103, acrescenta um critério de sucesso ao **Goal** e dois riscos.

### 1. A regra

104. Nos layouts `right`, `left` e `bottom`, a janela do Claude fica sempre na borda do layout, qualquer que seja a ordem em que as janelas abriram. O resultado é o mesmo de quando ela abre por último (regras 17 e 98):

| Layout   | Na borda quer dizer                                                                      |
| -------- | ---------------------------------------------------------------------------------------- |
| `right`  | Última coluna da aba do Neovim, da primeira à última linha da área de janelas            |
| `left`   | Primeira coluna da aba do Neovim, da primeira à última linha da área de janelas          |
| `bottom` | Última linha de janelas da aba do Neovim, da primeira à última coluna da área de janelas |

105. Quando uma mudança na disposição das janelas da aba do Neovim onde a janela do Claude está a tira da borda, o plugin a devolve à borda logo em seguida, sem ação do usuário. Vale para qualquer causa: uma janela aberta depois (neo-tree, nvim-tree, `:Lexplore`, `:botright vsplit`, `:botright copen`, um `:vsplit` feito de dentro da própria janela do Claude) ou uma janela movida (`<C-w>L` em outra janela, `<C-w>H` ou `<C-w>K` na própria janela do Claude). Quem quer a janela em outro lugar troca `window.layout` (regra 85).
106. De volta à borda, a janela do Claude mantém o tamanho que tinha antes da mudança: a largura no `right` e no `left`, a altura no `bottom`. Esse tamanho é o da config (`window.<lado>.width`, `window.bottom.height`), o do diff enquanto um diff a redimensiona (regra 103) ou o que o usuário deu à mão, o que estiver valendo no momento.
107. O plugin não move nem redimensiona nenhuma outra janela por conta própria. As outras ficam na mesma ordem, do lado de dentro da janela do Claude (no caso do relato: `arquivo | neo-tree | Claude`). Só muda nelas o que o Neovim muda ao mover uma janela: uma janela com `winfixwidth` (`winfixheight` no `bottom`) mantém o tamanho, e as outras dividem o espaço que sobra pelas regras do Neovim (`'equalalways'`).
108. A correção não muda a janela em foco, o modo (terminal, normal, inserção), o cursor nem o buffer de nenhuma janela, e a janela do Claude continua a mesma, com a winbar e a statusline dela. Ela não mostra notificação, nem com a opção `notify` da regra 80 ligada. Mover a janela não é fechá-la: a regra 23 não se aplica.
109. Só janelas não flutuantes contam. Abrir, mover ou fechar uma janela flutuante (mini.files, `:Oil --float`, popups, notificações) nunca dispara a correção. Mudar só tamanhos (`<C-w>>`, `<C-w>=`, arrastar a divisa com o mouse, o redimensionamento do diff, a volta dos tamanhos quando o diff fecha) também não: isso não tira a janela da borda.
110. Nada disso vale nos layouts `float` e `tab`, com a janela do Claude escondida, nem nas abas do Neovim onde ela não está. Ao aparecer de novo, ela abre na borda, como hoje (regra 17).
111. Sem laço: uma correção por mudança. Se a janela do Claude sai da borda de novo logo depois de uma correção, antes da próxima ação do usuário (outro plugin que também insiste na borda e reage à correção), o plugin não corrige outra vez: a janela fica onde o outro plugin a deixou, sem erro e sem notificação, até a próxima mudança de disposição que venha depois de uma ação do usuário, ou até `hide` + `open`. No pior caso, cada ação do usuário causa uma correção só; nunca um laço, e o Neovim continua respondendo.
112. Não existe opção na config para desligar a correção. O layout é uma borda (regra 17), e o usuário decidiu que a janela fica sempre nela; uma opção dobraria os casos de teste e a documentação sem pedido real. Se um caso real aparecer (ver os riscos), uma opção booleana ligada por padrão entra depois sem quebrar nenhuma config.

### 2. `bottom` também

Decisão deste adendo: a regra vale também para o `bottom`. A regra 17 faz ao `bottom` a mesma promessa que ao `right` ("na borda de baixo, na largura toda"), o mecanismo é o mesmo e a regra 111 limita a disputa. Deixar o `bottom` de fora daria dois comportamentos para a mesma regra 17. A borda de baixo é a mais disputada (quickfix, terminais com `botright`, listas de diagnóstico); com a correção, essas janelas ficam acima da janela do Claude, na largura da área do editor, que é onde elas ficariam se o Claude tivesse aberto por último.

### 3. Diff

O diff continua com as regras dele; este adendo só diz como elas convivem com a correção.

| Regra / caso                                                        | Como convive                                                                                                                                                                                                                                                                                  |
| ------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Regra 25 (`float` esconde a janela quando um diff abre)             | Sem relação: o `float` fica fora da correção (regra 110)                                                                                                                                                                                                                                      |
| Regra 103 e `diff_opts.auto_resize_terminal`                        | O redimensionamento do diff só muda tamanhos e não dispara nada (regra 109). Uma correção durante o diff mantém a largura do diff (regra 106), e quando o diff fecha a largura volta como hoje                                                                                                |
| Janelas do diff na mesma aba do Neovim                              | Abrem na área do editor (a janela que o plugin escolhe nunca é a do Claude nem um explorer), então ficam do lado de dentro e nada se move                                                                                                                                                     |
| Diff com a janela do Claude sozinha na aba (fallback do issue #231) | A janela do diff fica do lado de dentro: à esquerda do Claude no `right`, à direita no `left`, acima no `bottom`. A janela do Claude fica na borda com o tamanho dela e não se move de forma visível. Quando o diff fecha, a janela do fallback fecha e o Claude volta a ocupar a aba sozinho |
| `diff_opts.open_in_new_tab` (regra 103)                             | A janela do Claude da aba original segue este adendo na aba dela. A janela que mostra o terminal na aba nova do diff é posta na borda quando a aba abre (regra 103) e fica fora da correção: ela é temporária e fecha com o diff, então uma janela aberta depois na aba do diff não a move    |

### Casos de borda

| Situação                                                                                                     | Comportamento esperado                                                                                                                                                                                                                                                                                                            |
| ------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Explorer aberto na esquerda com a janela do Claude já visível no `left`                                      | Substitui o caso do adendo de 2026-11-17 (layout `left`). O explorer abre onde o comando dele manda (ex.: nvim-tree e `:Lexplore` na primeira coluna); logo em seguida o plugin devolve o Claude à primeira coluna, e o explorer fica à direita dele com a largura dele (regras 105 a 107). `hide` + `open` não é mais necessário |
| `right`, neo-tree na direita: Claude visível, neo-tree fechado e reaberto (relato do usuário)                | O neo-tree reabre na borda direita; o plugin devolve o Claude à última coluna: `arquivo \| neo-tree \| Claude`, com a largura que o Claude tinha e o neo-tree com a dele                                                                                                                                                          |
| `right` ou `left` com uma janela aberta embaixo na largura toda (`:botright copen`, `:botright split`)       | O Claude volta a ter a altura toda; a janela de baixo fica embaixo da área do editor, com a altura dela quando tem `winfixheight`                                                                                                                                                                                                 |
| `bottom` com uma janela aberta embaixo (`:botright copen`) ou na altura toda do lado (`:botright vsplit`)    | O Claude volta a ser a última linha, na largura toda; a outra janela fica acima dele                                                                                                                                                                                                                                              |
| O usuário move a própria janela do Claude (`<C-w>H`, `<C-w>K`, `<C-w>x`)                                     | O plugin a devolve à borda (regra 105); para outro lugar, o caminho é `window.layout`                                                                                                                                                                                                                                             |
| `:vsplit` feito de dentro da janela do Claude com `splitright`                                               | A janela nova (que mostra o mesmo terminal) toma a borda; o plugin devolve o Claude à borda, e a janela nova fica do lado de dentro como qualquer outra janela                                                                                                                                                                    |
| Duas barras laterais no mesmo lado (ex.: neo-tree e uma de símbolos)                                         | As duas ficam do lado de dentro, na ordem em que estavam; o Claude na borda                                                                                                                                                                                                                                                       |
| Outro plugin devolve a janela dele à borda sempre que o layout muda (gerenciadores de janela como edgy.nvim) | Regra 111: uma correção; a reação do outro plugin vence, sem laço, sem erro e sem notificação; na próxima ação do usuário que mude a disposição, no máximo mais uma correção                                                                                                                                                      |
| Janela de linha de comando (`q:`) aberta                                                                     | O Neovim não deixa mover janelas enquanto ela está aberta; nada é corrigido nesse meio-tempo e nenhum erro aparece. Se o Claude ainda estiver fora da borda quando ela fecha, a correção acontece nesse momento                                                                                                                   |
| Tela estreita: as larguras fixas não cabem nas colunas                                                       | O Neovim reparte o espaço pelas regras dele; o Claude volta à borda com a maior largura possível até a dele, sem erro                                                                                                                                                                                                             |
| Janela do Claude na aba 1 do Neovim e o usuário abre splits na aba 2                                         | Nada acontece (regra 110); a janela continua onde estava na aba 1                                                                                                                                                                                                                                                                 |

### Critério de sucesso

Acrescenta ao **Goal**:

| Critério                         | Como medir                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| -------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A janela do Claude fica na borda | Teste de integração, para `right`, `left` e `bottom`: com o Claude visível, abrir uma janela na borda dele com `winfixwidth` (`winfixheight` no `bottom`) e tamanho fixo (`botright vsplit`, `topleft vsplit`, `botright split`): o Claude volta à borda, na altura toda (largura toda no `bottom`), com o tamanho de antes, a outra janela fica colada a ele do lado de dentro com o tamanho dela, e a janela em foco e o modo não mudam. Com um autocmd de teste que devolve a outra janela à borda a cada mudança de disposição, um `botright vsplit` causa no máximo uma correção e o Neovim continua respondendo |

### Riscos

| Risco                                                                                                     | Impacto                                                                | Mitigação                                                                                                                                                                |
| --------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Outro plugin também insiste na borda (gerenciadores de janela como edgy.nvim, barras que se reposicionam) | Uma troca visível por ação do usuário; o outro plugin fica com a borda | Regra 111 limita a uma correção por ação, sem laço; o README registra o caso. Se um caso real incomodar, a opção booleana da regra 112 entra depois, sem quebrar config  |
| Mover a janela muda tamanhos que o usuário ou o diff acertaram                                            | Explorer ou diff com largura errada depois da correção                 | Regras 106 e 107; o teste do critério confere os tamanhos das duas janelas, e a spec cobre a correção durante um diff aberto e o fechamento do diff (volta dos tamanhos) |

A spec atualiza junto o que dizia "não reposiciona": a tabela de explorers da seção 15 e o roteiro manual do layout `left`. Os dois READMEs explicam que a janela do Claude volta sozinha à borda e o limite da regra 111, e a mudança entra em `## [Unreleased]` no `CHANGELOG.md` (regra 78).

## Addendum 2026-11-18: guarda no `select-model` e subcomandos novos

Origem: decisão do usuário em 2026-11-18, no plano da feature [status-interativo](../status-interativo/plan.md) (Draft). Este adendo só aponta o que muda aqui; as regras ficam naquele plano e valem quando ele for entregue. Até lá, as regras abaixo continuam como estão. O texto aprovado acima não foi reescrito.

| Regra desta feature                          | O que muda                                                                                                                                                                                                                                                                           | Onde está a regra nova            |
| -------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------- |
| 66 (`select-model`)                          | Com uma aba ativa rodando, o `/model <valor>` só é enviado com o campo de prompt do Claude à vista, vazio e sem diálogo aberto, checado antes de abrir a escolha e de novo depois dela; senão nada é enviado e uma resposta curta explica. Sem abas e com a aba encerrada, nada muda | status-interativo, regras 9 a 15  |
| 64 (tabela de subcomandos) e 68 (completion) | Entram `select-effort` (abre o seletor `/effort` do Claude na aba ativa) e `mode-next` (Shift+Tab na aba ativa), com completion e a mesma guarda                                                                                                                                     | status-interativo, regras 17 a 28 |
| 69 (preset)                                  | Decidido pelo usuário em 2026-11-19: o preset opcional ganha `<leader>ae` (`select-effort`) e `<leader>ap` (`mode-next`), com a mesma proteção contra tecla já mapeada; desligado por padrão, como hoje                                                                              | status-interativo, regra 28       |
