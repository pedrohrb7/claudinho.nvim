-- Real-Neovim check of two server instances side by side over real sockets: each takes its own port, answers
-- initialize and tools/list, and a broadcast of one never reaches the client of the other.
-- Under busted's mock vim it is pending; scripts/run_integration_tests_individually.sh runs it in Neovim.
if vim == nil or vim.fn.has("nvim") ~= 1 or (vim.uv or vim.loop) == nil or vim.wait == nil then
  describe("server instances", function()
    pending("needs a real Neovim")
  end)
  return
end

describe("server instances", function()
  local server = require("claudinho.server.init")
  local ws_client = require("tests.helpers.ws_client")
  local config = { port_range = { min = 20000, max = 40000 } }
  local token_a, token_b = "instance-a-token-0123456789", "instance-b-token-0123456789"
  local a, b, client_a, client_b

  before_each(function()
    a, b = server.new(), server.new()
    assert(a:start(config, token_a))
    assert(b:start(config, token_b))
    client_a = ws_client.connect(a.port, token_a)
    client_b = ws_client.connect(b.port, token_b)
  end)

  after_each(function()
    client_a:close()
    client_b:close()
    a:stop()
    b:stop()
  end)

  it("listens on two ports with two tokens", function()
    assert.are_not.equal(a.port, b.port)
    assert.are_not.equal(a.auth_token, b.auth_token)
    assert.equals(1, a:get_status().client_count)
    assert.equals(1, b:get_status().client_count)
  end)

  it("refuses the token of the other instance", function()
    local ok = pcall(ws_client.connect, a.port, token_b, 500)
    assert.is_false(ok)
    assert.equals(1, a:get_status().client_count)
  end)

  it("answers initialize and tools/list on both", function()
    for _, client in ipairs({ client_a, client_b }) do
      client:send({ jsonrpc = "2.0", id = 1, method = "initialize", params = {} })
      local init = assert(client:next_message())
      assert.equals(1, init.id)
      assert.equals("claudinho-nvim", init.result.serverInfo.name)

      client:send({ jsonrpc = "2.0", id = 2, method = "tools/list" })
      local list = assert(client:next_message())
      assert.equals(2, list.id)
      assert.is_true(#list.result.tools > 0)
    end
  end)

  it("keeps a broadcast inside its instance", function()
    assert.is_true(a:broadcast("only/a", { n = 1 }))

    local message = assert(client_a:next_message())
    assert.equals("only/a", message.method)
    assert.is_false(vim.wait(200, function()
      return client_b:pending() > 0
    end, 10))
    assert.equals(0, client_b:pending())
    assert.is_true(a:drain(1000))
  end)

  it("stops one instance and leaves the other serving", function()
    a:stop()

    client_b:send({ jsonrpc = "2.0", id = 3, method = "tools/list" })
    local list = assert(client_b:next_message())
    assert.equals(3, list.id)
    assert.is_true(b:get_status().running)
    assert.is_false(a:get_status().running)
  end)
end)
