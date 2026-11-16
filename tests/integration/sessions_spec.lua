-- Real-Neovim check of the tab registry: three real tabs with a test command in real terminal jobs, each with its own
-- server, token and lock file; the status POSTs of one tab; kill_all and the buffer of a tab ending the tabs.
-- Under busted's mock vim it is pending; scripts/run_integration_tests_individually.sh runs it in Neovim.
if vim == nil or vim.fn.has("nvim") ~= 1 or (vim.uv or vim.loop) == nil or vim.wait == nil or vim.system == nil then
  describe("sessions", function()
    pending("needs a real Neovim")
  end)
  return
end

describe("sessions", function()
  local uv = vim.uv or vim.loop
  local lockfile = require("claudinho.lockfile")
  local http_post = require("tests.helpers.http_post")
  local tab_env = require("tests.helpers.tab_env")

  local sessions, env, saved_lock_dir, saved_plugin

  ---@return table config
  local function make_config()
    return vim.tbl_deep_extend("force", vim.deepcopy(require("claudinho.config").defaults), {
      port_range = { min = 20000, max = 40000 },
      terminal_cmd = env.idle_cmd,
      -- HOME and CLAUDE_CONFIG_DIR of the test, never the real ones.
      env = { HOME = env.home, CLAUDE_CONFIG_DIR = env.config_dir },
    })
  end

  ---@return string[] The lock files in the lock folder of the test
  local function lock_files()
    local files = {}
    for name, kind in vim.fs.dir(env.lock_dir) do
      if kind == "file" and name:match("%.lock$") then
        table.insert(files, name)
      end
    end
    table.sort(files)
    return files
  end

  local function alive(pid)
    return uv.kill(pid, 0) == 0
  end

  before_each(function()
    env = tab_env.new()
    saved_lock_dir = lockfile.lock_dir
    -- lock_dir is read once when the module loads, so the spec points it at its own folder.
    lockfile.lock_dir = env.lock_dir
    -- sessions.new reads the configuration of the running plugin.
    saved_plugin = package.loaded["claudinho"]
    package.loaded["claudinho"] = { state = { config = make_config() } }
    package.loaded["claudinho.sessions"] = nil
    sessions = require("claudinho.sessions")
  end)

  after_each(function()
    sessions.kill_all()
    pcall(vim.api.nvim_del_augroup_by_name, "ClaudinhoSessions")
    package.loaded["claudinho"] = saved_plugin
    package.loaded["claudinho.sessions"] = nil
    lockfile.lock_dir = saved_lock_dir
    tab_env.remove(env)
  end)

  it(
    "starts three tabs with their own port, token and lock file, and kill_all leaves no job and no lock file",
    function()
      local first = assert(sessions.new())
      local second = assert(sessions.new())
      local third = assert(sessions.new())

      assert.same({ 1, 2, 3 }, { first.number, second.number, third.number })
      assert.equals(third, sessions.active())
      local ports, tokens = {}, {}
      for _, s in ipairs({ first, second, third }) do
        assert.equals("running", s.state)
        ports[s.lock_port] = true
        tokens[s.token] = true
        assert.equals(1, vim.fn.filereadable(env.lock_dir .. "/" .. s.lock_port .. ".lock"))
      end
      assert.equals(3, vim.tbl_count(ports))
      assert.equals(3, vim.tbl_count(tokens))
      assert.equals(3, #lock_files())
      local pids = { first.pid, second.pid, third.pid }
      for _, pid in ipairs(pids) do
        assert.is_true(alive(pid))
      end

      sessions.kill_all()

      for _, pid in ipairs(pids) do
        assert.is_true(vim.wait(3000, function()
          return not alive(pid)
        end, 20))
      end
      assert.same({}, lock_files())
      assert.same({}, sessions.state.tabs)
      assert.is_nil(sessions.active())
    end
  )

  it("finds the tab of a server and sends only through the server of the active tab", function()
    local first = assert(sessions.new())
    local second = assert(sessions.new())

    assert.equals(first, sessions.for_client({ server_id = first.server.id }))
    assert.equals(second, sessions.for_client({ server_id = second.server.id }))
    -- Nobody is connected, so the broadcast of the active tab reaches no client, and it does not fail.
    assert.is_false(sessions.router.broadcast("selection_changed", {}))
    assert.is_true(sessions.activate(1))
    assert.equals(first, sessions.active())
    assert.is_false(sessions.router.broadcast("selection_changed", {}))
  end)

  it("takes a status POST into the data of its own tab only", function()
    local first = assert(sessions.new())
    local second = assert(sessions.new())

    local result = http_post.post(
      second.lock_port,
      "/claudinho/statusline",
      '{"session_id":"sid-2","model":{"id":"claude-opus-5-5","display_name":"Opus"}}',
      { ["X-Claudinho-Token"] = second.token, ["Content-Type"] = "application/json" }
    )
    assert.equals(204, result.status)
    assert.is_true(vim.wait(2000, function()
      return second.data.model ~= nil
    end, 10))

    assert.equals("Opus 5.5", second.data.model)
    assert.equals("sid-2", second.data.session_id)
    assert.same({}, first.data)
  end)

  it("a token of another tab is refused", function()
    local first = assert(sessions.new())
    local second = assert(sessions.new())

    local result = http_post.post(
      second.lock_port,
      "/claudinho/statusline",
      '{"session_id":"sid-x"}',
      { ["X-Claudinho-Token"] = first.token, ["Content-Type"] = "application/json" }
    )

    assert.equals(401, result.status)
    vim.wait(100, function()
      return false
    end, 10)
    assert.same({}, second.data)
  end)

  it("closes a tab on its own and moves to the neighbour, leaving the others running", function()
    local first = assert(sessions.new())
    local second = assert(sessions.new())
    local port = second.lock_port
    local pid = second.pid
    assert.is_true(sessions.activate(2))

    assert.is_true(sessions.close(2))

    assert.is_true(vim.wait(3000, function()
      return not alive(pid)
    end, 20))
    assert.equals(1, sessions.state.active)
    assert.equals(0, vim.fn.filereadable(env.lock_dir .. "/" .. port .. ".lock"))
    assert.equals("running", first.state)
    assert.equals(1, #lock_files())
    -- The freed number comes back.
    assert.equals(2, assert(sessions.new()).number)
  end)

  it("closes the tab when its buffer is wiped", function()
    sessions.setup_autocmds()
    local first = assert(sessions.new())
    local second = assert(sessions.new())
    local buf, pid = second.buf, second.pid

    vim.cmd("silent! bwipeout! " .. buf)

    assert.is_nil(sessions.state.tabs[2])
    assert.is_true(vim.wait(3000, function()
      return not alive(pid)
    end, 20))
    assert.is_false(vim.api.nvim_buf_is_valid(buf))
    assert.equals(first, sessions.active())
    assert.equals(1, #lock_files())
  end)

  it("ExitPre and VimLeavePre end the tabs", function()
    sessions.setup_autocmds()
    local first = assert(sessions.new())
    local pid = first.pid

    vim.api.nvim_exec_autocmds("ExitPre", { modeline = false })
    assert.equals("running", first.state)
    assert.equals(first, sessions.state.tabs[1])

    vim.api.nvim_exec_autocmds("VimLeavePre", { modeline = false })

    assert.same({}, sessions.state.tabs)
    assert.is_true(vim.wait(3000, function()
      return not alive(pid)
    end, 20))
    assert.same({}, lock_files())
  end)
end)
