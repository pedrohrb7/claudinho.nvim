-- Success criterion 1 of base-ui (rules 1, 29, 30, 63, 90, 91): with three tabs and a WebSocket client on each server,
-- the selection and the @-mentions reach only the client of the active tab; switching tabs gives the new tab the
-- current selection; a second, "external" client on the server of a tab is that tab's client and leaves with it.
-- Under busted's mock vim it is pending; scripts/run_integration_tests_individually.sh runs it in Neovim.
if vim == nil or vim.fn.has("nvim") ~= 1 or (vim.uv or vim.loop) == nil or vim.wait == nil or vim.system == nil then
  describe("criterion: selection and @-mentions reach only the active tab", function()
    pending("needs a real Neovim")
  end)
  return
end

describe("criterion: selection and @-mentions reach only the active tab", function()
  local criteria = require("tests.helpers.criteria")
  local ws_client = require("tests.helpers.ws_client")

  local ctx, sessions, selection, dir, editor, clients, external

  ---Put the cursor of the editor window on a line and run the selection update the debounce would run.
  ---@param line integer
  local function move_cursor(line)
    vim.api.nvim_set_current_win(editor)
    vim.api.nvim_win_set_cursor(editor, { line, 0 })
    selection.update_selection()
  end

  ---@param client WsClient
  ---@return integer|nil line The 0-based start line of the next selection_changed, nil when none arrives
  local function selection_line(client)
    local message = criteria.next_of(client, "selection_changed", 1500)
    return message and message.params.selection.start.line or nil
  end

  ---@param clients_list WsClient[]
  ---@param method string
  ---@return integer count Messages of this method that reach the clients in the next 400 ms
  local function count_arrivals(clients_list, method)
    local total = 0
    for _, client in ipairs(clients_list) do
      total = total + #criteria.all_of(client, method, 200)
    end
    return total
  end

  before_each(function()
    ctx = criteria.start()
    sessions = ctx.sessions
    selection = require("claudinho.selection")
    dir = vim.fn.tempname() .. "-criteria-tabs"
    vim.fn.mkdir(dir, "p")
    vim.fn.writefile({ "one", "two", "three", "four" }, dir .. "/a.txt")
    vim.fn.writefile({ "alpha" }, dir .. "/b.txt")
    vim.cmd("edit " .. vim.fn.fnameescape(dir .. "/a.txt"))
    editor = vim.api.nvim_get_current_win()

    clients = {}
    for _ = 1, 3 do
      local tab = assert(sessions.new())
      table.insert(clients, ws_client.connect(tab.lock_port, tab.token))
    end
    external = nil
    assert.equals(3, sessions.state.active)
    -- Back in the editor, with tab 1 active: it is the tab that gets what is selected.
    vim.api.nvim_set_current_win(editor)
    assert.is_true(sessions.activate(1))
  end)

  after_each(function()
    for _, client in ipairs(clients) do
      client:close()
    end
    if external then
      external:close()
    end
    criteria.stop(ctx)
    vim.fn.delete(dir, "rf")
  end)

  it("sends the selection only to the client of the active tab", function()
    move_cursor(2)

    assert.equals(1, selection_line(clients[1]))
    assert.equals(0, count_arrivals({ clients[2], clients[3] }, "selection_changed"))

    assert.is_true(sessions.activate(3))
    vim.api.nvim_set_current_win(editor)
    -- Tab 3 got the current selection when it became active; moving on reaches it, not tab 1.
    assert.equals(1, selection_line(clients[3]))
    move_cursor(4)

    assert.equals(3, selection_line(clients[3]))
    assert.equals(0, count_arrivals({ clients[1], clients[2] }, "selection_changed"))
  end)

  it("gives the current selection to the tab that becomes active", function()
    move_cursor(3)
    assert.equals(2, selection_line(clients[1]))

    assert.is_true(sessions.activate(2))

    assert.equals(2, selection_line(clients[2]))
    assert.equals(0, count_arrivals({ clients[1], clients[3] }, "selection_changed"))
  end)

  it("sends an @-mention only to the client of the active tab", function()
    assert.is_true(sessions.activate(2))
    vim.api.nvim_set_current_win(editor)

    vim.cmd("Claudinho add " .. vim.fn.fnameescape(dir .. "/b.txt"))

    local mention = criteria.next_of(clients[2], "at_mentioned", 5000)
    assert.is_not_nil(mention)
    assert.matches("b%.txt$", mention.params.filePath)
    assert.equals(0, count_arrivals({ clients[1], clients[3] }, "at_mentioned"))
  end)

  it("treats a second client on the server of a tab as a client of that tab, and drops it with the tab", function()
    local tab_two = sessions.state.tabs[2]
    external = ws_client.connect(tab_two.lock_port, tab_two.token)
    assert.is_true(sessions.activate(2))
    vim.api.nvim_set_current_win(editor)
    -- Tab 2 became active: whatever was selected before arrives at both of its clients.
    count_arrivals({ clients[2], external }, "selection_changed")

    move_cursor(4)

    assert.equals(3, selection_line(clients[2]))
    assert.equals(3, selection_line(external))
    assert.equals(0, count_arrivals({ clients[1], clients[3] }, "selection_changed"))

    vim.cmd("Claudinho tab-close 2")

    assert.is_true(vim.wait(3000, function()
      return clients[2].closed and external.closed
    end, 20))
    assert.is_nil(sessions.state.tabs[2])
    assert.is_false(clients[1].closed)
    assert.is_false(clients[3].closed)
  end)
end)
