-- Success criterion 2 of base-ui (rule 87): hiding, showing, toggling, switching tabs and changing the layout never end
-- a session. After 10 cycles of each, the process of every tab is the one that started it and the three still run.
-- Under busted's mock vim it is pending; scripts/run_integration_tests_individually.sh runs it in Neovim.
if vim == nil or vim.fn.has("nvim") ~= 1 or (vim.uv or vim.loop) == nil or vim.wait == nil or vim.system == nil then
  describe("criterion: window cycles never end a session", function()
    pending("needs a real Neovim")
  end)
  return
end

describe("criterion: window cycles never end a session", function()
  local criteria = require("tests.helpers.criteria")

  local CYCLES = 10

  local ctx, sessions, window, pids

  ---@return integer[] pids The job pid of each of the three tabs, by number
  local function job_pids()
    local found = {}
    for number = 1, 3 do
      local tab = sessions.state.tabs[number]
      found[number] = tab and vim.b[tab.buf].terminal_job_pid or false
    end
    return found
  end

  local function assert_same_sessions()
    assert.same(pids, job_pids())
    for number = 1, 3 do
      local tab = sessions.state.tabs[number]
      assert.is_not_nil(tab, "tab " .. number .. " is gone")
      assert.equals("running", tab.state)
      assert.equals(pids[number], tab.pid)
      assert.is_true(criteria.alive(pids[number]), "process of tab " .. number .. " ended")
    end
    assert.equals(3, #criteria.lock_files(ctx.env.lock_dir))
  end

  before_each(function()
    ctx = criteria.start()
    sessions = ctx.sessions
    window = require("claudinho.ui.window")
    for _ = 1, 3 do
      assert(sessions.new())
    end
    pids = job_pids()
    for number = 1, 3 do
      assert.is_true(type(pids[number]) == "number" and pids[number] > 0)
    end
    assert_same_sessions()
  end)

  after_each(function()
    criteria.stop(ctx)
  end)

  it("keeps the three processes through 10 cycles of hide and open", function()
    for _ = 1, CYCLES do
      vim.cmd("Claudinho hide")
      assert.is_false(window.is_visible())
      vim.cmd("Claudinho open")
      assert.is_true(window.is_visible())
    end

    assert_same_sessions()
  end)

  it("keeps the three processes through 10 cycles of toggle", function()
    local visible = window.is_visible()
    for _ = 1, CYCLES * 2 do
      vim.cmd("Claudinho toggle")
      assert.is_not.equals(visible, window.is_visible())
      visible = window.is_visible()
    end

    assert_same_sessions()
  end)

  it("keeps the three processes through 10 cycles of tab switching", function()
    for _ = 1, CYCLES do
      for number = 1, 3 do
        vim.cmd("Claudinho tab " .. number)
        assert.equals(number, sessions.state.active)
      end
      vim.cmd("Claudinho tab-next")
      vim.cmd("Claudinho tab-prev")
    end

    assert_same_sessions()
  end)

  it("keeps the three processes through 10 cycles of layout changes", function()
    local layouts = { "right", "bottom", "float", "tab", "left" }
    local config = ctx.plugin.state.config
    for cycle = 1, CYCLES do
      -- A layout is read when the window opens, so each pass hides the window and opens it in the next layout.
      vim.cmd("Claudinho hide")
      config.window.layout = layouts[(cycle - 1) % #layouts + 1]
      vim.cmd("Claudinho open")
      assert.is_true(window.is_visible(), "not visible with layout " .. config.window.layout)
      -- The layout really changed: only the float is a floating window.
      local floating = vim.api.nvim_win_get_config(window.win()).relative ~= ""
      assert.equals(config.window.layout == "float", floating, "layout " .. config.window.layout)
    end

    assert_same_sessions()
  end)
end)
