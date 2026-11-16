-- Real-Neovim check of the HTTP routes over a real socket: the answer comes fast, the socket closes, the body reaches
-- on_post, and a POST never shows up among the clients.
-- Under busted's mock vim it is pending; scripts/run_integration_tests_individually.sh runs it in Neovim.
if vim == nil or vim.fn.has("nvim") ~= 1 or (vim.uv or vim.loop) == nil or vim.wait == nil then
  describe("server HTTP routes", function()
    pending("needs a real Neovim")
  end)
  return
end

describe("server HTTP routes", function()
  local server = require("claudinho.server.init")
  local http_post = require("tests.helpers.http_post")
  local ws_client = require("tests.helpers.ws_client")
  local config = { port_range = { min = 20000, max = 40000 } }
  local token = "http-instance-token-0123456789"
  local instance, posts

  before_each(function()
    posts = {}
    instance = server.new({
      on_post = function(kind, body)
        table.insert(posts, { kind = kind, body = body })
      end,
    })
    assert(instance:start(config, token))
  end)

  after_each(function()
    instance:stop()
  end)

  it("answers a POST in under 100 ms and closes the socket", function()
    local result = http_post.post(instance.port, "/claudinho/statusline", '{"session_id":"s1"}', {
      ["X-Claudinho-Token"] = token,
      ["Content-Type"] = "application/json",
    })

    assert.equals(204, result.status)
    assert.is_true(result.closed)
    assert.is_true(result.elapsed_ms < 100, "took " .. result.elapsed_ms .. " ms")
    assert.is_true(vim.wait(1000, function()
      return #posts == 1
    end, 10))
    assert.are.same({ kind = "statusline", body = '{"session_id":"s1"}' }, posts[1])
  end)

  it("answers 401 with a wrong token and calls nothing", function()
    local result = http_post.post(instance.port, "/claudinho/hook", "{}", { ["X-Claudinho-Token"] = "wrong" })

    assert.equals(401, result.status)
    assert.is_true(result.closed)
    assert.are.same({}, posts)
  end)

  it("keeps a POST out of the clients, and the WebSocket client in", function()
    local ws = ws_client.connect(instance.port, token)
    local result = http_post.post(instance.port, "/claudinho/hook", "{}", { ["X-Claudinho-Token"] = token })

    assert.equals(204, result.status)
    local status = instance:get_status()
    assert.equals(1, status.client_count)
    assert.equals(1, #status.clients)
    assert.is_true(instance:broadcast("ping/test", {}))
    assert.equals("ping/test", assert(ws:next_message()).method)
    ws:close()
  end)

  it("still upgrades a WebSocket client after a POST", function()
    http_post.post(instance.port, "/claudinho/hook", "{}", { ["X-Claudinho-Token"] = token })
    local ws = ws_client.connect(instance.port, token)

    ws:send({ jsonrpc = "2.0", id = 1, method = "tools/list" })
    assert.equals(1, assert(ws:next_message()).id)
    ws:close()
  end)
end)
