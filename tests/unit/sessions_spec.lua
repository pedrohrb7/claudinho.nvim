--- The registry of the Claude tabs: numbers, the active tab, switching, closing, restart, kill_all, the router that
--- the selection sends through, the owner of a client, and the autocmds that end the tabs. The session, the server
--- module, the window, the selection, the diff module and the notifications are fakes that record what the registry
--- asks of them; tests/integration/sessions_spec.lua runs the real ones.
require("tests.busted_setup")

describe("sessions", function()
  local sessions
  local loaded_names = {
    "claudinho",
    "claudinho.sessions",
    "claudinho.session",
    "claudinho.notify",
    "claudinho.server.init",
    "claudinho.ui.window",
    "claudinho.selection",
    "claudinho.diff",
  }
  local saved_loaded, restore_list
  local log, state

  ---Replace tbl[key] until after_each.
  local function stub(tbl, key, value)
    table.insert(restore_list, { tbl, key, tbl[key] })
    tbl[key] = value
  end

  local function count(name)
    local total = 0
    for _, entry in ipairs(log) do
      if entry == name then
        total = total + 1
      end
    end
    return total
  end

  ---A fake server of one tab.
  local function new_server()
    state.next_server_id = state.next_server_id + 1
    local server = { id = state.next_server_id, broadcasts = {}, drained = 0 }
    function server:broadcast(method, params, on_written)
      table.insert(self.broadcasts, { method = method, params = params, on_written = on_written })
      return true
    end
    function server:get_status()
      return { clients = {} }
    end
    function server:stop()
      return true
    end
    function server:drain(ms)
      self.drained = self.drained + 1
      self.drain_ms = ms
      return true
    end
    return server
  end

  ---A coroutine that waits for a diff, recording what it was resumed with.
  local function waiting_diff(name)
    local answers = {}
    local co = coroutine.create(function()
      local answer = coroutine.yield()
      table.insert(answers, answer)
      table.insert(log, "diff." .. name .. "." .. tostring(answer))
    end)
    coroutine.resume(co)
    return { tab_name = name, path = "/work/" .. name, co = co }, answers
  end

  before_each(function()
    saved_loaded, restore_list = {}, {}
    for _, name in ipairs(loaded_names) do
      saved_loaded[name] = package.loaded[name]
      package.loaded[name] = nil
    end
    log = {}
    state = {
      next_server_id = 0,
      cwd = "/work/one",
      start_error = nil,
      notices = {},
      sessions = {},
      augroups = {},
      autocmds = {},
      for_client_calls = 0,
      resend = 0,
      resend_result = true,
      window_refresh = 0,
      window_show = {},
      diff_closed = {},
    }

    stub(vim.fn, "getcwd", function()
      return state.cwd
    end)
    stub(vim.api, "nvim_create_augroup", function(name, opts)
      table.insert(state.augroups, { name = name, opts = opts })
      return name
    end)
    stub(vim.api, "nvim_create_autocmd", function(event, opts)
      table.insert(state.autocmds, { event = event, opts = opts })
      return #state.autocmds
    end)

    package.loaded["claudinho"] = { state = { config = { terminal_cmd = "claude" } } }
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
    package.loaded["claudinho.server.init"] = {
      for_client = function(client)
        state.for_client_calls = state.for_client_calls + 1
        if type(client) ~= "table" then
          return nil
        end
        return state.servers_by_id and state.servers_by_id[client.server_id] or nil
      end,
    }
    state.servers_by_id = {}
    package.loaded["claudinho.ui.window"] = {
      show = function(opts)
        table.insert(state.window_show, opts)
        table.insert(log, "window.show")
      end,
      close = function()
        table.insert(log, "window.close")
      end,
      refresh = function()
        state.window_refresh = state.window_refresh + 1
      end,
    }
    package.loaded["claudinho.selection"] = {
      resend_latest = function()
        state.resend = state.resend + 1
        return state.resend_result
      end,
    }
    package.loaded["claudinho.diff"] = {
      close_pending_diffs = function(reason)
        table.insert(state.diff_closed, reason)
        table.insert(log, "diff.close_pending_diffs")
        return 0
      end,
    }

    -- The real session.new (it reads the folder and builds the table); the process side is a fake.
    local session = require("claudinho.session")
    session.start = function(s, extra_args)
      table.insert(log, "session.start." .. s.number)
      state.last_extra_args = extra_args
      if state.start_error then
        return false, state.start_error
      end
      s.state = "running"
      s.buf = 100 + s.number
      s.server = new_server()
      state.servers_by_id[s.server.id] = s.server
      table.insert(state.sessions, s)
      return true
    end
    session.restart = function(s)
      if s.state ~= "exited" then
        return false, "Claude " .. s.number .. " is still running"
      end
      s.state = "running"
      s.server = new_server()
      state.servers_by_id[s.server.id] = s.server
      table.insert(log, "session.restart." .. s.number)
      return true
    end
    session.close = function(s, reason)
      table.insert(log, "session.close." .. s.number)
      s.closing = true
      s.state = "exited"
      state.close_reason = reason
    end

    sessions = require("claudinho.sessions")
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

  describe("new", function()
    it("takes the lowest free number from 1", function()
      assert.equals(1, sessions.new().number)
      assert.equals(2, sessions.new().number)
      assert.equals(3, sessions.new().number)

      sessions.close(2)

      assert.equals(2, sessions.new().number)
      assert.equals(4, sessions.new().number)
    end)

    it("becomes the active tab and shows the window with the focus", function()
      local s = assert(sessions.new())

      assert.equals(s, sessions.active())
      assert.equals(1, sessions.state.active)
      assert.equals(1, #state.window_show)
      assert.is_true(state.window_show[1].focus)
      assert.is_true(state.window_refresh >= 1)
    end)

    it("keeps the folder of the window when it was created, not the one after a :cd", function()
      state.cwd = "/work/one"
      local first = assert(sessions.new())
      state.cwd = "/work/two"
      local second = assert(sessions.new())

      assert.equals("/work/one", first.cwd)
      assert.equals("/work/two", second.cwd)
      state.cwd = "/work/three"
      assert.equals("/work/one", sessions.state.tabs[1].cwd)
    end)

    it("passes the configuration of the plugin and the extra arguments to the session", function()
      local s = assert(sessions.new(" --model 'opus'"))

      assert.equals("claude", s.base_cmd)
      assert.equals(package.loaded["claudinho"].state.config, s.config)
      assert.equals(" --model 'opus'", state.last_extra_args)
    end)

    it("shows the error and leaves no tab when the session does not start", function()
      state.start_error = "Could not start Claude 1: `claude` is not executable"

      local s, err = sessions.new()

      assert.is_nil(s)
      assert.equals("Could not start Claude 1: `claude` is not executable", err)
      assert.same({ { "error", "Could not start Claude 1: `claude` is not executable" } }, state.notices)
      assert.is_nil(sessions.active())
      assert.same({}, sessions.state.tabs)
      assert.equals(0, #state.window_show)
    end)

    it("works without the window module", function()
      package.loaded["claudinho.ui.window"] = nil
      package.preload["claudinho.ui.window"] = function()
        error("module 'claudinho.ui.window' not found")
      end

      local s = sessions.new()
      package.preload["claudinho.ui.window"] = nil

      assert.is_table(s)
      assert.equals(1, sessions.state.active)
    end)
  end)

  describe("activate", function()
    it("switches the active tab, sends the selection again and redraws", function()
      sessions.new()
      sessions.new()
      assert.equals(2, sessions.state.active)
      local before_resend, before_refresh = state.resend, state.window_refresh

      assert.is_true(sessions.activate(1))

      assert.equals(1, sessions.state.active)
      assert.equals(before_resend + 1, state.resend)
      assert.equals(before_refresh + 1, state.window_refresh)
    end)

    it("does not send the selection again when the tab is already active", function()
      sessions.new()
      local before_resend, before_refresh = state.resend, state.window_refresh

      assert.is_true(sessions.activate(1))

      assert.equals(before_resend, state.resend)
      assert.equals(before_refresh + 1, state.window_refresh)
    end)

    it("answers with a reply for a tab that does not exist", function()
      sessions.new()

      local ok, err = sessions.activate(7)

      assert.is_false(ok)
      assert.equals("No Claude 7", err)
      assert.same({ { "reply", "No Claude 7" } }, state.notices)
      assert.equals(1, sessions.state.active)
    end)

    it("opens the pending diffs of the tab, in the order they arrived, and empties the list", function()
      sessions.new()
      local second = assert(sessions.new())
      local d1 = waiting_diff("a")
      local d2 = waiting_diff("b")
      local d3 = waiting_diff("c")
      local first = assert(sessions.state.tabs[1])
      first.pending_diffs = { d1, d2, d3 }
      assert.equals(second, sessions.active())

      sessions.activate(1)

      assert.same({ "diff.a.open", "diff.b.open", "diff.c.open" }, {
        log[#log - 2],
        log[#log - 1],
        log[#log],
      })
      assert.same({}, first.pending_diffs)
    end)

    it("does not open the diffs of a tab that stays in the background", function()
      sessions.new()
      local second = assert(sessions.new())
      local pending = waiting_diff("z")
      sessions.state.tabs[1].pending_diffs = { pending }

      sessions.activate(2)

      assert.equals(second, sessions.active())
      assert.equals(1, #sessions.state.tabs[1].pending_diffs)
      assert.equals("suspended", coroutine.status(pending.co))
    end)
  end)

  describe("next and prev", function()
    it("go round the tabs by number", function()
      sessions.new()
      sessions.new()
      sessions.new()
      assert.equals(3, sessions.state.active)

      sessions.next()
      assert.equals(1, sessions.state.active)
      sessions.next()
      assert.equals(2, sessions.state.active)
      sessions.prev()
      assert.equals(1, sessions.state.active)
      sessions.prev()
      assert.equals(3, sessions.state.active)
    end)

    it("skip a gap in the numbers", function()
      sessions.new()
      sessions.new()
      sessions.new()
      sessions.close(2)
      sessions.activate(1)

      sessions.next()

      assert.equals(3, sessions.state.active)
    end)

    it("do nothing with one tab or none", function()
      sessions.next()
      sessions.prev()
      assert.is_nil(sessions.state.active)

      sessions.new()
      local before = state.window_refresh
      sessions.next()
      sessions.prev()

      assert.equals(1, sessions.state.active)
      assert.equals(before, state.window_refresh)
    end)
  end)

  describe("close", function()
    it("closes the session, drops the tab and redraws", function()
      sessions.new()
      sessions.new()
      sessions.activate(1)
      local before = state.window_refresh

      assert.is_true(sessions.close(2))

      assert.equals(1, count("session.close.2"))
      assert.is_nil(sessions.state.tabs[2])
      assert.equals(1, sessions.state.active)
      assert.is_true(state.window_refresh > before)
    end)

    it("activates the neighbour with the higher number, else the lower one", function()
      sessions.new()
      sessions.new()
      sessions.new()
      sessions.activate(2)

      sessions.close(2)
      assert.equals(3, sessions.state.active)

      sessions.close(3)
      assert.equals(1, sessions.state.active)
    end)

    it("closes the window when the last tab closes", function()
      sessions.new()

      sessions.close(1)

      assert.is_nil(sessions.state.active)
      assert.is_nil(sessions.active())
      assert.equals(1, count("window.close"))
    end)

    it("does not close the window while a tab is left", function()
      sessions.new()
      sessions.new()

      sessions.close(1)

      assert.equals(0, count("window.close"))
    end)

    it("replies when the tab does not exist", function()
      local ok, err = sessions.close(4)

      assert.is_false(ok)
      assert.equals("No Claude 4", err)
      assert.same({ { "reply", "No Claude 4" } }, state.notices)
    end)

    it("forgets the server of the tab", function()
      local s = assert(sessions.new())
      local server_id = s.server.id
      assert.equals(1, sessions.state.by_server[server_id])

      sessions.close(1)

      assert.is_nil(sessions.state.by_server[server_id])
    end)
  end)

  describe("restart", function()
    it("needs a tab number", function()
      sessions.new()

      local ok, err = sessions.restart(nil)

      assert.is_false(ok)
      assert.equals("tab-restart needs a tab number", err)
      assert.same({ { "reply", "tab-restart needs a tab number" } }, state.notices)
      assert.equals(0, count("session.restart.1"))
    end)

    it("answers that a running tab is still running", function()
      sessions.new()

      local ok, err = sessions.restart(1)

      assert.is_false(ok)
      assert.equals("Claude 1 is still running", err)
      assert.same({ { "reply", "Claude 1 is still running" } }, state.notices)
    end)

    it("replies when the tab does not exist", function()
      local ok, err = sessions.restart(3)

      assert.is_false(ok)
      assert.equals("No Claude 3", err)
    end)

    it("starts an exited tab again, maps its new server and redraws", function()
      local s = assert(sessions.new())
      local old_id = s.server.id
      sessions.on_exit(s)
      s.state = "exited"
      s.server = nil
      local before = state.window_refresh

      assert.is_true(sessions.restart(1))

      assert.equals(1, count("session.restart.1"))
      assert.is_nil(sessions.state.by_server[old_id])
      assert.equals(1, sessions.state.by_server[s.server.id])
      assert.is_true(state.window_refresh > before)
    end)

    it("shows the error of a restart that fails on an exited tab", function()
      local s = assert(sessions.new())
      s.state = "exited"
      require("claudinho.session").restart = function()
        return false, "Could not start Claude 1: the command did not start"
      end

      local ok, err = sessions.restart(1)

      assert.is_false(ok)
      assert.equals("Could not start Claude 1: the command did not start", err)
      assert.same({ { "error", "Could not start Claude 1: the command did not start" } }, state.notices)
    end)
  end)

  describe("kill_all", function()
    it("rejects the open and the waiting diffs, drains each server, closes each session and the window", function()
      local first = assert(sessions.new())
      local second = assert(sessions.new())
      local d1, answers1 = waiting_diff("a")
      local d2, answers2 = waiting_diff("b")
      first.pending_diffs = { d1 }
      second.pending_diffs = { d2 }
      local server1, server2 = first.server, second.server

      sessions.kill_all()

      assert.same({ "reject" }, answers1)
      assert.same({ "reject" }, answers2)
      assert.same({ "all tabs closed" }, state.diff_closed)
      assert.equals(1, server1.drained)
      assert.equals(1, server2.drained)
      assert.equals(200, server1.drain_ms)
      assert.equals(1, count("session.close.1"))
      assert.equals(1, count("session.close.2"))
      assert.equals(1, count("window.close"))
      assert.same({}, sessions.state.tabs)
      assert.same({}, sessions.state.by_server)
      assert.is_nil(sessions.state.active)
    end)

    it("rejects before it drains and drains before it closes", function()
      local first = assert(sessions.new())
      first.pending_diffs = { (waiting_diff("a")) }
      local position = {}
      local original_drain = first.server.drain
      first.server.drain = function(...)
        table.insert(log, "server.drain")
        return original_drain(...)
      end

      sessions.kill_all()

      for i, entry in ipairs(log) do
        position[entry] = position[entry] or i
      end
      assert.is_true(position["diff.close_pending_diffs"] < position["server.drain"])
      assert.is_true(position["diff.a.reject"] < position["server.drain"])
      assert.is_true(position["server.drain"] < position["session.close.1"])
      assert.is_true(position["session.close.1"] < position["window.close"])
    end)

    it("touches only the sessions of its own registry", function()
      local own = assert(sessions.new())
      local foreign = require("claudinho.session").new(9, {})
      foreign.server = new_server()

      sessions.kill_all()

      assert.equals(1, count("session.close." .. own.number))
      assert.equals(0, count("session.close.9"))
      assert.equals(0, foreign.server.drained)
    end)

    it("is safe with no tabs and when it runs twice", function()
      sessions.kill_all()
      sessions.new()
      sessions.kill_all()
      sessions.kill_all()

      assert.equals(1, count("session.close.1"))
    end)

    it("does not need the diff module when it was never loaded", function()
      package.loaded["claudinho.diff"] = nil
      sessions.new()

      sessions.kill_all()

      assert.equals(1, count("session.close.1"))
    end)
  end)

  describe("reject_all_pending", function()
    it("answers reject to the waiting diffs of every tab and leaves the open ones", function()
      local first = assert(sessions.new())
      local second = assert(sessions.new())
      local d1, answers1 = waiting_diff("a")
      local d2, answers2 = waiting_diff("b")
      first.pending_diffs = { d1 }
      second.pending_diffs = { d2 }

      assert.equals(2, sessions.reject_all_pending("user command"))

      assert.same({ "reject" }, answers1)
      assert.same({ "reject" }, answers2)
      assert.same({}, first.pending_diffs)
      assert.same({}, state.diff_closed)
    end)
  end)

  describe("active and for_client", function()
    it("active is nil without tabs", function()
      assert.is_nil(sessions.active())
    end)

    it("for_client gives the tab that owns the server of the client", function()
      local first = assert(sessions.new())
      local second = assert(sessions.new())

      assert.equals(first, sessions.for_client({ server_id = first.server.id }))
      assert.equals(second, sessions.for_client({ server_id = second.server.id }))
    end)

    it("for_client gives nil for a client of no known server and for nil", function()
      sessions.new()

      assert.is_nil(sessions.for_client({ server_id = 99 }))
      assert.is_nil(sessions.for_client(nil))
    end)

    it("for_client gives nil for a server that no tab owns", function()
      sessions.new()
      local stranger = new_server()
      state.servers_by_id[stranger.id] = stranger

      assert.is_nil(sessions.for_client({ server_id = stranger.id }))
    end)
  end)

  describe("on_change and on_exit", function()
    it("on_change redraws for a tab of the registry", function()
      local s = assert(sessions.new())
      local before = state.window_refresh

      sessions.on_change(s)

      assert.equals(before + 1, state.window_refresh)
    end)

    it("on_change ignores a session that is not a tab", function()
      sessions.new()
      local before = state.window_refresh

      sessions.on_change(require("claudinho.session").new(8, {}))

      assert.equals(before, state.window_refresh)
    end)

    it("on_exit tells the user, forgets the server and redraws", function()
      local s = assert(sessions.new())
      local server_id = s.server.id
      local before = state.window_refresh

      sessions.on_exit(s)

      assert.same({ { "info", "Claude 1 exited" } }, state.notices)
      assert.is_nil(sessions.state.by_server[server_id])
      assert.equals(before + 1, state.window_refresh)
      assert.equals(s, sessions.state.tabs[1])
    end)

    it("on_exit ignores a session that is not a tab", function()
      sessions.on_exit(require("claudinho.session").new(8, {}))

      assert.same({}, state.notices)
    end)
  end)

  describe("router", function()
    it("sends to the server of the active running tab", function()
      local first = assert(sessions.new())
      local second = assert(sessions.new())
      local on_written = function() end

      assert.is_true(sessions.router.broadcast("selection_changed", { a = 1 }, on_written))

      assert.equals(0, #first.server.broadcasts)
      assert.equals(1, #second.server.broadcasts)
      assert.equals("selection_changed", second.server.broadcasts[1].method)
      assert.same({ a = 1 }, second.server.broadcasts[1].params)
      assert.equals(on_written, second.server.broadcasts[1].on_written)
    end)

    it("follows the active tab", function()
      local first = assert(sessions.new())
      sessions.new()
      sessions.activate(1)

      sessions.router.broadcast("selection_changed", {})

      assert.equals(1, #first.server.broadcasts)
    end)

    it("gives false without tabs", function()
      assert.is_false(sessions.router.broadcast("selection_changed", {}))
    end)

    it("gives false when the active tab has exited, and sends nothing to the others", function()
      local first = assert(sessions.new())
      local second = assert(sessions.new())
      second.state = "exited"

      assert.is_false(sessions.router.broadcast("selection_changed", {}))
      assert.equals(0, #first.server.broadcasts)
      assert.equals(0, #second.server.broadcasts)
    end)
  end)

  describe("setup_autocmds", function()
    local function callback_of(event)
      for _, entry in ipairs(state.autocmds) do
        local events = type(entry.event) == "table" and entry.event or { entry.event }
        for _, name in ipairs(events) do
          if name == event then
            return entry.opts.callback, entry.opts
          end
        end
      end
      return nil
    end

    it("registers ExitPre, VimLeavePre, BufDelete and BufWipeout in one cleared group", function()
      sessions.setup_autocmds()

      assert.equals(1, #state.augroups)
      assert.equals("ClaudinhoSessions", state.augroups[1].name)
      assert.is_true(state.augroups[1].opts.clear)
      assert.is_function(callback_of("ExitPre"))
      assert.is_function(callback_of("VimLeavePre"))
      assert.is_function(callback_of("BufDelete"))
      assert.is_function(callback_of("BufWipeout"))
      for _, entry in ipairs(state.autocmds) do
        assert.equals("ClaudinhoSessions", entry.opts.group)
      end
    end)

    it("can run twice: each call clears the group", function()
      sessions.setup_autocmds()
      sessions.setup_autocmds()

      assert.equals(2, #state.augroups)
      assert.is_true(state.augroups[2].opts.clear)
    end)

    it("ExitPre rejects the diffs and drains the servers while the sessions stay alive", function()
      local s = assert(sessions.new())
      local d, answers = waiting_diff("a")
      s.pending_diffs = { d }
      sessions.setup_autocmds()

      callback_of("ExitPre")()

      assert.same({ "reject" }, answers)
      assert.same({ "Neovim exiting" }, state.diff_closed)
      assert.equals(1, s.server.drained)
      assert.equals(0, count("session.close.1"))
      assert.equals(s, sessions.state.tabs[1])
    end)

    it("ExitPre stops the process of every tab with a job, so :wqa meets no running job", function()
      local first = assert(sessions.new())
      local second = assert(sessions.new())
      first.job, second.job = 11, 12
      local stopped = {}
      stub(vim.fn, "jobstop", function(job)
        table.insert(stopped, job)
        return 1
      end)
      sessions.setup_autocmds()

      callback_of("ExitPre")()

      assert.same({ 11, 12 }, stopped)
      assert.equals(first, sessions.state.tabs[1])
      assert.equals(second, sessions.state.tabs[2])
    end)

    it("VimLeavePre does the rest of kill_all", function()
      sessions.new()
      sessions.new()
      sessions.setup_autocmds()

      callback_of("VimLeavePre")()

      assert.equals(1, count("session.close.1"))
      assert.equals(1, count("session.close.2"))
      assert.same({}, sessions.state.tabs)
    end)

    it("BufWipeout of the buffer of a tab closes the tab", function()
      local first = assert(sessions.new())
      local second = assert(sessions.new())
      sessions.setup_autocmds()

      callback_of("BufWipeout")({ buf = first.buf })

      assert.equals(1, count("session.close.1"))
      assert.is_nil(sessions.state.tabs[1])
      assert.equals(second, sessions.state.tabs[2])
      assert.equals(2, sessions.state.active)
    end)

    it("BufDelete of the buffer of a tab closes the tab", function()
      local s = assert(sessions.new())
      sessions.setup_autocmds()

      callback_of("BufDelete")({ buf = s.buf })

      assert.equals(1, count("session.close.1"))
      assert.is_nil(sessions.state.tabs[1])
    end)

    it("ignores a buffer that is not a tab and a tab that is already closing", function()
      local s = assert(sessions.new())
      sessions.setup_autocmds()

      callback_of("BufWipeout")({ buf = 9999 })
      s.closing = true
      callback_of("BufWipeout")({ buf = s.buf })

      assert.equals(0, count("session.close.1"))
      assert.equals(s, sessions.state.tabs[1])
    end)
    describe("with the real session close", function()
      local deleted

      before_each(function()
        -- The registry's closing calls the real session.close; only the Neovim API under it is a fake.
        local fake = package.loaded["claudinho.session"]
        package.loaded["claudinho.session"] = nil
        local real = require("claudinho.session")
        package.loaded["claudinho.session"] = fake
        fake.close = real.close
        deleted = {}
        stub(vim.api, "nvim_buf_is_valid", function()
          return true
        end)
        stub(vim.api, "nvim_buf_delete", function(buf)
          table.insert(deleted, buf)
        end)
      end)

      it("does not delete the buffer again when the tab closes from BufWipeout", function()
        local s = assert(sessions.new())
        local buf = s.buf
        sessions.setup_autocmds()

        callback_of("BufWipeout")({ buf = buf })

        assert.is_nil(sessions.state.tabs[1])
        assert.same({}, deleted)
      end)

      it("does not delete the buffer again when the tab closes from BufDelete", function()
        local s = assert(sessions.new())
        local buf = s.buf
        sessions.setup_autocmds()

        callback_of("BufDelete")({ buf = buf })

        assert.is_nil(sessions.state.tabs[1])
        assert.same({}, deleted)
      end)

      it("still deletes the buffer when the tab is closed by the user", function()
        local s = assert(sessions.new())
        local buf = s.buf

        sessions.close(1)

        assert.is_nil(sessions.state.tabs[1])
        assert.same({ buf }, deleted)
      end)
    end)
  end)
end)
