-- The routing of openDiff by tab: a client of the active tab (or of no tab) opens its diff at once; a client of a tab
-- in the background waits, the bar marks it, one notification says so, and the diff opens when the tab becomes active,
-- in the order of arrival. A rejected waiting diff answers DIFF_REJECTED with no window. The registry, the server
-- module, the window, the notifications and the diff module are fakes; tests/integration/diff_routing_spec.lua runs
-- the real ones.
require("tests.busted_setup")

describe("diff routing by tab", function()
  local sessions, open_diff
  local loaded_names = {
    "claudinho.sessions",
    "claudinho.notify",
    "claudinho.server.init",
    "claudinho.ui.window",
    "claudinho.selection",
    "claudinho.diff",
    "claudinho.tools.open_diff",
  }
  local saved_loaded, saved_senders
  local log, notices, refreshes, sent

  ---@param number integer
  ---@return table
  local function add_tab(number)
    local s = { number = number, server = { id = number }, pending_diffs = {}, state = "running", closing = false }
    sessions.state.tabs[number] = s
    sessions.state.by_server[number] = number
    return s
  end

  ---Run the openDiff handler of `client` the way the tools module does: in a coroutine, with the deferred sender the
  ---server leaves for it.
  ---@param client table|nil
  ---@param name string
  ---@return thread co
  ---@return table|nil immediate The result when the handler ended on the first resume
  local function call(client, name)
    local co = coroutine.create(function()
      return open_diff.handler({
        old_file_path = "/work/" .. name,
        new_file_path = "/work/" .. name,
        new_file_contents = "x",
        tab_name = name,
      }, client)
    end)
    local ok, result = coroutine.resume(co)
    assert.is_true(ok, tostring(result))
    if coroutine.status(co) == "suspended" then
      _G.claude_deferred_responses[tostring(co)] = function(response)
        table.insert(sent, { name = name, response = response })
      end
      return co, nil
    end
    return co, result
  end

  before_each(function()
    saved_loaded = {}
    for _, name in ipairs(loaded_names) do
      saved_loaded[name] = package.loaded[name]
      package.loaded[name] = nil
    end
    saved_senders = _G.claude_deferred_responses
    _G.claude_deferred_responses = {}
    log, notices, refreshes, sent = {}, {}, 0, {}

    package.loaded["claudinho.notify"] = {
      info = function(msg)
        table.insert(notices, msg)
      end,
      reply = function() end,
      error = function() end,
    }
    package.loaded["claudinho.server.init"] = {
      for_client = function(client)
        if type(client) == "table" and client.server_id then
          return { id = client.server_id }
        end
        return nil
      end,
    }
    package.loaded["claudinho.ui.window"] = {
      refresh = function()
        refreshes = refreshes + 1
      end,
    }
    package.loaded["claudinho.selection"] = { resend_latest = function() end }
    package.loaded["claudinho.diff"] = {
      rejected_response = function(tab_name)
        return {
          content = { { type = "text", text = "DIFF_REJECTED" }, { type = "text", text = tab_name } },
        }
      end,
      -- The diff opens and waits for the user, like the real one: it yields until it is resolved.
      open_diff_blocking = function(_, _, _, tab_name)
        table.insert(log, "open." .. tab_name)
        return coroutine.yield()
      end,
      close_pending_diffs = function()
        return 0
      end,
    }

    sessions = require("claudinho.sessions")
    open_diff = require("claudinho.tools.open_diff")
  end)

  after_each(function()
    _G.claude_deferred_responses = saved_senders
    for _, name in ipairs(loaded_names) do
      package.loaded[name] = saved_loaded[name]
    end
  end)

  it("opens at once for a client of the active tab", function()
    add_tab(1)
    add_tab(2)
    sessions.state.active = 2

    local co = call({ server_id = 2, id = "c" }, "a.lua")

    assert.same({ "open.a.lua" }, log)
    assert.equals("suspended", coroutine.status(co))
    assert.same({}, sessions.state.tabs[2].pending_diffs)
    assert.same({}, notices)
  end)

  it("opens at once for a client that belongs to no tab", function()
    add_tab(1)
    sessions.state.active = 1

    call({ server_id = 99, id = "outside" }, "a.lua")
    call(nil, "b.lua")

    assert.same({ "open.a.lua", "open.b.lua" }, log)
  end)

  it("makes the diff of a tab in the background wait, mark the tab and notify once", function()
    local first = add_tab(1)
    add_tab(2)
    sessions.state.active = 2

    local co = call({ server_id = 1, id = "c1" }, "src/login.lua")

    assert.same({}, log)
    assert.equals("suspended", coroutine.status(co))
    assert.equals(1, #first.pending_diffs)
    assert.same({ tab_name = "src/login.lua", path = "/work/src/login.lua", co = co }, first.pending_diffs[1])
    assert.equals(1, #notices)
    assert.is_truthy(notices[1]:find("Claude 1: pending diff for ", 1, true))
    assert.is_truthy(notices[1]:find("login.lua", 1, true))
    assert.is_true(refreshes >= 1)
  end)

  it("notifies once per request", function()
    add_tab(1)
    add_tab(2)
    sessions.state.active = 2

    call({ server_id = 1 }, "a.lua")
    call({ server_id = 1 }, "b.lua")

    assert.equals(2, #notices)
  end)

  it("opens the waiting diffs when the tab becomes active, in the order of arrival", function()
    local first = add_tab(1)
    add_tab(2)
    sessions.state.active = 2
    call({ server_id = 1 }, "a.lua")
    call({ server_id = 1 }, "b.lua")
    call({ server_id = 1 }, "c.lua")

    sessions.activate(1)

    assert.same({ "open.a.lua", "open.b.lua", "open.c.lua" }, log)
    assert.same({}, first.pending_diffs)
    assert.same({}, sent)
  end)

  it("keeps the waiting diffs of a tab that stays in the background", function()
    local first = add_tab(1)
    add_tab(2)
    sessions.state.active = 2
    call({ server_id = 1 }, "a.lua")

    sessions.activate(2)

    assert.same({}, log)
    assert.equals(1, #first.pending_diffs)
  end)

  it("answers DIFF_REJECTED, with no window, to a waiting diff that is rejected", function()
    local first = add_tab(1)
    add_tab(2)
    sessions.state.active = 2
    call({ server_id = 1 }, "a.lua")

    local count = sessions.reject_all_pending("user command")

    assert.equals(1, count)
    assert.same({}, log)
    assert.same({}, first.pending_diffs)
    assert.equals(1, #sent)
    assert.same({
      content = { { type = "text", text = "DIFF_REJECTED" }, { type = "text", text = "a.lua" } },
    }, sent[1].response)
  end)

  it("rejects the waiting diffs of every tab on close-all-diffs and redraws the bar", function()
    local first = add_tab(1)
    local second = add_tab(2)
    add_tab(3)
    sessions.state.active = 3
    call({ server_id = 1 }, "a.lua")
    call({ server_id = 2 }, "b.lua")
    call({ server_id = 2 }, "c.lua")
    local before = refreshes

    local count = sessions.reject_all_pending("user command")

    assert.equals(3, count)
    assert.same({}, first.pending_diffs)
    assert.same({}, second.pending_diffs)
    assert.same({ "a.lua", "b.lua", "c.lua" }, { sent[1].name, sent[2].name, sent[3].name })
    assert.is_true(refreshes > before)
  end)

  it("sends the answer of a waiting diff that resolves at once when its tab opens", function()
    add_tab(1)
    add_tab(2)
    sessions.state.active = 2
    package.loaded["claudinho.diff"].open_diff_blocking = function(_, _, _, tab_name)
      return { content = { { type = "text", text = "FILE_SAVED" }, { type = "text", text = tab_name } } }
    end
    call({ server_id = 1 }, "a.lua")

    sessions.activate(1)

    assert.equals(1, #sent)
    assert.equals("FILE_SAVED", sent[1].response.content[1].text)
  end)

  it("drops the waiting diffs with no answer when the tab ends by itself", function()
    local first = add_tab(1)
    add_tab(2)
    sessions.state.active = 2
    local co = call({ server_id = 1 }, "a.lua")

    -- A process that ended: the session empties the list (no client left to answer) and tells the registry.
    first.pending_diffs = {}
    sessions.on_exit(first)

    assert.equals("suspended", coroutine.status(co))
    assert.same({}, sent)
    assert.same({}, log)
  end)
end)
