--- A server is an instance: two of them run side by side with their own port, token, clients and deferred answers, and
--- stopping one leaves the other's state alone. The module-level functions still serve the default instance.
require("tests.busted_setup")

describe("Server instances", function()
  local server, tcp, closed, saved
  local config = { port_range = { min = 10000, max = 65535 } }

  local function upgrade(token)
    return "GET / HTTP/1.1\r\nHost: 127.0.0.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
      .. "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n"
      .. "x-claude-code-ide-authorization: "
      .. token
      .. "\r\n\r\n"
  end

  before_each(function()
    for _, name in ipairs({
      "claudinho.server.handshake",
      "claudinho.server.client",
      "claudinho.server.tcp",
      "claudinho.server.init",
    }) do
      package.loaded[name] = nil
    end
    closed = {}
    saved = { diff = package.loaded["claudinho.diff"], deferred = _G.claudinho_deferred_responses }
    _G.claudinho_deferred_responses = nil
    package.loaded["claudinho.diff"] = {
      close_diffs_for_client = function(client_id, reason)
        table.insert(closed, { client_id, reason })
      end,
      close_pending_diffs = function()
        error("stop() must not reject the diffs of other servers")
      end,
    }
    tcp = require("claudinho.server.tcp")
    server = require("claudinho.server.init")
  end)

  after_each(function()
    package.loaded["claudinho.diff"] = saved.diff
    _G.claudinho_deferred_responses = saved.deferred
  end)

  ---Accept a connection on the instance and finish its handshake.
  ---@return table client, string[] written The client and the raw writes to its socket
  local function connect(instance, token)
    tcp._handle_new_connection(instance.tcp)
    local client = assert(instance.tcp.clients["client_" .. _G.claudinho_clients_created])
    local handle, closing, written = client.tcp_handle, false, {}
    function handle:write(data, callback)
      table.insert(written, data)
      if callback then
        callback()
      end
    end
    function handle:close()
      closing = true
    end
    function handle:is_closing()
      return closing
    end
    handle._read_cb(nil, upgrade(token))
    assert.equals("connected", client.state)
    for i = #written, 1, -1 do
      written[i] = nil
    end
    return client, written
  end

  local function start_two()
    local a = server.new()
    local b = server.new()
    assert(a:start(config, "token-a-0123456789"))
    assert(b:start(config, "token-b-0123456789"))
    return a, b
  end

  it("gives each instance its own id, port and token", function()
    local a, b = start_two()

    assert.are_not.equal(a.id, b.id)
    assert.are_not.equal(a.port, b.port)
    assert.are_not.equal(a.auth_token, b.auth_token)
    assert.equals("token-a-0123456789", a.tcp.auth_token)
    assert.equals("token-b-0123456789", b.tcp.auth_token)

    a:stop()
    b:stop()
  end)

  it("keeps a broadcast of one instance away from the clients of the other", function()
    local a, b = start_two()
    local _, written_a = connect(a, "token-a-0123456789")
    local _, written_b = connect(b, "token-b-0123456789")

    assert.is_true(a:broadcast("only/a", { n = 1 }))

    assert.equals(1, #written_a)
    assert.equals(0, #written_b)
    assert.is_truthy(written_a[1]:find("only/a", 1, true))

    a:stop()
    b:stop()
  end)

  it("marks each client with its instance and finds the instance by that mark", function()
    local a, b = start_two()
    local client_a = connect(a, "token-a-0123456789")
    local client_b = connect(b, "token-b-0123456789")

    assert.equals(a.id, client_a.server_id)
    assert.equals(b.id, client_b.server_id)
    assert.equals(a, server.for_client(client_a))
    assert.equals(b, server.for_client(client_b))
    assert.is_nil(server.for_client({ id = "x" }))
    assert.is_nil(server.for_client(nil))

    a:stop()
    assert.is_nil(server.for_client(client_a))
    assert.equals(b, server.for_client(client_b))
    b:stop()
  end)

  it("lists only its own clients in the status", function()
    local a, b = start_two()
    connect(a, "token-a-0123456789")

    assert.equals(1, a:get_status().client_count)
    assert.equals(0, b:get_status().client_count)
    assert.is_true(a:get_status().running)

    a:stop()
    assert.is_false(a:get_status().running)
    b:stop()
  end)

  describe("stop()", function()
    local function defer(instance, client, id)
      local co = coroutine.create(function() end)
      instance:_setup_deferred_response({ client = client, id = id, coroutine = co })
      return tostring(co)
    end

    it("removes only its own deferred responses", function()
      local a, b = start_two()
      local client_a = connect(a, "token-a-0123456789")
      local client_b = connect(b, "token-b-0123456789")
      local key_a = defer(a, client_a, 1)
      local key_b = defer(b, client_b, 2)
      assert.is_function(_G.claudinho_deferred_responses[key_a])
      assert.is_function(_G.claudinho_deferred_responses[key_b])

      a:stop()

      assert.is_nil(_G.claudinho_deferred_responses[key_a])
      assert.is_function(_G.claudinho_deferred_responses[key_b])
      b:stop()
      assert.is_nil(_G.claudinho_deferred_responses[key_b])
    end)

    it("rejects only the diffs of its own clients", function()
      local a, b = start_two()
      local client_a = connect(a, "token-a-0123456789")
      connect(b, "token-b-0123456789")

      a:stop()

      assert.same({ { client_a.id, "server stopping" } }, closed)
      b:stop()
    end)

    it("does not touch the diffs of a client that never finished its handshake", function()
      local a = server.new()
      assert(a:start(config, "token-a-0123456789"))
      tcp._handle_new_connection(a.tcp)

      a:stop()

      assert.same({}, closed)
    end)

    it("reports a stopped instance and starts again", function()
      local a = server.new()
      assert(a:start(config, "token-a-0123456789"))
      assert.is_false(select(1, a:start(config, "token-a-0123456789")))
      assert.is_true(a:stop())
      assert.same({ false, "Server not running" }, { a:stop() })
      assert(a:start(config, "token-a-0123456789"))
      a:stop()
    end)
  end)

  it("answers a deferred call through the instance that took it", function()
    local a, b = start_two()
    local client_a, written_a = connect(a, "token-a-0123456789")
    local _, written_b = connect(b, "token-b-0123456789")

    local co = coroutine.create(function() end)
    local key = tostring(co)
    a:_setup_deferred_response({ client = client_a, id = 7, coroutine = co })
    _G.claudinho_deferred_responses[key]({ content = { { type = "text", text = "FILE_SAVED" } } })

    assert.equals(1, #written_a)
    assert.equals(0, #written_b)
    assert.is_nil(a.deferred[key])

    a:stop()
    b:stop()
  end)

  it("keeps the module functions on a default instance", function()
    assert.is_nil(server.state.server)
    assert.is_true(server.start(config, "token-d-0123456789"))
    assert.is_table(server.state.server)
    assert.equals("token-d-0123456789", server.state.auth_token)
    assert.is_function(server.state.handlers["initialize"])
    assert.is_true(server.get_status().running)

    local other = server.new()
    assert(other:start(config, "token-o-0123456789"))
    assert.is_true(server.get_status().running)
    assert.are_not.equal(server.state.port, other.port)
    other:stop()
    assert.is_true(server.get_status().running)

    assert.is_true(server.stop())
    assert.is_nil(server.state.server)
    assert.is_false(server.get_status().running)
  end)

  it("sends the answers of the default instance through the module functions", function()
    local sent = {}
    local original = server.send_response
    server.send_response = function(_, id)
      table.insert(sent, id)
      return true
    end
    server.register_handlers()
    server._handle_request({ id = "c" }, { jsonrpc = "2.0", id = 5, method = "prompts/list" })
    server.send_response = original

    assert.same({ 5 }, sent)
  end)
end)
