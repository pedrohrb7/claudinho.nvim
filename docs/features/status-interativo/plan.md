# Status interativo: statusline clicável, modo ao vivo e comandos de esforço e modo

- **Date:** 2026-11-18
- **Status:** Draft
- **Spec:** [spec.md](spec.md) <!-- quando existir -->
- **Revisão 2026-11-18:** o usuário decidiu as três perguntas abertas: clique que não pode enviar não envia e responde (regra 11); a mesma guarda vale para o `/model` do `select-model` (regra 15, com [adendo na base-ui](../base-ui/plan.md#addendum-2026-11-18-guarda-no-select-model-e-subcomandos-novos)); entram os subcomandos `select-effort` e `mode-next` (regras 23 a 28).
- **Revisão 2026-11-18 (2):** decisão do usuário: uma linha de modo com rótulo desconhecido mostra o rótulo como veio, em vez de manter o último modo; sem linha de modo e com o campo de prompt não reconhecido, o último modo continua (regras 30 a 33).
- **Revisão 2026-11-19:** decisão do usuário: o preset opcional de atalhos ganha `<leader>ae` (`select-effort`) e `<leader>ap` (`mode-next`), com a proteção da regra 69 da base-ui (regra 28). Nenhuma pergunta em aberto.

## Goal

A statusline da janela do Claude (`Opus 5.5 · high · manual`) deixa de ser só leitura: cada item vira um atalho para trocar aquilo que mostra, e o modo passa a acompanhar a TUI na hora, sem esperar o próximo prompt. O plugin nunca digita por cima do usuário nem responde a um diálogo do Claude no lugar dele.

- Clicar no modelo abre a escolha de modelo do plugin (`:Claudinho select-model`).
- Clicar no esforço, ou `:Claudinho select-effort`, abre o seletor de esforço do próprio Claude (`/effort`) na aba ativa.
- Clicar no modo, ou `:Claudinho mode-next`, passa ao próximo modo de permissão da aba ativa, como o Shift+Tab na TUI.
- O modo mostrado muda logo depois de cada troca, feita pelo plugin ou direto na TUI, e aparece desde o início da sessão.
- Toda tecla que o plugin manda à TUI por esta feature, inclusive o `/model` do `select-model`, passa pela mesma guarda: campo de prompt à vista e sem diálogo aberto.

Critérios de sucesso, todos verificáveis na máquina do usuário (Claude Code 2.1.328 ou a versão instalada na entrega, registrada no log):

| Critério                            | Como medir                                                                                                                                                                                                                                                                        |
| ----------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Modo ao vivo                        | Numa aba ociosa, 20 trocas com Shift+Tab digitado na TUI: em 20 de 20, a statusline mostra o modo novo em até 1 s                                                                                                                                                                 |
| Modo desde o início                 | Aba nova, sem nenhum prompt: o modo aparece em até 1 s depois do primeiro status (modelo ou esforço)                                                                                                                                                                              |
| Clique no modo e `mode-next`        | Com a aba ociosa e o prompt vazio, 5 cliques no modo, e depois 5 `:Claudinho mode-next`, percorrem o mesmo ciclo que 5 Shift+Tab na TUI, e o status acompanha cada um                                                                                                             |
| Clique no esforço e `select-effort` | Com o prompt vazio, cada um abre o seletor de esforço do Claude e foca o terminal da aba; escolher um nível muda o esforço da sessão                                                                                                                                              |
| Clique no modelo                    | Um clique abre a mesma escolha de `:Claudinho select-model`                                                                                                                                                                                                                       |
| Preset                              | Com `keymaps.preset = true`, `<leader>ae` e `<leader>ap` fazem o mesmo que `select-effort` e `mode-next`; com uma dessas teclas já mapeada pelo usuário, o mapeamento dele continua; com o preset desligado (padrão), nenhuma das duas é criada                                   |
| Nada é digitado por cima do usuário | Com texto digitado no prompt, `select-effort`, `select-model` e os cliques no esforço e no modelo não mudam o texto; com um pedido de permissão ou a aprovação de plano aberta, o clique no modo e `mode-next` não respondem ao pedido (o diálogo continua aberto e sem resposta) |
| Funciona com a statusline global    | Com `laststatus=3` e a janela do Claude em foco, os três cliques funcionam como com `laststatus=2`                                                                                                                                                                                |
| Texto desconhecido não mente        | Com fixtures de rodapé: `⏵⏵ foo mode on` mostra `foo mode`; um rodapé sem linha de modo e sem campo de prompt reconhecido mantém o último modo; um rodapé com só `install gh for PR status` (ou outra dica) nunca aparece no status                                               |
| Entrega fechada                     | `mise run all` verde, README (pt e en) atualizado, nenhuma entrada nova em `docs/backlog/` e release `0.3.0` (`mise run release minor`)                                                                                                                                           |

## Context

A UI base ([base-ui](../base-ui/plan.md), regras 47 a 54) entregou o status na statusline da janela, só para leitura. Duas limitações ficaram:

- O modo vem só dos hooks `SessionStart`, `UserPromptSubmit` e `Stop` (`session_settings.lua`, `sources/session_data.lua` `from_hook`). Ele só aparece depois do primeiro prompt e fica velho entre um Shift+Tab e o próximo prompt ou fim de turno. O README registra isso em **Limitações**.
- Trocar modelo, esforço ou modo exige ir até a TUI ou lembrar de um comando, e o `select-model` (regra 66 da base-ui) manda `/model <valor>` sem olhar a tela: com texto no prompt, o comando se mistura ao texto.

O que foi medido de ponta a ponta (Claude Code 2.1.328, `claude` real num terminal de um Neovim headless):

| Fato                                                                                                                                            | Consequência                                                         |
| ----------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------- |
| O comando de statusline roda de novo a cada troca de modo (início + 2 trocas = 3 execuções)                                                     | Cada troca de modo gera um POST de statusline para o servidor da aba |
| O JSON da statusline não traz o modo; entre as execuções só mudaram `cost.total_duration_ms` e `rate_limits`                                    | O POST avisa que algo mudou, mas o modo precisa vir de outro lugar   |
| Nenhum hook dispara numa troca de modo                                                                                                          | Os hooks não resolvem o atraso                                       |
| O rodapé da TUI mostra o modo em texto: `⏵⏵ accept edits on (shift+tab to cycle)`, `⏸ plan mode on`, `auto mode on`; sem linha de modo = manual | O plugin lê o modo da tela do terminal da aba quando o POST chega    |

Decisões do usuário (2026-11-18):

- A cada POST de statusline, o plugin lê o modo no rodapé da TUI, no buffer do terminal da sessão. Os hooks continuam mandando o modo quando disparam. Rodapé não reconhecido mantém o último modo conhecido. Risco aceito: o texto do rodapé pode mudar entre versões do Claude.
- Quando a TUI não está pronta, nada é enviado e uma resposta curta explica (não envia às cegas, não guarda para depois).
- A mesma guarda vale para o `/model` do `select-model`, pelo comando e pelo clique.
- Entram os subcomandos de esforço e de modo, com completion e a mesma guarda.

A documentação do Claude Code confirma por que mandar teclas às cegas é perigoso ([Interactive mode](https://code.claude.com/docs/en/interactive-mode)): num pedido de permissão de arquivo, o Shift+Tab escolhe a opção que permite a ação pelo resto da sessão, e na aprovação de plano ele aprova o plano. O `/effort` e o `/model` rodam na hora mesmo com o Claude trabalhando (não entram na fila); o `/effort` sem argumento abre um seletor interativo ([Model configuration](https://code.claude.com/docs/en/model-config)).

O mecanismo de clique é o mesmo da barra de abas: regiões `%N@v:lua.<função>@...%X` (`lua/claudinho/ui/tabbar.lua`, `M.CLICK_FUNC`). Relação com o roadmap do PRD:

| Fase / área do PRD        | Item                                                                                                     | Neste plano                                 |
| ------------------------- | -------------------------------------------------------------------------------------------------------- | ------------------------------------------- |
| 3 · Painel de informações | Modo da sessão atualizado ao vivo                                                                        | Dentro                                      |
| 3 · Painel de informações | Estado ao vivo (pensando, tool, permissão), custo, % de contexto, arquivos editados                      | Fora (feature Painel)                       |
| 4 · Mouse                 | Regiões clicáveis na statusline (`%@Func@`)                                                              | Dentro, só a statusline da janela do Claude |
| 4 · Mouse                 | Menu `PopUp`, clique nos itens do painel, arrastar                                                       | Fora (feature Envio de contexto e mouse)    |
| 5 · Comandos e atalhos    | Subcomandos novos `select-effort` e `mode-next`, com teclas no preset opcional; guarda no `select-model` | Dentro                                      |

## Scope

**In scope:**

- Regiões clicáveis (botão esquerdo) no modelo, no esforço e no modo da statusline da janela do Claude.
- Subcomandos `:Claudinho select-effort` e `:Claudinho mode-next`, com completion e teclas no preset opcional de atalhos (`<leader>ae` e `<leader>ap`).
- A guarda que decide quando o plugin pode mandar teclas à TUI, e a resposta quando não pode, para os cliques, os dois subcomandos novos e o `/model` do `select-model`.
- Leitura do modo no rodapé da TUI a cada POST de statusline, para todas as abas rodando, ativas ou não.
- Adendo na [base-ui](../base-ui/plan.md) apontando a mudança da regra 66 e da tabela de subcomandos (regra 64).
- README (pt e en): a seção da statusline, os comandos novos, a guarda e o texto de **Limitações** sobre o modo; `CHANGELOG.md`.
- Testes, incluindo fixtures de telas reais do rodapé, do campo de prompt e dos diálogos.

**Out of scope:**

- Mudar o texto, a ordem ou os destaques da statusline (regras 47 a 51 da base-ui continuam).
- Argumentos nos subcomandos novos (ex.: `select-effort high`, escolher um modo pelo nome).
- Cliques na statusline de outras janelas, menu `PopUp`, botão direito e do meio.
- Estado ao vivo do Claude (pensando, rodando tool, esperando permissão) e o resto do painel.
- Hooks novos: a lista continua `SessionStart`, `UserPromptSubmit` e `Stop`.
- Proteger os outros envios ao terminal (`send-text`, `send`, `add`, `tree-add`): seguem como hoje.

## Business rules

Os textos que o plugin mostra saem em inglês (adendo de idioma da base-ui); o texto final das mensagens fica para a spec.

### Regiões clicáveis

1. O modelo, o esforço e o modo da statusline da janela do Claude são clicáveis, cada um na sua região. O separador `·` e o espaço fora dos itens não são clicáveis.
2. Só o botão esquerdo age. Botão direito, do meio e rolagem nas regiões não fazem nada.
3. Cada clique esquerdo é uma ação, inclusive os cliques de um clique duplo ou triplo (dois cliques rápidos no modo trocam o modo duas vezes, se a guarda permitir cada um).
4. O clique age sempre sobre a aba ativa, a mesma cujo status a statusline está mostrando.
5. Um item que não está no status (sem dado, regra 51 da base-ui) não tem região. Sem nenhum dado, nada é clicável.
6. O texto, a ordem, os separadores e as cores da statusline não mudam: ela fica igual à de hoje, só que clicável.
7. Os cliques funcionam com o foco em qualquer janela e em qualquer modo do Neovim (normal, inserção, terminal), sempre que a statusline da janela do Claude estiver à vista: com `laststatus=2`, e com `laststatus=3` quando a janela do Claude está em foco (é quando a statusline global mostra o status dela).
8. Fora o esforço (regra 18) e a escolha de modelo do Neovim (regra 15), um clique ou subcomando desta feature não muda a janela em foco, o modo do Neovim nem o cursor.

### A guarda: quando o plugin pode mandar teclas à TUI

9. Toda tecla que esta feature manda à TUI (clique no esforço e no modo, `select-effort`, `mode-next` e o `/model` do `select-model`, pelo comando ou pelo clique) só é enviada quando a tela da aba ativa mostra o campo de prompt do Claude, sem nenhum diálogo aberto por cima (pedido de permissão, aprovação de plano, pergunta de confiança da pasta, seletor de `/model` ou `/effort`, menus). O Claude pode estar trabalhando: o Shift+Tab, o `/effort` e o `/model` agem na hora mesmo assim.
10. O `/effort` e o `/model` exigem também o campo de prompt vazio, porque são digitados no prompt. O Shift+Tab não exige (regra 21). Quando o plugin não consegue dizer se o prompt está vazio, conta como não vazio.
11. Quando a guarda não é cumprida, ou o plugin não reconhece a tela, nada é enviado, nada fica guardado para depois, o texto do usuário e qualquer diálogo aberto ficam intactos, e uma resposta curta diz por quê. A resposta sempre aparece, com `notify` ligado ou desligado, como as respostas da regra 89 da base-ui:

| Situação                               | Resposta (texto final na spec)                       |
| -------------------------------------- | ---------------------------------------------------- |
| Diálogo aberto ou tela não reconhecida | `Claude <n>: finish the open prompt in Claude first` |
| Texto no prompt (`/effort` e `/model`) | `Claude <n>: clear the prompt first`                 |

12. A checagem da guarda e o envio acontecem no mesmo passo, sem espera entre eles.
13. Antes da guarda vêm as respostas que já existem: sem abas, `No Claude tabs open` (exceto o `select-model`, regra 15); aba ativa encerrada, `Claude <n> has exited; run :Claudinho tab-restart <n>`.

### Modelo

14. Clicar no modelo faz o mesmo que `:Claudinho select-model`.
15. `select-model`, pelo comando ou pelo clique, muda a regra 66 da base-ui assim:
    - sem abas: como hoje, abre a escolha e cria a aba 1 com `claude --model <valor>`, sem guarda (não há TUI);
    - com a aba ativa encerrada: a resposta de hoje, sem abrir a escolha;
    - com a aba ativa rodando: a guarda (regras 9 e 10) é checada antes de abrir a escolha; sem ela, a resposta da regra 11 e a escolha não abre;
    - depois da escolha, a guarda é checada de novo na aba ativa naquele momento (que pode ser outra, regra 66 da base-ui); cumprida, `/model <valor>` é enviado; não cumprida, a resposta da regra 11 e nada é enviado.
16. Com a escolha de modelo do Neovim já aberta, um novo clique ou `select-model` não abre uma segunda.

### Esforço

17. Clicar no esforço e `:Claudinho select-effort` fazem o mesmo: mandam `/effort` e Enter à TUI da aba ativa, o que abre o seletor de esforço do Claude, se a guarda permitir (regras 9 e 10).
18. Depois de enviar, o plugin mostra a janela do Claude (se estiver escondida) e foca o terminal da aba ativa em modo terminal, para o usuário escolher o nível no seletor com o teclado. Quem escolhe o nível e como ele persiste é o Claude (Enter salva como padrão, `s` vale só para a sessão).

### Modo

19. Clicar no modo e `:Claudinho mode-next` fazem o mesmo: mandam um Shift+Tab (`ESC [ Z`) à TUI da aba ativa, que passa ao próximo modo do ciclo do Claude, se a guarda permitir (regra 9). O ciclo e os modos disponíveis são os do Claude; o plugin não escolhe o modo.
20. O status mostra o modo novo pela leitura da regra 29, não por suposição: o plugin nunca adivinha o próximo modo do ciclo.
21. Com texto digitado no prompt, o Shift+Tab é enviado (ele não mexe no texto). A spec confirma isso de ponta a ponta; se o Shift+Tab mexer no texto, o modo passa a exigir o prompt vazio, como o esforço (regra 10).
22. `mode-next` não mostra nem foca a janela (regra 8). Com a janela escondida, o modo muda na aba e aparece no status quando a janela voltar.

### Subcomandos

23. A tabela de subcomandos (regra 64 da base-ui) ganha as duas linhas abaixo. Os nomes seguem os que existem: `select-effort` abre um seletor, como `select-model`; `mode-next` passa ao próximo de um ciclo, como `tab-next`.

| Subcomando      | O que faz      | Antes |
| --------------- | -------------- | ----- |
| `select-effort` | Regras 17 e 18 | -     |
| `mode-next`     | Regras 19 a 22 | -     |

24. Os dois agem sempre sobre a aba ativa, mesmo com a janela escondida (regra 28 da base-ui), e não recebem argumentos; argumentos extras são ignorados, como no `tab-next`.
25. A completion do `:Claudinho` (regra 68 da base-ui) lista os dois entre os subcomandos; não há completion de argumento para eles.
26. Sem abas, os dois respondem `No Claude tabs open` e não criam aba (ao contrário do `select-model`, não há o que escolher antes de a sessão existir). Com a aba ativa encerrada, respondem `Claude <n> has exited; run :Claudinho tab-restart <n>`. As duas respostas sempre aparecem (regra 89 da base-ui).
27. Os dois funcionam com o mouse desligado e com qualquer `laststatus`: não dependem da statusline.
28. O preset opcional de atalhos (regra 69 da base-ui, desligado por padrão) ganha `<leader>ae` para `select-effort` e `<leader>ap` para `mode-next`, no modo normal, ao lado de `<leader>am` (`select-model`). Valem as regras do preset: nada é mapeado com o preset desligado, e uma tecla que o usuário já mapeou não é sobrescrita e fica de fora, com o aviso da regra 69 (informativo, só com `notify` ligado, regra 81 da base-ui). As teclas chamam os subcomandos, então seguem a guarda e as respostas das regras 9 a 13 e 26.

### Modo ao vivo

29. A cada POST de statusline de uma sessão, o plugin lê o modo no rodapé da TUI, na tela do terminal dessa sessão, e atualiza o modo da aba dela. Vale para abas em segundo plano e com a janela escondida.
30. Linha de modo é uma linha do rodapé (abaixo do campo de prompt, ou nas últimas linhas da tela quando o campo não é reconhecido) com este formato: o símbolo de modo do Claude (`⏵⏵`, `⏸` ou outro que a spec achar nas telas reais), um rótulo e ` on`, seguido ou não da dica entre parênteses (ex.: `(shift+tab to cycle)`). O rótulo é o texto entre o símbolo e o ` on`, sem espaços nas pontas, numa linha só e curto (limite na spec). Os rótulos conhecidos da regra 31 também contam sem o símbolo (ex.: `auto mode on`, como medido). Qualquer outra linha não é linha de modo.
31. Leitura do rodapé:

| Na tela                                                                                                                                                  | Modo guardado                   | Mostrado (regra 50 da base-ui)                                                        |
| -------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------- | ------------------------------------------------------------------------------------- |
| Campo de prompt reconhecido, sem linha de modo                                                                                                           | `default`                       | `manual`                                                                              |
| Linha de modo `accept edits on`                                                                                                                          | `acceptEdits`                   | `accept edits`                                                                        |
| Linha de modo `plan mode on`                                                                                                                             | `plan`                          | `plan`                                                                                |
| Linha de modo `auto mode on`                                                                                                                             | `auto`                          | `auto`                                                                                |
| Linha de modo `bypass permissions on` (se a spec confirmar o texto)                                                                                      | `bypassPermissions`             | `bypass permissions`                                                                  |
| Linha de modo com rótulo desconhecido (ex.: `⏵⏵ foo mode on`)                                                                                            | o rótulo como veio (`foo mode`) | o rótulo como veio (`foo mode`), como um `permission_mode` desconhecido vindo de hook |
| Nenhuma linha de modo e o campo de prompt não reconhecido (diálogo aberto, Claude trabalhando com outro rodapé, tela de início, layout do rodapé mudado) | o último conhecido, sem mudança | o último conhecido                                                                    |

32. O status nunca mostra texto do rodapé que não seja o rótulo de uma linha de modo (regra 30): avisos e dicas do rodapé (ex.: `install gh for PR status`) nunca viram modo.
33. `manual` só é concluído quando o campo de prompt é reconhecido e não há linha de modo: a falta da linha de modo numa tela não reconhecida nunca vira `manual`.
34. Os hooks continuam trazendo o `permission_mode` quando disparam. Hook e leitura da tela são duas fontes do mesmo dado: vale o que chegou por último.
35. Antes de qualquer leitura que defina o modo (regra 31) e de qualquer hook com o campo, o modo fica fora do status, como hoje (regra 51 da base-ui).
36. A leitura usa só a tela do terminal da sessão. O plugin guarda só o modo lido: nunca grava, registra em log nem envia o conteúdo da tela. O mesmo vale para a leitura da guarda (regras 9 e 10).
37. A leitura nunca gera erro nem atrasa a sessão ou o Neovim de forma perceptível; uma falha na leitura mantém o último modo conhecido (e, na guarda, conta como tela não reconhecida, regra 11).
38. A leitura só atualiza a aba da sessão que mandou o POST (regra 37 da base-ui).

## Edge cases

| Situação                                                                                                           | Comportamento esperado                                                                                                                                                                                                                                                      |
| ------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `select-effort` ou `mode-next` sem nenhuma aba                                                                     | `No Claude tabs open`; nenhuma aba é criada (regra 26)                                                                                                                                                                                                                      |
| Aba ativa encerrada (`[exited]`), por clique ou subcomando                                                         | Mantém o último status e as regiões (regra 52 da base-ui). Modelo, esforço e modo: `Claude <n> has exited; run :Claudinho tab-restart <n>`; nada é enviado e a escolha de modelo não abre                                                                                   |
| Aba iniciando, sem nenhum dado                                                                                     | Statusline vazia, nada clicável (regra 5); os subcomandos passam pela guarda                                                                                                                                                                                                |
| Aba iniciando, a TUI ainda sem campo de prompt (ou a pergunta de confiança da pasta aberta)                        | Esforço, modo e `select-model` respondem pela regra 11 e não enviam nada; a escolha de modelo não abre                                                                                                                                                                      |
| Várias abas                                                                                                        | A statusline mostra a aba ativa e clique e subcomandos agem nela (regras 4 e 24); as abas em segundo plano seguem atualizando o próprio modo (regra 29) e mostram o valor certo ao serem ativadas                                                                           |
| Troca de aba entre abrir a escolha de modelo e escolher                                                            | O `/model` vai para a aba ativa no momento da escolha, se a guarda dela permitir (regra 15)                                                                                                                                                                                 |
| Usuário digita no prompt depois de abrir a escolha de modelo e antes de escolher                                   | A segunda checagem (regra 15) acha texto: `Claude <n>: clear the prompt first`, nada é enviado, o texto fica intacto                                                                                                                                                        |
| `select-model` com texto no prompt                                                                                 | A escolha não abre; `Claude <n>: clear the prompt first`                                                                                                                                                                                                                    |
| `select-model` sem abas                                                                                            | Como hoje: cria a aba 1 com `--model <valor>`                                                                                                                                                                                                                               |
| Mouse desligado (`mouse=`)                                                                                         | Cliques não fazem nada; `select-model`, `select-effort`, `mode-next` e a própria TUI continuam disponíveis; o modo ao vivo funciona igual                                                                                                                                   |
| Preset ligado e `<leader>ae` ou `<leader>ap` já mapeada pelo usuário                                               | A tecla dele não muda; a do preset fica de fora, com o aviso da regra 69 da base-ui (só com `notify` ligado); o subcomando continua disponível (regra 28)                                                                                                                   |
| `laststatus=0`                                                                                                     | Sem statusline, nada a clicar; os subcomandos funcionam; o modo ao vivo continua atualizando o estado da aba                                                                                                                                                                |
| `laststatus=3` com o foco fora da janela do Claude                                                                 | A statusline global é a da janela em foco, sem o status do Claude: nada a clicar. Com o foco no Claude, regra 7                                                                                                                                                             |
| `laststatus=1` com a janela do Claude sozinha na aba do Neovim (layout `tab`)                                      | Sem statusline, como `laststatus=0`                                                                                                                                                                                                                                         |
| Janela do Claude escondida                                                                                         | Nada a clicar. `select-effort` envia, mostra a janela e foca o terminal (regra 18). `mode-next` envia sem mostrar a janela (regra 22). O modo ao vivo continua por aba                                                                                                      |
| Clique no modo ou `mode-next` com um pedido de permissão ou a aprovação de plano aberta                            | Nada é enviado (regra 9): o Shift+Tab ali aprovaria a ação pela sessão ou o plano. `Claude <n>: finish the open prompt in Claude first`                                                                                                                                     |
| Esforço ou modelo com o seletor de `/effort` ou `/model` já aberto na TUI                                          | Nada é enviado (regra 9); resposta da regra 11                                                                                                                                                                                                                              |
| Esforço com texto no prompt                                                                                        | Nada é enviado (regra 10); o texto fica intacto                                                                                                                                                                                                                             |
| Modo com texto no prompt                                                                                           | Shift+Tab enviado; o texto fica intacto (regra 21)                                                                                                                                                                                                                          |
| Escolha de modelo do Neovim já aberta                                                                              | Um novo clique ou `select-model` não abre outra (regra 16)                                                                                                                                                                                                                  |
| Cliques ou `mode-next` rápidos seguidos                                                                            | Cada um é avaliado pela guarda no momento; o status mostra o que a leitura achou por último                                                                                                                                                                                 |
| `select-effort foo` ou `mode-next foo`                                                                             | O argumento é ignorado (regra 24)                                                                                                                                                                                                                                           |
| Canal do terminal fechado no momento do envio                                                                      | A resposta de hoje do envio ao terminal (`Cannot send text: ...`)                                                                                                                                                                                                           |
| Usuário troca o modo com Shift+Tab direto na TUI                                                                   | A statusline do Claude roda de novo, o POST chega e o modo muda (regra 29); é o caso principal do modo ao vivo                                                                                                                                                              |
| O Claude muda o modo sozinho (ex.: sai do `plan` ao aprovar o plano)                                               | Igual: o próximo POST de statusline traz a leitura nova                                                                                                                                                                                                                     |
| Linha de modo com rótulo desconhecido (modo novo ou renomeado numa versão do Claude, ex.: `⏵⏵ foo mode on`)        | O status mostra o rótulo como veio (`foo mode`), como um `permission_mode` desconhecido vindo de hook (regra 31); clique e `mode-next` seguem mandando o Shift+Tab                                                                                                          |
| Rodapé sem linha de modo e campo de prompt não reconhecido (outra versão, layout do rodapé mudado, diálogo aberto) | Mantém o último modo conhecido (regras 31 e 33); nunca mostra `manual` por falta da linha. A guarda também não reconhece a tela: esforço, modo e `/model` respondem pela regra 11 até a spec ser atualizada para a versão nova                                              |
| Rodapé com avisos ou dicas (ex.: `install gh for PR status`)                                                       | Nunca viram modo (regra 32); a leitura considera só a linha de modo                                                                                                                                                                                                         |
| Linha de modo traduzida ou com símbolo novo que a spec não conhece                                                 | Sem o símbolo conhecido e sem rótulo conhecido, não é linha de modo (regra 30): vale o caso "rodapé sem linha de modo" acima                                                                                                                                                |
| O POST chega antes de a TUI redesenhar o rodapé                                                                    | A spec mede; se acontecer, o plugin lê de novo logo depois, para cumprir o critério de 1 s                                                                                                                                                                                  |
| Esforço escolhido no seletor do Claude                                                                             | O esforço mostrado muda no próximo POST de statusline (regra 49 da base-ui); a spec registra se a escolha dispara uma execução da statusline                                                                                                                                |
| Modo desconhecido vindo de hook (outro valor)                                                                      | Mostrado como veio (regra 50 da base-ui), como o rótulo desconhecido do rodapé; se hook e rodapé trazem o mesmo modo novo com textos diferentes (ex.: `fooMode` e `foo mode`), vale o que chegou por último (regra 34). Clique e `mode-next` mandam o Shift+Tab normalmente |
| `disableAllHooks` (sem statusline do plugin)                                                                       | Sem POST de statusline: status vazio como hoje, nada clicável; os subcomandos funcionam, porque a guarda lê a tela, não a statusline                                                                                                                                        |
| `allowManagedHooksOnly`                                                                                            | Se a statusline do plugin roda, o modo passa a vir da tela; se não roda, o status fica como hoje; os subcomandos funcionam                                                                                                                                                  |
| Sessão externa conectada pelo `/ide` à aba N                                                                       | Não tem terminal no Neovim: a leitura, os cliques e os subcomandos valem só para o processo da própria aba                                                                                                                                                                  |

## Approach

### A janela

```text
 1 Fix login bug │ 2 Claude 2 │ +                                     <- winbar (sem mudança)
 ┌──────────────────────────────────────────────────────────────┐
 │ TUI do Claude da aba ativa                                   │
 │ > _                                                          │   <- campo de prompt (guarda, regras 9 e 10)
 │ ⏵⏵ accept edits on (shift+tab to cycle)                      │   <- rodapé lido a cada POST (regra 29)
 └──────────────────────────────────────────────────────────────┘
 [Opus 5.5] · [high] · [accept edits]                                 <- statusline: 3 regiões clicáveis
     |           |            '-- Shift+Tab na TUI = mode-next (regra 19)
     |           '-- /effort na TUI + foco no terminal = select-effort (regras 17 e 18)
     '-- escolha de modelo do Neovim = select-model (regras 14 e 15)
```

Os colchetes só marcam as regiões no esboço; o texto mostrado não muda (regra 6).

### Estados

| Estado                                                                                   | O que o usuário vê                                                               | Clique ou subcomando                                                                                             |
| ---------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| Carregando (aba iniciando)                                                               | Status vazio ou parcial; modo fora até a primeira leitura reconhecida            | Cliques só nos itens presentes; esforço, modo e `/model` respondem pela regra 11 enquanto não há campo de prompt |
| Vazio (sem dado)                                                                         | Statusline vazia                                                                 | Nada a clicar; subcomandos passam pela guarda                                                                    |
| Sem abas                                                                                 | Nenhuma janela                                                                   | `select-effort` e `mode-next`: `No Claude tabs open`; `select-model`: cria a aba 1                               |
| Sucesso                                                                                  | `Opus 5.5 · high · manual`; o modo muda em até 1 s depois de cada troca          | Modelo abre a escolha; esforço abre o seletor do Claude e foca o terminal; modo passa ao próximo                 |
| Não pronto (diálogo aberto, texto no prompt para esforço e modelo, tela não reconhecida) | O status de antes                                                                | Nada é enviado; resposta da regra 11                                                                             |
| Erro (canal do terminal fechado)                                                         | O status de antes                                                                | Resposta de hoje do envio ao terminal (`Cannot send text: ...`)                                                  |
| Aba encerrada                                                                            | Último status mantido                                                            | `Claude <n> has exited; run :Claudinho tab-restart <n>`                                                          |
| Permissão negada (hooks ou statusline bloqueados por política)                           | Como hoje: status parcial ou vazio; com a statusline rodando, o modo vem da tela | Cliques só nos itens presentes; subcomandos normais                                                              |
| Offline                                                                                  | Sem efeito: a statusline, o rodapé e a guarda são locais                         | Normal; a TUI mostra os próprios erros                                                                           |
| Mouse desligado                                                                          | Status normal, com modo ao vivo                                                  | Cliques não fazem nada; subcomandos normais                                                                      |

### Fluxos

| Fluxo                      | Passos                                                                                                                                                                                                                                     |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Trocar o modo pela TUI     | Shift+Tab na TUI -> o Claude roda a statusline -> POST no servidor da aba -> o plugin lê o rodapé -> o modo da aba muda -> a statusline redesenha                                                                                          |
| Trocar o modo pelo plugin  | Clique no modo ou `:Claudinho mode-next` -> guarda: campo de prompt sem diálogo -> Shift+Tab enviado -> mesmo caminho acima                                                                                                                |
| Trocar o esforço           | Clique no esforço ou `:Claudinho select-effort` -> guarda: campo de prompt vazio e sem diálogo -> `/effort` + Enter -> a janela aparece e o terminal da aba ganha o foco -> o usuário escolhe no seletor -> o esforço muda no próximo POST |
| Trocar o modelo            | Clique no modelo ou `:Claudinho select-model` -> guarda -> escolha do Neovim -> guarda de novo na aba ativa -> `/model <valor>`                                                                                                            |
| Trocar o modelo sem abas   | `:Claudinho select-model` -> escolha -> aba 1 criada com `--model <valor>`                                                                                                                                                                 |
| Pedido que não pode enviar | Clique ou subcomando -> diálogo aberto, texto no prompt (esforço e modelo) ou tela não reconhecida -> nada enviado -> resposta curta da regra 11                                                                                           |
| Início da sessão           | Aba nova -> primeiro POST de statusline -> leitura reconhece o campo de prompt -> o modo aparece antes do primeiro prompt                                                                                                                  |

### O que as fontes fazem (nível de produto)

- O servidor da aba não muda: continua recebendo os POSTs de statusline e de hook só com o token da aba.
- O POST de statusline passa a disparar também a leitura do rodapé da sessão; o JSON continua sendo a fonte de modelo, esforço e `session_id`.
- A guarda lê a tela do terminal da aba ativa no momento do pedido; não depende de POST nem de hook.
- O plugin guarda por aba o mesmo de hoje (último `session_id`, modelo, esforço e modo); nenhum dado novo vai para disco.

### Documentação

- README (pt e en): a linha **Modo** da tabela da statusline passa a dizer que o modo vem do rodapé da TUI a cada atualização da statusline e dos hooks; uma frase sobre os cliques nos três itens; `select-effort` e `mode-next` na tabela de comandos, e `<leader>ae` e `<leader>ap` na tabela do preset; a guarda (o que o plugin espera ver na TUI antes de enviar) e as duas respostas; o `select-model` que agora também passa pela guarda.
- **Limitações**: sai "O modo só aparece depois do primeiro prompt da sessão, e muda no prompt ou no fim de turno seguinte"; entra que o modo é lido da linha de modo do rodapé do Claude; um modo que o plugin não conhece aparece com o rótulo do Claude; se uma versão nova mudar o formato do rodapé, o status mantém o último modo conhecido até o próximo hook, e esforço, modo e `/model` passam a responder "não pronto" até o plugin ser atualizado.

## Risks & mitigations

| Risco                                                                                                                                      | Impacto                                                                                                              | Mitigação                                                                                                                                                                                                                  |
| ------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| O formato do rodapé ou do campo de prompt muda numa versão nova do Claude (risco aceito pelo usuário)                                      | O modo volta a atualizar só pelos hooks; esforço, modo e `/model` respondem "não pronto" até o plugin ser atualizado | Regras 31 a 33 (sem linha de modo, mantém o último; nunca conclui `manual` às cegas) e regra 11 (nunca envia às cegas); fixtures de telas reais por versão nos testes; o log registra a versão medida; limitação no README |
| Um modo é renomeado ou um modo novo aparece                                                                                                | O status mostra o rótulo do Claude (ex.: `foo mode`) em vez do texto curto do plugin                                 | Decisão do usuário: o rótulo como veio facilita identificar a mudança; a tabela da regra 31 ganha o modo novo numa versão seguinte                                                                                         |
| Uma linha do rodapé que não é de modo tem o formato da linha de modo (símbolo, texto, ` on`)                                               | Texto estranho no lugar do modo                                                                                      | Regra 30 exige o símbolo de modo, o ` on` no fim e um rótulo curto; fixtures com rodapés reais (dicas, avisos como `install gh for PR status`) nos testes provam que não casam                                             |
| Com a statusline do plugin configurada, a TUI esconde dicas do rodapé (risco aceito na base-ui) e talvez a linha de modo                   | A leitura não acharia o modo                                                                                         | A spec confirma, com os settings reais da sessão, que a linha de modo aparece; se não aparecer, volta ao usuário antes de implementar                                                                                      |
| Shift+Tab, `/effort` ou `/model` chegam num diálogo e respondem por ele (aprovar permissão pela sessão, aprovar plano)                     | Ação perigosa que o usuário não pediu                                                                                | Regra 9: só envia com o campo de prompt reconhecido e nenhum diálogo; tela não reconhecida conta como "não pronto"                                                                                                         |
| Reconhecer "prompt vazio" é difícil: o Claude mostra uma sugestão em cinza no prompt vazio, e o texto do buffer do terminal não traz a cor | Esforço e modelo nunca enviam, ou enviam por cima de texto                                                           | A spec define o reconhecimento com telas reais (inclusive a sugestão em cinza); na dúvida, conta como "não vazio" (regra 10)                                                                                               |
| A guarda nova no `select-model` recusa um envio que hoje passa                                                                             | Quem usa `select-model` com texto no prompt passa a ver uma resposta em vez de um `/model` misturado ao texto        | É o comportamento pedido; README e `CHANGELOG.md` registram a mudança; adendo na base-ui                                                                                                                                   |
| O POST chega antes de a TUI redesenhar o rodapé                                                                                            | O status fica um passo atrás                                                                                         | A spec mede; se acontecer, uma releitura curta depois do POST; critério de 20 em 20 em até 1 s                                                                                                                             |
| A leitura roda a cada execução da statusline, que é frequente                                                                              | Custo no Neovim                                                                                                      | Ler só as últimas linhas da tela; regra 37; a spec mede o custo                                                                                                                                                            |
| Corrida: a tela muda entre a checagem da guarda e o envio                                                                                  | Tecla num diálogo que acabou de abrir                                                                                | Regra 12: checagem e envio no mesmo passo; a janela de risco fica no tempo de um redraw. Risco residual registrado                                                                                                         |
| Clicar na statusline em modo terminal ou com `laststatus=3` se comporta diferente do winbar                                                | Cliques que não funcionam em algum modo                                                                              | Teste de integração com `laststatus` 2 e 3, foco no editor e no terminal                                                                                                                                                   |

## Open questions

Nenhuma em aberto. As quatro perguntas foram decididas pelo usuário em 2026-11-18 e 2026-11-19 e estão nas regras: clique que não pode enviar (regra 11), guarda no `select-model` (regra 15), subcomandos novos (regras 23 a 27) e teclas do preset (regra 28).
