require("tests.busted_setup")
local temp_dir = require("tests.helpers.temp_dir")

describe("Diff auto_resize_terminal flag", function()
  local diff = require("claudinho.diff")

  it("defaults to enabled when diff_opts is empty", function()
    diff.setup({ terminal = {}, diff_opts = {} })
    assert.is_true(diff._auto_resize_enabled())
  end)

  it("defaults to enabled when diff_opts is absent", function()
    diff.setup({ terminal = {} })
    assert.is_true(diff._auto_resize_enabled())
  end)

  it("is enabled when explicitly true", function()
    diff.setup({ terminal = {}, diff_opts = { auto_resize_terminal = true } })
    assert.is_true(diff._auto_resize_enabled())
  end)

  it("is disabled only when explicitly false", function()
    diff.setup({ terminal = {}, diff_opts = { auto_resize_terminal = false } })
    assert.is_false(diff._auto_resize_enabled())
  end)
end)

describe("resize_terminal_for_diff gating", function()
  local diff = require("claudinho.diff")

  -- Drive the resize helper with controlled window APIs and capture set_width calls.
  local function capture_resize(opts)
    local saved = {
      valid = vim.api.nvim_win_is_valid,
      cfg = vim.api.nvim_win_get_config,
      setw = vim.api.nvim_win_set_width,
      cols = vim.o.columns,
    }
    local calls = {}
    vim.o.columns = 200
    vim.api.nvim_win_is_valid = function()
      return opts.valid ~= false
    end
    vim.api.nvim_win_get_config = function()
      return { relative = opts.floating and "editor" or "" }
    end
    vim.api.nvim_win_set_width = function(w, width)
      calls[#calls + 1] = { win = w, width = width }
    end

    diff.setup({ window = opts.window or {}, diff_opts = opts.diff_opts or {} })
    diff._resize_terminal_for_diff(opts.win or 4242, opts.when or "diff")

    vim.api.nvim_win_is_valid = saved.valid
    vim.api.nvim_win_get_config = saved.cfg
    vim.api.nvim_win_set_width = saved.setw
    vim.o.columns = saved.cols
    return calls
  end

  it("resizes a split terminal to the diff width when enabled", function()
    local calls = capture_resize({
      window = { right = { width = 0.5, diff_width = 0.2 } },
      diff_opts = { auto_resize_terminal = true },
      when = "diff",
    })
    assert.are.equal(1, #calls)
    assert.are.equal(math.floor(200 * 0.2), calls[1].width) -- 40
  end)

  it("restores to the idle width when phase is idle", function()
    local calls = capture_resize({
      window = { right = { width = 0.5, diff_width = 0.2 } },
      diff_opts = { auto_resize_terminal = true },
      when = "idle",
    })
    assert.are.equal(1, #calls)
    assert.are.equal(math.floor(200 * 0.5), calls[1].width) -- 100
  end)

  it("does NOT resize when auto_resize_terminal is false", function()
    local calls = capture_resize({
      window = { right = { width = 0.5, diff_width = 0.2 } },
      diff_opts = { auto_resize_terminal = false },
      when = "diff",
    })
    assert.are.equal(0, #calls)
  end)

  it("does NOT resize a floating terminal window", function()
    local calls = capture_resize({
      window = { right = { width = 0.5, diff_width = 0.2 } },
      diff_opts = { auto_resize_terminal = true },
      floating = true,
      when = "diff",
    })
    assert.are.equal(0, #calls)
  end)

  it("does NOT resize when window.layout is bottom, float or tab", function()
    for _, layout in ipairs({ "bottom", "float", "tab" }) do
      local calls = capture_resize({
        window = { layout = layout, right = { width = 0.5, diff_width = 0.2 } },
        diff_opts = { auto_resize_terminal = true },
        when = "diff",
      })
      assert.are.equal(0, #calls, layout)
    end
  end)

  it("resizes when window.layout is right", function()
    local calls = capture_resize({
      window = { layout = "right", right = { width = 0.5, diff_width = 0.2 } },
      diff_opts = { auto_resize_terminal = true },
      when = "diff",
    })
    assert.are.equal(1, #calls)
  end)

  it("resizes when window.layout is left, with window.left's widths", function()
    local calls = capture_resize({
      window = { layout = "left", left = { width = 0.4, diff_width = 0.2 }, right = { width = 0.5, diff_width = 0.6 } },
      diff_opts = { auto_resize_terminal = true },
      when = "diff",
    })
    assert.are.equal(1, #calls)
    assert.are.equal(40, calls[1].width)
    calls = capture_resize({
      window = { layout = "left", left = { width = 0.4, diff_width = 0.2 } },
      when = "idle",
    })
    assert.are.equal(80, calls[1].width)
  end)

  it("does NOT resize with the left layout when auto_resize_terminal is false", function()
    local calls = capture_resize({
      window = { layout = "left", left = { width = 0.4, diff_width = 0.2 } },
      diff_opts = { auto_resize_terminal = false },
      when = "diff",
    })
    assert.are.equal(0, #calls)
  end)

  describe("a Claude window of fixed width", function()
    local saved, commands

    before_each(function()
      saved = {
        valid = vim.api.nvim_win_is_valid,
        cfg = vim.api.nvim_win_get_config,
        setw = vim.api.nvim_win_set_width,
        opt = vim.api.nvim_get_option_value,
        tabpage = vim.api.nvim_win_get_tabpage,
        current = vim.api.nvim_get_current_tabpage,
        cmd = vim.cmd,
      }
      commands = {}
      vim.api.nvim_win_is_valid = function()
        return true
      end
      vim.api.nvim_win_get_config = function()
        return { relative = "" }
      end
      vim.api.nvim_win_set_width = function() end
      vim.api.nvim_get_option_value = function(name)
        return name == "winfixwidth"
      end
      vim.api.nvim_win_get_tabpage = function()
        return 7
      end
      vim.api.nvim_get_current_tabpage = function()
        return 7
      end
      vim.cmd = function(command)
        commands[#commands + 1] = command
      end
      diff.setup({ window = { right = { width = 0.5, diff_width = 0.2 } }, diff_opts = {} })
    end)

    after_each(function()
      vim.api.nvim_win_is_valid = saved.valid
      vim.api.nvim_win_get_config = saved.cfg
      vim.api.nvim_win_set_width = saved.setw
      vim.api.nvim_get_option_value = saved.opt
      vim.api.nvim_win_get_tabpage = saved.tabpage
      vim.api.nvim_get_current_tabpage = saved.current
      vim.cmd = saved.cmd
    end)

    it("equalizes the other windows after the diff width, so the diff windows share the rest", function()
      diff._resize_terminal_for_diff(4242, "diff")
      assert.are.same({ "wincmd =" }, commands)
    end)

    it("leaves the other windows alone when the diff ends", function()
      diff._resize_terminal_for_diff(4242, "idle")
      assert.are.same({}, commands)
    end)

    it("leaves the windows of another tab alone", function()
      vim.api.nvim_win_get_tabpage = function()
        return 8
      end
      diff._resize_terminal_for_diff(4242, "diff")
      assert.are.same({}, commands)
    end)
  end)

  it("does NOT resize an invalid window", function()
    local calls = capture_resize({
      diff_opts = { auto_resize_terminal = true },
      valid = false,
      when = "diff",
    })
    assert.are.equal(0, #calls)
  end)

  it("no-ops for a nil window", function()
    diff.setup({ terminal = {}, diff_opts = { auto_resize_terminal = true } })
    assert.has_no.errors(function()
      diff._resize_terminal_for_diff(nil, "diff")
    end)
  end)
end)

describe("Diff lifecycle User events", function()
  local diff = require("claudinho.diff")
  local open_diff_tool = require("claudinho.tools.open_diff")

  local dir, test_old_file
  setup(function()
    dir = temp_dir.new()
    test_old_file = dir .. "/claudinho_events_old.lua"
  end)
  teardown(function()
    temp_dir.remove(dir)
  end)

  -- Capture ONLY the nvim_exec_autocmds calls made during `action`. This is
  -- hermetic: it does not depend on the shared mock recorder or on spec ordering
  -- (other diff specs in the same busted process also fire ClaudinhoDiff* events).
  local function capture_events(action)
    local captured = {}
    local orig = vim.api.nvim_exec_autocmds
    vim.api.nvim_exec_autocmds = function(event, opts)
      captured[#captured + 1] = { event = event, opts = opts }
      if orig then
        return orig(event, opts)
      end
    end
    local ok, err = pcall(action)
    vim.api.nvim_exec_autocmds = orig
    assert(ok, tostring(err))
    return captured
  end

  local function find_events(captured, pattern)
    local events = {}
    for _, e in ipairs(captured) do
      if e.event == "User" and e.opts and e.opts.pattern == pattern then
        events[#events + 1] = e
      end
    end
    return events
  end

  local function find_event(captured, pattern)
    for i = #captured, 1, -1 do
      local e = captured[i]
      if e.event == "User" and e.opts and e.opts.pattern == pattern then
        return e
      end
    end
    return nil
  end

  local function reset_to_terminal_only()
    assert(vim and vim._mock and vim._mock.reset, "expected vim mock with _mock.reset()")

    vim._mock.reset()
    vim._tabs = { [1] = true }
    vim._current_tabpage = 1
    vim._current_window = 1000
    vim._next_winid = 1001

    vim._mock.add_buffer(1, "term://fake/claude", "", { buftype = "terminal", modified = false })
    vim._mock.add_window(1000, 1, { 1, 0 })
    vim._win_tab[1000] = 1
    vim._tab_windows[1] = { 1000 }
  end

  local function reset_to_default_editor_window()
    if not (vim and vim._mock and vim._mock.reset) then
      return
    end

    vim._mock.reset()
    vim._tabs = { [1] = true }
    vim._current_tabpage = 1
    vim._current_window = 1000
    vim._next_winid = 1001

    vim._mock.add_buffer(1, "/home/user/project/test.lua", "local test = {}\nreturn test")
    vim._mock.add_window(1000, 1, { 1, 0 })
    vim._win_tab[1000] = 1
    vim._tab_windows[1] = { 1000 }
  end

  before_each(function()
    local f = io.open(test_old_file, "w")
    f:write("local a = 1\nlocal b = 2\n")
    f:close()

    diff.setup({ terminal = {}, diff_opts = {} })
    diff._cleanup_all_active_diffs("test_reset")
    package.loaded["claudinho.terminal"] = {
      get_active_terminal_bufnr = function()
        return nil
      end,
      ensure_visible = function() end,
    }
  end)

  after_each(function()
    diff._cleanup_all_active_diffs("test_cleanup")
    package.loaded["claudinho.terminal"] = nil
    os.remove(test_old_file)
    reset_to_default_editor_window()
  end)

  it("emits ClaudinhoDiffOpened with the full payload when a diff opens", function()
    local co = coroutine.create(function()
      open_diff_tool.handler({
        old_file_path = test_old_file,
        new_file_path = test_old_file,
        new_file_contents = "local a = 1\nlocal b = 99\nlocal c = 3\n",
        tab_name = "opened-tab",
      })
    end)
    local captured = capture_events(function()
      local ok, err = coroutine.resume(co)
      assert(ok, tostring(err))
    end)

    local ev = find_event(captured, "ClaudinhoDiffOpened")
    assert.is_not_nil(ev)
    local data = ev.opts.data
    assert.are.equal("opened-tab", data.tab_name)
    assert.are.equal(test_old_file, data.file_path)
    assert.are.equal(test_old_file, data.new_file_path)
    assert.is_false(data.is_new_file)
    assert.is_not_nil(data.diff_window)
    assert.is_not_nil(data.target_window)
    assert.is_false(ev.opts.modeline) -- never re-process the current buffer's modeline

    vim.schedule(function()
      diff._resolve_diff_as_rejected("opened-tab")
    end)
    vim.wait(100, function()
      return coroutine.status(co) == "dead"
    end)
  end)

  it("emits ClaudinhoDiffOpened and ClaudinhoDiffClosed for unified layout", function()
    diff.setup({ terminal = {}, diff_opts = { layout = "unified" } })

    local co = coroutine.create(function()
      open_diff_tool.handler({
        old_file_path = test_old_file,
        new_file_path = test_old_file,
        new_file_contents = "local a = 1\nlocal b = 42\nlocal c = 3\n",
        tab_name = "opened-unified-tab",
      })
    end)
    local opened_captured = capture_events(function()
      local ok, err = coroutine.resume(co)
      assert(ok, tostring(err))
    end)

    local opened_events = find_events(opened_captured, "ClaudinhoDiffOpened")
    assert.are.equal(1, #opened_events)
    local opened_data = opened_events[1].opts.data
    assert.are.equal("opened-unified-tab", opened_data.tab_name)
    assert.are.equal(test_old_file, opened_data.file_path)
    assert.are.equal(test_old_file, opened_data.new_file_path)
    assert.is_false(opened_data.is_new_file)
    assert.is_not_nil(opened_data.diff_window)
    assert.is_true(vim.api.nvim_win_is_valid(opened_data.diff_window))
    assert.is_not_nil(opened_data.target_window)
    assert.is_true(vim.api.nvim_win_is_valid(opened_data.target_window))
    assert.is_false(opened_events[1].opts.modeline)

    local closed_captured = capture_events(function()
      diff._cleanup_diff_state("opened-unified-tab", "diff rejected")
    end)
    local closed_events = find_events(closed_captured, "ClaudinhoDiffClosed")
    assert.are.equal(1, #closed_events)
    local closed_data = closed_events[1].opts.data
    assert.are.equal("opened-unified-tab", closed_data.tab_name)
    assert.are.equal(test_old_file, closed_data.file_path)
    assert.are.equal("diff rejected", closed_data.reason)
  end)

  it("emits unified ClaudinhoDiffOpened with a valid target_window from a terminal-only tab", function()
    reset_to_terminal_only()
    assert.is_nil(diff._find_main_editor_window())
    diff.setup({ terminal = {}, diff_opts = { layout = "unified" } })

    local co = coroutine.create(function()
      open_diff_tool.handler({
        old_file_path = test_old_file,
        new_file_path = test_old_file,
        new_file_contents = "local a = 1\nlocal b = 43\nlocal c = 3\n",
        tab_name = "opened-unified-terminal-only-tab",
      })
    end)
    local opened_captured = capture_events(function()
      local ok, err = coroutine.resume(co)
      assert(ok, tostring(err))
    end)

    local opened_events = find_events(opened_captured, "ClaudinhoDiffOpened")
    assert.are.equal(1, #opened_events)
    local opened_data = opened_events[1].opts.data
    assert.is_not_nil(opened_data.diff_window)
    assert.is_true(vim.api.nvim_win_is_valid(opened_data.diff_window))
    assert.is_not_nil(opened_data.target_window)
    assert.is_true(vim.api.nvim_win_is_valid(opened_data.target_window))
    assert.are_not.equal(1000, opened_data.target_window)
    local target_buf = vim.api.nvim_win_get_buf(opened_data.target_window)
    assert.are_not.equal("terminal", vim.api.nvim_buf_get_option(target_buf, "buftype"))

    local state = diff._get_active_diffs()["opened-unified-terminal-only-tab"]
    assert.is_table(state)
    assert.are.equal(opened_data.target_window, state.fallback_window)

    diff._cleanup_diff_state("opened-unified-terminal-only-tab", "diff rejected")
    assert.is_false(vim.api.nvim_win_is_valid(opened_data.target_window))
    assert.is_true(vim.api.nvim_win_is_valid(1000))
    reset_to_default_editor_window()
  end)

  it("cleans up a terminal-only unified fallback when setup fails before state registration", function()
    reset_to_terminal_only()
    assert.is_nil(diff._find_main_editor_window())
    diff.setup({ terminal = {}, diff_opts = { layout = "unified" } })

    local original_cmd = vim.cmd
    local vsplit_count = 0
    vim.cmd = function(command)
      if command == "rightbelow vsplit" then
        vsplit_count = vsplit_count + 1
        if vsplit_count == 2 then
          error("forced unified setup failure after fallback split")
        end
      end
      return original_cmd(command)
    end

    local co = coroutine.create(function()
      open_diff_tool.handler({
        old_file_path = test_old_file,
        new_file_path = test_old_file,
        new_file_contents = "local a = 1\nlocal b = 44\nlocal c = 3\n",
        tab_name = "failed-unified-terminal-only-tab",
      })
    end)
    local ok = coroutine.resume(co)
    vim.cmd = original_cmd

    assert.is_false(ok)
    assert.are.equal(2, vsplit_count)
    assert.is_nil(diff._get_active_diffs()["failed-unified-terminal-only-tab"])
    assert.is_true(vim.api.nvim_win_is_valid(1000))
    local wins = vim.api.nvim_list_wins()
    assert.are.equal(1, #wins)
    assert.are.equal(1000, wins[1])
  end)

  it("emits ClaudinhoDiffClosed with tab_name/file_path/reason on cleanup", function()
    diff._register_diff_state("events-tab", {
      old_file_path = test_old_file,
      status = "pending",
    })
    local captured = capture_events(function()
      diff._cleanup_diff_state("events-tab", "diff rejected")
    end)

    local ev = find_event(captured, "ClaudinhoDiffClosed")
    assert.is_not_nil(ev)
    assert.are.equal("events-tab", ev.opts.data.tab_name)
    assert.are.equal(test_old_file, ev.opts.data.file_path)
    assert.are.equal("diff rejected", ev.opts.data.reason)
  end)

  it("forwards the cleanup reason verbatim (not a hardcoded value)", function()
    diff._register_diff_state("events-tab-2", { old_file_path = test_old_file, status = "pending" })
    local captured = capture_events(function()
      diff._cleanup_diff_state("events-tab-2", "replaced by new diff")
    end)

    local ev = find_event(captured, "ClaudinhoDiffClosed")
    assert.is_not_nil(ev)
    assert.are.equal("replaced by new diff", ev.opts.data.reason)
  end)
end)
