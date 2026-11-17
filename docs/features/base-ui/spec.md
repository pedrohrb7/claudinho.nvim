# UI base: janela do Claude com abas de sessão - spec técnica

- **Date:** 2026-11-15
- **Status:** In progress
- **Plan:** [plan.md](plan.md)
- **Decisões de 2026-11-15:** as cinco Open questions da primeira versão desta spec foram decididas pelo usuário, todas com a recomendação, e registradas no [adendo (2) do plano](plan.md#addendum-2026-11-15-2-revisão-da-spec) (errata da regra 89 e regras 90 a 97); ver [Open questions](#open-questions).
- **Implementation log:** [log.md](log.md)

## Summary

Troca o modelo de uma sessão global (um servidor, um lock file, um terminal escolhido entre os providers `native`, `external` e `none`) por "uma sessão = uma aba". Cada aba tem processo do Claude, servidor WebSocket, porta, token, lock file e arquivo de settings próprios. O plugin desenha em volta da TUI do Claude só a winbar (abas) e a statusline (status) de uma janela única, e toda a API vira `:Claudinho <subcomando>`. Tudo é Lua puro dentro do Neovim, mais um script de repasse (`nvim --clean -l`) que a statusline e os hooks do Claude executam.

| Camada                    | O que muda                                                                                                                                                                   |
| ------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Servidor (`server/`)      | Instâncias em vez de estado global; rotas HTTP `POST /claudinho/statusline` e `POST /claudinho/hook` com o token da aba; respostas adiadas e rejeição de diffs por instância |
| Sessão e abas (novos)     | `session.lua` (uma sessão), `sessions.lua` (registro, aba ativa, roteamento, encerramento, saída do Neovim)                                                                  |
| UI (novos)                | `ui/window.lua` (layouts `right`, `bottom`, `float`, `tab`), `ui/tabbar.lua` (winbar clicável), `ui/status.lua` (statusline)                                                 |
| Fontes (novas)            | `sources/relay.lua` (script de repasse), `sources/session_data.lua` (lê o JSON da statusline e dos hooks), `session_settings.lua` (arquivo de `--settings`)                  |
| Comandos                  | `commands.lua` com `:Claudinho`, completion e preset de atalhos; saem os 17 `:ClaudeCode*`                                                                                   |
| Terminal                  | Saem `terminal/native.lua`, `external.lua`, `none.lua`, `owned.lua`; `terminal.lua` vira fachada sobre a aba ativa; `terminal/paste_fix.lua` fica                            |
| Config                    | Chaves novas `window`, `keymaps`, `notify`; chaves removidas com aviso pelo mecanismo da Fase 0; layout inválido cai em `right`                                              |
| Diff, seleção, @-mentions | Diff de aba em segundo plano espera a ativação; seleção e @-mentions só para a aba ativa; fila de @-mentions por aba                                                         |
| claudecode.nvim junto     | A recusa da Fase 0 vira aviso (informativo) e warning no `:checkhealth`                                                                                                      |
| Docs e release            | READMEs, `CLAUDE.md`, `CHANGELOG.md`, `PROTOCOL.md`, `ARCHITECTURE.md`, linha de origem nos módulos; release `0.2.0`                                                         |

## Background

Implementa o [plano aprovado](plan.md): regras 1 a 71, os dois adendos de 2026-11-12 (textos em inglês; Neovim mínimo 0.12), o adendo de 2026-11-15 (regras 72 a 89) e o adendo de 2026-11-15 (2), a revisão desta spec (errata e regras 90 a 97). Cada adendo vale onde diverge do texto anterior. Pela errata do adendo (2), a regra das respostas a comandos do usuário (seção 5 do adendo de 2026-11-15) é a **regra 89**, e as de layout (seção 6) são as 85 a 88.

Parte do estado da Fase 0 ([fork-limpo](../fork-limpo/spec.md), `Implemented`, versão `0.1.0`). Fatos do código em que a spec se apoia (conferidos em `HEAD` = `6c12c61`):

- `server/init.lua` guarda um servidor só em `M.state` (`server`, `port`, `auth_token`, `handlers`, `ping_timer`). `server/tcp.lua` já é por instância: `create_server(config, callbacks, auth_token)` devolve um objeto com `clients`, `port` e callbacks próprios.
- `server/init.lua:147-149` zera **todo** `_G.claude_deferred_responses` no `stop()`, e `:139-142` rejeita **todos** os diffs pendentes (`diff.close_pending_diffs`). Com várias instâncias, parar a aba 2 apagaria as respostas e rejeitaria os diffs da aba 1. As duas coisas passam a ser por instância.
- Os ids de cliente já são únicos no Neovim inteiro (`client.lua:47-48`, contador em `_G.claudinho_clients_created`), então `diff.close_diffs_for_client(client_id)` continua servindo por aba.
- `terminal.lua:325-371` monta o ambiente do processo (`CLAUDE_CODE_SSE_PORT`, `ENABLE_IDE_INTEGRATION`, `FORCE_CODE_TERMINAL`, `no_proxy`) e lê a porta do servidor global (`:342`). `terminal/native.lua` usa `termopen`, `bufhidden=hide`, e espera o `TermClose` antes de apagar o buffer por causa de neovim/neovim#42508 (`:287-322`); a sessão nova mantém essa espera.
- `diff.lua`, `diff_inline.lua`, `selection.lua` e `init.lua` falam com o terminal só por `require("claudinho.terminal")`: `get_active_terminal_bufnr`, `ensure_visible`, `open`, `simple_toggle`, `focus_toggle`, `close`, `send_to_terminal`. Dezenas de specs fazem mock desse módulo. Por isso ele vira uma fachada com as mesmas funções de leitura e foco, e só as de provider saem.
- `diff.lua:50-110` e `:413-414` leem `config.terminal.split_side`, `split_width_percentage` e `diff_split_width_percentage`.
- `selection.lua` difunde por `M.server.broadcast` (`:1201`) e reconhece o terminal do Claude pelo nome `term://...//pid:claude...` ou pelo buffer ativo (`:1209-1226`).
- A fila de @-mentions mora em `init.lua:83-289`, sobre `M.state` (`mention_queue`, `mention_timer`, `connection_timer`) e o servidor global.
- `config.removed_options` e `config.without_removed_options` (`config.lua:47-140`) são o mecanismo da Fase 0 que a regra 77 manda reusar. Hoje a linha de `terminal.provider` só vale para o valor `"snacks"` e troca por `"native"`.
- `conflict.lua` recusa rodar (`check()` com aviso; `detected()` sem aviso), chamado por `plugin/claudinho.lua:10` e `init.setup:459`; `health.lua:33-38` mostra o conflito como erro.
- `lockfile.create(port, token)` grava `ideName = "Neovim"` e `workspaceFolders = getcwd() + pastas do LSP`.
- `tests/bin/claude` é um stub que dorme 30 s e fica primeiro no `PATH` de todo teste (`tests/minimal_init.lua:1-9`).
- Suítes e gates: os nomes da tabela `Test suites` do `CLAUDE.md`. Lições do log da Fase 0: o `unit` leva de 600 a 840 s (timeout de pelo menos 1200 s); um arquivo de integração isolado só roda com o ambiente do runner (`VIMINIT`, `CLAUDINHO_MINIMAL_INIT`, `XDG_STATE_HOME`/`XDG_CONFIG_HOME` temporários); o runner de integração dá 40 s por arquivo.

Decisões do plano que a spec fecha: estrutura de módulos (seção 0), estado por aba (seções 1, 6 e 7), textos em inglês (seção 4), nome da opção de notificações (`notify`), convivência das linhas de `terminal.provider` (seção 4), `:qa` sem "job still running" (seção 7), clique e corte da winbar (seção 3), guarda de conflito só como aviso (seção 11), meio de repasse dos hooks e da statusline (seção 2).

## Design

### 0. Estrutura de módulos

```text
lua/claudinho/
  init.lua               setup, API Lua pública (send_at_mention, ...)        reescrito
  commands.lua           :Claudinho, completion, preset de atalhos            novo (derivado de init.lua do upstream)
  config.lua             defaults, validação, chaves removidas                alterado
  notify.lua             notificação informativa x erro x resposta a comando  novo
  conflict.lua           detecção do claudecode.nvim, só aviso                alterado
  health.lua             :checkhealth claudinho                               alterado
  session.lua            uma sessão: servidor, lock, settings, job            novo (derivado de terminal.lua e terminal/native.lua)
  sessions.lua           abas: registro, ativa, roteamento, encerramento      novo
  mention_queue.lua      fila de @-mentions por aba                           novo (derivado de init.lua)
  session_settings.lua   arquivo de --settings da sessão                      novo
  sources/relay.lua      script de repasse (nvim --clean -l)                  novo
  sources/session_data.lua  JSON da statusline e dos hooks -> dados da aba    novo
  ui/window.lua          a janela do Claude e os layouts                      novo (derivado de terminal/native.lua)
  ui/tabbar.lua          winbar: rótulos, corte, clique                       novo
  ui/status.lua          statusline: modelo, esforço, modo                    novo
  terminal.lua           fachada sobre a aba ativa                            reescrito
  terminal/paste_fix.lua fica                                                  -
  server/init.lua        instâncias                                           alterado
  server/http.lua        rotas POST                                           novo
  server/{client,tcp,handshake}.lua                                            alterados (roteamento HTTP, id da instância)
  lockfile.lua           ideName e pasta por aba                              alterado
  selection.lua          alvo = aba ativa                                     alterado
  diff.lua, tools/open_diff.lua  diff por aba                                 alterados
  terminal/{native,external,none,owned}.lua, cwd.lua                           removidos
```

Decisão sobre a fundação do PRD (`events.lua`, `sources/`, `ui/adapters`):

- `sources/` entra: as duas fontes novas (statusline e hooks) ficam isoladas ali, atrás de `session_data.lua`, que só devolve tabelas simples. Um campo novo ou ausente no JSON muda só esse módulo.
- `events.lua` não entra. Hoje cada evento tem um consumidor só: dado de sessão -> redesenho da janela, diff aberto -> esconder o float (já existe o `User ClaudinhoDiffOpened`). Um barramento sem segundo consumidor é código especulativo. Ele entra com a feature Painel de informações, quando houver vários consumidores. As chamadas diretas ficam concentradas em `sessions.lua` (`sessions.on_change`), o ponto que vira `emit` depois.
- `ui/adapters` não entra: esta feature só tem a implementação nativa, e nenhuma lib externa é suportada.

### Ordem dos passos

A ordem mantém o plugin funcionando e os testes verdes entre tasks: primeiro peças novas ao lado do código atual (sem mudar nada visível), depois a troca da API num passo, e só então a limpeza.

| Passo | Tasks | Regras                     | Por que nesta posição                                                                                  |
| ----- | ----- | -------------------------- | ------------------------------------------------------------------------------------------------------ |
| 0     | 1     | -                          | Números de antes                                                                                       |
| 1     | 2-4   | 1, 3, 7, 55-60             | Servidor por instância, rotas HTTP, lock file por aba, settings e relay; o servidor global segue usado |
| 2     | 5-7   | 9-15, 47-54, 70, 80-83, 88 | Funções puras de status e barra, config nova e `notify`, fila por instância; nada visível muda         |
| 3     | 8-11  | 1-46, 61-63                | Sessão, abas, janela e diff por aba, testados sem comandos                                             |
| 4     | 12    | 64-69, 86                  | A troca: `:Claudinho`, fim dos `:ClaudeCode*` e dos providers                                          |
| 5     | 13-14 | 71, 73-77, 84, 93-95       | Chaves removidas e aviso do claudecode.nvim (regra 76: só junto com a troca dos comandos)              |
| 6     | 15-16 | critérios, 72              | Critérios de sucesso como testes de integração; linhas de origem                                       |
| 7     | 17-20 | 72, 78, 92, 97             | Docs do estado final                                                                                   |
| 8     | 21-22 | 79                         | Gate final, medição, roteiro manual e release `0.2.0`                                                  |

Nenhuma task faz commit; o commit da feature e o release ficam na Task 22, com autorização do usuário.

### 1. Servidor por aba (Tasks 2 e 3)

#### API de instância

```lua
---@class ClaudinhoServer
---@field id integer                 -- único no Neovim (1, 2, ...)
---@field port integer|nil
---@field auth_token string|nil
---@field tcp TCPServer|nil          -- objeto de server/tcp.lua
---@field ping_timer uv.uv_timer_t|nil
---@field deferred table<string, true>  -- chaves que esta instância pôs em _G.claude_deferred_responses
---@field on_open fun(client)|nil        -- cliente terminou o handshake
---@field on_disconnect fun(client)|nil
---@field on_post fun(kind: "statusline"|"hook", body: string)|nil  -- Task 3

M.new(opts) -> ClaudinhoServer            -- opts: on_open, on_disconnect, on_post
server:start(config, auth_token) -> ok, port_or_error
server:stop() -> ok, err
server:broadcast(method, params, on_written) -> boolean
server:send(client, method, params) -> boolean
server:send_response(client, id, result, error_data) -> boolean
server:get_status() -> { running, port, client_count, clients }
server:drain(timeout_ms) -> boolean       -- espera a fila de escrita de todo cliente esvaziar (get_write_queue_size() == 0)
M.for_client(client) -> ClaudinhoServer|nil  -- pela marca client.server_id posta no accept
```

- O `tcp.lua` grava `client.server_id = <id da instância>` ao criar o cliente. Os handlers JSON-RPC (`initialize`, `tools/list`, `tools/call`, ...) passam a ser fechados sobre a instância, e `_setup_deferred_response` usa `self:send_response`. A resposta de um diff sempre sai pela instância do cliente que o pediu (regra 33).
- `stop()` só tira de `_G.claude_deferred_responses` as chaves de `self.deferred` e só rejeita os diffs pendentes dos próprios clientes (`diff.close_diffs_for_client(client.id, "server stopping")` para cada cliente com handshake), no lugar de `close_pending_diffs` global.
- O `on_open` padrão continua chamando `require("claudinho").process_mention_queue(true)` até a Task 7, que o troca pela fila da sessão.
- As funções de módulo (`M.start`, `M.stop`, `M.broadcast`, `M.send`, `M.send_response`, `M.get_status`, `M.state`, `M._handle_message`) continuam, delegando a uma instância padrão criada no primeiro uso. Só os testes de servidor do upstream as usam; depois da Task 12 nenhum código de `lua/` fora de `server/` as chama (comando de critério na Verificação).

#### Rotas HTTP (Task 3)

O `client.lua`, antes do handshake, olha a linha de requisição: começando com `POST `, o cliente entra em modo HTTP e nunca vira cliente WebSocket (fica fora de `broadcast`, `get_status().clients` e `is_claude_connected`). `server/http.lua` faz o parse e responde na hora, ainda no callback do libuv, sem `vim.schedule`, para que o relay termine rápido mesmo com o Neovim ocupado; só a atualização de estado é agendada (`on_post`, que a sessão agenda com `vim.schedule`).

| Rota                         | Request                                                                                                 | Resposta                                                                   | Erros                                                                                                                                                                             | Auth                                                                                                    |
| ---------------------------- | ------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| `POST /claudinho/statusline` | `Content-Type: application/json`, `Content-Length` obrigatório, corpo = JSON que o Claude deu ao script | `204 No Content`, `Connection: close`; chama `on_post("statusline", body)` | `401` token ausente ou errado (nada muda); `400` sem `Content-Length` ou cabeçalhos com mais de 8 KiB; `413` corpo com mais de 1 MiB (fecha sem ler o resto); `404` outro caminho | `X-Claudinho-Token` igual ao token da aba, comparado em tempo constante (`utils.constant_time_compare`) |
| `POST /claudinho/hook`       | Igual, corpo = JSON do hook                                                                             | `204`; `on_post("hook", body)`                                             | Iguais                                                                                                                                                                            | Igual                                                                                                   |

Corpo que não é JSON válido ainda recebe `204` (regra 54): a validação é do `session_data.lua`, que ignora o que não entende. `GET` com upgrade continua no caminho WebSocket de hoje; qualquer outro método ou caminho recebe `404` e o socket fecha.

### 2. Lock file, settings da sessão e relay (Task 4)

#### Lock file por aba

`lockfile.create(port, token, opts)` ganha `opts.ide_name` (padrão `"Neovim"`) e `opts.workspace_folders` (padrão `get_workspace_folders()`); `get_workspace_folders(cwd)` aceita a pasta da aba no lugar de `getcwd()`. O resto do arquivo (gravação atômica, `0600`, pasta `0700`, `CLAUDE_CONFIG_DIR`) não muda.

| Campo              | Valor                                                               |
| ------------------ | ------------------------------------------------------------------- |
| `pid`              | PID do Neovim (`vim.fn.getpid()`), igual em todas as abas           |
| `workspaceFolders` | pasta da aba (cwd na criação), seguida das pastas do LSP, como hoje |
| `ideName`          | `Neovim (Claudinho <n>)` (regra 7)                                  |
| `transport`        | `ws`                                                                |
| `authToken`        | token da aba (32 hex, CSPRNG)                                       |

Como o `/ide` mostra isso está em [Fatos conferidos](#fatos-conferidos-no-cli-e-no-neovim) (F5): o rótulo é o `ideName`, e com dois nomes iguais (dois Neovims, cada um com uma aba 1) o CLI já mostra as pastas de cada um ao lado. Nada é acrescentado ao nome (regra 96). Com os dois Neovims na mesma pasta, as duas linhas ficam iguais no `/ide` de um claude externo, o que é aceito e documentado nos READMEs (regra 97); no `/ide` de uma aba só aparecem as abas do mesmo Neovim (F5).

#### Conexão automática do CLI (regras 90 a 92)

Com a conexão automática do CLI ligada pelo próprio usuário (`autoConnectIde` em `~/.claude.json`, `claude --ide` ou `CLAUDE_CODE_AUTO_CONNECT_IDE=1`), um claude aberto fora do Neovim se conecta sozinho a uma aba quando a pasta dela é a única, entre os lock files de `~/.claude/ide/`, que contém a cwd dele (F6). O CLI não lê nenhum campo do lock file que evite isso e mantenha a aba selecionável no `/ide`, então o plugin aceita o comportamento e não tenta impedi-lo (regra 90). Nada muda no código:

- Com o padrão do CLI (conexão automática desligada), vale a regra 62 inteira: nenhuma sessão externa se conecta sozinha.
- A parte de ambiente da regra 62 não muda: as variáveis da tabela abaixo existem só no processo de cada aba.
- Uma sessão externa conectada sozinha é cliente do servidor da aba como qualquer outra; `sessions.for_client` a trata como da aba, então ela recebe a seleção quando a aba está ativa, os diffs dela seguem as regras da aba, e o `tab-close` a desconecta sem encerrá-la (regras 63 e 91).
- Os dois READMEs explicam o caso e como evitar: `CLAUDE_CODE_AUTO_CONNECT_IDE=0` numa sessão, ou `autoConnectIde` desligado (regra 92).

#### Ambiente do processo da aba

Só no `env` do `jobstart` da aba; nunca em `vim.env` (regra 62).

| Variável                 | Valor                     | Para quê                                                              |
| ------------------------ | ------------------------- | --------------------------------------------------------------------- |
| `CLAUDE_CODE_SSE_PORT`   | porta da aba              | o CLI acha o lock file da própria aba e se conecta sozinho a ele (F6) |
| `ENABLE_IDE_INTEGRATION` | `true`                    | como hoje                                                             |
| `FORCE_CODE_TERMINAL`    | `true`                    | como hoje; faz o `/ide` da aba listar só lock files deste Neovim (F5) |
| `CLAUDINHO_PORT`         | porta da aba              | relay (regra 59)                                                      |
| `CLAUDINHO_TOKEN`        | token da aba              | relay (regra 59)                                                      |
| `no_proxy`, `NO_PROXY`   | mescla de hoje + loopback | como hoje (issue #70 do upstream)                                     |
| chaves de `config.env`   | do usuário                | como hoje                                                             |

#### Arquivo de settings da sessão

`session_settings.write(session)` grava, com `vim.uv.fs_open(path, "wx", 384)` (`0600`), em `vim.fn.tempname() .. ".claudinho-<n>.json"` (a pasta temporária do próprio Neovim, `0700`, que o Neovim apaga ao sair). Nunca em `~/.claude/` nem em `.claude/` do projeto (regra 57). O arquivo é apagado quando a aba fecha, quando o processo termina e no `kill-all`/saída; `tab-restart` grava outro.

```json
{
  "statusLine": {
    "type": "command",
    "command": "'<progpath>' --clean -l '<relay>' statusline"
  },
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "'<progpath>' --clean -l '<relay>' hook",
            "async": true
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "'<progpath>' --clean -l '<relay>' hook",
            "async": true
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "'<progpath>' --clean -l '<relay>' hook",
            "async": true
          }
        ]
      }
    ]
  }
}
```

- `<progpath>` é `vim.v.progpath` (o binário do próprio Neovim) e `<relay>` o caminho absoluto de `lua/claudinho/sources/relay.lua`, os dois com `vim.fn.shellescape`. Forma de shell, não `args`: funciona em qualquer versão do CLI.
- Eventos escolhidos (F3): `SessionStart` traz o `session_id` logo no início e de novo depois de `/clear`, `/compact` e `--resume` (campo `source`); `UserPromptSubmit` e `Stop` trazem `session_id` e `permission_mode` a cada prompt e a cada fim de turno. Os eventos de ferramenta trariam o modo mais cedo durante um turno, mas abririam um processo por chamada de ferramenta; ficam fora.
- `async: true`: o hook roda em segundo plano, sem prazo, não atrasa a sessão, e sem saída não manda nada ao Claude (regra 58). `async` só existe para hooks `command`, e `SessionStart` só aceita `command` e `mcp_tool` (F3), por isso não se usa hook `http`.
- Só `statusLine` e `hooks`. Pela precedência do CLI, `--settings` fica acima dos arquivos do usuário e do projeto: a `statusLine` do usuário é sobreposta naquela sessão, os hooks se somam aos dele, e toda outra chave dele continua valendo (regra 56, F1).

#### Relay (`lua/claudinho/sources/relay.lua`)

Módulo com `M.main(kind)` e as funções puras (`M.build_request(kind, body, token)`); executado por `nvim --clean -l <relay> <kind>`. Rodado assim, `...` é `nil` e o argumento está em `_G.arg[1]` (conferido no 0.12.3), então o fim do arquivo é `if select("#", ...) == 0 and _G.arg then os.exit(M.main(_G.arg[1])) end`; com `require` ele só devolve o módulo.

1. `kind` diferente de `statusline` ou `hook`: sai com 0.
2. Lê todo o stdin.
3. `statusline`: escreve `"\n"` no stdout antes de qualquer rede (regra 53: a TUI mostra uma linha vazia, mesmo que o repasse falhe).
4. Sem `CLAUDINHO_PORT` válido (1-65535): sai com 0.
5. Conecta em `127.0.0.1:<porta>` com `vim.uv`, envia `POST /claudinho/<kind>` com `Content-Length` e `X-Claudinho-Token`, e espera a resposta ou o fechamento por no máximo 500 ms (`vim.wait`).
6. Sempre `os.exit(0)`, com tudo dentro de `pcall`; `hook` nunca escreve no stdout nem no stderr (regra 58).

Custo medido (protótipo idêntico, Neovim 0.12.3, esta máquina, 10 execuções contra um servidor local): 9,7 a 12,1 ms por chamada, com o corpo recebido 10/10; porta morta: saída 0 em 10,9 ms e stdout vazio. Zero dependências: só o Neovim que já está rodando (regra 60).

### 3. Dados da sessão, status e barra de abas (Task 5)

Funções puras, sem estado de sessão; a Task 10 as liga à janela.

#### `sources/session_data.lua`

| Função               | Entrada                  | Saída                                                                                                         |
| -------------------- | ------------------------ | ------------------------------------------------------------------------------------------------------------- |
| `decode(body)`       | string                   | tabela, ou `nil` para JSON inválido ou não objeto (sem erro)                                                  |
| `from_statusline(t)` | JSON da statusline       | `{ session_id?, model?, effort? }`: `model = model_label(t.model)`, `effort = t.effort.level` quando é string |
| `from_hook(t)`       | JSON de hook             | `{ session_id?, mode? }`: `mode = t.permission_mode` quando é string                                          |
| `model_label(m)`     | `{ id?, display_name? }` | regra 48 (abaixo)                                                                                             |

`model_label`: `display_name` com algum dígito vale como está. Senão, a versão vem do `id`: tira prefixo até `claude-` (cobre `us.anthropic.`), sufixos `@...`, `-v1:0`, `[1m]` e data `-AAAAMMDD`; aceita `claude-<família>-<maior>[-<menor>]` (`claude-opus-5-5` -> `Opus 5.5`, `claude-haiku-4-5-20251001` -> `Haiku 4.5`, `claude-opus-5` -> `Opus 5`) e o formato antigo `claude-<maior>-<menor>-<família>` (`claude-3-5-haiku-20241022` -> `Haiku 3.5`). A família vem do `display_name` quando ele existe (`Opus` + `5.5`), senão do `id` com inicial maiúscula. `id` que não casa: `display_name` como veio; sem nenhum dos dois: `nil`. Campos de tipo errado contam como ausentes (regra 54).

#### `ui/status.lua`

`status.text(data)` junta, nesta ordem e separados por `·`, modelo, esforço e modo, pulando os ausentes, sem separador sobrando; sem nada, `""` (regras 47 e 51). `%` vira `%%` para a statusline.

| `permission_mode`   | Mostrado             |
| ------------------- | -------------------- |
| `default`           | `manual`             |
| `manual`            | `manual`             |
| `plan`              | `plan`               |
| `auto`              | `auto`               |
| `acceptEdits`       | `accept edits`       |
| `dontAsk`           | `don't ask`          |
| `bypassPermissions` | `bypass permissions` |
| outro               | o valor como veio    |

A linha `manual` é defensiva: o CLI 2.1.325 aceita `--permission-mode manual`, mas os hooks mandam o modo Manual como `default` (F9).

#### `ui/tabbar.lua`

- `clean_title(raw, ctx)` (regras 10 e 11): tira espaços nas pontas; se o primeiro token separado por espaço não tem nenhuma letra nem dígito ASCII (`✳`, `✻`, `·`, spinners braille U+2800-U+28FF), ele sai. O resultado é genérico, e a função devolve `nil`, quando está vazio, começa com `term://`, ou é igual (sem diferenciar maiúsculas) a `claude code`, `claude`, ao comando configurado ou ao nome do executável dele.
- `label(tab, max)`: `<n> <título>` + marcas; título `nil` vira `Claude <n>`; título maior que `max` vira os primeiros `max - 1` caracteres de largura + `…` (regra 12). Marcas: ` ● diff` com diff esperando ativação, ` [exited]` com processo encerrado (regra 14).
- `layout(tabs, active, width, max)`: as abas em ordem crescente (regra 6), cada célula `<rótulo>`, separadas por `│`, e `+` no fim (regra 15). Se não cabe, o limite do título cai de 1 em 1 para todas as abas até 0 (só número e marcas). Se ainda não cabe, mostra a aba ativa e o `+`, e acrescenta vizinhas alternando direita e esquerda enquanto couber, com `‹` ou `›` indicando o que ficou de fora. Número e marcas nunca são cortados; a ativa e o `+` nunca somem (caso de borda).
- `render(win)`: monta a string da winbar com cliques `%<n>@v:lua.ClaudinhoTabClick@ ... %X` por aba e `%0@v:lua.ClaudinhoTabClick@ + %X` no `+`. Grupos de destaque, `default = true`: `ClaudinhoTabActive` -> `TabLineSel`, `ClaudinhoTab` -> `TabLine`, `ClaudinhoTabMark` -> `WarningMsg`, `ClaudinhoTabExited` -> `Comment`, `ClaudinhoTabNew` -> `TabLine`, `ClaudinhoTabFill` -> `TabLineFill`.
- `_G.ClaudinhoTabClick(minwid, clicks, button, mods)`: só botão `l`; `minwid == 0` -> `sessions.new()`, senão `sessions.activate(minwid)`. Com `mouse=` o Neovim não manda cliques e nada acontece (caso de borda).

### 4. Config e notificações (Tasks 6 e 13)

#### Chaves novas (Task 6)

| Chave                     | Padrão    | Validação                                                                                                              |
| ------------------------- | --------- | ---------------------------------------------------------------------------------------------------------------------- |
| `window.layout`           | `"right"` | `right`, `bottom`, `float` ou `tab`; outro valor -> `"right"` com erro (regra 88)                                      |
| `window.right.width`      | `0.30`    | número em (0, 1); senão, padrão com erro                                                                               |
| `window.right.diff_width` | `nil`     | `nil` ou número em (0, 1): largura da janela enquanto um diff está aberto (era `terminal.diff_split_width_percentage`) |
| `window.bottom.height`    | `0.30`    | número em (0, 1)                                                                                                       |
| `window.float.width`      | `0.80`    | número em (0, 1)                                                                                                       |
| `window.float.height`     | `0.80`    | número em (0, 1)                                                                                                       |
| `window.tab_title_max`    | `24`      | inteiro >= 1                                                                                                           |
| `keymaps.preset`          | `false`   | booleano (regra 69)                                                                                                    |
| `notify`                  | `false`   | booleano (regra 80)                                                                                                    |

Ficam como hoje: `terminal_cmd`, `env`, `models`, `log_level`, `track_selection`, `focus_after_send`, `visual_demotion_delay_ms`, `connection_wait_delay`, `connection_timeout`, `port_range`, `diff_opts`, `terminal.auto_insert`, `terminal.fix_streamed_paste`. As chaves novas com valor inválido não levantam erro no `setup` (diferente das antigas, que seguem com `assert`): o valor cai no padrão e sai uma mensagem de erro que nomeia a chave, o valor e os válidos. A borda do float usa `'winborder'` quando ele não está vazio, senão `"rounded"`; não há chave para isso.

#### Chaves removidas (Task 13, regras 71, 77 e 93 a 95)

Mesmo mecanismo da Fase 0. A linha atual `terminal.provider` com `value = "snacks"` sai e dá lugar a uma linha `terminal.provider` sem `value` (qualquer valor conta): quem tinha `"snacks"` recebe um aviso só, o novo. As linhas da Fase 0 ficam.

| Chave removida                                                                                          | Mensagem (`[Claudinho] ` + texto)                                                                                            |
| ------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| `terminal.provider`                                                                                     | `terminal.provider was removed and is ignored. Claude always runs in Neovim's terminal, in the window set by window.layout.` |
| `terminal.provider_opts`                                                                                | `terminal.provider_opts was removed and is ignored. External terminals are no longer supported.`                             |
| `terminal.external_terminal_cmd`                                                                        | `terminal.external_terminal_cmd was removed and is ignored. External terminals are no longer supported.`                     |
| `terminal.split_side`                                                                                   | `terminal.split_side was removed and is ignored. Use window.layout instead.`                                                 |
| `terminal.split_width_percentage`                                                                       | `terminal.split_width_percentage was removed and is ignored. Use window.right.width instead.`                                |
| `terminal.diff_split_width_percentage`                                                                  | `terminal.diff_split_width_percentage was removed and is ignored. Use window.right.diff_width instead.`                      |
| `terminal.auto_close`                                                                                   | `terminal.auto_close was removed and is ignored. Tabs never close by themselves; use :Claudinho tab-close.`                  |
| `terminal.show_native_term_exit_tip`                                                                    | `terminal.show_native_term_exit_tip was removed and is ignored.`                                                             |
| `auto_start` e `terminal.auto_start`                                                                    | `<chave> was removed and is ignored. Nothing starts with setup(); each tab starts its own server.`                           |
| `terminal.cwd`, `terminal.git_repo_cwd`, `terminal.cwd_provider`, `cwd`, `git_repo_cwd`, `cwd_provider` | `<chave> was removed and is ignored. New tabs start in Neovim's current directory (:pwd).` (regras 93 e 94)                  |

`without_removed_options(user_config, { notify = <bool> })` passa a avisar só com `notify = true` (lido cru de `user_config.notify == true`, antes do `config.apply`) e devolve também a lista das linhas encontradas, que `init` guarda em `state.removed_found` para o health (regras 83 e 84). Saem `cwd.lua` e `tests/unit/cwd_spec.lua` (regra 95); o `init.setup` deixa de copiar `cwd`, `git_repo_cwd` e `cwd_provider` do topo para `terminal`, e a pasta de uma aba nova é sempre o `getcwd()` da janela atual (regras 4 e 93). `diff.lua` passa a ler `config.window.right.width` e `config.window.right.diff_width`; o redimensionamento durante o diff só vale para o layout `right` (no `bottom` a janela já tem a largura toda), e o split do terminal num diff em aba nova (`display_terminal_in_new_tab`) é vertical à direita, ou horizontal embaixo com o layout `bottom`.

#### `notify.lua` (regras 80 a 85 e 89)

| Função                   | Classe                                             | Aparece                                                                                                |
| ------------------------ | -------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| `notify.info(msg, opts)` | informativa (regra 81)                             | só com `config.notify = true`; `opts.once` usa `vim.notify_once`; nível INFO, ou WARN com `opts.level` |
| `notify.reply(msg)`      | resposta a comando que não fez o pedido (regra 89) | sempre, WARN                                                                                           |
| `notify.error(msg)`      | erro (regra 82)                                    | sempre, ERROR                                                                                          |

Todas passam `{ title = "Claudinho" }`. Textos (inglês):

| Situação                                                                                                                       | Classe                         | Texto exato                                                                                                                                                                                                                     |
| ------------------------------------------------------------------------------------------------------------------------------ | ------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Diff de aba em segundo plano (regra 31)                                                                                        | informativa                    | `Claude <n>: pending diff for <arquivo relativo à cwd, :~:.>`                                                                                                                                                                   |
| Processo da aba terminou (regra 40)                                                                                            | informativa                    | `Claude <n> exited`                                                                                                                                                                                                             |
| Chave removida (regras 71 e 77)                                                                                                | informativa, uma vez           | tabela acima                                                                                                                                                                                                                    |
| claudecode.nvim instalado (regra 73)                                                                                           | informativa, uma vez           | `[Claudinho] claudecode.nvim is also installed. Both plugins run, but Claudinho replaces it: remove claudecode.nvim.`                                                                                                           |
| Tecla do preset já mapeada (regra 69)                                                                                          | informativa, uma vez por tecla | `[Claudinho] keymaps.preset left <lhs> alone: it is already mapped.`                                                                                                                                                            |
| Resumos do `close-all-diffs` e de envio de arquivos (`Closed <n> pending Claude diff(s)`, `Added <n> files to Claude context`) | informativa                    | textos de hoje                                                                                                                                                                                                                  |
| Comando do Claude ausente                                                                                                      | erro                           | `[Claudinho] Could not start Claude <n>: '<executável>' is not executable`                                                                                                                                                      |
| Falha de porta, lock file, settings ou job                                                                                     | erro                           | `[Claudinho] Could not start Claude <n>: <motivo>` (o motivo é o texto de hoje, ex. `No free port in 10000-65535 (EADDRINUSE)`, `Failed to write lock file: ...`)                                                               |
| Subcomando desconhecido (regra 67)                                                                                             | erro                           | `[Claudinho] Unknown subcommand '<x>'. Valid: toggle, open, hide, focus, new, tab, tab-next, tab-prev, tab-close, tab-restart, kill-all, send, add, tree-add, send-text, diff-accept, diff-deny, close-all-diffs, select-model` |
| Uso errado                                                                                                                     | erro                           | `[Claudinho] Usage: :Claudinho tab <n>` / `... tab-restart <n>` / `... tab-close [n]` / `... send-text <text>`                                                                                                                  |
| Número de aba inexistente                                                                                                      | erro                           | `[Claudinho] No Claude tab <x>. Open tabs: 1, 2, 3`                                                                                                                                                                             |
| Layout inválido (regra 88)                                                                                                     | erro                           | `[Claudinho] window.layout = "<v>" is not valid; using "right". Valid layouts: right, bottom, float, tab.`                                                                                                                      |
| Outro valor novo inválido                                                                                                      | erro                           | `[Claudinho] <chave> = <v> is not valid; using <padrão>.`                                                                                                                                                                       |
| Comando sem abas (casos de borda)                                                                                              | resposta                       | `No Claude tabs open`                                                                                                                                                                                                           |
| `tab-restart` numa aba rodando (regra 42)                                                                                      | resposta                       | `Claude <n> is still running`                                                                                                                                                                                                   |
| `tab-restart` sem `session_id` (regra 43)                                                                                      | resposta                       | `Claude <n>: no session to resume, started a new one`                                                                                                                                                                           |
| Envio para aba encerrada (casos de borda)                                                                                      | resposta                       | `Claude <n> has exited; run :Claudinho tab-restart <n>`                                                                                                                                                                         |

As respostas que já existem (`No Claude diffs to close`, avisos de edição aceita não salva, `No active diff found in current buffer`, `Cannot send text: ...`) seguem como hoje e passam por `notify.reply`. O logger (`log_level`) não muda: ele é log de diagnóstico, não notificação do plugin.

### 5. Fila de @-mentions por aba (Task 7)

`mention_queue.lua` recebe o código de `init.lua:83-289` e `:1382-1404` sem mudar o comportamento: `Queue.new({ server = <ClaudinhoServer>, config = <config> })`, com `queue:send(file, s, e)` (o caminho de `_broadcast_at_mention`), `queue:on_open()` (o antigo `process_mention_queue(true)`), `queue:flush()`, `queue:clear()`, `queue:is_connected()` e `queue:ready_in()`. Timers, prazos (`connection_timeout + connection_wait_delay`), ordem e mensagens são os de hoje. Até a Task 12 o `init` usa uma fila ligada ao servidor padrão; depois, cada sessão tem a sua, e um envio para uma aba que ainda não conectou espera na fila dela (regra 65).

### 6. Sessão (Task 8)

```lua
---@class ClaudinhoSession
---@field number integer
---@field cwd string                 -- getcwd() da janela atual na criação (regras 4 e 8)
---@field base_cmd string            -- config.terminal_cmd ou "claude"
---@field state "running"|"exited"
---@field buf integer|nil
---@field job integer|nil
---@field pid integer|nil
---@field exit_code integer|nil
---@field server ClaudinhoServer|nil
---@field token string|nil
---@field lock_port integer|nil
---@field settings_path string|nil
---@field data { session_id?: string, model?: string, effort?: string, mode?: string }
---@field title string|nil           -- clean_title de b:term_title
---@field pending_diffs { tab_name: string, path: string, co: thread }[]
---@field queue ClaudinhoMentionQueue
---@field closing boolean
```

`session.start(s, extra_args)`: tudo ou nada (casos de borda "o comando não existe" e "sem porta ou lock file").

1. `vim.fn.executable(<primeiro token de base_cmd>) == 1`, senão erro e nada criado.
2. Token (`lockfile.generate_auth_token`), `server.new({ on_open, on_disconnect, on_post })`, `:start(config, token)`.
3. `lockfile.create(port, token, { ide_name = "Neovim (Claudinho <n>)", workspace_folders = get_workspace_folders(cwd) })`.
4. `session_settings.write(s)`.
5. Buffer novo (`bufhidden=hide`, `b:claudinho_session = n`, filetype `claudinho`), `vim.fn.jobstart(base_cmd .. " --settings " .. shellescape(path) .. (extra_args or ""), { term = true, cwd = cwd, env = <tabela do item 2>, on_exit = ... })` dentro de `nvim_buf_call`.
6. Qualquer falha desfaz na ordem inversa (job, buffer, settings, lock, servidor) e devolve `false, motivo`.

`on_post` decodifica com `session_data`, mescla em `s.data` só o que veio (campo ausente não apaga o anterior, regra 52) e chama `sessions.on_change(s)`. `on_open` -> `s.queue:on_open()`.

Fim do processo sem `tab-close` (`on_exit`/`TermClose`, regra 40): `state = "exited"`, `exit_code`; a fila é limpa; os diffs abertos da aba fecham sem resposta pelo caminho de hoje (`on_disconnect` -> `close_diffs_for_client`), e os que esperam ativação são descartados; `server:stop()`, lock file e settings removidos; o buffer fica, com a saída final; `sessions.on_exit(s)` marca `[exited]` e avisa `Claude <n> exited`. Uma tecla no terminal encerrado não fecha o buffer (regra 39): a janela nunca entra em modo terminal num buffer encerrado (sem `startinsert`; `TermEnter` nele agenda `stopinsert`), e o plugin não apaga o buffer no `TermClose`. O autocmd padrão `nvim.terminal` só apaga buffers de shell, não o da aba (conferido em `runtime/lua/vim/_core/defaults.lua` do 0.12.3).

`session.restart(s)` (regra 41): só com `state == "exited"`; mesmo `number` e `cwd`; servidor, token, porta, lock file e settings novos; `--resume <session_id>` (com `shellescape`) quando `data.session_id` existe, senão sem argumento e com a resposta da regra 43. O buffer antigo é trocado na mesma posição da barra e apagado depois do `jobstart` novo. `data` (status) fica até o primeiro dado novo.

`session.close(s, reason)`: idempotente (`closing`). Rejeita os diffs da aba (abertos: `close_diffs_for_client` de cada cliente; esperando: retomados com `"reject"`), `server:drain(200)`, para o job e espera o `TermClose` por até 1000 ms como `native.lua` fazia (neovim/neovim#42508), `server:stop()`, remove lock file e settings, apaga o buffer.

### 7. Abas (Task 9)

`sessions.lua` guarda `{ tabs = { [n] = ClaudinhoSession }, active = n|nil, by_server = { [server_id] = n } }`.

| Função                        | Comportamento                                                                                                                                                               | Regras            |
| ----------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------- |
| `new(extra_args)`             | menor número livre a partir de 1; cwd = `getcwd()` da janela atual; `session.start`; em sucesso vira ativa e `window.show({ focus = true })`; em falha, erro e nenhuma aba  | 4, 5, 8           |
| `activate(n)`                 | troca a ativa; reenvia a seleção atual à nova (`selection.resend_latest()`); abre os diffs pendentes dela na ordem de chegada; redesenha winbar e statusline no mesmo ciclo | 26-28, 30-31, 52  |
| `next()` / `prev()`           | dão a volta; com uma aba só, nada                                                                                                                                           | 26                |
| `close(n)`                    | `session.close`; tira da barra; nova ativa = vizinha de número maior, senão menor; sem abas, `window.close()`                                                               | 38, 44            |
| `restart(n)`                  | exige número; rodando -> `Claude <n> is still running`                                                                                                                      | 41-43             |
| `kill_all()`                  | rejeita todos os diffs (abertos com `diff.close_pending_diffs`, esperando com `"reject"`), `drain` de cada servidor, fecha todas as sessões, fecha a janela                 | 45                |
| `active()` / `for_client(c)`  | a aba ativa; a aba dona do servidor do cliente (cliente externo conectado pelo `/ide` conta como da aba, regra 63)                                                          | 28, 63            |
| `on_change(s)` / `on_exit(s)` | redesenha winbar e statusline se a janela está visível                                                                                                                      | 13, 37, 40        |
| `router`                      | objeto `{ broadcast = fn }` que a seleção usa: manda só para o servidor da aba ativa rodando, senão devolve `false`                                                         | 29                |
| `setup_autocmds()`            | `ExitPre`, `VimLeavePre`, `BufDelete`/`BufWipeout` dos buffers de aba (ver abaixo)                                                                                          | 46, caso de borda |

- Seleção: `selection.enable(router, delay)` passa a ser chamado no `setup` quando `track_selection` é `true`, sem servidor (regra 2 continua: nenhum servidor nem lock file nasce no `setup`). Assim a seleção atual está sempre conhecida para a regra 30 e para um `send` sem abas. `selection.is_claude_terminal_buffer` reconhece também qualquer buffer com `b:claudinho_session`.
- @-mentions: `init.send_at_mention` pega a aba ativa; sem abas, `sessions.new()` e enfileira na aba 1; aba ativa encerrada, `Claude <n> has exited; run :Claudinho tab-restart <n>` e nada é enviado; senão `s.queue:send(...)` (regras 29 e 65).
- Diff de aba em segundo plano: seção 9.
- `:bdelete`/`:bwipeout` num buffer de aba: o `BufDelete`/`BufWipeout` chama `sessions.close(n)` (sem repetir o que já foi feito, pela marca `closing`).
- Saída do Neovim (regra 46): `ExitPre` (dispara antes de o Neovim sair por `:q`, `:wq`, `:qa`, `:wqa`, `:xa`) rejeita os diffs pendentes de todas as abas e faz `drain(200)` dos servidores, enquanto as sessões ainda estão vivas. `VimLeavePre` faz o resto do `kill_all` (jobs, servidores, lock files, settings). Conferido no 0.12.3 (F11): `:qa` com jobs de terminal rodando, visíveis e escondidos, sai sem perguntar, também com `confirm` e `nohidden`; então nada é preciso para o "job still running". O teste de integração cobre `:qa`, `:wqa` e `:q` na última janela também no 0.12.0 (suíte `on-demand`).
- Nada encerra processo, para servidor ou remove lock file que o plugin não criou: `kill_all` só itera `tabs`, e `lockfile.remove` só recebe portas das próprias abas (regra 61).

### 8. Janela (Task 10)

Uma janela por Neovim (regra 16), estado `{ win, tabpage, hidden_by_diff }`; o layout é sempre `config.window.layout` (regras 85 e 86).

| Layout   | Abrir                                                                                                                     | Tamanho                                                                     |
| -------- | ------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| `right`  | `botright vsplit`, `winfixwidth`                                                                                          | `floor(columns * window.right.width)`                                       |
| `bottom` | `botright split`, `winfixheight`                                                                                          | `floor(lines * window.bottom.height)`                                       |
| `float`  | `nvim_open_win(buf, true, { relative = "editor", ... })` centralizada, sem `style = "minimal"` (para ter statusline, F12) | `window.float.width` e `.height` da área do editor; refeito no `VimResized` |
| `tab`    | `tabnew` e a janela ocupa a aba toda                                                                                      | -                                                                           |

- Opções locais aplicadas a cada troca de buffer (opções de janela no Neovim acompanham o buffer): `winbar = "%!v:lua.require'claudinho.ui.tabbar'.render()"`, `statusline = "%!v:lua.require'claudinho.ui.status'.render()"`, `number`, `relativenumber`, `signcolumn=no`, `foldcolumn=0`, `winfixbuf` (desligado só durante a troca de aba feita pelo plugin). Floats exigem winbar local, e ela é local aqui (F12).
- `show({ focus })`: visível na aba atual do Neovim -> só foca (com `focus`); visível em outra aba do Neovim -> fecha lá e abre aqui (caso de borda `gt`; no layout `tab`, vai para a aba do Claude); escondida -> abre. Com foco e aba rodando e `terminal.auto_insert`, `startinsert` (regra 24).
- `hide()`: `nvim_win_hide`; no layout `tab`, fecha a aba do Neovim (sendo a única, abre antes uma aba vazia). Nunca encerra sessão (regra 23).
- `toggle`, `open`, `hide`, `focus`: regras 19 a 22; `focus` com a janela em foco esconde.
- `WinClosed` da janela (`:q`, `<C-w>c`, `:tabclose`) = esconder (regra 23).
- `QuitPre` (caso de borda "`:q` na última janela do editor"): se a janela que sai é a última janela não flutuante fora do Claude em todas as abas do Neovim, o plugin fecha antes a janela do Claude; o `:q` então fecha a última janela, o Neovim sai e vale a regra 46.
- Título: `TermRequest` no buffer da aba com sequência OSC 0 ou 2 agenda a leitura de `b:term_title`, guarda `clean_title` em `s.title` e redesenha a winbar (`nvim__redraw({ win, winbar = true })` em `pcall`, senão `redrawstatus!`) (regra 13).
- Status: `ui/status.render()` lê `sessions.active().data`; `activate` redesenha winbar e statusline juntas (regra 52).
- Float e diff (regra 25): um autocmd `User ClaudinhoDiffOpened` esconde a janela quando o layout é `float` (`hidden_by_diff = true`); `terminal.ensure_visible()` (chamado pelo diff ao fechar) não a traz de volta nesse estado; `toggle`, `open` ou `focus` trazem.
- Limitação aceita: com `laststatus=3` a statusline da janela só aparece quando ela está em foco; com `laststatus=0`, nunca (Trade-offs, README).

### 9. Diff por aba (Task 11)

- `tools/open_diff.lua`: antes de `diff.open_diff_blocking`, `sessions.gate_diff(client, params)`. Cliente de aba ativa (ou de nenhuma aba, como o servidor padrão dos testes): segue na hora (regra 32). Cliente de aba em segundo plano: entra em `s.pending_diffs` (`{ tab_name, path, co = coroutine.running() }`), a barra mostra ` ● diff`, `notify.info("Claude <n>: pending diff for <path>")` uma vez por pedido, e `coroutine.yield()`. Na ativação, cada um é retomado com `"open"`, na ordem de chegada, e continua no `open_diff_blocking` de hoje, que abre o diff e espera o usuário (regra 31); a marca some quando a lista esvazia.
- Retomado com `"reject"` (`tab-close`, `kill-all`, `close-all-diffs`, saída): devolve `diff.rejected_response(tab_name)`, o mesmo conteúdo do `_resolve_diff_as_rejected` de hoje (`DIFF_REJECTED`, `tab_name`), sem abrir janela (regras 35, 38, 45).
- Processo da aba morreu: os pendentes são descartados sem resposta; as chaves deles saem de `_G.claude_deferred_responses` no `server:stop()` (regra 40).
- Aceitar, rejeitar, salvar, `diff-accept`, `diff-deny`: inalterados; a resposta sai pelo servidor da instância do cliente (Task 2), então vai para a aba que pediu mesmo com outra ativa (regras 33 e 34).
- `close-all-diffs` (regra 35): o comando de hoje mais `sessions.reject_all_pending("user command")`; os resumos são informativos.
- Outras tools respondem a qualquer aba, como hoje (regra 36): nada muda em `tools/`.
- `diff.lua` não conhece abas: `find_claudinho_terminal_window` e `display_terminal_in_new_tab` continuam pela fachada `terminal.get_active_terminal_bufnr()`.

### 10. Comando `:Claudinho` (Task 12)

`nvim_create_user_command("Claudinho", handler, { nargs = "*", range = true, bang = true, complete = complete })`.

| Subcomando                        | Ação                                                                                                                                                                                                         | Regras |
| --------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------ |
| (nenhum), `toggle`                | sai do modo visual; com abas `window.toggle()`; sem abas `sessions.new()`                                                                                                                                    | 19, 67 |
| `open`                            | com abas `window.show({ focus = true })`; sem abas `sessions.new()`                                                                                                                                          | 20     |
| `hide`                            | sem abas -> `No Claude tabs open`; senão `window.hide()` (escondida: nada)                                                                                                                                   | 21     |
| `focus`                           | regra 22; sem abas, como `open`                                                                                                                                                                              | 22     |
| `new`                             | `sessions.new()`                                                                                                                                                                                             | 4      |
| `tab <n>`, `tab-next`, `tab-prev` | ativa e mostra; sem abas -> `No Claude tabs open`; número inexistente -> erro com a lista                                                                                                                    | 26     |
| `tab-close [n]`                   | sem número, a ativa                                                                                                                                                                                          | 38     |
| `tab-restart <n>`                 | número obrigatório                                                                                                                                                                                           | 41-43  |
| `kill-all`                        | `sessions.kill_all()`, sem confirmação                                                                                                                                                                       | 45     |
| `send` (com range)                | `handle_send_normal`/`handle_send_visual` de hoje                                                                                                                                                            | 29, 65 |
| `add <arquivo> [início] [fim]`    | validação e mensagens de hoje (`ClaudeCodeAdd:` vira `Claudinho add:`); `complete = file` no segundo argumento                                                                                               | 65     |
| `tree-add`                        | como hoje                                                                                                                                                                                                    | 65     |
| `send-text <texto>`               | `terminal.send_to_terminal(texto, { submit = not bang })`; `:Claudinho! send-text` ou `send-text!` inserem sem enviar; sem abas -> `No Claude tabs open`; aba encerrada -> resposta da aba encerrada         | 65     |
| `diff-accept`, `diff-deny`        | como hoje                                                                                                                                                                                                    | 33     |
| `close-all-diffs`                 | seção 9                                                                                                                                                                                                      | 35     |
| `select-model`                    | `vim.ui.select(config.models)`; aba ativa rodando -> `send_to_terminal("/model " .. value)`; sem abas -> `sessions.new(" --model " .. shellescape(value))`; aba ativa encerrada -> resposta da aba encerrada | 66     |

- `layout` e qualquer outra palavra -> erro de subcomando desconhecido (regras 67 e 86).
- Completion (regra 68): primeiro argumento, os subcomandos que começam com o prefixo; segundo argumento de `tab`, `tab-close`, `tab-restart`, os números das abas existentes; de `add`, arquivos (`vim.fn.getcompletion(arg, "file")`).
- `send`, `add`, `tree-add` sem abas criam a aba 1 e entregam quando ela conectar (regra 65); a aba ativa encerrada recebe a resposta da aba encerrada.
- Preset (regra 69, `keymaps.preset = true`), aplicado no `setup` com `vim.keymap.set`, `desc` em inglês:

| Tecla               | Modo | Comando                                  |
| ------------------- | ---- | ---------------------------------------- |
| `<leader>ac`        | n    | `<cmd>Claudinho toggle<cr>`              |
| `<leader>af`        | n    | `<cmd>Claudinho focus<cr>`               |
| `<leader>an`        | n    | `<cmd>Claudinho new<cr>`                 |
| `<leader>al` / `ah` | n    | `tab-next` / `tab-prev`                  |
| `<leader>a1` a `a9` | n    | `tab 1` a `tab 9`                        |
| `<leader>ax`        | n    | `tab-close`                              |
| `<leader>am`        | n    | `select-model`                           |
| `<leader>ab`        | n    | `add %`                                  |
| `<leader>as`        | x    | `:Claudinho send<cr>` (range automático) |
| `<leader>aa` / `ad` | n    | `diff-accept` / `diff-deny`              |

Antes de cada uma, `vim.fn.maparg(lhs, mode, false, true)`: não vazio -> a tecla fica de fora, com o aviso informativo da seção 4.

- `terminal.lua` vira fachada: `setup(term_config)` (`auto_insert`, `fix_streamed_paste` -> `paste_fix`), `get_active_terminal_bufnr()`, `ensure_visible()`, `open()`, `send_to_terminal(text, opts)` (mesma lógica de hoje sobre o canal da aba ativa). Saem `simple_toggle`, `focus_toggle`, `toggle`, `close`, `toggle_open_no_focus`, providers, `defaults` e `_get_managed_terminal_for_test`.
- `init.lua`: `setup` (conflito como aviso, chaves removidas, `config.apply`, logger, fachada, `diff.setup`, seleção, `sessions.setup_autocmds`, comandos, preset); saem `start`, `stop`, `process_mention_queue`, `_maybe_warn_unfocusable_provider`, o autocmd `VimLeavePre` próprio e os 17 `:ClaudeCode*` (regra 64). Ficam `send_at_mention`, `is_claude_connected` (aba ativa), `open_with_model`, `get_version`, `_format_path_for_at_mention`, `_broadcast_at_mention`, `_add_paths_to_claude` e o evento `ClaudinhoSendComplete`.
- Fixtures (`fixtures/*/lua/plugins/dev-claudinho.lua`, `fixtures/repro/`) passam a `:Claudinho`.

### 11. claudecode.nvim instalado junto (Task 14, regras 73 a 76)

- `conflict.detected()` igual (regra 75). `conflict.MESSAGE` vira o texto da seção 4. `conflict.check()` sai; `conflict.warn(notify_enabled)` devolve `detected()` e avisa uma vez por sessão (`notify_once`) só com `notify` ligado.
- `plugin/claudinho.lua` não chama mais o conflito (não conhece a config) e segue para o auto-setup. `init.setup` chama `conflict.warn(opts.notify == true)` e continua normalmente.
- `health.lua`: `check_conflict()` sempre roda, com ou sem setup, e mostra WARN `claudecode.nvim is installed (lua/claudecode/init.lua is on the runtimepath)` ou `claudecode.nvim is loaded (g:loaded_claudecode is set)`, com o conselho `Both plugins run, but Claudinho replaces it. Remove claudecode.nvim from your plugin manager and restart Neovim.` (regra 74). O ramo de erro da Fase 0 sai.

### 12. `:checkhealth claudinho` depois da feature

| Item                 | Resultado                                                                                                                                                                                                          |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Neovim, setup, CLI   | como hoje                                                                                                                                                                                                          |
| claudecode.nvim      | WARN da seção 11                                                                                                                                                                                                   |
| Chaves removidas     | um WARN por chave em `state.removed_found`: `Removed config key: <chave>`, conselho = a mensagem da linha (regra 83)                                                                                               |
| Notificações         | INFO `Informative notifications are off (notify = false)` quando desligadas                                                                                                                                        |
| Abas                 | sem abas: INFO `No Claude tabs open`; por aba: OK `Claude <n>: running, port <p>, <k> client(s), lock file <caminho>`, ERROR se o lock file sumiu ou não lê (lógica de hoje), INFO `Claude <n>: exited (code <c>)` |
| Provider do terminal | sai                                                                                                                                                                                                                |

### 13. Linhas de origem (Task 16, regra 72)

Todo arquivo de `lua/claudinho/` e `plugin/` que vem de um arquivo do upstream leva na primeira linha:

```lua
-- Origin: coder/claudecode.nvim@d1237072, <caminho no upstream> (MIT, see LICENSE)
```

`<caminho no upstream>` é o arquivo de origem (`lua/claudecode/terminal.lua`, `plugin/claudecode.lua`, ...). Derivados com nome novo apontam o arquivo de onde vieram: `commands.lua` e `mention_queue.lua` -> `lua/claudecode/init.lua`; `session.lua` -> `lua/claudecode/terminal.lua`; `ui/window.lua` -> `lua/claudecode/terminal/native.lua`. Módulos novos sem arquivo de origem (`conflict.lua`, `notify.lua`, `sessions.lua`, `session_settings.lua`, `sources/*`, `ui/tabbar.lua`, `ui/status.lua`, `server/http.lua`) não levam a linha. A mais longa (`tools/get_current_selection.lua`) tem 108 colunas, dentro das 120 do luacheck. Um spec (`tests/unit/provenance_spec.lua`) confere a tabela arquivo -> origem.

### 14. Docs (Tasks 17 a 20)

| Arquivo                          | Conteúdo                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `README.md`, `README.en.md`      | Mesmas seções nas duas línguas. Uso rápido com `:Claudinho`; tabela de subcomandos; abas, winbar, statusline e o que cada item significa; layouts e chaves `window`, `keymaps`, `notify`; preset; limitações (modo só depois do primeiro prompt ou fim de turno, dicas do rodapé da TUI escondidas, status vazio até aceitar a confiança da pasta, `disableAllHooks`/`allowManagedHooksOnly`, `laststatus` 0 e 3); conexão automática do CLI: com `autoConnectIde`, `--ide` ou `CLAUDE_CODE_AUTO_CONNECT_IDE=1`, um claude aberto fora do Neovim pode se conectar sozinho a uma aba, e `CLAUDE_CODE_AUTO_CONNECT_IDE=0` numa sessão ou `autoConnectIde` desligado evitam (regra 92); dois Neovims com abas de mesmo número mostram a pasta de cada uma no `/ide` de um claude externo, na mesma pasta as linhas ficam iguais, e dentro de uma aba o `/ide` só lista o próprio Neovim (regra 97); "Vindo do claudecode.nvim": os dois rodam, mas o recomendado é remover o claudecode.nvim (regra 33 da Fase 0 atualizada), tabela `:ClaudeCode*` -> `:Claudinho`, chaves removidas, incluindo as seis de diretório, que saem da seção de configuração (regra 95); atribuição ao upstream mantida |
| `CLAUDE.md`                      | Visão sem providers, sem recusa do claudecode.nvim e com `:Claudinho`; estrutura de módulos nova; o resto (Commands, Test suites, Language, Version, Workflow) fica                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| `CHANGELOG.md`                   | Em `## [Unreleased]`, entradas Added/Changed/Removed de tudo o que o usuário vê (as tasks de código já deixam uma linha cada; a Task 19 revisa e completa); linha do hard fork mantida                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| `PROTOCOL.md`, `ARCHITECTURE.md` | Nota do topo atualizada: o Claudinho tem um servidor e um lock file por aba, `ideName = "Neovim (Claudinho <n>)"`, as rotas `POST /claudinho/*` e o relay; seção nova curta "Claudinho: sessions per tab"; o resto do texto do upstream fica como está                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| `LICENSE`                        | Sem mudança (aviso da Coder e linha do fork); a Task 19 só confere                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |

### Contratos públicos antes e depois

| Item                  | 0.1.0                                                                 | 0.2.0                                                                                            |
| --------------------- | --------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| Comandos              | 17 `:ClaudeCode*`                                                     | `:Claudinho <subcomando>`                                                                        |
| Servidor no `setup`   | sim, com `auto_start = true`                                          | nunca; um por aba                                                                                |
| Lock file             | `~/.claude/ide/<porta>.lock`, `ideName = "Neovim"`                    | um por aba, `ideName = "Neovim (Claudinho <n>)"`                                                 |
| Terminal              | providers `auto`, `native`, `external`, `none`                        | só o terminal do Neovim, janela única com abas                                                   |
| Processo do Claude    | `claude [args do comando]`                                            | `claude --settings <arquivo>` (+ `--resume <id>` no restart, `--model` no select-model sem abas) |
| Eventos `User`        | `ClaudinhoSendComplete`, `ClaudinhoDiffOpened`, `ClaudinhoDiffClosed` | iguais                                                                                           |
| Rotas HTTP            | -                                                                     | `POST /claudinho/statusline`, `POST /claudinho/hook` no servidor de cada aba                     |
| claudecode.nvim junto | Claudinho não roda                                                    | os dois rodam; aviso informativo e WARN no health                                                |

### Segurança, privacidade, observabilidade e rollout

- **Segurança:** todos os servidores escutam só em `127.0.0.1`; as rotas POST exigem o token da aba (o mesmo do lock file, 128 bits) com comparação em tempo constante; corpo limitado a 1 MiB e cabeçalhos a 8 KiB; um POST nunca vira cliente WebSocket. O token também passa a estar no ambiente do processo da aba (`CLAUDINHO_TOKEN`), legível pelos processos que o Claude abre; é a mesma fronteira do lock file, que o mesmo usuário já lê. O arquivo de settings é `0600` na pasta temporária `0700` do Neovim.
- **Privacidade:** o plugin guarda só `session_id`, rótulo do modelo, esforço e modo, em memória; nada vai para o disco além do lock file e do arquivo de settings. Os logs nunca registram corpo de POST nem token, só o tipo (`statusline`/`hook`) e o tamanho.
- **Observabilidade:** logger com componente por aba (`[Claudinho] [session 2] ...`); em `debug`: início e fim de sessão (porta, pid), POST aceito ou recusado (código), retomada de diff pendente. Num plugin local não há request id; o id de cliente (`client_<n>`) segue nos logs do servidor, e o `:checkhealth` lista as abas.
- **Rollout:** sem flag; release única `0.2.0`. Reverter: o usuário fixa `v0.1.0` no gerenciador de plugins; no repo, `git revert` dos commits da feature.

### Fatos conferidos no CLI e no Neovim

CLI instalado: `claude --version` = `2.1.325 (Claude Code)`. Docs oficiais lidas em 2026-11-15. A inspeção do binário foi só leitura de strings do JavaScript embutido (`~/.local/share/claude/versions/2.1.325`); os nomes de função citados são os minificados daquela versão e mudam a cada build.

| #   | Fato                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | Fonte                                                                                                                                                                                                                                                                                    |
| --- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| F1  | `--settings <file-or-json>` existe. Fica acima dos arquivos do usuário, do projeto e local e abaixo dos managed; chave ausente mantém o valor dos arquivos. Listas se somam; hooks se somam entre níveis; `statusLine` é uma chave única, então a do `--settings` vale. `--settings` precisa ser repassado num `--resume`.                                                                                                                                                                                                                                                                                                                                                                                                                                             | `claude --help`; [settings](https://code.claude.com/docs/en/settings) "Settings precedence" e "Lists merge"; [settings-reference `hooks`](https://code.claude.com/docs/en/settings-reference#hooks); [sessions](https://code.claude.com/docs/en/sessions) "Resume by session ID or name" |
| F2  | JSON da statusline: `session_id`, `model.id`, `model.display_name` (o exemplo traz `"Opus"` para `claude-opus-5-5`, sem versão), `effort.level` (`low` a `max`, ausente quando o modelo não tem esforço); nenhum `permission_mode`. Roda no início (e no resume), a cada mensagem do assistente, após `/compact`, ao mudar o modo de permissão; debounce de 300 ms; execução anterior cancelada. Saída vazia ou código diferente de 0 deixam a linha em branco. Desligada por `disableAllHooks` fora de managed e por `allowManagedHooksOnly`; só roda depois de aceitar a confiança da pasta. Com statusline custom, o rodapé esconde dicas como `esc to interrupt`.                                                                                                  | [statusline](https://code.claude.com/docs/en/statusline) "Available data", "How status lines work", "Troubleshooting"; [settings-reference `statusLine`](https://code.claude.com/docs/en/settings-reference#statusline)                                                                  |
| F3  | Hooks: `permission_mode` só em parte dos eventos (`UserPromptSubmit`, `PreToolUse`, `PermissionRequest`, `PostToolUse`, `PostToolUseFailure`, `PostToolBatch`, `PermissionDenied`, `Stop` e outros); `SessionStart` traz `session_id` e `source` (`startup`, `resume`, `clear`, `compact`, `fork`), sem modo, e só aceita hooks `command` e `mcp_tool`. `async: true` só existe em hooks `command`: roda em segundo plano, sem prazo, avisos de término escondidos. Hook `http` que falha na conexão é erro não bloqueante com aviso `hook error` na transcrição. O processo do hook herda o ambiente do Claude. Hooks de arquivos de settings só rodam depois da confiança da pasta.                                                                                  | [hooks](https://code.claude.com/docs/en/hooks) "Common input fields", "SessionStart", "UserPromptSubmit", "Stop", "HTTP response handling", "Run hooks in the background", "Workspace trust"                                                                                             |
| F4  | `nvim --clean -l <script> <arg>` lê o stdin com `io.read("*a")`, recebe o argumento em `_G.arg[1]` (`...` é `nil`) e tem `vim.uv`. Relay protótipo: 9,7-12,1 ms por chamada (10 execuções), porta morta sai 0 em 10,9 ms.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              | Sonda local no Neovim 0.12.3 (scripts na pasta de rascunho da sessão; a Task 4 reproduz como `tests/integration/relay_spec.lua`)                                                                                                                                                         |
| F5  | `/ide`: o rótulo de cada entrada é o `ideName` do lock file (só `windsurf` é reescrito); quando duas entradas disponíveis têm o mesmo nome, cada uma mostra as suas `workspaceFolders` como descrição. Disponível = uma pasta do lock contém a cwd ou está dentro dela; as outras só aparecem como "Found N other running IDE(s). However, their workspace or project directories don't match the current directory." e não são selecionáveis. Num terminal "suportado" (`FORCE_CODE_TERMINAL`, que as abas recebem), só entram lock files de PID vivo que seja ancestral do processo, ou com a porta de `CLAUDE_CODE_SSE_PORT`: o `/ide` de uma aba lista as abas do mesmo Neovim e nada de fora.                                                                     | Binário 2.1.325: função de detecção `JSo` e componente do `/ide` (`availableIDEs`, `unavailableIDEs`, descrição quando `name` se repete)                                                                                                                                                 |
| F6  | Conexão automática: roda quando `CLAUDE_CODE_AUTO_CONNECT_IDE` não é falso e há `autoConnectIde`, `--ide`, terminal suportado, `CLAUDE_CODE_SSE_PORT` ou `CLAUDE_CODE_AUTO_CONNECT_IDE=1` (`G_t`). Ela procura a cada 1 s por 30 s e conecta quando **exatamente um** lock file tem uma pasta que contém a cwd (`XSo`). O CLI lê do lock só `workspaceFolders`, `pid`, `ideName`, `transport`, `runningInWindows` e `authToken` (`qXn`): nenhum campo tira um lock file da conexão automática sem também tirá-lo da lista selecionável do `/ide`. `autoConnectIde` vale `false` por padrão e fica em `~/.claude.json`; nesta máquina a chave não está definida. Com um processo de aba (`CLAUDE_CODE_SSE_PORT` definido) a procura devolve só o lock da própria porta. | Binário 2.1.325 (`G_t`, `XSo`, `JSo`, `qXn`); [settings-reference `autoConnectIde`](https://code.claude.com/docs/en/settings-reference#autoconnectide); `grep` da chave em `~/.claude.json`                                                                                              |
| F7  | PID morto: antes da procura automática, o CLI apaga lock files ilegíveis e os de PID que não responde a `kill(pid, 0)` (fora do WSL) (`sfs`). Toda aba do Claudinho dispara essa procura ao iniciar. O `/ide` de um claude externo não confere o PID, então um lock velho pode aparecer ali até alguma limpeza rodar; ele não conecta. Conclusão: o plugin não precisa de limpeza própria, e a regra 61 o proíbe de apagar lock que não criou.                                                                                                                                                                                                                                                                                                                         | Binário 2.1.325 (`sfs`, `zXn`, chamada em `XSo`; `/ide` chama `JSo(!0)` sem `sfs`)                                                                                                                                                                                                       |
| F8  | `claude --resume <session-id>` procura primeiro no projeto atual e depois em todos os outros projetos (quando um só tem a sessão), então acha uma sessão movida por `/cd`; `/clear` salva a sessão anterior e começa outra (novo `session_id`, `SessionStart` com `source = "clear"`). O comportamento real precisa de sessão interativa: passos 7 e 8 do roteiro manual.                                                                                                                                                                                                                                                                                                                                                                                              | [sessions](https://code.claude.com/docs/en/sessions) "Resume by session ID or name", "/clear"; [hooks](https://code.claude.com/docs/en/hooks) "SessionStart"                                                                                                                             |
| F9  | `--permission-mode` aceita `acceptEdits`, `auto`, `bypassPermissions`, `manual`, `dontAsk`, `plan`; nos hooks o modo Manual chega como `"default"`, nunca `"manual"`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  | `claude --help`; [hooks](https://code.claude.com/docs/en/hooks) "Common input fields"                                                                                                                                                                                                    |
| F10 | O CLI grava `~/.claude.json` a cada início (contador `numStartups` e outros), então o checksum desse arquivo muda com qualquer sessão real, com ou sem plugin.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         | Binário 2.1.325 (`numStartups:(W.numStartups??0)+1`)                                                                                                                                                                                                                                     |
| F11 | Neovim 0.12.3: `:qa` com dois jobs de terminal rodando (um visível, um escondido com `bufhidden=hide`) sai com código 0, sem pergunta, também com `confirm` e com `nohidden`; `ExitPre` dispara antes de `VimLeavePre`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                | Sonda local headless no 0.12.3                                                                                                                                                                                                                                                           |
| F12 | Neovim 0.12: floats podem mostrar statusline; winbar de float precisa de valor local; `%N@func@` passa `minwid`, cliques, botão (`l`, `r`, `m`) e modificadores; `TermRequest` dispara para cada OSC do processo do terminal.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          | `:help news` (0.12), `:help 'winbar'`, `:help 'statusline'`, `:help TermRequest`                                                                                                                                                                                                         |

## Alternatives considered

| Decisão                                    | Alternativa                                                                                                     | Por que não                                                                                                                                                                                                                 |
| ------------------------------------------ | --------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Repasse de hooks e statusline              | **Escolhida:** relay `nvim --clean -l` que faz POST ao servidor da aba com o token                              | Zero dependências, 10 ms, sempre sai 0, respeita a regra 59                                                                                                                                                                 |
|                                            | Cliente RPC do Neovim por `$NVIM` (`nvim --server $NVIM --remote-expr`, ou `sockconnect`)                       | Passa por fora do servidor e do token da aba (regra 59); `$NVIM` está no ambiente de qualquer `:terminal`, então qualquer processo ali poderia mudar o status de uma aba; um `nvim --remote-expr` é tão caro quanto o relay |
|                                            | Hooks `type: "http"` direto no servidor                                                                         | `SessionStart` não aceita `http`; falha de conexão vira aviso `hook error` na TUI (fere a regra 58); hook síncrono com prazo padrão de 600 s; a statusline teria de ser `command` de qualquer jeito                         |
|                                            | Arquivos de estado + `fs_event`                                                                                 | Grava em disco a cada atualização (o plano só aceita lock file e settings); latência e limpeza piores                                                                                                                       |
| Eventos de hook                            | **Escolhida:** `SessionStart`, `UserPromptSubmit`, `Stop`                                                       | Modo atualizado a cada prompt e fim de turno com 2 processos por turno                                                                                                                                                      |
|                                            | Também `PreToolUse`/`PostToolUse`                                                                               | Um processo por chamada de ferramenta, só para adiantar o modo dentro de um turno                                                                                                                                           |
| Estado do servidor                         | **Escolhida:** instâncias, com funções de módulo delegando a uma instância padrão só para os testes do upstream | Muda pouco os 15 specs de `server/`, que continuam provando o protocolo                                                                                                                                                     |
|                                            | Remover as funções de módulo                                                                                    | Reescreveria os specs de protocolo inteiros, o maior risco do plano (Risks: "Tirar o estado global"), sem ganho no plugin                                                                                                   |
| Janela                                     | **Escolhida:** uma janela que troca o buffer da aba ativa                                                       | Regra 16 literal; trocar de aba não mexe em layout                                                                                                                                                                          |
|                                            | Uma janela por aba, só uma visível                                                                              | Mais estado de janela para sincronizar; nada ganha                                                                                                                                                                          |
| Terminal                                   | **Escolhida:** `claudinho.terminal` como fachada                                                                | `diff.lua`, `diff_inline.lua`, `selection.lua` e cerca de 40 specs não mudam                                                                                                                                                |
|                                            | Trocar todos os chamadores para `sessions`/`ui.window`                                                          | Reescreve specs de diff que nada têm com abas                                                                                                                                                                               |
| Rejeição na saída                          | **Escolhida:** `ExitPre` rejeita os diffs e drena; `VimLeavePre` encerra o resto                                | Os frames saem enquanto o loop e as sessões ainda rodam (regra 46)                                                                                                                                                          |
|                                            | Tudo no `VimLeavePre`                                                                                           | É o ponto de hoje, mas não há garantia de que os frames de rejeição saiam antes de os sockets fecharem                                                                                                                      |
| `session_id` sem hooks                     | `claude --session-id <uuid>` gerado pelo plugin                                                                 | A regra 41 define a fonte (hooks ou statusline) e a 43 o caso sem `session_id`; fica como ideia para quando os hooks estiverem desligados                                                                                   |
| Barramento `events.lua`                    | Criar já                                                                                                        | Um consumidor por evento hoje; entra com o Painel (seção 0)                                                                                                                                                                 |
| Conexão automática do CLI (regras 90 a 92) | `workspaceFolders` vazio no lock file; recusar no servidor o cliente que não descende do processo da aba        | O primeiro tira as abas da lista selecionável do `/ide` de um claude externo (regras 7 e 63); o segundo não distingue conexão automática de `/ide` explícito (regra 63). Decidido em 2026-11-15: aceitar e documentar       |
| Nome no `/ide` (regra 96)                  | Acrescentar o PID do Neovim ou a pasta ao `ideName`                                                             | O CLI já mostra a pasta quando os nomes se repetem (F5); o PID põe ruído em toda entrada, e a pasta não resolve dois Neovims na mesma pasta                                                                                 |
| Pasta da aba (regras 93 a 95)              | Manter `cwd`, `git_repo_cwd` e `cwd_provider`, aplicados na criação de cada aba                                 | Contraria a regra 4 (a aba nova sempre inicia no `getcwd()` da janela atual)                                                                                                                                                |

## Trade-offs

- O modo aparece só depois do primeiro prompt (`UserPromptSubmit`) e muda só no próximo prompt ou fim de turno; a statusline do Claude roda quando o modo muda, mas não traz o modo (F2, risco do plano).
- Com a statusline do plugin, a TUI esconde dicas do rodapé como `esc to interrupt` (F2; consequência aceita no plano).
- Status vazio numa pasta ainda sem confiança aceita, com `disableAllHooks` ou com `allowManagedHooksOnly` (F2, F3); as abas funcionam igual.
- Com `laststatus=3` a statusline do Claude só aparece quando a janela está em foco; com `laststatus=0`, nunca.
- O token da aba fica no ambiente do processo do Claude e dos filhos dele.
- Recarregar os módulos do plugin com abas abertas não é suportado: o estado em memória se perde, e as abas antigas só fecham com o Neovim (a Fase 0 adotava o terminal único depois de um reload; com várias abas isso não compensa).
- Uma rejeição feita no `ExitPre` não volta atrás se a saída for cancelada por outro buffer modificado do usuário: o Claude já recebeu `DIFF_REJECTED`, e as sessões seguem.
- Duas abas que pedem diff com o mesmo `tab_name` seguem a regra de hoje entre clientes (o pedido novo substitui o pendente antigo).
- Com a conexão automática do CLI ligada pelo usuário (`autoConnectIde`, `--ide`, `CLAUDE_CODE_AUTO_CONNECT_IDE=1`), um claude externo pode se conectar sozinho a uma aba (regra 90); com o padrão do CLI, não.
- Dois Neovims na mesma pasta, com abas de mesmo número, aparecem iguais no `/ide` de um claude externo (regra 97).
- Quem usava `cwd`, `git_repo_cwd` ou `cwd_provider` perde essas opções: a aba sempre nasce no `:pwd` (regras 93 a 95).
- As funções de módulo do servidor ficam só para os testes.

## Testing

### Suítes

Nomes da tabela `Test suites` do `CLAUDE.md`: `check`, `unit`, `format`, `integration` (Neovim 0.12.3; `on-demand` no 0.12.0) e `all`. Gate por task (política da Fase 0): tasks de código rodam `check`, `unit` (`BUSTED_SEED=12345 CI=true mise run test`, timeout de pelo menos 1200 s, em segundo plano pelo harness), `format` e `integration` com o script inteiro; tasks só de docs rodam `format`; a Task 21 roda o gate final. Arquivo de integração isolado só com o ambiente do runner. Todo spec novo de integração termina em menos de 40 s (limite do runner) e usa `CLAUDE_CONFIG_DIR` e `HOME` temporários, nunca a pasta real do usuário. Specs de integração ficam `pending("needs a real Neovim")` sob o busted, como os de hoje.

Helpers novos em `tests/helpers/`: `ws_client.lua` (cliente WebSocket mínimo com `vim.uv` e `claudinho.server.frame`: handshake com token, frames mascarados, leitura de `selection_changed`/`at_mentioned`), `http_post.lua` (POST cru), `tab_env.lua` (cria `CLAUDE_CONFIG_DIR`, `HOME` e um comando de teste `sh -c '... ; exec sleep 30'` que grava o ambiente num arquivo).

### Testes novos e alterados por task

| Task | Arquivo                                                                                                                                                                                                                                                                                                                                                                                                                                   | Casos                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| ---- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 2    | `tests/unit/server/instances_spec.lua` (novo)                                                                                                                                                                                                                                                                                                                                                                                             | Duas instâncias: portas e tokens distintos; `broadcast` de uma não chega aos clientes da outra; `client.server_id` e `for_client`; `stop()` de uma mantém as respostas adiadas e os diffs pendentes da outra e remove só as próprias chaves; resposta adiada sai pela instância do cliente; funções de módulo seguem na instância padrão                                                                                                                                              |
|      | `tests/unit/server_spec.lua`, `tests/unit/server/*_spec.lua`, `tests/server_test.lua`                                                                                                                                                                                                                                                                                                                                                     | Ajustes de mock (`server_id`); comportamento igual                                                                                                                                                                                                                                                                                                                                                                                                                                    |
|      | `tests/integration/server_instances_spec.lua` (novo)                                                                                                                                                                                                                                                                                                                                                                                      | TCP real: dois servidores, um `ws_client` em cada; `broadcast` isolado; `initialize` e `tools/list` respondem nos dois                                                                                                                                                                                                                                                                                                                                                                |
| 3    | `tests/unit/server/http_spec.lua` (novo)                                                                                                                                                                                                                                                                                                                                                                                                  | `204` com token certo e `on_post(kind, body)` chamado; `401` sem token e com token errado (`on_post` não chamado); `404` caminho ou método desconhecido; `413` acima de 1 MiB; `400` sem `Content-Length` e cabeçalho acima de 8 KiB; corpo em vários pedaços; JSON inválido ainda `204`; cliente HTTP fora de `get_status().clients` e de `broadcast`                                                                                                                                |
|      | `tests/unit/server/handshake_spec.lua`                                                                                                                                                                                                                                                                                                                                                                                                    | `GET` com upgrade segue igual; `POST` não passa pelo handshake                                                                                                                                                                                                                                                                                                                                                                                                                        |
|      | `tests/integration/server_http_spec.lua` (novo)                                                                                                                                                                                                                                                                                                                                                                                           | POST real com `http_post`, resposta em menos de 100 ms, socket fechado                                                                                                                                                                                                                                                                                                                                                                                                                |
| 4    | `tests/lockfile_test.lua`                                                                                                                                                                                                                                                                                                                                                                                                                 | `ide_name` e `workspace_folders` gravados; padrões iguais aos de hoje; `get_workspace_folders(cwd)`                                                                                                                                                                                                                                                                                                                                                                                   |
|      | `tests/unit/session_settings_spec.lua` (novo)                                                                                                                                                                                                                                                                                                                                                                                             | JSON com exatamente `statusLine` e `hooks` (`SessionStart`, `UserPromptSubmit`, `Stop`), `async = true`, comando com `vim.v.progpath` e caminho do relay escapados (caminho com espaço e aspas); arquivo `0600` dentro de `tempname()`; `remove` apaga; nada fora da pasta temporária                                                                                                                                                                                                 |
|      | `tests/unit/sources/relay_spec.lua` (novo)                                                                                                                                                                                                                                                                                                                                                                                                | `build_request` (linha, cabeçalhos, `Content-Length` em bytes UTF-8); `kind` inválido; sem porta                                                                                                                                                                                                                                                                                                                                                                                      |
|      | `tests/integration/relay_spec.lua` (novo)                                                                                                                                                                                                                                                                                                                                                                                                 | `vim.system({ progpath, "--clean", "-l", relay, kind })` contra uma instância real: corpo chega com o token; `statusline` imprime `"\n"`; `hook` imprime nada; porta morta e porta sem servidor saem 0; `PATH` vazio funciona (só o binário absoluto); cada execução em menos de 2000 ms (o tempo medido vai para o log)                                                                                                                                                              |
| 5    | `tests/unit/sources/session_data_spec.lua` (novo)                                                                                                                                                                                                                                                                                                                                                                                         | Fixtures em `tests/fixtures/claude/*.json` (statusline com `display_name` `"Opus"` e `"Opus 5.5"`, sem `effort`, ids `claude-opus-5-5`, `claude-haiku-4-5-20251001`, `claude-3-5-haiku-20241022`, `us.anthropic...-v1:0`, `claude-opus-5[1m]`, id desconhecido; hooks `SessionStart` `clear`, `UserPromptSubmit`, `Stop`, evento desconhecido); campos com tipo errado; JSON inválido -> `nil` sem erro                                                                               |
|      | `tests/unit/ui/status_spec.lua` (novo)                                                                                                                                                                                                                                                                                                                                                                                                    | Ordem e separador; cada linha da tabela de modos; item ausente sem separador sobrando; vazio -> `""`; `%` escapado                                                                                                                                                                                                                                                                                                                                                                    |
|      | `tests/unit/ui/tabbar_spec.lua` (novo)                                                                                                                                                                                                                                                                                                                                                                                                    | `clean_title` com `✳ Fix login bug`, spinner braille, `✳ Claude Code`, `claude`, comando configurado, `term://...`, vazio; rótulo `1 Fix login bug ● diff`, `3 Refactor [exited]`; corte com `…` em 24; ordem crescente; `+` no fim; destaque da ativa; encolhimento até só números; janela pequena mantém ativa e `+` com `‹`/`›`; marcas nunca cortadas; clique `l` em aba e no `+`, outros botões ignorados                                                                        |
| 6    | `tests/unit/config_spec.lua`, `tests/config_test.lua`                                                                                                                                                                                                                                                                                                                                                                                     | Defaults novos; cada chave nova inválida cai no padrão com a mensagem de erro exata (`window.layout = "sidebar"` -> `right`, regra 88), sem `assert`; resto da config vale                                                                                                                                                                                                                                                                                                            |
|      | `tests/unit/notify_spec.lua` (novo)                                                                                                                                                                                                                                                                                                                                                                                                       | `info` só com `notify = true`; `once`; `reply` e `error` sempre; `title = "Claudinho"`                                                                                                                                                                                                                                                                                                                                                                                                |
| 7    | `tests/unit/mention_queue_spec.lua`                                                                                                                                                                                                                                                                                                                                                                                                       | Os casos de hoje sobre `Queue.new`; duas filas em servidores diferentes não se misturam                                                                                                                                                                                                                                                                                                                                                                                               |
|      | `tests/unit/at_mention_spec.lua`, `at_mention_edge_cases_spec.lua`, `init_spec.lua`, `send_complete_event_spec.lua`, demais da lista da Task 7                                                                                                                                                                                                                                                                                            | Só a origem da fila muda; asserções iguais                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| 8    | `tests/unit/session_spec.lua` (novo)                                                                                                                                                                                                                                                                                                                                                                                                      | Ordem de início e desfazer em cada falha (executável ausente, porta, lock, settings, `jobstart` com 0 e -1): nada sobra e a mensagem certa sai; comando montado com `--settings`; `extra_args`; `env` com as variáveis da tabela e `vim.env` intacto; `on_post` mescla sem apagar; fim do processo (estado, servidor, lock, settings, fila); `restart` com e sem `session_id`; `close` idempotente                                                                                    |
|      | `tests/integration/session_spec.lua` (novo)                                                                                                                                                                                                                                                                                                                                                                                               | Neovim real e comando de teste: o ambiente gravado pelo processo tem porta e token da aba e `vim.env.CLAUDINHO_PORT == nil`; lock file com `Neovim (Claudinho 1)` e `pid`; arquivo de settings existe e some no `close`; `TermClose` deixa o buffer válido mesmo com teclas enviadas                                                                                                                                                                                                  |
| 9    | `tests/unit/sessions_spec.lua` (novo)                                                                                                                                                                                                                                                                                                                                                                                                     | Menor número livre (1, 2, 3; fecha 2; nova = 2); cwd na criação e `:cd` depois não muda; `activate` reenvia a seleção; ativa depois de fechar (maior, senão menor; última fecha a janela); `next`/`prev` dão a volta; `restart` rodando e sem número; `router` só para a ativa rodando; `send_at_mention` sem abas cria a 1 e enfileira; aba encerrada responde; `on_post` atualiza só a própria aba; `kill_all` só toca abas próprias; `BufWipeout` fecha a aba                      |
|      | `tests/selection_test.lua`                                                                                                                                                                                                                                                                                                                                                                                                                | `enable(router)` no setup sem servidor; `is_claude_terminal_buffer` com `b:claudinho_session`; `resend_latest`                                                                                                                                                                                                                                                                                                                                                                        |
|      | `tests/integration/sessions_spec.lua` (novo)                                                                                                                                                                                                                                                                                                                                                                                              | Três abas reais com o comando de teste: portas, tokens e lock files distintos; `kill_all` deixa 0 jobs e 0 lock files                                                                                                                                                                                                                                                                                                                                                                 |
| 10   | `tests/unit/ui/window_geometry_spec.lua` (novo)                                                                                                                                                                                                                                                                                                                                                                                           | Tamanhos dos quatro layouts e do float centralizado para várias `columns`/`lines`                                                                                                                                                                                                                                                                                                                                                                                                     |
|      | `tests/integration/window_spec.lua` (novo)                                                                                                                                                                                                                                                                                                                                                                                                | Cada layout abre, tem winbar e statusline, foca em modo terminal; `toggle`/`open`/`hide`/`focus` (regras 19-22); `:q` e `<C-w>c` escondem e o PID não muda; troca de aba troca buffer e status no mesmo redraw; título por `TermRequest` (sequência OSC escrita pelo comando de teste) atualiza a winbar; `gt` e `open` em outra aba do Neovim; float escondido por `ClaudinhoDiffOpened` e `ensure_visible` não o traz; `:q` na última janela do editor sai do Neovim (Neovim filho) |
| 11   | `tests/unit/diff_routing_spec.lua` (novo)                                                                                                                                                                                                                                                                                                                                                                                                 | Cliente da ativa abre na hora; de aba em segundo plano espera, marca, notifica (com `notify`) e abre na ativação em ordem; `reject` devolve `DIFF_REJECTED`; descarte no fim do processo; `close-all-diffs` rejeita os pendentes de todas as abas                                                                                                                                                                                                                                     |
|      | `tests/unit/opendiff_blocking_spec.lua`, `tests/unit/diff_mcp_spec.lua`                                                                                                                                                                                                                                                                                                                                                                   | Sem abas (servidor padrão) igual a hoje                                                                                                                                                                                                                                                                                                                                                                                                                                               |
|      | `tests/integration/diff_routing_spec.lua` (novo)                                                                                                                                                                                                                                                                                                                                                                                          | Duas abas, um `ws_client` em cada: `openDiff` da aba 2 em segundo plano não abre; ao ativar, abre; aceitar com a aba 1 ativa responde só ao cliente da aba 2 (regras 31-34); `getOpenEditors` responde numa aba em segundo plano (regra 36)                                                                                                                                                                                                                                           |
| 12   | `tests/unit/commands_spec.lua` (novo)                                                                                                                                                                                                                                                                                                                                                                                                     | Cada linha da tabela de subcomandos, incluindo sem abas, número inexistente, uso errado, `layout` desconhecido, sem subcomando = `toggle`, `send-text!` e `:Claudinho!`, `select-model` nos três estados; completion (subcomandos, números, arquivos); `exists(':ClaudeCode') == 0` para os 17 nomes                                                                                                                                                                                  |
|      | `tests/unit/keymaps_spec.lua` (novo)                                                                                                                                                                                                                                                                                                                                                                                                      | Preset desligado não mapeia; ligado mapeia as 19 teclas com os comandos; tecla já mapeada fica e avisa (com `notify`)                                                                                                                                                                                                                                                                                                                                                                 |
|      | `tests/unit/terminal_facade_spec.lua` (novo); `tests/unit/terminal/send_text_spec.lua`                                                                                                                                                                                                                                                                                                                                                    | Fachada sobre a aba ativa; `send_to_terminal` com as regras de hoje (bracketed paste, CR, canal fechado) e sem abas                                                                                                                                                                                                                                                                                                                                                                   |
|      | `tests/unit/init_spec.lua`, `send_command_spec.lua`, `send_text_command_spec.lua`, `add_command_spec.lua`, `tree_send_visual_spec.lua`, `tree_buffer_classification_spec.lua`, `focus_after_send_spec.lua`, `visual_delay_timing_spec.lua`, `health_spec.lua`; `tests/integration/diff_hand_over_spec.lua`, `diff_window_sizes_spec.lua`, `diff_close_save_spec.lua`, `select_mode_send_spec.lua`, `diff_disconnect_window_lock_spec.lua` | Mesmos comportamentos pela API nova (`:Claudinho send`, `add`, ...); `setup` não cria servidor nem lock file (regra 2)                                                                                                                                                                                                                                                                                                                                                                |
| 13   | `tests/unit/removed_options_spec.lua`, `tests/integration/removed_options_spec.lua`                                                                                                                                                                                                                                                                                                                                                       | Cada linha nova com a mensagem exata, só com `notify = true`; `provider = "snacks"` dá um aviso só (o novo); as seis chaves de diretório (`terminal.cwd`, `terminal.git_repo_cwd`, `terminal.cwd_provider`, `cwd`, `git_repo_cwd`, `cwd_provider`) com a mensagem exata, e `init.setup` com elas não muda a pasta da aba nova, que continua o `getcwd()` (regras 93 e 94); `notify = false` não avisa e `removed_found` lista as chaves; linhas da Fase 0 iguais                      |
|      | `tests/unit/config_spec.lua`, `tests/config_test.lua`, `tests/unit/health_spec.lua`, specs `diff_*` que usam `terminal.split_width_percentage`                                                                                                                                                                                                                                                                                            | Defaults sem as chaves; WARN por chave no health; diff com `window.right.width`/`diff_width`, resize só no `right`                                                                                                                                                                                                                                                                                                                                                                    |
| 14   | `tests/unit/conflict_spec.lua`, `tests/unit/plugin_loader_spec.lua`, `tests/unit/health_spec.lua`, `tests/integration/loader_spec.lua`                                                                                                                                                                                                                                                                                                    | Detectado: `setup` configura tudo e cria `:Claudinho`; aviso uma vez só com `notify`; health WARN nos dois textos sem `setup`; loader segue para o auto-setup                                                                                                                                                                                                                                                                                                                         |
| 15   | `tests/integration/criteria_tabs_ws_spec.lua` (novo)                                                                                                                                                                                                                                                                                                                                                                                      | Critério 1 e regras 29, 30, 63: três abas, um `ws_client` em cada servidor; mover a seleção e `:Claudinho add` só chegam ao cliente da ativa; trocar de aba entrega a seleção atual à nova; um segundo cliente "externo" no servidor da aba 2 recebe a seleção quando a 2 está ativa e é desconectado no `tab-close 2`                                                                                                                                                                |
|      | `tests/integration/criteria_cycles_spec.lua` (novo)                                                                                                                                                                                                                                                                                                                                                                                       | Critério 2 (regra 87): 10 ciclos de `hide`/`open`, de `toggle` e de troca de aba, com `jobpid` de cada aba igual ao inicial e os três processos vivos                                                                                                                                                                                                                                                                                                                                 |
|      | `tests/integration/criteria_exit_spec.lua` (novo)                                                                                                                                                                                                                                                                                                                                                                                         | Critério 4 (regra 46), em Neovim filho com `CLAUDE_CONFIG_DIR` temporário: três abas e um diff pendente em segundo plano; `:qa`, `:wqa` e `:q` na última janela: saída 0 sem prompt, o cliente de teste recebe `DIFF_REJECTED` antes do fechamento, 0 processos do comando de teste vivos depois de 3 s, 0 arquivos em `<CLAUDE_CONFIG_DIR>/ide`, 0 arquivos de settings                                                                                                              |
|      | `tests/integration/criteria_isolation_spec.lua` (novo)                                                                                                                                                                                                                                                                                                                                                                                    | Critério 5 como o adendo (2) do plano o mede (regras 57, 61, 62 e 90): com o `claude` stub (`tests/bin/claude`), que não escreve nada, prova que o plugin não escreve; `settings.json`, `.claude.json` e `.claude/` de um `HOME` temporário com o mesmo SHA-256 antes e depois de abrir, usar e fechar três abas; um `:terminal` comum não tem `CLAUDE_CODE_SSE_PORT`, `CLAUDINHO_PORT`, `CLAUDINHO_TOKEN`; um lock file alheio na pasta continua lá depois do `kill-all`             |
| 16   | `tests/unit/provenance_spec.lua` (novo)                                                                                                                                                                                                                                                                                                                                                                                                   | Cada arquivo da tabela da seção 13 tem a linha exata na primeira linha; os módulos novos listados não têm                                                                                                                                                                                                                                                                                                                                                                             |

### Testes que saem

| Arquivo                                                                               | Task | Por quê                                                                    |
| ------------------------------------------------------------------------------------- | ---- | -------------------------------------------------------------------------- |
| `tests/unit/terminal_spec.lua`                                                        | 12   | Providers removidos; substituído por `terminal_facade_spec`                |
| `tests/unit/native_terminal_toggle_spec.lua`                                          | 12   | `terminal/native.lua` removido; coberto por `window_spec` e `session_spec` |
| `tests/unit/terminal/external_spec.lua`, `tests/unit/terminal/none_provider_spec.lua` | 12   | Providers `external` e `none` removidos (regra 64)                         |
| `tests/unit/focus_after_send_provider_warning_spec.lua`                               | 12   | `_maybe_warn_unfocusable_provider` removido                                |
| `tests/unit/command_args_spec.lua`, `tests/integration/command_args_spec.lua`         | 12   | Argumentos extras do `claude` nos comandos saem do escopo                  |
| `tests/unit/cwd_spec.lua`                                                             | 13   | `cwd.lua` removido (regra 95)                                              |

Nenhum teste é desligado nem marcado como pendente fora do padrão "needs a real Neovim".

### Regras do plano e testes

| Regra             | Coberta por                                                                                                  |
| ----------------- | ------------------------------------------------------------------------------------------------------------ |
| 1                 | `session_spec`, `sessions_spec` (integração), `criteria_tabs_ws_spec`                                        |
| 2                 | `init_spec` (setup sem servidor nem lock file)                                                               |
| 3                 | `session_spec` (unit e integração), `criteria_isolation_spec`                                                |
| 4, 5, 8           | `sessions_spec`                                                                                              |
| 6, 9-12, 14, 15   | `tabbar_spec`                                                                                                |
| 7                 | `lockfile_test`, `session_spec` (integração); roteiro manual 2 e 3                                           |
| 13, 16, 17, 19-24 | `window_spec`, `window_geometry_spec`                                                                        |
| 18, 85, 86, 88    | `config_spec`, `commands_spec` (`layout` desconhecido)                                                       |
| 25                | `window_spec`                                                                                                |
| 26-28             | `commands_spec`, `tabbar_spec` (clique), `sessions_spec`, `criteria_cycles_spec`                             |
| 29, 30            | `criteria_tabs_ws_spec`, `sessions_spec`                                                                     |
| 31-36             | `diff_routing_spec` (unit e integração)                                                                      |
| 37                | `sessions_spec`, `http_spec`                                                                                 |
| 38-45             | `sessions_spec`, `session_spec`, `commands_spec`                                                             |
| 46                | `criteria_exit_spec`                                                                                         |
| 47-52             | `session_data_spec`, `status_spec`, `window_spec`                                                            |
| 53, 58, 60        | `relay_spec` (unit e integração), `session_settings_spec`                                                    |
| 54                | `session_data_spec`, `http_spec`                                                                             |
| 55, 56            | `session_settings_spec`, `session_spec`; roteiro manual 4 (F1)                                               |
| 57                | `session_settings_spec`, `criteria_isolation_spec`; roteiro manual 10                                        |
| 59                | `http_spec`                                                                                                  |
| 61, 62            | `criteria_isolation_spec`, `sessions_spec`; roteiro manual 9 e 18                                            |
| 63                | `criteria_tabs_ws_spec`; roteiro manual 3                                                                    |
| 64-68             | `commands_spec`                                                                                              |
| 69                | `keymaps_spec`                                                                                               |
| 70                | `config_spec`                                                                                                |
| 71, 77, 84        | `removed_options_spec` (unit e integração)                                                                   |
| 72                | `provenance_spec`; checklist das docs                                                                        |
| 73-75             | `conflict_spec`, `health_spec`, `loader_spec`, `plugin_loader_spec`                                          |
| 76                | Ordem das tasks (14 depois de 12, mesma release)                                                             |
| 78, 79            | Checklist das docs; Task 22                                                                                  |
| 80-83, 89         | `notify_spec`, `commands_spec`, `health_spec`, `diff_routing_spec`, `keymaps_spec`                           |
| 87                | `criteria_cycles_spec`                                                                                       |
| 90, 91            | `criteria_tabs_ws_spec` (um cliente externo no servidor de uma aba é tratado como da aba); roteiro manual 18 |
| 92, 97            | Checklist das docs (Task 17)                                                                                 |
| 93-95             | `removed_options_spec`, `sessions_spec` (pasta na criação); comando de critério de `cwd.lua`                 |
| 96                | `lockfile_test`, `session_spec` (integração); roteiro manual 13                                              |

## Implementation order

### Pré-condição do /implement

Os agentes `lua`, `test-runner` e `docs-writer` existem (usados na Fase 0). As Open questions foram decididas em 2026-11-15 (adendo (2) do plano) e esta spec está `Approved`. Stacks fora da lista do template, como na Fase 0: `lua` para código, `docs-writer` para docs, `test-runner` para medição e gate, `usuário` para o que nenhum agente executa. Nenhuma task faz commit até a Task 22.

### Task 1 - Linha de base de testes e cobertura

- **Stack:** test-runner (sem código)
- **Files:** nenhum arquivo do repo (os números vão para `log.md`, escrito pelo `/implement`)
- **Depends on:** -
- **Done when:** o `log.md` registra, sobre o `HEAD` e com `BUSTED_SEED=12345 CI=true`: totais do `unit` (sucessos, falhas, erros, pendentes) e o tempo; warnings do `check`; cobertura total e por arquivo de `lua/claudinho/` e `plugin/` (`./.luarocks/bin/luacov` e `scripts/coverage-summary.sh luacov.report.out "$PWD"`); totais do `integration` no 0.12.3 (arquivos, passados); `claude --version`
- **Status:** done

### Task 2 - Servidor por instância

- **Stack:** lua
- **Files:** `lua/claudinho/server/init.lua`, `lua/claudinho/server/client.lua`, `lua/claudinho/server/tcp.lua`, `lua/claudinho/server/mock.lua`, `lua/claudinho/tools/init.lua`, `lua/claudinho/types.lua`, `tests/unit/server_spec.lua`, `tests/unit/server/**`, `tests/server_test.lua`, `tests/integration/server_instances_spec.lua`, `tests/helpers/ws_client.lua`, `tests/mocks/vim.lua`
- **Depends on:** Task 1
- **Done when:** a seção 1 (API de instância) está aplicada; `stop()` remove só as próprias respostas adiadas e rejeita só os diffs dos próprios clientes; `instances_spec` e `server_instances_spec` passam; os specs de servidor existentes passam sem mudar asserções de protocolo; `check`, `unit`, `format` e `integration` verdes
- **Status:** done

### Task 3 - Rotas HTTP de status e hooks

- **Stack:** lua
- **Files:** `lua/claudinho/server/http.lua`, `lua/claudinho/server/client.lua`, `lua/claudinho/server/tcp.lua`, `lua/claudinho/server/init.lua`, `lua/claudinho/server/handshake.lua`, `lua/claudinho/types.lua`, `tests/unit/server/**`, `tests/integration/server_http_spec.lua`, `tests/helpers/http_post.lua`
- **Depends on:** Task 2
- **Done when:** a tabela de rotas da seção 1 está aplicada; `http_spec`, `handshake_spec` e `server_http_spec` passam; um POST não aparece em `get_status().clients`; gate verde
- **Status:** done

### Task 4 - Lock file por aba, settings da sessão e relay

- **Stack:** lua
- **Files:** `lua/claudinho/lockfile.lua`, `lua/claudinho/session_settings.lua`, `lua/claudinho/sources/relay.lua`, `lua/claudinho/types.lua`, `tests/lockfile_test.lua`, `tests/unit/session_settings_spec.lua`, `tests/unit/sources/relay_spec.lua`, `tests/integration/relay_spec.lua`
- **Depends on:** Task 3
- **Done when:** a seção 2 está aplicada; `lockfile_test`, `session_settings_spec`, `relay_spec` (unit e integração) passam; o tempo médio do relay medido em `relay_spec` está no log; gate verde
- **Status:** done

### Task 5 - Dados da sessão, status e barra de abas (funções puras)

- **Stack:** lua
- **Files:** `lua/claudinho/sources/session_data.lua`, `lua/claudinho/ui/status.lua`, `lua/claudinho/ui/tabbar.lua`, `tests/unit/sources/session_data_spec.lua`, `tests/unit/ui/status_spec.lua`, `tests/unit/ui/tabbar_spec.lua`, `tests/fixtures/claude/*.json`
- **Depends on:** Task 1
- **Done when:** a seção 3 está aplicada sem estado global (render recebe tudo por argumento; a ligação às abas é da Task 10); os três specs passam; gate verde
- **Status:** done

### Task 6 - Config nova e notificações

- **Stack:** lua
- **Files:** `lua/claudinho/config.lua`, `lua/claudinho/notify.lua`, `lua/claudinho/types.lua`, `tests/unit/config_spec.lua`, `tests/config_test.lua`, `tests/unit/notify_spec.lua`, `tests/mocks/vim.lua`
- **Depends on:** Task 1
- **Done when:** as chaves novas da seção 4 existem com padrão e validação com queda no padrão e erro exato; `notify.lua` segue a tabela de classes; nenhuma chave antiga muda; `config_spec` e `notify_spec` passam; gate verde
- **Status:** done

### Task 7 - Fila de @-mentions por instância

- **Stack:** lua
- **Files:** `lua/claudinho/mention_queue.lua`, `lua/claudinho/init.lua`, `lua/claudinho/server/init.lua`, `lua/claudinho/types.lua`, `tests/unit/mention_queue_spec.lua`, `tests/unit/at_mention_spec.lua`, `tests/unit/at_mention_edge_cases_spec.lua`, `tests/unit/init_spec.lua`, `tests/unit/send_complete_event_spec.lua`, `tests/unit/focus_after_send_spec.lua`, `tests/unit/add_command_spec.lua`, `tests/unit/send_command_spec.lua`, `tests/unit/directory_at_mention_spec.lua`, `tests/unit/tree_send_visual_spec.lua`, `tests/unit/tree_buffer_classification_spec.lua`, `tests/selection_test.lua`
- **Depends on:** Task 2
- **Done when:** a seção 5 está aplicada, com a linha de origem em `mention_queue.lua`; o `init` usa uma fila ligada ao servidor padrão; os mesmos casos de hoje passam, mais o de duas filas isoladas; a contagem do `unit` é a da Task 2 mais os casos novos; gate verde
- **Status:** done

### Task 8 - Sessão: processo, servidor, lock file e settings

- **Stack:** lua
- **Files:** `lua/claudinho/session.lua`, `lua/claudinho/types.lua`, `tests/unit/session_spec.lua`, `tests/integration/session_spec.lua`, `tests/helpers/tab_env.lua`, `tests/mocks/vim.lua`
- **Depends on:** Task 4, Task 5, Task 7
- **Done when:** a seção 6 está aplicada, com a linha de origem; `session_spec` (unit e integração) passa; nenhum comando usa a sessão ainda; gate verde
- **Status:** done

### Task 9 - Abas: registro, aba ativa, roteamento e encerramento

- **Stack:** lua
- **Files:** `lua/claudinho/sessions.lua`, `lua/claudinho/selection.lua`, `lua/claudinho/types.lua`, `tests/unit/sessions_spec.lua`, `tests/selection_test.lua`, `tests/integration/sessions_spec.lua`, `tests/helpers/**`, `tests/mocks/vim.lua`
- **Depends on:** Task 6, Task 8
- **Done when:** a tabela da seção 7 está aplicada, incluindo `setup_autocmds` (ainda não chamado pelo `init`) e o `router`; `selection.lua` aceita o router e reconhece `b:claudinho_session` sem mudar o comportamento atual; `sessions_spec` (unit e integração) e `selection_test` passam; gate verde
- **Status:** done

### Task 10 - Janela do Claude: layouts, winbar e statusline

- **Stack:** lua
- **Files:** `lua/claudinho/ui/window.lua`, `lua/claudinho/ui/tabbar.lua`, `lua/claudinho/ui/status.lua`, `lua/claudinho/sessions.lua`, `lua/claudinho/types.lua`, `tests/unit/ui/**`, `tests/integration/window_spec.lua`, `tests/helpers/**`, `tests/mocks/vim.lua`
- **Depends on:** Task 9
- **Done when:** a seção 8 está aplicada, com a linha de origem em `ui/window.lua`; `sessions.new` e `activate` usam a janela; `window_geometry_spec` e `window_spec` passam; gate verde
- **Status:** done

### Task 11 - Diff por aba

- **Stack:** lua
- **Files:** `lua/claudinho/tools/open_diff.lua`, `lua/claudinho/diff.lua`, `lua/claudinho/sessions.lua`, `lua/claudinho/types.lua`, `tests/unit/diff_routing_spec.lua`, `tests/unit/opendiff_blocking_spec.lua`, `tests/unit/diff_mcp_spec.lua`, `tests/integration/diff_routing_spec.lua`, `tests/helpers/**`
- **Depends on:** Task 10
- **Done when:** a seção 9 está aplicada; `diff_routing_spec` (unit e integração) passa e os specs de diff existentes passam sem mudança de asserção; gate verde
- **Status:** done

### Task 12 - Comando `:Claudinho` e fim dos `:ClaudeCode*` e dos providers

- **Stack:** lua
- **Files:** `lua/claudinho/init.lua`, `lua/claudinho/commands.lua`, `lua/claudinho/terminal.lua`, `lua/claudinho/terminal/native.lua`, `lua/claudinho/terminal/external.lua`, `lua/claudinho/terminal/none.lua`, `lua/claudinho/terminal/owned.lua`, `lua/claudinho/selection.lua`, `lua/claudinho/visual_commands.lua`, `lua/claudinho/sessions.lua`, `lua/claudinho/ui/window.lua`, `lua/claudinho/health.lua`, `lua/claudinho/types.lua`, `plugin/claudinho.lua`, `tests/unit/init_spec.lua`, `tests/unit/commands_spec.lua`, `tests/unit/keymaps_spec.lua`, `tests/unit/terminal_facade_spec.lua`, `tests/unit/terminal_spec.lua`, `tests/unit/native_terminal_toggle_spec.lua`, `tests/unit/terminal/**`, `tests/unit/focus_after_send_provider_warning_spec.lua`, `tests/unit/focus_after_send_spec.lua`, `tests/unit/command_args_spec.lua`, `tests/unit/send_command_spec.lua`, `tests/unit/send_text_command_spec.lua`, `tests/unit/add_command_spec.lua`, `tests/unit/tree_send_visual_spec.lua`, `tests/unit/tree_buffer_classification_spec.lua`, `tests/unit/send_complete_event_spec.lua`, `tests/unit/at_mention_spec.lua`, `tests/unit/at_mention_edge_cases_spec.lua`, `tests/unit/mention_queue_spec.lua`, `tests/unit/directory_at_mention_spec.lua`, `tests/unit/visual_delay_timing_spec.lua`, `tests/unit/health_spec.lua`, `tests/selection_test.lua`, `tests/integration/command_args_spec.lua`, `tests/integration/diff_hand_over_spec.lua`, `tests/integration/diff_window_sizes_spec.lua`, `tests/integration/diff_close_save_spec.lua`, `tests/integration/select_mode_send_spec.lua`, `tests/integration/diff_disconnect_window_lock_spec.lua`, `tests/integration/mcp_tools_spec.lua`, `tests/helpers/**`, `tests/mocks/vim.lua`, `fixtures/netrw/lua/plugins/dev-claudinho.lua`, `fixtures/nvim-tree/lua/plugins/dev-claudinho.lua`, `fixtures/oil/lua/plugins/dev-claudinho.lua`, `fixtures/mini-files/lua/plugins/dev-claudinho.lua`, `fixtures/repro/**`, `scripts/manual_test_helper.lua`, `CHANGELOG.md`
- **Depends on:** Task 11
- **Done when:** a seção 10 está aplicada, com a linha de origem em `commands.lua`; os quatro arquivos de provider não existem; `rg -n 'ClaudeCode' lua plugin fixtures scripts` só acha as exceções da Verificação; `commands_spec`, `keymaps_spec`, `terminal_facade_spec` e os specs portados passam; os specs da tabela "Testes que saem" da Task 12 foram apagados e a queda na contagem é só deles; o `CHANGELOG.md` tem as entradas da troca em `## [Unreleased]`; gate verde
- **Status:** done

### Task 13 - Chaves removidas (terminal e diretório), cwd.lua e tamanhos da janela no diff

- **Stack:** lua
- **Files:** `lua/claudinho/config.lua`, `lua/claudinho/init.lua`, `lua/claudinho/diff.lua`, `lua/claudinho/terminal.lua`, `lua/claudinho/health.lua`, `lua/claudinho/types.lua`, `lua/claudinho/cwd.lua`, `tests/unit/config_spec.lua`, `tests/config_test.lua`, `tests/unit/removed_options_spec.lua`, `tests/integration/removed_options_spec.lua`, `tests/unit/health_spec.lua`, `tests/unit/cwd_spec.lua`, `tests/unit/init_spec.lua`, `tests/unit/diff_*_spec.lua`, `tests/integration/diff_*_spec.lua`, `fixtures/netrw/lua/plugins/dev-claudinho.lua`, `fixtures/nvim-tree/lua/plugins/dev-claudinho.lua`, `fixtures/oil/lua/plugins/dev-claudinho.lua`, `fixtures/mini-files/lua/plugins/dev-claudinho.lua`, `fixtures/repro/**`, `CHANGELOG.md`
- **Depends on:** Task 12
- **Done when:** a tabela de chaves removidas da seção 4 está aplicada, com as seis chaves de diretório (regras 93 e 94), o aviso só sai com `notify`, o health mostra cada chave; `diff.lua` lê `config.window`; `cwd.lua` e `tests/unit/cwd_spec.lua` não existem (regra 95) e `rg -n 'git_repo_cwd|cwd_provider' lua plugin` só acha as linhas de chave removida em `config.lua`; os specs listados passam; entradas no `## [Unreleased]`; gate verde
- **Status:** pending

### Task 14 - claudecode.nvim vira aviso

- **Stack:** lua
- **Files:** `lua/claudinho/conflict.lua`, `plugin/claudinho.lua`, `lua/claudinho/init.lua`, `lua/claudinho/health.lua`, `tests/unit/conflict_spec.lua`, `tests/unit/plugin_loader_spec.lua`, `tests/unit/health_spec.lua`, `tests/integration/loader_spec.lua`, `CHANGELOG.md`
- **Depends on:** Task 12
- **Done when:** a seção 11 está aplicada; com o claudecode.nvim falso do `loader_spec` no runtimepath, `:Claudinho` existe e o aviso aparece uma vez só com `notify = true`; o health mostra WARN; os quatro specs passam; entrada no `## [Unreleased]`; gate verde
- **Status:** pending

### Task 15 - Critérios de sucesso como testes de integração

- **Stack:** lua
- **Files:** `tests/integration/criteria_tabs_ws_spec.lua`, `tests/integration/criteria_cycles_spec.lua`, `tests/integration/criteria_exit_spec.lua`, `tests/integration/criteria_isolation_spec.lua`, `tests/helpers/**`
- **Depends on:** Task 13, Task 14
- **Done when:** o `criteria_isolation_spec` mede "nada muda fora das sessões do plugin" com o `claude` stub, como o adendo (2) do plano define; os quatro specs da tabela de Testing passam no 0.12.3, cada um em menos de 40 s; um defeito de código achado aqui vira pedido de escopo registrado no log, não mudança silenciosa; gate verde
- **Status:** pending

### Task 16 - Linhas de origem nos módulos

- **Stack:** lua
- **Files:** `lua/claudinho/**/*.lua`, `plugin/claudinho.lua`, `tests/unit/provenance_spec.lua`
- **Depends on:** Task 15
- **Done when:** a seção 13 está aplicada, só com a linha de comentário (nenhuma outra mudança de código: `git diff` de cada arquivo tem uma linha adicionada); `provenance_spec` passa; gate verde
- **Status:** pending

### Task 17 - README.md e README.en.md

- **Stack:** docs-writer
- **Files:** `README.md`, `README.en.md`
- **Depends on:** Task 16
- **Done when:** a linha de READMEs da seção 14 está aplicada nas duas línguas, com as mesmas seções, incluindo as notas das regras 92 (conexão automática e `CLAUDE_CODE_AUTO_CONNECT_IDE=0`) e 97 (linhas iguais no `/ide`) e as seis chaves de diretório fora da configuração e listadas entre as removidas (regra 95); todo subcomando, chave e padrão citado bate com `commands.lua` e `config.lua`; a atribuição ao upstream continua; sem travessão; `format` verde
- **Status:** pending

### Task 18 - CLAUDE.md

- **Stack:** docs-writer
- **Files:** `CLAUDE.md`
- **Depends on:** Task 16
- **Done when:** a linha de `CLAUDE.md` da seção 14 está aplicada; nenhum caminho citado deixou de existir; `## Test suites` e `## Workflow` iguais; `format` verde
- **Status:** pending

### Task 19 - CHANGELOG.md e conferência do LICENSE

- **Stack:** docs-writer
- **Files:** `CHANGELOG.md`
- **Depends on:** Task 16
- **Done when:** `## [Unreleased]` tem Added (abas, janela e layouts, status, `:Claudinho`, preset, `notify`), Changed (um servidor e lock file por aba, `ideName`, claudecode.nvim só aviso, `--settings` por sessão) e Removed (`:ClaudeCode*`, providers, chaves da seção 4), em inglês; a linha do hard fork continua; o `LICENSE` tem o aviso da Coder e a linha do fork, sem mudança; `format` verde
- **Status:** pending

### Task 20 - PROTOCOL.md e ARCHITECTURE.md

- **Stack:** docs-writer
- **Files:** `PROTOCOL.md`, `ARCHITECTURE.md`
- **Depends on:** Task 16
- **Done when:** a linha de `PROTOCOL.md`/`ARCHITECTURE.md` da seção 14 está aplicada; o texto do upstream fora da nota e da seção nova não muda; `format` verde
- **Status:** pending

### Task 21 - Verificação final e medição

- **Stack:** test-runner (sem código), com o roteiro manual feito pelo usuário
- **Files:** nenhum arquivo do repo (resultados no `log.md`)
- **Depends on:** Task 17, Task 18, Task 19, Task 20
- **Done when:** `all` verde; `integration` verde no 0.12.3 e no 0.12.0 (`on-demand`), com o plenary no SHA do CI; os comandos de critério da Verificação só mostram as exceções; o log tem a tabela antes/depois (testes por estado, cobertura total e por arquivo, tempo do relay) explicando cada diferença pelos testes novos e pelos de "Testes que saem"; o usuário fez o roteiro manual inteiro e o resultado de cada passo está no log; `git status docs/backlog` sem entrada nova
- **Status:** pending

### Task 22 - Fechamento: release 0.2.0

- **Stack:** usuário (a sessão principal só roda cada comando com autorização explícita no momento)
- **Files:** `docs/features/base-ui/plan.md`, `docs/features/base-ui/spec.md`, `docs/features/README.md`, `VERSION`, `CHANGELOG.md`
- **Depends on:** Task 21
- **Done when:** o trabalho da feature está commitado no `main` com autorização do usuário (mensagens Conventional Commits); plano e spec em `Implemented` e o Index atualizado, também commitados; `mise run release minor --dry-run` mostra `0.2.0`; `mise run release minor` gravou `0.2.0` no `VERSION`, transformou o Unreleased em `## [0.2.0] - <data>`, fez o commit `chore(release): 0.2.0` e criou a tag local `v0.2.0`; o push (`git push origin main v0.2.0`) fica com o usuário (regras 78 e 79)
- **Status:** pending

## Verification

### Suítes ao fim

`check`, `unit`, `format`, `integration` (0.12.3) e o `on-demand` `integration` no 0.12.0 (`mise exec neovim@0.12.0 -- ./scripts/run_integration_tests_individually.sh`), depois `all`.

### Comandos de critério (sessão principal, só leitura)

```sh
# Nenhum :ClaudeCode* fora de docs, CHANGELOG, READMEs e dos textos de migração
rg -n 'ClaudeCode' lua plugin fixtures scripts tests | rg -v 'conflict|loader_spec|provenance_spec|removed_options|commands_spec'
# Providers e servidor global fora do plugin
test -e lua/claudinho/terminal/native.lua -o -e lua/claudinho/terminal/external.lua -o -e lua/claudinho/terminal/none.lua -o -e lua/claudinho/terminal/owned.lua && echo "PROVIDER AINDA EXISTE"
test -e lua/claudinho/cwd.lua -o -e tests/unit/cwd_spec.lua && echo "CWD.LUA AINDA EXISTE"
rg -n 'require\("claudinho\.server\.init"\)\.(start|stop|broadcast|get_status|state)' lua | rg -v '^lua/claudinho/server/'
# Variáveis da sessão nunca no ambiente do Neovim
rg -n 'vim\.env\.(CLAUDE_CODE_SSE_PORT|CLAUDINHO_)|setenv' lua
# O plugin não escreve em ~/.claude nem em .claude/ do projeto (só lock file em lockfile.lua)
rg -n 'settings\.json|\.claude\.json|"\.claude/' lua
# Linhas de origem
rg -c '^-- Origin: coder/claudecode.nvim@d1237072, ' lua plugin | wc -l
# Travessão nas docs e no código
rg -n '\x{2014}' README.md README.en.md CHANGELOG.md CLAUDE.md PROTOCOL.md ARCHITECTURE.md lua docs/features/base-ui
```

Exceções esperadas do primeiro comando: as mensagens de chave removida que citam o `terminal.provider`, o texto do conflito e os specs de migração; nada de `nvim_create_user_command("ClaudeCode...`.

### Checklist das docs (Tasks 17 a 20)

Primeira linha de cada README aponta para o outro; mesmas seções nas duas línguas; uso com `:Claudinho`; tabela de subcomandos igual à do `commands.lua`; chaves `window`, `keymaps`, `notify` com padrões do `config.lua`; limitações (modo, rodapé, confiança da pasta, hooks desligados, `laststatus`); conexão automática do CLI e `CLAUDE_CODE_AUTO_CONNECT_IDE=0` (regra 92); dois Neovims no `/ide` (regra 97); opções de diretório só entre as chaves removidas (regra 95); "Vindo do claudecode.nvim" com "os dois rodam, mas o recomendado é remover", tabela de comandos e chaves removidas; `CHANGELOG.md` em inglês com o Unreleased completo; `PROTOCOL.md` e `ARCHITECTURE.md` com a nota e a seção curta; `LICENSE` intacto; linha de origem nos módulos (regra 72).

### Roteiro manual do usuário

Feito pelo usuário no Neovim 0.12.3 do mise, com o `claude` real (2.1.325 ou mais novo), numa config de teste com `require("claudinho").setup({ notify = true })`. Cada resultado vai para o log da Task 21.

1. `:checkhealth claudinho`: OK do setup, `No Claude tabs open`; sem claudecode.nvim, nenhum WARN de conflito. `ls ~/.claude/ide` não tem lock novo (regra 2).
2. `:Claudinho` abre a janela à direita com a aba 1; `:Claudinho new` duas vezes. Winbar `1 ... │ 2 ... │ 3 ... │ +`; clique em cada aba e no `+`; `cat ~/.claude/ide/*.lock` mostra `Neovim (Claudinho 1)`, `2`, `3` com portas diferentes.
3. Num terminal fora do Neovim, na mesma pasta: `claude`, depois `/ide`. Aparecem as três entradas pelo nome; conectar na 2; selecionar texto no Neovim com a aba 1 ativa (o claude externo não recebe), ativar a aba 2 (recebe). `:Claudinho tab-close 2`: o externo desconecta e segue rodando (regras 7, 62, 63).
4. Statusline da janela mostra `<modelo> · <esforço>` logo no início e o modo depois do primeiro prompt; a TUI não mostra linha de status própria. `shift+tab` e um prompt: o modo muda. Anotar o `model.display_name` real (com ou sem versão).
5. Títulos: `:echo b:term_title` no buffer de uma aba parada e trabalhando; anotar os valores reais para as fixtures do `tabbar_spec`.
6. Diff em segundo plano: pedir uma mudança na aba 3 e trocar para a 1 antes do diff; aparece `● diff` e a notificação; ativar a 3 abre o diff; aceitar com a 1 ativa responde à 3.
7. `/clear` na aba 1, depois `/exit`: aparece `[exited]` e `Claude 1 exited`; `:Claudinho tab-restart 1` abre a conversa de depois do `/clear` (F8).
8. `/cd ..` (ou outra pasta) na aba 1, `/exit`, `:Claudinho tab-restart 1`: a conversa volta, iniciada na pasta original da aba (F8).
9. Num `:terminal` comum: `env | grep -E 'CLAUDE_CODE_SSE_PORT|CLAUDINHO'` não mostra nada (regra 62).
10. Com o CLI real, só `~/.claude/settings.json` e `.claude/` do projeto (critério do adendo (2) do plano): `sha256sum ~/.claude/settings.json` e `find .claude -type f -exec sha256sum {} +` antes e depois dos passos 2 a 8, sem mudar settings pela TUI: iguais. `~/.claude.json` fica fora, porque o próprio CLI o regrava a cada início (F10); que o plugin não o escreve é o `criteria_isolation_spec` com o stub que prova.
11. Uma aba pede diff e fica pendente; `:qa`: nenhuma pergunta; `pgrep -af 'claude --settings'` vazio depois de 3 s; nenhum lock `Neovim (Claudinho` em `~/.claude/ide` (regra 46).
12. `kill -9` num Neovim com uma aba: o lock fica; abrir uma aba em outro Neovim e `ls ~/.claude/ide`: o lock velho sumiu (F7).
13. Dois Neovims em pastas diferentes, cada um com uma aba 1, e `/ide` num claude externo numa pasta que contém as duas: as duas entradas aparecem como `Neovim (Claudinho 1)`, com a pasta de cada uma (F5, regra 96); com os dois Neovims na mesma pasta, as linhas ficam iguais (aceito, regra 97).
14. Layouts: `window.layout = "bottom"`, `"float"`, `"tab"` na config e reinício; no float, um diff esconde a janela e `:Claudinho open` a traz; `:Claudinho layout` dá o erro de subcomando desconhecido.
15. `:set mouse=` e clique na winbar: nada; janela estreita (`:vertical resize 30`): títulos encolhem, ativa e `+` ficam.
16. Preset: `keymaps = { preset = true }` com `<leader>ac` já mapeado por você: as outras teclas funcionam e `<leader>ac` continua o seu.
17. Pasta nova, ainda sem confiança: status vazio até aceitar o diálogo de confiança (F2).
18. Conexão automática (regras 90 a 92): num terminal externo, numa pasta que só a aba 1 contém, `CLAUDE_CODE_AUTO_CONNECT_IDE=1 claude` se conecta sozinho a ela e recebe a seleção quando ela está ativa (regra 91); `CLAUDE_CODE_AUTO_CONNECT_IDE=0 claude` e um `claude` sem nenhuma das opções não se conectam.

## Open questions

Nenhuma em aberto. As cinco perguntas da primeira versão desta spec foram decididas pelo usuário em 2026-11-15, todas com a recomendação, e registradas no [adendo (2) do plano](plan.md#addendum-2026-11-15-2-revisão-da-spec):

| #   | Pergunta                                                     | Decisão                                                                                                                       | Onde está nesta spec                                                                    |
| --- | ------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| 1   | `autoConnectIde` conecta um claude externo sozinho a uma aba | Aceitar e documentar; nada muda no código (regras 90 a 92)                                                                    | Seção 2 "Conexão automática do CLI", seção 14, Alternatives, Task 17, roteiro manual 18 |
| 2   | Opções de diretório                                          | Removidas com aviso; `cwd.lua` e os testes dele saem (regras 93 a 95)                                                         | Seção 4, Testing (Task 13), Task 13, Task 17                                            |
| 3   | Dois Neovims na mesma pasta, cada um com uma aba 1           | `ideName` sem acréscimo; linhas iguais aceitas e documentadas (regras 96 e 97)                                                | Seção 2, seção 14, Task 17, roteiro manual 13                                           |
| 4   | Critério "nada muda fora das sessões" com o CLI real         | O `claude` stub prova que o plugin não escreve; o roteiro manual confere só `~/.claude/settings.json` e `.claude/` do projeto | `criteria_isolation_spec`, Task 15, roteiro manual 10                                   |
| 5   | Duas regras 85 no adendo de 2026-11-15                       | A da seção 5 é a regra 89; as de layout ficam 85 a 88 (errata do adendo (2))                                                  | Background                                                                              |
