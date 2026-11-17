--- The plugin module: what `setup` does (and does not: no server, no lock file, no process), the @-mention send to the
--- active tab, and the model choice. The tab registry, the commands, the selection, the terminal facade and the diff
--- module are fakes that record what `init` asks of them.
require("tests.busted_setup")

describe("claudinho.init", function()
  local claudinho
  local loaded_names = {
    "claudinho",
    "claudinho.conflict",
    "claudinho.sessions",
    "claudinho.commands",
    "claudinho.selection",
    "claudinho.terminal",
    "claudinho.diff",
    "claudinho.server.init",
    "claudinho.lockfile",
    "claudinho.notify",
  }
  local saved_loaded, restore_list
  local log, state

  ---Replace tbl[key] until after_each.
  local function stub(tbl, key, value)
    table.insert(restore_list, { tbl, key, tbl[key] })
    tbl[key] = value
  end

  ---@param name string
  ---@return integer How many times the log has the entry
  local function count(name)
    local total = 0
    for _, entry in ipairs(log) do
      if entry == name then
        total = total + 1
      end
    end
    return total
  end

  ---A fake mention queue of one tab.
  local function new_queue()
    local queue = { enqueued = {}, sent = {}, connected = false, send_result = { true, nil, nil } }
    function queue:is_connected()
      return self.connected
    end
    function queue:enqueue(file_path, start_line, end_line)
      table.insert(self.enqueued, { file_path, start_line, end_line })
      if self.format_error then
        return nil, self.format_error
      end
      return { file_path = file_path }
    end
    function queue:send(file_path, start_line, end_line)
      table.insert(self.sent, { file_path, start_line, end_line })
      return unpack(self.send_result)
    end
    return queue
  end

  ---A fake tab.
  local function new_tab(number, tab_state)
    return { number = number, state = tab_state or "running", queue = new_queue() }
  end

  before_each(function()
    saved_loaded, restore_list = {}, {}
    for _, name in ipairs(loaded_names) do
      saved_loaded[name] = package.loaded[name]
      package.loaded[name] = nil
    end
    log = {}
    state = { active = nil, new_error = nil, notices = {}, autocmds = {}, selects = {} }

    package.loaded["claudinho.conflict"] = {
      warn = function(notify_enabled)
        state.warn_notify = notify_enabled
        return state.conflict == true
      end,
    }
    package.loaded["claudinho.notify"] = {
      info = function(msg)
        table.insert(state.notices, { "info", msg })
      end,
      reply = function(msg)
        table.insert(state.notices, { "reply", msg })
      end,
      error = function(msg)
        table.insert(state.notices, { "error", msg })
      end,
    }
    local router = { broadcast = function() end }
    package.loaded["claudinho.sessions"] = {
      NO_TABS = "No Claude tabs open",
      router = router,
      active = function()
        return state.active
      end,
      new = function(extra_args)
        table.insert(log, "sessions.new" .. (extra_args or ""))
        if state.new_error then
          return nil, state.new_error
        end
        state.active = new_tab(1)
        return state.active
      end,
      setup_autocmds = function()
        table.insert(log, "sessions.setup_autocmds")
      end,
      exited_message = function(s)
        return ("Claude %d has exited; run :Claudinho tab-restart %d"):format(s.number, s.number)
      end,
    }
    package.loaded["claudinho.commands"] = {
      setup = function(config)
        table.insert(log, "commands.setup")
        state.commands_config = config
      end,
    }
    package.loaded["claudinho.selection"] = {
      enable = function(target, delay)
        table.insert(log, "selection.enable")
        state.selection_target, state.selection_delay = target, delay
      end,
    }
    package.loaded["claudinho.terminal"] = {
      setup = function(term_config)
        table.insert(log, "terminal.setup")
        state.terminal_config = term_config
      end,
      open = function()
        table.insert(log, "terminal.open")
      end,
      ensure_visible = function()
        table.insert(log, "terminal.ensure_visible")
      end,
      send_to_terminal = function(text)
        table.insert(log, "terminal.send_to_terminal " .. text)
        return true
      end,
    }
    package.loaded["claudinho.diff"] = {
      setup = function()
        table.insert(log, "diff.setup")
      end,
    }
    -- Nothing in `setup` may start a server or write a lock file (rule 2).
    package.loaded["claudinho.server.init"] = setmetatable({}, {
      __index = function(_, key)
        error("init touched the server module: " .. tostring(key))
      end,
    })
    package.loaded["claudinho.lockfile"] = setmetatable({}, {
      __index = function(_, key)
        error("init touched the lock file module: " .. tostring(key))
      end,
    })

    stub(vim.fn, "shellescape", function(value)
      return "'" .. value .. "'"
    end)
    stub(vim, "ui", {
      select = function(items, opts, on_choice)
        table.insert(state.selects, { items = items, opts = opts })
        state.on_choice = on_choice
      end,
    })

    claudinho = require("claudinho")
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

  describe("setup", function()
    it("sets up the terminal facade, the diff, the selection, the tabs and the commands, in that order", function()
      claudinho.setup()

      assert.are.same({
        "terminal.setup",
        "diff.setup",
        "selection.enable",
        "sessions.setup_autocmds",
        "commands.setup",
      }, log)
      assert.is_true(claudinho.state.initialized)
    end)

    it("starts no server and writes no lock file", function()
      -- The fakes of both modules raise on any access.
      assert.has_no.errors(function()
        claudinho.setup()
      end)
    end)

    it("points the selection at the router of the tabs, with the demotion delay of the configuration", function()
      claudinho.setup({ visual_demotion_delay_ms = 123 })

      assert.are.equal(package.loaded["claudinho.sessions"].router, state.selection_target)
      assert.are.equal(123, state.selection_delay)
    end)

    it("does not enable the selection with track_selection = false", function()
      claudinho.setup({ track_selection = false })

      assert.is_nil(state.selection_target)
      assert.are.equal(0, count("selection.enable"))
    end)

    it("gives the terminal facade the terminal table and the commands the whole configuration", function()
      claudinho.setup({ keymaps = { preset = true } })

      assert.are.equal(claudinho.state.config.terminal, state.terminal_config)
      assert.are.equal(claudinho.state.config, state.commands_config)
      assert.is_true(state.commands_config.keymaps.preset)
    end)

    it("sets up normally when claudecode.nvim is detected, passing the notify flag to the warning", function()
      state.conflict = true

      local returned = claudinho.setup({ notify = true })

      assert.are.equal(claudinho, returned)
      assert.is_true(state.warn_notify)
      assert.is_true(claudinho.state.initialized)
      assert.are.equal(1, count("commands.setup"))
    end)

    it("can run twice", function()
      claudinho.setup()
      claudinho.setup()

      assert.are.equal(2, count("commands.setup"))
      assert.is_true(claudinho.state.initialized)
    end)
  end)

  describe("the API that left", function()
    it("has no start, stop, queue of its own or command creation", function()
      for _, name in ipairs({
        "start",
        "stop",
        "default_queue",
        "process_mention_queue",
        "_create_commands",
        "_maybe_warn_unfocusable_provider",
        "_ensure_terminal_visible_if_connected",
      }) do
        assert.is_nil(claudinho[name], name)
      end
    end)

    it("keeps no server in its state", function()
      assert.is_nil(claudinho.state.server)
      assert.is_nil(claudinho.state.port)
      assert.is_nil(claudinho.state.auth_token)
    end)
  end)

  describe("is_claude_connected", function()
    it("is false without tabs", function()
      assert.is_false(claudinho.is_claude_connected())
    end)

    it("follows the queue of the active tab", function()
      state.active = new_tab(1)
      assert.is_false(claudinho.is_claude_connected())

      state.active.queue.connected = true
      assert.is_true(claudinho.is_claude_connected())
    end)

    it("is false when the active tab has exited", function()
      state.active = new_tab(2, "exited")
      state.active.queue.connected = true

      assert.is_false(claudinho.is_claude_connected())
    end)
  end)

  describe("send_at_mention", function()
    local fired

    before_each(function()
      fired = {}
      stub(vim.api, "nvim_exec_autocmds", function(event, opts)
        table.insert(fired, { event = event, opts = opts })
      end)
      claudinho.state.config = { focus_after_send = false }
    end)

    it("starts the first tab without tabs and queues the mention there", function()
      local ok, err = claudinho.send_at_mention("/work/a.lua", 1, 2, "test")

      assert.is_true(ok)
      assert.is_nil(err)
      assert.are.same({ "sessions.new" }, log)
      assert.are.same({ { "/work/a.lua", 1, 2 } }, state.active.queue.enqueued)
      assert.are.same({}, state.active.queue.sent)
    end)

    it("returns the error of a tab that could not start", function()
      state.new_error = "Could not start Claude 1: nope"

      local ok, err = claudinho.send_at_mention("/work/a.lua")

      assert.is_false(ok)
      assert.are.equal("Could not start Claude 1: nope", err)
    end)

    it("returns the format error of a path the queue cannot take", function()
      local ok, err

      -- The tab starts first, with a queue that refuses the path.
      local sessions = package.loaded["claudinho.sessions"]
      local original_new = sessions.new
      sessions.new = function(...)
        local s = original_new(...)
        s.queue.format_error = "path does not exist"
        return s
      end
      ok, err = claudinho.send_at_mention("/work/missing.lua")

      assert.is_false(ok)
      assert.are.equal("path does not exist", err)
    end)

    it("sends at once to a connected tab, keeps the window visible and fires ClaudinhoSendComplete", function()
      state.active = new_tab(1)
      state.active.queue.connected = true
      state.active.queue.send_result = { true, nil, { file_path = "/work/a.lua", start_line = 3, end_line = 4 } }

      local ok = claudinho.send_at_mention("/work/a.lua", 3, 4, "ctx")

      assert.is_true(ok)
      assert.are.same({ { "/work/a.lua", 3, 4 } }, state.active.queue.sent)
      assert.are.same({ "terminal.ensure_visible" }, log)
      assert.are.equal("User", fired[1].event)
      assert.are.equal("ClaudinhoSendComplete", fired[1].opts.pattern)
      assert.are.same({ file_path = "/work/a.lua", start_line = 3, end_line = 4, context = "ctx" }, fired[1].opts.data)
    end)

    it("focuses the terminal after a send with focus_after_send", function()
      claudinho.state.config = { focus_after_send = true }
      state.active = new_tab(1)
      state.active.queue.connected = true

      claudinho.send_at_mention("/work/a.lua")

      assert.are.same({ "terminal.open" }, log)
    end)

    it("fires nothing when the queue refuses the send", function()
      state.active = new_tab(1)
      state.active.queue.connected = true
      state.active.queue.send_result = { false, "refused", nil }

      local ok, err = claudinho.send_at_mention("/work/a.lua")

      assert.is_false(ok)
      assert.are.equal("refused", err)
      assert.are.same({}, fired)
      assert.are.same({}, log)
    end)

    it("queues for a tab that has not connected yet and shows the window", function()
      state.active = new_tab(1)

      local ok = claudinho.send_at_mention("/work/a.lua", nil, nil, "test")

      assert.is_true(ok)
      assert.are.same({ { "/work/a.lua" } }, state.active.queue.enqueued)
      assert.are.same({}, state.active.queue.sent)
      assert.are.same({ "terminal.open" }, log)
      assert.are.same({}, fired)
    end)

    it("sends nothing to a tab that has exited and says how to bring it back", function()
      state.active = new_tab(2, "exited")

      local ok, err = claudinho.send_at_mention("/work/a.lua")

      assert.is_false(ok)
      assert.are.equal("Claude 2 has exited; run :Claudinho tab-restart 2", err)
      assert.are.same({}, state.active.queue.enqueued)
      assert.are.same({}, state.active.queue.sent)
    end)
  end)

  describe("_broadcast_at_mention", function()
    it("answers without tabs", function()
      local ok, err = claudinho._broadcast_at_mention("/work/a.lua")

      assert.is_false(ok)
      assert.are.equal("No Claude tabs open", err)
    end)

    it("sends through the queue of the active tab", function()
      state.active = new_tab(1)

      assert.is_true(claudinho._broadcast_at_mention("/work/a.lua", 0, 1))
      assert.are.same({ { "/work/a.lua", 0, 1 } }, state.active.queue.sent)
    end)

    it("answers for a tab that has exited", function()
      state.active = new_tab(3, "exited")

      local ok, err = claudinho._broadcast_at_mention("/work/a.lua")

      assert.is_false(ok)
      assert.are.equal("Claude 3 has exited; run :Claudinho tab-restart 3", err)
    end)
  end)

  describe("open_with_model", function()
    before_each(function()
      claudinho.state.config = {
        models = { { name = "Opus", value = "opus" }, { name = "Opus 1M", value = "opus[1m]" } },
      }
    end)

    it("starts the first tab with --model when there are no tabs", function()
      claudinho.open_with_model()
      state.on_choice(claudinho.state.config.models[2])

      assert.are.same({ "sessions.new --model 'opus[1m]'" }, log)
    end)

    it("sends /model to the running active tab", function()
      state.active = new_tab(1)

      claudinho.open_with_model()
      state.on_choice(claudinho.state.config.models[1])

      assert.are.same({ "terminal.send_to_terminal /model opus" }, log)
    end)

    it("replies and shows no choice when the active tab has exited", function()
      state.active = new_tab(2, "exited")

      claudinho.open_with_model()

      assert.are.same({}, state.selects)
      assert.are.same({ { "reply", "Claude 2 has exited; run :Claudinho tab-restart 2" } }, state.notices)
    end)

    it("replies when the tab exits while the choice is open", function()
      state.active = new_tab(1)

      claudinho.open_with_model()
      state.active.state = "exited"
      state.on_choice(claudinho.state.config.models[1])

      assert.are.same({}, log)
      assert.are.same({ { "reply", "Claude 1 has exited; run :Claudinho tab-restart 1" } }, state.notices)
    end)

    it("does nothing when the choice is cancelled", function()
      claudinho.open_with_model()
      state.on_choice(nil)

      assert.are.same({}, log)
    end)

    it("lists the models by name", function()
      claudinho.open_with_model()

      assert.are.equal(claudinho.state.config.models, state.selects[1].items)
      assert.are.equal("Opus 1M", state.selects[1].opts.format_item(claudinho.state.config.models[2]))
    end)
  end)

  describe("get_version", function()
    it("describes the version", function()
      local version = claudinho.get_version()

      assert.are.equal(claudinho.version:string(), version.version)
      assert.are.equal("number", type(version.major))
    end)
  end)
end)
