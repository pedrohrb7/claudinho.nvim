--- The HTTP POST routes of the server: the token check, the answers, the limits and the fact that a POST client never
--- becomes a WebSocket client. They run the real tcp.lua, client.lua and http.lua against a fake socket.
require("tests.busted_setup")

describe("Server HTTP routes", function()
  local tcp, server, posts
  local token = "http-token-0123456789"

  before_each(function()
    for _, name in ipairs({ "claudinho.server.client", "claudinho.server.http", "claudinho.server.tcp" }) do
      package.loaded[name] = nil
    end
    tcp = require("claudinho.server.tcp")
    posts = {}
    local err
    server, err = tcp.create_server({ port_range = { min = 10000, max = 65535 } }, {
      on_post = function(kind, body)
        table.insert(posts, { kind = kind, body = body })
      end,
    }, token)
    assert(server, err)
  end)

  after_each(function()
    tcp.stop_server(server)
  end)

  ---Accept a connection with a socket that records its writes and closes.
  ---@return table client
  ---@return table handle writes in `handle.writes`, `handle.closed`
  local function connect()
    tcp._handle_new_connection(server)
    local client = assert(server.clients["client_" .. _G.claudinho_clients_created])
    local handle = client.tcp_handle
    handle.writes, handle.closed = {}, false
    function handle:write(data, callback)
      table.insert(self.writes, data)
      if callback then
        callback()
      end
      return true
    end
    function handle:get_write_queue_size()
      return 0
    end
    function handle:close()
      assert(not self.closed, "handle is already closing")
      self.closed = true
    end
    function handle:is_closing()
      return self.closed
    end
    return client, handle
  end

  ---@param path string
  ---@param body string|nil
  ---@param opts { token: string|nil|false, length: string|number|false|nil }|nil
  local function request(path, body, opts)
    opts = opts or {}
    body = body or ""
    local lines = { "POST " .. path .. " HTTP/1.1", "Host: 127.0.0.1" }
    local sent = opts.token
    if sent == nil then
      sent = token
    end
    if sent then
      table.insert(lines, "X-Claudinho-Token: " .. sent)
    end
    table.insert(lines, "Content-Type: application/json")
    if opts.length ~= false then
      table.insert(lines, "Content-Length: " .. (opts.length or #body))
    end
    return table.concat(lines, "\r\n") .. "\r\n\r\n" .. body
  end

  local function status_of(handle)
    return tonumber((handle.writes[1] or ""):match("^HTTP/1%.1 (%d+)"))
  end

  describe("routes", function()
    for _, route in ipairs({ { "/claudinho/statusline", "statusline" }, { "/claudinho/hook", "hook" } }) do
      local path, kind = route[1], route[2]
      it("answers 204 on " .. path .. " and passes the body to on_post", function()
        local _, handle = connect()
        handle._read_cb(nil, request(path, '{"a":1}'))

        assert.equals(204, status_of(handle))
        assert.truthy(handle.writes[1]:find("Connection: close", 1, true))
        assert.are.same({ { kind = kind, body = '{"a":1}' } }, posts)
        assert.is_true(handle.closed)
      end)
    end

    it("still answers 204 for a body that is not JSON", function()
      local _, handle = connect()
      handle._read_cb(nil, request("/claudinho/hook", "not json {"))

      assert.equals(204, status_of(handle))
      assert.are.same({ { kind = "hook", body = "not json {" } }, posts)
    end)

    it("answers 204 for an empty body", function()
      local _, handle = connect()
      handle._read_cb(nil, request("/claudinho/statusline", ""))

      assert.equals(204, status_of(handle))
      assert.equals("", posts[1].body)
    end)

    it("joins a body that arrives in several reads", function()
      local _, handle = connect()
      local full = request("/claudinho/statusline", "0123456789")
      handle._read_cb(nil, full:sub(1, 20))
      handle._read_cb(nil, full:sub(21, #full - 6))
      assert.equals(0, #handle.writes)
      handle._read_cb(nil, full:sub(#full - 5))

      assert.equals(204, status_of(handle))
      assert.equals("0123456789", posts[1].body)
    end)

    it("tells a POST when the first read is shorter than the verb", function()
      local _, handle = connect()
      local full = request("/claudinho/hook", "{}")
      handle._read_cb(nil, "PO")
      handle._read_cb(nil, full:sub(3))

      assert.equals(204, status_of(handle))
      assert.equals(1, #posts)
    end)

    it("answers 404 for another path, and does not call on_post", function()
      local _, handle = connect()
      handle._read_cb(nil, request("/claudinho/other", "{}"))

      assert.equals(404, status_of(handle))
      assert.are.same({}, posts)
      assert.is_true(handle.closed)
    end)

    it("answers 404 for a POST to the WebSocket path", function()
      local _, handle = connect()
      handle._read_cb(nil, request("/", "{}"))

      assert.equals(404, status_of(handle))
    end)
  end)

  describe("token", function()
    it("answers 401 without a token", function()
      local _, handle = connect()
      handle._read_cb(nil, request("/claudinho/hook", "{}", { token = false }))

      assert.equals(401, status_of(handle))
      assert.are.same({}, posts)
      assert.is_true(handle.closed)
    end)

    it("answers 401 with a wrong token", function()
      local _, handle = connect()
      handle._read_cb(nil, request("/claudinho/statusline", "{}", { token = "http-token-0123456780" }))

      assert.equals(401, status_of(handle))
      assert.are.same({}, posts)
    end)

    it("accepts a request when the server has no token", function()
      server.auth_token = nil
      local _, handle = connect()
      handle._read_cb(nil, request("/claudinho/hook", "{}", { token = false }))

      assert.equals(204, status_of(handle))
    end)
  end)

  describe("limits", function()
    it("answers 400 without Content-Length", function()
      local _, handle = connect()
      handle._read_cb(nil, request("/claudinho/hook", "{}", { length = false }))

      assert.equals(400, status_of(handle))
      assert.are.same({}, posts)
    end)

    it("answers 400 for a Content-Length that is not a number", function()
      local _, handle = connect()
      handle._read_cb(nil, request("/claudinho/hook", "{}", { length = "abc" }))

      assert.equals(400, status_of(handle))
    end)

    it("answers 400 for headers over 8 KiB, with the end of the headers in the read", function()
      local _, handle = connect()
      local big = "POST /claudinho/hook HTTP/1.1\r\nX-Pad: " .. ("a"):rep(9000) .. "\r\nContent-Length: 0\r\n\r\n"
      handle._read_cb(nil, big)

      assert.equals(400, status_of(handle))
      assert.are.same({}, posts)
    end)

    it("answers 400 for headers over 8 KiB that never end", function()
      local _, handle = connect()
      handle._read_cb(nil, "POST /claudinho/hook HTTP/1.1\r\nX-Pad: " .. ("a"):rep(9000))

      assert.equals(400, status_of(handle))
      assert.is_true(handle.closed)
    end)

    it("answers 413 above 1 MiB at once, without reading the body", function()
      local _, handle = connect()
      handle._read_cb(nil, request("/claudinho/hook", "", { length = 1024 * 1024 + 1 }))

      assert.equals(413, status_of(handle))
      assert.are.same({}, posts)
      assert.is_true(handle.closed)
    end)

    it("accepts a body of exactly 1 MiB", function()
      local _, handle = connect()
      local body = ("x"):rep(1024 * 1024)
      handle._read_cb(nil, request("/claudinho/hook", body))

      assert.equals(204, status_of(handle))
      assert.equals(#body, #posts[1].body)
    end)

    it("ignores bytes that come after the answer", function()
      local _, handle = connect()
      handle._read_cb(nil, request("/claudinho/hook", "{}", { token = false }))
      handle._read_cb(nil, request("/claudinho/hook", "{}"))

      assert.equals(1, #handle.writes)
      assert.are.same({}, posts)
    end)
  end)

  describe("a POST client", function()
    it("is not in the clients of the server, and is not counted", function()
      local client, handle = connect()
      assert.is_not_nil(server.clients[client.id])
      -- Headers read, body still to come: the client waits as an HTTP client.
      handle._read_cb(nil, request("/claudinho/hook", "{}"):sub(1, 60))

      assert.is_nil(server.clients[client.id])
      assert.equals(0, tcp.get_client_count(server))
      assert.are.same({}, tcp.get_clients_info(server))
      assert.equals("http", client.mode)
      assert.is_false(client.handshake_complete)
    end)

    it("leaves no trace after the answer", function()
      local client, handle = connect()
      handle._read_cb(nil, request("/claudinho/hook", "{}"))

      assert.is_nil(server.clients[client.id])
      assert.is_nil(server.http_clients[client.id])
    end)

    it("is closed by stop_server while its body is awaited", function()
      local client, handle = connect()
      handle._read_cb(nil, request("/claudinho/hook", "{}"):sub(1, 60))
      assert.is_not_nil(server.http_clients[client.id])

      tcp.stop_server(server)

      assert.is_true(handle.closed)
    end)

    it("does not run the on_disconnect callback when it hangs up", function()
      local disconnects = 0
      server.on_disconnect = function()
        disconnects = disconnects + 1
      end
      local client, handle = connect()
      handle._read_cb(nil, request("/claudinho/hook", "{}"):sub(1, 60))
      handle._read_cb(nil, nil)

      assert.equals(0, disconnects)
      assert.is_true(handle.closed)
      assert.is_nil(server.http_clients[client.id])
    end)

    it("leaves a WebSocket client untouched", function()
      local client, handle = connect()
      handle._read_cb(
        nil,
        "GET / HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
          .. "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n"
          .. "x-claude-code-ide-authorization: "
          .. token
          .. "\r\n\r\n"
      )

      assert.is_nil(client.mode)
      assert.truthy(handle.writes[1]:find("101 Switching Protocols", 1, true))
      assert.is_not_nil(server.clients[client.id])
    end)
  end)
end)
