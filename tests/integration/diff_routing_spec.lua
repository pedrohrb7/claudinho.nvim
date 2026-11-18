-- Real-Neovim check of the diff routing by tab: two real tabs, one WebSocket client on each. The openDiff of the tab
-- in the background does not open; it opens when the tab is activated; the answer goes to the client that asked, with
-- the other tab active; other tools answer a tab in the background.
-- Under busted's mock vim it is pending; scripts/run_integration_tests_individually.sh runs it in Neovim.
if vim == nil or vim.fn.has("nvim") ~= 1 or (vim.uv or vim.loop) == nil or vim.wait == nil or vim.system == nil then
  describe("diff routing by tab", function()
    pending("needs a real Neovim")
  end)
  return
end

describe("diff routing by tab", function()
  local lockfile = require("claudinho.lockfile")
  local tab_env = require("tests.helpers.tab_env")
  local ws_client = require("tests.helpers.ws_client")
  local diff = require("claudinho.diff")

  local sessions, env, saved_lock_dir, saved_plugin, dir, first, second, client_1, client_2

  ---@return table config
  local function make_config()
    return vim.tbl_deep_extend("force", vim.deepcopy(require("claudinho.config").defaults), {
      port_range = { min = 20000, max = 40000 },
      terminal_cmd = env.idle_cmd,
      env = { HOME = env.home, CLAUDE_CONFIG_DIR = env.config_dir },
    })
  end

  ---@param client WsClient
  ---@param id integer
  ---@param name string
  ---@param arguments table
  local function call_tool(client, id, name, arguments)
    client:send({ jsonrpc = "2.0", id = id, method = "tools/call", params = { name = name, arguments = arguments } })
  end

  ---@param name string
  ---@return table arguments
  local function diff_arguments(name)
    return {
      old_file_path = dir .. "/" .. name,
      new_file_path = dir .. "/" .. name,
      new_file_contents = "one\nTWO\n",
      tab_name = name,
    }
  end

  before_each(function()
    env = tab_env.new()
    dir = vim.fn.tempname() .. "-routing"
    vim.fn.mkdir(dir, "p")
    vim.fn.writefile({ "one", "two" }, dir .. "/a.txt")
    vim.fn.writefile({ "one", "two" }, dir .. "/b.txt")
    saved_lock_dir = lockfile.lock_dir
    lockfile.lock_dir = env.lock_dir
    saved_plugin = package.loaded["claudinho"]
    package.loaded["claudinho"] = { state = { config = make_config() } }
    package.loaded["claudinho.sessions"] = nil
    sessions = require("claudinho.sessions")
    require("claudinho.tools.init").register_all()
    diff.setup({ diff_opts = { layout = "horizontal" } })

    first = assert(sessions.new())
    second = assert(sessions.new())
    client_1 = ws_client.connect(first.lock_port, first.token)
    client_2 = ws_client.connect(second.lock_port, second.token)
  end)

  after_each(function()
    client_1:close()
    client_2:close()
    diff._cleanup_all_active_diffs("test cleanup")
    sessions.kill_all()
    vim.cmd("silent! tabonly!")
    pcall(vim.api.nvim_del_augroup_by_name, "ClaudinhoSessions")
    package.loaded["claudinho"] = saved_plugin
    package.loaded["claudinho.sessions"] = nil
    lockfile.lock_dir = saved_lock_dir
    tab_env.remove(env)
    vim.fn.delete(dir, "rf")
  end)

  it("keeps the diff of a tab in the background closed until the tab is activated", function()
    assert.equals(second, sessions.active())

    call_tool(client_1, 1, "openDiff", diff_arguments("a.txt"))

    assert.is_true(vim.wait(2000, function()
      return #first.pending_diffs == 1
    end, 10))
    assert.same({}, diff._get_active_diffs())
    assert.equals(0, client_1:pending())

    assert.is_true(sessions.activate(1))

    assert.is_true(vim.wait(2000, function()
      return diff._get_active_diffs()["a.txt"] ~= nil
    end, 10))
    assert.same({}, first.pending_diffs)
    assert.equals(0, client_1:pending())
  end)

  it("answers the client that asked, with the other tab active", function()
    sessions.activate(2)
    call_tool(client_2, 7, "openDiff", diff_arguments("b.txt"))
    assert.is_true(vim.wait(2000, function()
      return diff._get_active_diffs()["b.txt"] ~= nil
    end, 10))

    sessions.activate(1)
    assert.is_not_nil(diff._get_active_diffs()["b.txt"])
    diff._resolve_diff_as_rejected("b.txt")

    local reply = assert(client_2:next_message())
    assert.equals(7, reply.id)
    assert.equals("DIFF_REJECTED", reply.result.content[1].text)
    assert.is_false(vim.wait(200, function()
      return client_1:pending() > 0
    end, 10))
  end)

  it("answers DIFF_REJECTED to a waiting diff on close-all-diffs, with no window", function()
    call_tool(client_1, 3, "openDiff", diff_arguments("a.txt"))
    assert.is_true(vim.wait(2000, function()
      return #first.pending_diffs == 1
    end, 10))

    assert.equals(1, sessions.reject_all_pending("user command"))

    local reply = assert(client_1:next_message())
    assert.equals(3, reply.id)
    assert.equals("DIFF_REJECTED", reply.result.content[1].text)
    assert.equals("a.txt", reply.result.content[2].text)
    assert.same({}, diff._get_active_diffs())
    assert.same({}, first.pending_diffs)
  end)

  it("answers DIFF_REJECTED to a waiting diff when its tab closes (rule 38)", function()
    call_tool(client_1, 4, "openDiff", diff_arguments("a.txt"))
    assert.is_true(vim.wait(2000, function()
      return #first.pending_diffs == 1
    end, 10))

    assert.is_true(sessions.close(1))

    local reply = assert(client_1:next_message())
    assert.equals(4, reply.id)
    assert.equals("DIFF_REJECTED", reply.result.content[1].text)
    assert.equals("a.txt", reply.result.content[2].text)
  end)

  it("answers the other tools on a tab in the background", function()
    assert.equals(second, sessions.active())

    -- An empty Lua table would encode as an array, so the request is written out.
    client_1:send('{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"getOpenEditors","arguments":{}}}')

    local reply = assert(client_1:next_message())
    assert.equals(5, reply.id)
    assert.is_nil(reply.error)
    assert.is_not_nil(reply.result)
  end)
end)
