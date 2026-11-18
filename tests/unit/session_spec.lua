--- One session: the order in which it starts its server, lock file, settings file, buffer and job, how it undoes them
--- when a step fails, what its process gets in its environment, how the status POSTs merge into its data, what it does
--- when the process ends, and restart and close. The server, the lock file, the settings file, the mention queue and
--- the Neovim API are fakes that record what the session asks of them; tests/integration/session_spec.lua runs the real
--- ones.
require("tests.busted_setup")

describe("session", function()
  local session_module
  local loaded_names = {
    "claudinho.session",
    "claudinho.server.init",
    "claudinho.lockfile",
    "claudinho.session_settings",
    "claudinho.mention_queue",
    "claudinho.sessions",
    "claudinho.diff",
  }
  local saved_loaded, restore_list
  local log, state, config, sessions_calls, server_opts

  ---Replace tbl[key] until after_each.
  local function stub(tbl, key, value)
    table.insert(restore_list, { tbl, key, tbl[key] })
    tbl[key] = value
  end

  local function index_of(name)
    for i, entry in ipairs(log) do
      if entry == name then
        return i
      end
    end
    return nil
  end

  before_each(function()
    saved_loaded, restore_list = {}, {}
    for _, name in ipairs(loaded_names) do
      saved_loaded[name] = package.loaded[name]
      package.loaded[name] = nil
    end
    log = {}
    sessions_calls = {}
    server_opts = nil
    state = {
      executable = 1,
      job = 77,
      jobstart_raises = nil,
      server_start = { true, 41234 },
      lock_create = { true, "/tmp/ide/41234.lock" },
      settings_write = "/tmp/nvim.x/0.claudinho-1.json",
      next_buf = 10,
      valid_bufs = {},
      jobstart_calls = {},
      deleted_bufs = {},
      windows = {},
      autocmds = {},
      stopinsert = 0,
    }
    config = { port_range = { min = 20000, max = 40000 }, env = {} }

    -- The fake server instance, lock file, settings file and queue.
    local Server = {}
    Server.__index = Server
    function Server:start(cfg, token)
      table.insert(log, "server.start")
      self.config, self.token = cfg, token
      state.server_start_token = token
      if state.server_start[1] then
        self.port = state.server_start[2]
      end
      return state.server_start[1], state.server_start[2]
    end
    function Server:stop()
      table.insert(log, "server.stop")
      return true
    end
    function Server:drain(ms)
      table.insert(log, "server.drain")
      state.drain_ms = ms
      return true
    end
    function Server:get_status()
      return { clients = state.clients or {} }
    end
    package.loaded["claudinho.server.init"] = {
      new = function(opts)
        server_opts = opts
        state.server = setmetatable({}, Server)
        return state.server
      end,
    }
    package.loaded["claudinho.lockfile"] = {
      generate_auth_token = function()
        return "0123456789abcdef0123456789abcdef"
      end,
      get_workspace_folders = function(cwd)
        return { cwd, "/lsp/folder" }
      end,
      create = function(port, token, opts)
        table.insert(log, "lock.create")
        state.lock_args = { port = port, token = token, opts = opts }
        return state.lock_create[1], state.lock_create[2]
      end,
      remove = function(port)
        table.insert(log, "lock.remove")
        state.lock_removed = port
        return true
      end,
    }
    package.loaded["claudinho.session_settings"] = {
      write = function(session)
        table.insert(log, "settings.write")
        if state.settings_write then
          session.settings_path = state.settings_write
          return state.settings_write
        end
        return nil, "disk full"
      end,
      remove = function(session)
        table.insert(log, "settings.remove")
        session.settings_path = nil
        return true
      end,
    }
    package.loaded["claudinho.mention_queue"] = {
      new = function(opts)
        local queue = { opts = opts, opened = 0, cleared = 0 }
        function queue:on_open()
          self.opened = self.opened + 1
        end
        function queue:clear()
          self.cleared = self.cleared + 1
        end
        state.queues = state.queues or {}
        table.insert(state.queues, queue)
        return queue
      end,
    }
    package.loaded["claudinho.sessions"] = {
      on_change = function(session)
        table.insert(sessions_calls, { "on_change", session })
      end,
      on_exit = function(session)
        table.insert(sessions_calls, { "on_exit", session })
      end,
    }

    -- The fake Neovim API.
    stub(vim.fn, "executable", function()
      return state.executable
    end)
    stub(vim.fn, "getcwd", function()
      return "/work/project"
    end)
    stub(vim.fn, "shellescape", function(text)
      return "'" .. text .. "'"
    end)
    stub(vim.fn, "jobstart", function(cmd, opts)
      table.insert(log, "jobstart")
      table.insert(state.jobstart_calls, { cmd = cmd, opts = opts })
      if state.jobstart_raises then
        error(state.jobstart_raises, 0)
      end
      return state.job
    end)
    stub(vim.fn, "jobstop", function(job)
      table.insert(log, "jobstop")
      state.jobstopped = job
      return 1
    end)
    stub(vim.fn, "jobpid", function()
      return 4242
    end)
    stub(vim.api, "nvim_create_buf", function()
      state.next_buf = state.next_buf + 1
      state.valid_bufs[state.next_buf] = true
      table.insert(log, "buf.create")
      return state.next_buf
    end)
    stub(vim.api, "nvim_buf_is_valid", function(buf)
      return state.valid_bufs[buf] == true
    end)
    stub(vim.api, "nvim_buf_call", function(_, callback)
      return callback()
    end)
    stub(vim.api, "nvim_buf_delete", function(buf)
      table.insert(log, "buf.delete")
      table.insert(state.deleted_bufs, buf)
      state.valid_bufs[buf] = nil
    end)
    stub(vim.api, "nvim_create_augroup", function(name)
      return name
    end)
    stub(vim.api, "nvim_create_autocmd", function(event, opts)
      table.insert(state.autocmds, { event = event, opts = opts })
      return #state.autocmds
    end)
    stub(vim.api, "nvim_list_wins", function()
      local wins = {}
      for win in pairs(state.windows) do
        table.insert(wins, win)
      end
      table.sort(wins)
      return wins
    end)
    stub(vim.api, "nvim_win_get_buf", function(win)
      return state.windows[win]
    end)
    stub(vim.api, "nvim_win_set_buf", function(win, buf)
      table.insert(log, "win.set_buf")
      state.windows[win] = buf
    end)
    stub(vim.api, "nvim_get_current_buf", function()
      return state.current_buf
    end)
    stub(
      vim,
      "bo",
      setmetatable({}, {
        __index = function(tbl, buf)
          local options = {}
          rawset(tbl, buf, options)
          return options
        end,
      })
    )
    stub(
      vim,
      "b",
      setmetatable({}, {
        __index = function(tbl, buf)
          local vars = {}
          rawset(tbl, buf, vars)
          return vars
        end,
      })
    )
    stub(
      vim,
      "cmd",
      setmetatable({
        stopinsert = function()
          state.stopinsert = state.stopinsert + 1
        end,
      }, {
        __call = function() end,
      })
    )
    stub(vim, "env", {})

    session_module = require("claudinho.session")
  end)

  after_each(function()
    for i = #restore_list, 1, -1 do
      local entry = restore_list[i]
      entry[1][entry[2]] = entry[3]
    end
    for _, name in ipairs(loaded_names) do
      package.loaded[name] = saved_loaded[name]
    end
  end)

  ---A started session, with the log cleared.
  local function started(extra_config)
    for key, value in pairs(extra_config or {}) do
      config[key] = value
    end
    local session = session_module.new(1, config)
    assert.is_true((session_module.start(session)))
    log = {}
    return session
  end

  describe("new", function()
    it("takes the folder of the window and the command from the config", function()
      local session = session_module.new(3, { terminal_cmd = "claude --model opus" })
      assert.equals(3, session.number)
      assert.equals("/work/project", session.cwd)
      assert.equals("claude --model opus", session.base_cmd)
      assert.equals("exited", session.state)
      assert.same({}, session.data)
      assert.same({}, session.pending_diffs)
      assert.is_false(session.closing)
    end)

    it("falls back to claude for a missing or empty command", function()
      assert.equals("claude", session_module.new(1, {}).base_cmd)
      assert.equals("claude", session_module.new(1, { terminal_cmd = "" }).base_cmd)
    end)
  end)

  describe("start", function()
    it("makes the server, the lock file, the settings file, the buffer and the job, in that order", function()
      local session = session_module.new(1, config)
      local ok, err = session_module.start(session)

      assert.is_true(ok)
      assert.is_nil(err)
      assert.same({ "server.start", "lock.create", "settings.write", "buf.create", "jobstart" }, log)
      assert.equals("running", session.state)
      assert.equals(state.server, session.server)
      assert.equals("0123456789abcdef0123456789abcdef", session.token)
      assert.equals(41234, session.lock_port)
      assert.equals("/tmp/nvim.x/0.claudinho-1.json", session.settings_path)
      assert.equals(77, session.job)
      assert.equals(4242, session.pid)
      assert.equals(11, session.buf)
      assert.is_nil(session.exit_code)
    end)

    it("starts the server with the config and the token of the tab", function()
      session_module.start(session_module.new(1, config))
      assert.equals(config, state.server.config)
      assert.equals("0123456789abcdef0123456789abcdef", state.server_start_token)
    end)

    it("writes the lock file of the tab", function()
      session_module.start(session_module.new(2, config))
      assert.equals(41234, state.lock_args.port)
      assert.equals("0123456789abcdef0123456789abcdef", state.lock_args.token)
      assert.equals("Neovim (Claudinho 2)", state.lock_args.opts.ide_name)
      assert.same({ "/work/project", "/lsp/folder" }, state.lock_args.opts.workspace_folders)
    end)

    it("runs the command with --settings and without a shell", function()
      session_module.start(session_module.new(1, config))
      assert.same({ "claude", "--settings", "/tmp/nvim.x/0.claudinho-1.json" }, state.jobstart_calls[1].cmd)
    end)

    it("keeps the arguments of the configured command, bracketed aliases included", function()
      session_module.start(session_module.new(1, { terminal_cmd = "claude --model opus[1m]", env = {} }))
      assert.same(
        { "claude", "--model", "opus[1m]", "--settings", "/tmp/nvim.x/0.claudinho-1.json" },
        state.jobstart_calls[1].cmd
      )
    end)

    it("appends the extra arguments", function()
      local session = session_module.new(1, config)
      session_module.start(session, " --resume 'abc-123'")
      assert.same(
        { "claude", "--settings", "/tmp/nvim.x/0.claudinho-1.json", "--resume", "abc-123" },
        state.jobstart_calls[1].cmd
      )
    end)

    it("checks the first word of the command, not the whole string", function()
      local checked
      vim.fn.executable = function(name)
        checked = name
        return 1
      end
      session_module.start(session_module.new(1, { terminal_cmd = "/opt/bin/claude --flag", env = {} }))
      assert.equals("/opt/bin/claude", checked)
    end)

    it("starts a terminal job in the folder of the session", function()
      local session = session_module.new(1, config)
      session.cwd = "/other/folder"
      session_module.start(session)
      local opts = state.jobstart_calls[1].opts
      assert.is_true(opts.term)
      assert.equals("/other/folder", opts.cwd)
      assert.is_function(opts.on_exit)
    end)

    it("makes a hidden buffer that belongs to the session", function()
      local session = session_module.new(4, config)
      session_module.start(session)
      assert.equals("hide", vim.bo[session.buf].bufhidden)
      assert.equals("claudinho", vim.bo[session.buf].filetype)
      assert.equals(4, vim.b[session.buf].claudinho_session)
    end)

    it("gives the mention queue the server of the tab", function()
      local session = session_module.new(1, config)
      session_module.start(session)
      assert.equals(session.queue, state.queues[1])
      assert.equals(state.server, session.queue.opts.server)
      assert.equals(config, session.queue.opts.config)
    end)

    describe("environment", function()
      it("has the variables of the tab and leaves vim.env alone", function()
        session_module.start(session_module.new(1, config))
        local env = state.jobstart_calls[1].opts.env
        assert.equals("41234", env.CLAUDE_CODE_SSE_PORT)
        assert.equals("true", env.ENABLE_IDE_INTEGRATION)
        assert.equals("true", env.FORCE_CODE_TERMINAL)
        assert.equals("41234", env.CLAUDINHO_PORT)
        assert.equals("0123456789abcdef0123456789abcdef", env.CLAUDINHO_TOKEN)
        assert.same({}, vim.env)
        assert.is_nil(vim.env.CLAUDINHO_PORT)
        assert.is_nil(vim.env.CLAUDINHO_TOKEN)
      end)

      it("adds the keys of config.env", function()
        session_module.start(session_module.new(1, { env = { MY_KEY = "mine" } }))
        assert.equals("mine", state.jobstart_calls[1].opts.env.MY_KEY)
      end)

      it("keeps the loopback hosts out of every proxy", function()
        session_module.start(session_module.new(1, { env = { no_proxy = "internal.example, localhost" } }))
        local env = state.jobstart_calls[1].opts.env
        assert.is_truthy(env.no_proxy:find("internal.example", 1, true))
        assert.is_truthy(env.no_proxy:find("127.0.0.1", 1, true))
        assert.is_truthy(env.no_proxy:find("::1", 1, true))
        assert.equals(env.no_proxy, env.NO_PROXY)
        -- localhost was in the user's value and is not repeated.
        local _, count = env.no_proxy:gsub("localhost", "")
        assert.equals(1, count)
      end)
    end)

    describe("when a step fails", function()
      local cases = {
        {
          name = "the command is not executable",
          arrange = function()
            state.executable = 0
          end,
          message = "is not executable",
          log = {},
        },
        {
          name = "the server does not start",
          arrange = function()
            state.server_start = { false, "no free port" }
          end,
          message = "no free port",
          log = { "server.start" },
        },
        {
          name = "the lock file is not written",
          arrange = function()
            state.lock_create = { false, "read-only folder" }
          end,
          message = "read-only folder",
          log = { "server.start", "lock.create", "server.stop" },
        },
        {
          name = "the settings file is not written",
          arrange = function()
            state.settings_write = nil
          end,
          message = "disk full",
          log = { "server.start", "lock.create", "settings.write", "lock.remove", "server.stop" },
        },
        {
          name = "jobstart returns 0",
          arrange = function()
            state.job = 0
          end,
          message = "did not start",
          log = {
            "server.start",
            "lock.create",
            "settings.write",
            "buf.create",
            "jobstart",
            "buf.delete",
            "settings.remove",
            "lock.remove",
            "server.stop",
          },
        },
        {
          name = "jobstart returns -1",
          arrange = function()
            state.job = -1
          end,
          message = "did not start",
          log = {
            "server.start",
            "lock.create",
            "settings.write",
            "buf.create",
            "jobstart",
            "buf.delete",
            "settings.remove",
            "lock.remove",
            "server.stop",
          },
        },
        {
          name = "jobstart raises",
          arrange = function()
            state.jobstart_raises = "E475: bad cwd"
          end,
          message = "E475: bad cwd",
          log = {
            "server.start",
            "lock.create",
            "settings.write",
            "buf.create",
            "jobstart",
            "buf.delete",
            "settings.remove",
            "lock.remove",
            "server.stop",
          },
        },
      }

      for _, case in ipairs(cases) do
        it("undoes everything in the inverse order when " .. case.name, function()
          case.arrange()
          local session = session_module.new(1, config)

          local ok, err = session_module.start(session)

          assert.is_false(ok)
          assert.is_truthy(tostring(err):find(case.message, 1, true))
          assert.is_truthy(tostring(err):find("^Could not start Claude 1: "))
          assert.is_truthy(tostring(err):find("Claude 1", 1, true))
          assert.same(case.log, log)
          -- Nothing is left on the session.
          assert.equals("exited", session.state)
          assert.is_nil(session.server)
          assert.is_nil(session.token)
          assert.is_nil(session.lock_port)
          assert.is_nil(session.settings_path)
          assert.is_nil(session.buf)
          assert.is_nil(session.job)
          assert.is_nil(session.queue)
          for _, valid in pairs(state.valid_bufs) do
            assert.is_nil(valid)
          end
        end)
      end

      it("stops the job it started when the buffer vanished", function()
        vim.fn.jobstart = function(cmd, opts)
          table.insert(log, "jobstart")
          state.jobstart_calls[1] = { cmd = cmd, opts = opts }
          state.valid_bufs[state.next_buf] = nil
          return state.job
        end
        local session = session_module.new(1, config)

        local ok = session_module.start(session)

        assert.is_false(ok)
        assert.equals(77, state.jobstopped)
        assert.is_truthy(index_of("jobstop") < index_of("settings.remove"))
        assert.is_truthy(index_of("server.stop"))
      end)
    end)
  end)

  describe("status POSTs", function()
    local session

    before_each(function()
      vim.json = vim.json or {}
      local saved_decode = vim.json.decode
      table.insert(restore_list, { vim.json, "decode", saved_decode })
      vim.json.decode = function(body)
        if body:sub(1, 1) ~= "{" then
          error("bad json")
        end
        -- The bodies of these tests are written as key=value pairs inside braces.
        local result = {}
        for key, value in body:gmatch('"([%w_]+)":"([^"]*)"') do
          result[key] = value
        end
        return result
      end
      session = started()
    end)

    it("merges the model and the session id of a statusline and tells the registry", function()
      server_opts.on_post("statusline", '{"session_id":"s1","model":"Opus"}')
      assert.equals("s1", session.data.session_id)
      assert.equals(1, #sessions_calls)
      assert.equals("on_change", sessions_calls[1][1])
      assert.equals(session, sessions_calls[1][2])
    end)

    it("does not erase what an earlier POST brought (rule 52)", function()
      server_opts.on_post("hook", '{"session_id":"s1","permission_mode":"plan"}')
      server_opts.on_post("statusline", '{"session_id":"s1"}')
      assert.equals("plan", session.data.mode)
      assert.equals("s1", session.data.session_id)
    end)

    it("takes the new value of a field that changed", function()
      server_opts.on_post("hook", '{"permission_mode":"plan"}')
      server_opts.on_post("hook", '{"permission_mode":"auto"}')
      assert.equals("auto", session.data.mode)
    end)

    it("ignores a body it cannot decode", function()
      server_opts.on_post("statusline", "not json")
      assert.same({}, session.data)
      assert.equals(0, #sessions_calls)
    end)

    it("tells the registry only when something changed", function()
      server_opts.on_post("hook", '{"permission_mode":"plan"}')
      server_opts.on_post("hook", '{"permission_mode":"plan"}')
      assert.equals(1, #sessions_calls)
    end)

    it("does nothing after the session closed", function()
      session_module.close(session)
      server_opts.on_post("hook", '{"permission_mode":"plan"}')
      assert.is_nil(session.data.mode)
    end)
  end)

  describe("a client connects", function()
    it("lets the mention queue send what waits", function()
      local session = started()
      server_opts.on_open({ id = "c1" })
      assert.equals(1, session.queue.opened)
    end)

    it("does not feed a queue of a closed session", function()
      local session = started()
      local queue = session.queue
      session_module.close(session)
      server_opts.on_open({ id = "c1" })
      assert.equals(0, queue.opened)
    end)
  end)

  describe("when the process ends", function()
    local session, queue

    before_each(function()
      session = started()
      queue = session.queue
      session.pending_diffs = { { tab_name = "x", path = "/a", co = coroutine.create(function() end) } }
    end)

    it("marks the session as exited and keeps the buffer", function()
      local buf = session.buf
      state.jobstart_calls[1].opts.on_exit(77, 3)

      assert.equals("exited", session.state)
      assert.equals(3, session.exit_code)
      assert.is_nil(session.job)
      assert.equals(buf, session.buf)
      assert.is_true(vim.api.nvim_buf_is_valid(buf))
      assert.same({}, state.deleted_bufs)
    end)

    it("clears the queue, drops the waiting diffs and releases the server and the files", function()
      state.jobstart_calls[1].opts.on_exit(77, 0)

      assert.equals(1, queue.cleared)
      assert.same({}, session.pending_diffs)
      assert.same({ "server.stop", "lock.remove", "settings.remove" }, log)
      assert.is_nil(session.server)
      assert.is_nil(session.lock_port)
      assert.is_nil(session.settings_path)
      assert.is_nil(session.token)
    end)

    it("tells the registry", function()
      state.jobstart_calls[1].opts.on_exit(77, 0)
      assert.equals(1, #sessions_calls)
      assert.equals("on_exit", sessions_calls[1][1])
      assert.equals(session, sessions_calls[1][2])
    end)

    it("ignores the end of a job that is no longer the session's", function()
      state.jobstart_calls[1].opts.on_exit(5, 1)
      assert.equals("running", session.state)
      assert.equals(0, #sessions_calls)
    end)

    it("ignores the end of a job after close", function()
      session_module.close(session)
      sessions_calls = {}
      state.jobstart_calls[1].opts.on_exit(77, 0)
      assert.equals(0, #sessions_calls)
      assert.is_nil(session.exit_code)
    end)

    it("starts no terminal mode in the ended buffer (rule 39)", function()
      state.jobstart_calls[1].opts.on_exit(77, 0)
      local guard
      for _, entry in ipairs(state.autocmds) do
        if entry.event == "TermEnter" and entry.opts.buffer == session.buf then
          guard = entry.opts
        end
      end
      assert.is_not_nil(guard)

      state.current_buf = session.buf
      guard.callback()
      assert.equals(1, state.stopinsert)
    end)

    it("lets a running session enter terminal mode", function()
      local guard
      for _, entry in ipairs(state.autocmds) do
        if entry.event == "TermEnter" and entry.opts.buffer == session.buf then
          guard = entry.opts
        end
      end
      state.current_buf = session.buf
      guard.callback()
      assert.equals(0, state.stopinsert)
    end)

    describe("the TermClose guard", function()
      local guard

      before_each(function()
        state.mode = "t"
        stub(vim.api, "nvim_get_mode", function()
          return { mode = state.mode }
        end)
        for _, entry in ipairs(state.autocmds) do
          if entry.event == "TermClose" and entry.opts.buffer == session.buf then
            guard = entry.opts
          end
        end
        assert.is_not_nil(guard)
      end)

      it("leaves terminal mode when the ended terminal is the current buffer", function()
        state.current_buf = session.buf
        guard.callback()
        assert.equals(1, state.stopinsert)
      end)

      it("does nothing when another buffer is current", function()
        state.current_buf = session.buf + 100
        guard.callback()
        assert.equals(0, state.stopinsert)
      end)

      it("does nothing when the mode is not terminal mode", function()
        state.current_buf = session.buf
        state.mode = "n"
        guard.callback()
        assert.equals(0, state.stopinsert)
      end)

      it("does nothing when the session no longer owns the buffer", function()
        state.current_buf = session.buf
        session.buf = nil
        guard.callback()
        assert.equals(0, state.stopinsert)
      end)
    end)
  end)

  describe("restart", function()
    it("refuses a running session", function()
      local session = started()
      local ok, err = session_module.restart(session)
      assert.is_false(ok)
      assert.is_truthy(err:find("still running", 1, true))
      assert.same({}, log)
    end)

    it("resumes the Claude session when the data has its id", function()
      local session = started()
      session.data.session_id = "sid-9"
      state.jobstart_calls[1].opts.on_exit(77, 0)
      state.jobstart_calls = {}

      assert.is_true((session_module.restart(session)))

      assert.same({
        "claude",
        "--settings",
        "/tmp/nvim.x/0.claudinho-1.json",
        "--resume",
        "sid-9",
      }, state.jobstart_calls[1].cmd)
      assert.equals("running", session.state)
    end)

    it("starts without arguments when there is no session id", function()
      local session = started()
      state.jobstart_calls[1].opts.on_exit(77, 0)
      state.jobstart_calls = {}

      assert.is_true((session_module.restart(session)))

      assert.same({ "claude", "--settings", "/tmp/nvim.x/0.claudinho-1.json" }, state.jobstart_calls[1].cmd)
    end)

    it("keeps the number, the folder and the data, and makes a new server and queue", function()
      local session = started()
      session.cwd = "/kept/folder"
      session.data = { model = "Opus 5.5", session_id = "sid" }
      local first_server, first_queue = session.server, session.queue
      state.jobstart_calls[1].opts.on_exit(77, 0)

      assert.is_true((session_module.restart(session)))

      assert.equals(1, session.number)
      assert.equals("/kept/folder", session.cwd)
      assert.equals("/kept/folder", state.jobstart_calls[#state.jobstart_calls].opts.cwd)
      assert.equals("Opus 5.5", session.data.model)
      assert.are_not.equal(first_server, session.server)
      assert.are_not.equal(first_queue, session.queue)
      assert.is_nil(session.exit_code)
    end)

    it("puts the new buffer in the windows of the old one and deletes the old one after the new job", function()
      local session = started()
      local old_buf = session.buf
      state.windows = { [1000] = old_buf, [1001] = 3 }
      state.jobstart_calls[1].opts.on_exit(77, 0)
      log = {}

      assert.is_true((session_module.restart(session)))

      assert.are_not.equal(old_buf, session.buf)
      assert.equals(session.buf, state.windows[1000])
      assert.equals(3, state.windows[1001])
      assert.same({ old_buf }, state.deleted_bufs)
      assert.is_truthy(index_of("jobstart") < index_of("buf.delete"))
    end)

    it("leaves the ended session as it was when the new start fails", function()
      local session = started()
      local old_buf = session.buf
      state.jobstart_calls[1].opts.on_exit(77, 5)
      state.settings_write = nil

      local ok = session_module.restart(session)

      assert.is_false(ok)
      assert.equals("exited", session.state)
      assert.equals(5, session.exit_code)
      assert.equals(old_buf, session.buf)
      assert.is_true(vim.api.nvim_buf_is_valid(old_buf))
    end)
  end)

  describe("close", function()
    it("stops the job, the server and the files, and deletes the buffer", function()
      local session = started()
      local buf = session.buf

      session_module.close(session, "tab closed")

      assert.equals(77, state.jobstopped)
      assert.same({ "server.drain", "jobstop", "server.stop", "lock.remove", "settings.remove", "buf.delete" }, log)
      assert.same({ buf }, state.deleted_bufs)
      assert.is_nil(session.server)
      assert.is_nil(session.buf)
      assert.is_nil(session.job)
      assert.is_nil(session.settings_path)
      assert.equals("exited", session.state)
      assert.is_true(session.closing)
    end)

    it("waits at most 200 ms for the write queues", function()
      local session = started()
      session_module.close(session)
      assert.equals(200, state.drain_ms)
    end)

    it("clears the mention queue", function()
      local session = started()
      session_module.close(session)
      assert.equals(1, session.queue.cleared)
    end)

    it("is idempotent", function()
      local session = started()
      session_module.close(session)
      log = {}
      session_module.close(session)
      assert.same({}, log)
    end)

    it("rejects the diffs that wait for the tab", function()
      local session = started()
      local answer
      local co = coroutine.create(function()
        answer = coroutine.yield()
      end)
      coroutine.resume(co)
      session.pending_diffs = { { tab_name = "t", path = "/a", co = co } }

      session_module.close(session)

      assert.equals("reject", answer)
      assert.same({}, session.pending_diffs)
    end)

    it("rejects the open diffs of every client that finished its handshake", function()
      local session = started()
      local closed = {}
      package.loaded["claudinho.diff"] = {
        close_diffs_for_client = function(client_id, reason)
          table.insert(closed, { client_id, reason })
        end,
      }
      state.clients = {
        { id = "c1", handshake_complete = true },
        { id = "c2", handshake_complete = false },
        { id = "c3", handshake_complete = true },
      }

      session_module.close(session, "tab closed")

      assert.same({ { "c1", "tab closed" }, { "c3", "tab closed" } }, closed)
      -- The answers leave before the server stops.
      assert.is_truthy(index_of("server.drain") < index_of("server.stop"))
    end)

    it("closes a session whose process already ended without stopping a job", function()
      local session = started()
      state.jobstart_calls[1].opts.on_exit(77, 0)
      log = {}
      local buf = session.buf

      session_module.close(session)

      assert.is_nil(index_of("jobstop"))
      assert.same({ buf }, state.deleted_bufs)
    end)

    it("does not wait for a job that jobstop says already ended", function()
      local session = started()
      vim.fn.jobstop = function()
        return 0
      end
      local waited = false
      stub(vim, "wait", function()
        waited = true
        return true
      end)

      session_module.close(session)

      assert.is_false(waited)
    end)

    describe("when Neovim is already deleting the buffer", function()
      it("stops the job with no wait and does not delete the buffer again", function()
        local session = started()
        local waited = false
        stub(vim, "wait", function()
          waited = true
          return true
        end)

        session_module.close(session, "buffer gone", { buf_gone = true })

        assert.equals(77, state.jobstopped)
        assert.is_false(waited)
        assert.is_nil(index_of("buf.delete"))
        assert.same({}, state.deleted_bufs)
        assert.is_nil(session.buf)
        assert.equals("exited", session.state)
      end)

      it("still deletes the buffer without the option", function()
        local session = started()
        local buf = session.buf
        stub(vim, "wait", function()
          return true
        end)

        session_module.close(session, "tab closed")

        assert.same({ buf }, state.deleted_bufs)
      end)
    end)
  end)
end)
