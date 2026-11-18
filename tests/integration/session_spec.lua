-- Real-Neovim check of one session: a real server, lock file and settings file, and a test command in a real terminal
-- job. The command (tests/helpers/tab_env.lua) writes its environment to a file, so the spec reads what the process
-- of the tab really got.
-- Under busted's mock vim it is pending; scripts/run_integration_tests_individually.sh runs it in Neovim.
if vim == nil or vim.fn.has("nvim") ~= 1 or (vim.uv or vim.loop) == nil or vim.wait == nil or vim.system == nil then
  describe("session", function()
    pending("needs a real Neovim")
  end)
  return
end

describe("session", function()
  local uv = vim.uv or vim.loop
  local session_module = require("claudinho.session")
  local lockfile = require("claudinho.lockfile")
  local http_post = require("tests.helpers.http_post")
  local tab_env = require("tests.helpers.tab_env")

  local env, saved_lock_dir, session

  ---@param terminal_cmd string
  ---@return table config
  local function make_config(terminal_cmd)
    local config = vim.tbl_deep_extend("force", vim.deepcopy(require("claudinho.config").defaults), {
      port_range = { min = 20000, max = 40000 },
      terminal_cmd = terminal_cmd,
      -- The way a user sets the environment of Claude: HOME and CLAUDE_CONFIG_DIR of the test, never the real ones.
      env = { HOME = env.home, CLAUDE_CONFIG_DIR = env.config_dir },
    })
    return config
  end

  ---@return table<string, string> The environment that the idle command wrote
  local function wait_for_env()
    assert.is_true(
      vim.wait(5000, function()
        return tab_env.read_env(env) ~= nil
      end, 20),
      "the test command did not write its environment"
    )
    return assert(tab_env.read_env(env))
  end

  local function read_json(path)
    local file = assert(io.open(path, "r"))
    local content = file:read("*a")
    file:close()
    return vim.json.decode(content)
  end

  local function alive(pid)
    return uv.kill(pid, 0) == 0
  end

  before_each(function()
    env = tab_env.new()
    saved_lock_dir = lockfile.lock_dir
    -- lock_dir is read once when the module loads, so the spec points it at its own folder.
    lockfile.lock_dir = env.lock_dir
    session = nil
  end)

  after_each(function()
    if session then
      session_module.close(session, "test over")
    end
    lockfile.lock_dir = saved_lock_dir
    tab_env.remove(env)
  end)

  it("gives the process the port and the token of its own tab, and not vim.env", function()
    session = session_module.new(1, make_config(env.idle_cmd))
    assert.is_true((session_module.start(session)))

    local seen = wait_for_env()

    assert.equals(tostring(session.lock_port), seen.CLAUDINHO_PORT)
    assert.equals(session.token, seen.CLAUDINHO_TOKEN)
    assert.equals(tostring(session.lock_port), seen.CLAUDE_CODE_SSE_PORT)
    assert.equals("true", seen.ENABLE_IDE_INTEGRATION)
    assert.equals("true", seen.FORCE_CODE_TERMINAL)
    assert.equals(env.home, seen.HOME)
    assert.is_truthy(seen.no_proxy:find("127.0.0.1", 1, true))
    assert.is_nil(vim.env.CLAUDINHO_PORT)
    assert.is_nil(vim.env.CLAUDINHO_TOKEN)
  end)

  it("writes a lock file named for the tab, with the pid of this Neovim", function()
    session = session_module.new(1, make_config(env.idle_cmd))
    assert.is_true((session_module.start(session)))

    local lock = read_json(env.lock_dir .. "/" .. session.lock_port .. ".lock")

    assert.equals("Neovim (Claudinho 1)", lock.ideName)
    assert.equals(vim.fn.getpid(), lock.pid)
    assert.equals(session.token, lock.authToken)
    assert.equals("ws", lock.transport)
    assert.equals(session.cwd, lock.workspaceFolders[1])
  end)

  it("writes a settings file that is gone after close", function()
    session = session_module.new(1, make_config(env.idle_cmd))
    assert.is_true((session_module.start(session)))
    local path = session.settings_path

    assert.equals(1, vim.fn.filereadable(path))
    assert.is_not_nil(read_json(path).statusLine)
    assert.is_nil(path:find(".claude", 1, true))

    local port = session.lock_port
    session_module.close(session)

    assert.equals(0, vim.fn.filereadable(path))
    assert.equals(0, vim.fn.filereadable(env.lock_dir .. "/" .. port .. ".lock"))
  end)

  it("stops the process on close", function()
    session = session_module.new(1, make_config(env.idle_cmd))
    assert.is_true((session_module.start(session)))
    wait_for_env()
    local pid = session.pid
    assert.is_true(alive(pid))

    session_module.close(session)

    assert.is_true(vim.wait(3000, function()
      return not alive(pid)
    end, 20))
    assert.is_nil(session.server)
  end)

  it("takes the status POSTs of its own tab into its data", function()
    session = session_module.new(1, make_config(env.idle_cmd))
    assert.is_true((session_module.start(session)))

    local result = http_post.post(
      session.lock_port,
      "/claudinho/statusline",
      '{"session_id":"123e4567-e89b-12d3-a456-426614174001","model":{"id":"claude-opus-5-5","display_name":"Opus"}}',
      { ["X-Claudinho-Token"] = session.token, ["Content-Type"] = "application/json" }
    )
    assert.equals(204, result.status)
    assert.is_true(vim.wait(2000, function()
      return session.data.model ~= nil
    end, 10))
    assert.equals("Opus 5.5", session.data.model)
    assert.equals("123e4567-e89b-12d3-a456-426614174001", session.data.session_id)

    http_post.post(
      session.lock_port,
      "/claudinho/hook",
      '{"session_id":"123e4567-e89b-12d3-a456-426614174001","permission_mode":"plan"}',
      { ["X-Claudinho-Token"] = session.token, ["Content-Type"] = "application/json" }
    )
    assert.is_true(vim.wait(2000, function()
      return session.data.mode == "plan"
    end, 10))
    -- The hook did not erase the model.
    assert.equals("Opus 5.5", session.data.model)
  end)

  describe("when the process ends", function()
    it("keeps a valid buffer and releases the server, the lock file and the settings file", function()
      session = session_module.new(1, make_config(env.exit_cmd(3)))
      assert.is_true((session_module.start(session)))
      local port, settings_path, buf = session.lock_port, session.settings_path, session.buf

      assert.is_true(vim.wait(5000, function()
        return session.state == "exited"
      end, 20))

      assert.equals(3, session.exit_code)
      assert.is_true(vim.api.nvim_buf_is_valid(buf))
      assert.is_nil(session.server)
      assert.equals(0, vim.fn.filereadable(settings_path))
      assert.equals(0, vim.fn.filereadable(env.lock_dir .. "/" .. port .. ".lock"))
    end)

    it("does not close the buffer on a key typed in it (rule 39)", function()
      session = session_module.new(1, make_config(env.exit_cmd(0)))
      assert.is_true((session_module.start(session)))
      assert.is_true(vim.wait(5000, function()
        return session.state == "exited"
      end, 20))
      local buf = session.buf

      vim.api.nvim_win_set_buf(0, buf)
      vim.cmd("startinsert")
      vim.api.nvim_feedkeys("x", "t", false)
      vim.wait(300, function()
        return false
      end, 20)

      assert.is_true(vim.api.nvim_buf_is_valid(buf))
      assert.are_not.equal("t", vim.api.nvim_get_mode().mode)
    end)
  end)

  it("restarts with a new port, token and lock file", function()
    session = session_module.new(1, make_config(env.idle_cmd))
    assert.is_true((session_module.start(session)))
    wait_for_env()
    local first_port, first_token = session.lock_port, session.token

    vim.fn.jobstop(session.job)
    assert.is_true(vim.wait(5000, function()
      return session.state == "exited"
    end, 20))
    assert.equals(0, vim.fn.filereadable(env.lock_dir .. "/" .. first_port .. ".lock"))
    os.remove(env.env_file)

    assert.is_true((session_module.restart(session)))
    local seen = wait_for_env()

    assert.equals("running", session.state)
    assert.are_not.equal(first_token, session.token)
    assert.equals(session.token, seen.CLAUDINHO_TOKEN)
    assert.equals(tostring(session.lock_port), seen.CLAUDINHO_PORT)
    assert.equals(1, vim.fn.filereadable(env.lock_dir .. "/" .. session.lock_port .. ".lock"))
  end)

  it("answers with an error and leaves nothing when the command does not exist", function()
    session = session_module.new(1, make_config("claudinho-no-such-command-xyz"))

    local ok, err = session_module.start(session)

    assert.is_false(ok)
    assert.is_truthy(err:find("is not executable", 1, true))
    assert.same({}, vim.fn.glob(env.lock_dir .. "/*", false, true))
  end)
end)
