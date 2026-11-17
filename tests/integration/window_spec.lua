-- Real-Neovim check of the Claude window: each layout opens with its winbar and statusline and takes the terminal
-- mode, toggle/open/hide/focus, `:q` and `<C-w>c` hiding without ending the process, the tab switch swapping buffer and
-- status, the title from a terminal OSC sequence, `gt`, the float and the diff, and `:q` on the last editor window.
-- Under busted's mock vim it is pending; scripts/run_integration_tests_individually.sh runs it in Neovim.
if vim == nil or vim.fn.has("nvim") ~= 1 or (vim.uv or vim.loop) == nil or vim.wait == nil or vim.system == nil then
  describe("window", function()
    pending("needs a real Neovim")
  end)
  return
end

describe("window", function()
  local uv = vim.uv or vim.loop
  local lockfile = require("claudinho.lockfile")
  local tab_env = require("tests.helpers.tab_env")

  local sessions, window, env, saved_lock_dir, saved_plugin, layout, terminal_cmd

  ---@return table config
  local function make_config()
    return vim.tbl_deep_extend("force", vim.deepcopy(require("claudinho.config").defaults), {
      port_range = { min = 20000, max = 40000 },
      terminal_cmd = terminal_cmd or env.idle_cmd,
      env = { HOME = env.home, CLAUDE_CONFIG_DIR = env.config_dir },
      window = { layout = layout or "right" },
    })
  end

  local function alive(pid)
    return uv.kill(pid, 0) == 0
  end

  local function setup_plugin()
    package.loaded["claudinho"] = { state = { config = make_config() } }
  end

  ---The winbar or statusline of a window as drawn: its `%!` expression evaluated for that window.
  ---@param win integer
  ---@param option "winbar"|"statusline"
  ---@return string
  local function drawn(win, option)
    local expression = vim.api.nvim_get_option_value(option, { scope = "local", win = win })
    assert.is_true(expression:find("^%%!") ~= nil, option .. " is " .. expression)
    vim.g.statusline_winid = win
    local text = vim.api.nvim_eval_statusline(vim.fn.eval(expression:sub(3)), { winid = win })
    return text.str
  end

  -- `startinsert` only takes effect when the command that runs the spec returns to the main loop, so the spec records
  -- the calls instead of reading the mode.
  local real_cmd, startinserts

  ---@param win integer
  ---@return boolean focused_and_asked_for_terminal_mode
  local function in_terminal_mode(win)
    return startinserts > 0 and vim.api.nvim_get_current_win() == win
  end

  local function pause(ms)
    vim.wait(ms, function()
      return false
    end, 10)
  end

  before_each(function()
    env = tab_env.new()
    layout, terminal_cmd = nil, nil
    saved_lock_dir = lockfile.lock_dir
    lockfile.lock_dir = env.lock_dir
    saved_plugin = package.loaded["claudinho"]
    setup_plugin()
    package.loaded["claudinho.sessions"] = nil
    package.loaded["claudinho.ui.window"] = nil
    package.loaded["claudinho.ui.tabbar"] = nil
    package.loaded["claudinho.ui.status"] = nil
    sessions = require("claudinho.sessions")
    window = require("claudinho.ui.window")
    vim.cmd("silent! tabonly | silent! only")
    real_cmd, startinserts = vim.cmd, 0
    vim.cmd = setmetatable({}, {
      __index = real_cmd,
      __call = function(_, command, ...)
        if command == "startinsert" then
          startinserts = startinserts + 1
        end
        return real_cmd(command, ...)
      end,
    })
  end)

  after_each(function()
    vim.cmd = real_cmd
    sessions.kill_all()
    window.teardown()
    pcall(vim.api.nvim_del_augroup_by_name, "ClaudinhoSessions")
    vim.cmd("stopinsert")
    vim.cmd("silent! tabonly | silent! only")
    package.loaded["claudinho"] = saved_plugin
    package.loaded["claudinho.sessions"] = nil
    package.loaded["claudinho.ui.window"] = nil
    lockfile.lock_dir = saved_lock_dir
    tab_env.remove(env)
  end)

  describe("layouts", function()
    local layouts = { "right", "left", "bottom", "float", "tab" }
    for _, name in ipairs(layouts) do
      it(("opens as %s with a winbar and a statusline and takes the terminal mode"):format(name), function()
        layout = name
        setup_plugin()
        local first = assert(sessions.new())

        local win = assert(window.win())
        assert.equals(first.buf, vim.api.nvim_win_get_buf(win))
        assert.is_true(in_terminal_mode(win))
        local bar = drawn(win, "winbar")
        assert.is_true(bar:find("1 Claude 1", 1, true) ~= nil)
        assert.is_true(bar:find("+", 1, true) ~= nil)
        assert.equals("", drawn(win, "statusline"))
        assert.is_true(vim.wo[win].winfixbuf)
        assert.is_false(vim.wo[win].number)
        assert.equals("no", vim.wo[win].signcolumn)
      end)
    end

    it("right takes floor(columns * 0.30) columns on the far right", function()
      local first = assert(sessions.new())
      local win = assert(window.win())
      assert.equals(math.floor(vim.o.columns * 0.30), vim.api.nvim_win_get_width(win))
      assert.is_true(vim.wo[win].winfixwidth)
      assert.equals(first.buf, vim.api.nvim_win_get_buf(win))
      assert.equals(win, vim.fn.win_getid(vim.fn.winnr("$")))
    end)

    ---@return integer left, integer right the two editor windows of the spec
    local function two_editor_splits()
      vim.cmd("vsplit")
      local right = vim.api.nvim_get_current_win()
      vim.cmd("vsplit")
      return vim.api.nvim_get_current_win(), right
    end

    ---@param width integer
    ---@return integer win a simulated explorer on the left edge: a fixed-width window with the NvimTree filetype
    local function open_explorer(width)
      local buf = vim.api.nvim_create_buf(false, true)
      vim.bo[buf].filetype = "NvimTree"
      local win = vim.api.nvim_open_win(buf, false, { split = "left", win = -1, width = width })
      vim.wo[win].winfixwidth = true
      return win
    end

    it("left takes floor(columns * 0.30) columns on column 0, the whole height, beside two editor splits", function()
      layout = "left"
      setup_plugin()
      local first_editor, second_editor = two_editor_splits()
      local first = assert(sessions.new())
      local win = assert(window.win())

      assert.equals(first.buf, vim.api.nvim_win_get_buf(win))
      assert.equals(math.floor(vim.o.columns * 0.30), vim.api.nvim_win_get_width(win))
      assert.is_true(vim.wo[win].winfixwidth)
      local position = vim.api.nvim_win_get_position(win)
      assert.equals(0, position[2])
      for _, editor in ipairs({ first_editor, second_editor }) do
        assert.equals(vim.api.nvim_win_get_position(editor)[1], position[1])
        assert.equals(vim.api.nvim_win_get_height(editor), vim.api.nvim_win_get_height(win))
      end
      local top = vim.fn.winlayout()
      assert.equals("row", top[1])
      assert.equals(4, #top[2], "Claude and three editor windows in one row")
      assert.same({ "leaf", win }, top[2][1])
    end)

    it("left follows window.left.width and ignores window.right.width", function()
      layout = "left"
      local config = make_config()
      config.window.left.width = 0.45
      config.window.right.width = 0.10
      package.loaded["claudinho"] = { state = { config = config } }
      assert(sessions.new())
      local win = assert(window.win())
      assert.equals(math.floor(vim.o.columns * 0.45), vim.api.nvim_win_get_width(win))
    end)

    it("left: open from another Neovim tab and toggle put the window on the left edge there", function()
      layout = "left"
      setup_plugin()
      assert(sessions.new())
      vim.cmd("stopinsert")
      vim.cmd("tabnew")
      two_editor_splits()

      window.open()

      local win = assert(window.win())
      assert.equals(vim.api.nvim_get_current_tabpage(), vim.api.nvim_win_get_tabpage(win))
      assert.equals(0, vim.api.nvim_win_get_position(win)[2])

      window.toggle()
      assert.is_nil(window.win())
      window.toggle()
      win = assert(window.win())
      assert.equals(0, vim.api.nvim_win_get_position(win)[2])
      assert.same({ "leaf", win }, vim.fn.winlayout()[2][1])
    end)

    it("left opens to the left of an explorer that was open, and the explorer keeps its columns", function()
      layout = "left"
      setup_plugin()
      local explorer = open_explorer(30)

      assert(sessions.new())
      local win = assert(window.win())

      assert.equals(0, vim.api.nvim_win_get_position(win)[2])
      assert.is_true(vim.api.nvim_win_get_position(explorer)[2] > 0)
      assert.equals(30, vim.api.nvim_win_get_width(explorer))
    end)

    it("left does not move when an explorer opens after it, and hide plus open bring it back to column 0", function()
      layout = "left"
      setup_plugin()
      assert(sessions.new())
      local win = assert(window.win())
      vim.cmd("stopinsert")
      local explorer = open_explorer(30)

      assert.equals(win, window.win())
      assert.equals(0, vim.api.nvim_win_get_position(explorer)[2])
      assert.is_true(vim.api.nvim_win_get_position(win)[2] > 0)

      window.hide()
      window.open()

      win = assert(window.win())
      assert.equals(0, vim.api.nvim_win_get_position(win)[2])
      assert.equals(30, vim.api.nvim_win_get_width(explorer))
    end)

    it("bottom takes about floor(lines * 0.30) rows at the bottom", function()
      layout = "bottom"
      setup_plugin()
      assert(sessions.new())
      local win = assert(window.win())
      local expected = math.floor(vim.o.lines * 0.30)
      assert.is_true(math.abs(vim.api.nvim_win_get_height(win) - expected) <= 2)
      assert.is_true(vim.wo[win].winfixheight)
      assert.equals(win, vim.fn.win_getid(vim.fn.winnr("$")))
    end)

    it("float is centered, and VimResized fits it to the screen again", function()
      layout = "float"
      setup_plugin()
      assert(sessions.new())
      local win = assert(window.win())
      local config = vim.api.nvim_win_get_config(win)
      assert.equals("editor", config.relative)
      assert.equals(math.floor(vim.o.columns * 0.80), config.width)
      assert.equals(math.floor((vim.o.columns - config.width) / 2), config.col)

      vim.api.nvim_win_set_config(win, { relative = "editor", width = 10, height = 5, row = 0, col = 0 })
      vim.api.nvim_exec_autocmds("VimResized", { modeline = false })
      local resized = vim.api.nvim_win_get_config(win)
      assert.equals(config.width, resized.width)
      assert.equals(config.col, resized.col)
    end)

    it("tab fills a Neovim tab of its own", function()
      layout = "tab"
      setup_plugin()
      assert(sessions.new())
      local win = assert(window.win())
      assert.equals(2, #vim.api.nvim_list_tabpages())
      assert.equals(1, #vim.api.nvim_tabpage_list_wins(vim.api.nvim_win_get_tabpage(win)))
      assert.equals(vim.api.nvim_get_current_tabpage(), vim.api.nvim_win_get_tabpage(win))
    end)

    it("an invalid layout opens as right", function()
      layout = "diagonal"
      setup_plugin()
      assert(sessions.new())
      local win = assert(window.win())
      assert.equals("", vim.api.nvim_win_get_config(win).relative)
      assert.equals(math.floor(vim.o.columns * 0.30), vim.api.nvim_win_get_width(win))
    end)
  end)

  describe("toggle, open, hide and focus", function()
    it("toggle hides a visible window and shows a hidden one, and the process lives on", function()
      local first = assert(sessions.new())
      local pid = first.pid
      assert.is_true(window.is_visible())

      window.toggle()
      assert.is_false(window.is_visible())
      assert.is_true(alive(pid))
      assert.equals("running", first.state)

      window.toggle()
      assert.is_true(window.is_visible())
      assert.is_true(in_terminal_mode(assert(window.win())))
      assert.equals(pid, first.pid)
    end)

    it("open shows a hidden window and only focuses a visible one", function()
      assert(sessions.new())
      local editor = vim.fn.win_getid(1)
      window.hide()
      assert.is_false(window.is_visible())

      window.open()
      local win = assert(window.win())
      assert.equals(win, vim.api.nvim_get_current_win())

      vim.cmd("stopinsert")
      vim.api.nvim_set_current_win(editor)
      local count = #vim.api.nvim_list_wins()
      window.open()
      assert.equals(win, vim.api.nvim_get_current_win())
      assert.equals(count, #vim.api.nvim_list_wins())
    end)

    it("hide hides, and does nothing when it is already hidden", function()
      assert(sessions.new())
      window.hide()
      assert.is_false(window.is_visible())
      window.hide()
      assert.is_false(window.is_visible())
      assert.equals(1, vim.tbl_count(sessions.state.tabs))
    end)

    it("focus shows a hidden window, hides one in focus and focuses one out of focus", function()
      assert(sessions.new())
      local editor = vim.fn.win_getid(1)
      window.hide()

      window.focus()
      local win = assert(window.win())
      assert.equals(win, vim.api.nvim_get_current_win())

      window.focus()
      assert.is_false(window.is_visible())

      window.show({ focus = true })
      vim.cmd("stopinsert")
      vim.api.nvim_set_current_win(editor)
      window.focus()
      assert.equals(assert(window.win()), vim.api.nvim_get_current_win())
    end)

    it("with auto_insert off the window takes focus but not the terminal mode", function()
      package.loaded["claudinho"].state.config.terminal.auto_insert = false
      assert(sessions.new())
      local win = assert(window.win())
      assert.equals(win, vim.api.nvim_get_current_win())
      assert.equals(0, startinserts)
    end)

    it("show does nothing without a tab", function()
      assert.is_false(window.show({ focus = true }))
      assert.is_false(window.is_visible())
    end)
  end)

  describe("closing the window with Neovim commands", function()
    it(":q and <C-w>c hide the window and the process keeps its PID", function()
      local first = assert(sessions.new())
      local pid = first.pid

      vim.cmd("stopinsert")
      local claude_win = assert(window.win())
      vim.api.nvim_set_current_win(claude_win)
      vim.cmd("quit")
      assert.is_false(window.is_visible())
      assert.is_true(alive(pid))

      window.show({ focus = true })
      vim.cmd("stopinsert")
      vim.cmd("wincmd c")
      assert.is_false(window.is_visible())
      assert.is_true(alive(pid))
      assert.equals(pid, first.pid)
      assert.equals("running", first.state)
    end)

    it(":tabclose of the tab layout hides the window and keeps the session", function()
      layout = "tab"
      setup_plugin()
      local first = assert(sessions.new())
      vim.cmd("stopinsert")
      vim.cmd("tabclose")
      assert.is_false(window.is_visible())
      assert.is_true(alive(first.pid))
    end)

    it("hide in the tab layout closes the Neovim tab of the window", function()
      layout = "tab"
      setup_plugin()
      assert(sessions.new())
      assert.equals(2, #vim.api.nvim_list_tabpages())
      vim.cmd("stopinsert")
      window.hide()
      assert.equals(1, #vim.api.nvim_list_tabpages())
      assert.is_false(window.is_visible())
    end)

    it("hide of a window that is alone in the only Neovim tab opens an empty tab first", function()
      assert(sessions.new())
      vim.cmd("stopinsert")
      local claude_win = assert(window.win())
      vim.api.nvim_set_current_win(claude_win)
      vim.cmd("wincmd o")
      assert.equals(1, #vim.api.nvim_tabpage_list_wins(0))

      window.hide()

      assert.is_false(window.is_visible())
      assert.equals(1, #vim.api.nvim_list_tabpages())
      assert.equals(1, #vim.api.nvim_list_wins())
    end)
  end)

  describe("tabs", function()
    it("the tab switch changes buffer and status in the same window", function()
      local first = assert(sessions.new())
      first.data = { model = "Opus 5.5", effort = "high", mode = "plan" }
      local second = assert(sessions.new())
      second.data = { model = "Haiku 4.5", mode = "auto" }
      local win = assert(window.win())
      assert.equals(second.buf, vim.api.nvim_win_get_buf(win))
      assert.equals("Haiku 4.5 \xC2\xB7 auto", drawn(win, "statusline"))

      assert.is_true(sessions.activate(1))

      assert.equals(win, window.win())
      assert.equals(first.buf, vim.api.nvim_win_get_buf(win))
      assert.equals("Opus 5.5 \xC2\xB7 high \xC2\xB7 plan", drawn(win, "statusline"))
      local bar = drawn(win, "winbar")
      -- The window is narrow, so the titles may shrink; the numbers and the `+` stay.
      assert.is_true(bar:find("1", 1, true) ~= nil and bar:find("2", 1, true) ~= nil and bar:find("+", 1, true) ~= nil)
      assert.is_true(vim.wo[win].winfixbuf)
    end)

    it("an ended tab keeps its last status and shows the mark", function()
      local first = assert(sessions.new())
      first.data = { model = "Opus 5.5" }
      vim.fn.jobstop(first.job)
      assert.is_true(vim.wait(3000, function()
        return first.state == "exited"
      end, 20))
      local win = assert(window.win())
      assert.equals("Opus 5.5", drawn(win, "statusline"))
      assert.is_true(drawn(win, "winbar"):find("[exited]", 1, true) ~= nil)
    end)

    it("closing the active tab shows its neighbour in the same window, and the last one closes the window", function()
      local first = assert(sessions.new())
      local second = assert(sessions.new())
      local second_buf = second.buf
      local win = assert(window.win())

      assert.is_true(sessions.close(2))
      assert.equals(win, window.win())
      assert.equals(first.buf, vim.api.nvim_win_get_buf(win))
      assert.is_false(vim.api.nvim_buf_is_valid(second_buf))

      assert.is_true(sessions.close(1))
      assert.is_false(window.is_visible())
    end)

    it("a restart puts the new buffer in the window", function()
      terminal_cmd = env.exit_cmd(0)
      setup_plugin()
      local first = assert(sessions.new())
      assert.is_true(vim.wait(3000, function()
        return first.state == "exited"
      end, 20))
      local old = first.buf
      first.base_cmd = env.idle_cmd

      assert.is_true(sessions.restart(1))

      local win = assert(window.win())
      assert.are_not.equals(old, first.buf)
      assert.equals(first.buf, vim.api.nvim_win_get_buf(win))
      assert.is_true(vim.wo[win].winfixbuf)
    end)

    it("showing an ended tab with focus does not ask for the terminal mode", function()
      terminal_cmd = env.exit_cmd(0)
      setup_plugin()
      local first = assert(sessions.new())
      assert.is_true(vim.wait(3000, function()
        return first.state == "exited"
      end, 20))
      local win = assert(window.win())
      vim.cmd("stopinsert")
      startinserts = 0

      window.show({ focus = true })

      assert.equals(win, vim.api.nvim_get_current_win())
      assert.equals(0, startinserts)
    end)
  end)

  describe("title", function()
    it("an OSC 2 sequence from the process updates the winbar", function()
      terminal_cmd = [[sh -c 'printf "\033]2;Fix the parser\007"; exec sleep 30' claude-test]]
      setup_plugin()
      local first = assert(sessions.new())
      local win = assert(window.win())

      assert.is_true(vim.wait(3000, function()
        return first.title == "Fix the parser"
      end, 20))
      assert.is_true(drawn(win, "winbar"):find("1 Fix the parser", 1, true) ~= nil)
    end)

    it("a generic title is ignored", function()
      terminal_cmd = [[sh -c 'printf "\033]0;Claude Code\007"; exec sleep 30' claude-test]]
      setup_plugin()
      local first = assert(sessions.new())
      pause(500)
      assert.is_nil(first.title)
      assert.is_true(drawn(assert(window.win()), "winbar"):find("1 Claude 1", 1, true) ~= nil)
    end)
  end)

  describe("other Neovim tabs", function()
    it("open from another tab closes the window there and opens it here", function()
      assert(sessions.new())
      local first_win = assert(window.win())
      vim.cmd("stopinsert")
      vim.cmd("tabnew")
      local second_tab = vim.api.nvim_get_current_tabpage()
      assert.are_not.equals(second_tab, vim.api.nvim_win_get_tabpage(first_win))

      window.open()

      local win = assert(window.win())
      assert.equals(second_tab, vim.api.nvim_win_get_tabpage(win))
      assert.is_false(vim.api.nvim_win_is_valid(first_win))
      assert.equals(win, vim.api.nvim_get_current_win())
    end)

    it("layout tab: open from another Neovim tab goes to the Claude tab", function()
      layout = "tab"
      setup_plugin()
      assert(sessions.new())
      local win = assert(window.win())
      vim.cmd("stopinsert")
      vim.cmd("tabprevious")
      assert.are_not.equals(vim.api.nvim_get_current_tabpage(), vim.api.nvim_win_get_tabpage(win))

      window.open()

      assert.equals(win, window.win())
      assert.equals(vim.api.nvim_win_get_tabpage(win), vim.api.nvim_get_current_tabpage())
    end)
  end)

  describe("float and diff", function()
    it("a diff hides the float, ensure_visible does not bring it back, and open does", function()
      layout = "float"
      setup_plugin()
      local first = assert(sessions.new())
      assert.is_true(window.is_visible())

      vim.api.nvim_exec_autocmds("User", { pattern = "ClaudinhoDiffOpened", modeline = false })
      assert.is_false(window.is_visible())
      assert.is_true(window.state.hidden_by_diff)
      assert.is_true(alive(first.pid))

      window.ensure_visible()
      assert.is_false(window.is_visible())

      window.open()
      assert.is_true(window.is_visible())
      assert.is_false(window.state.hidden_by_diff)
    end)

    it("toggle and focus also bring the float back", function()
      layout = "float"
      setup_plugin()
      assert(sessions.new())
      vim.api.nvim_exec_autocmds("User", { pattern = "ClaudinhoDiffOpened", modeline = false })
      window.toggle()
      assert.is_true(window.is_visible())

      vim.api.nvim_exec_autocmds("User", { pattern = "ClaudinhoDiffOpened", modeline = false })
      window.focus()
      assert.is_true(window.is_visible())
    end)

    it("in the other layouts a diff leaves the window alone", function()
      assert(sessions.new())
      vim.api.nvim_exec_autocmds("User", { pattern = "ClaudinhoDiffOpened", modeline = false })
      assert.is_true(window.is_visible())
      assert.is_false(window.state.hidden_by_diff)
    end)

    it("ensure_visible shows a hidden window without taking focus", function()
      assert(sessions.new())
      local editor = vim.fn.win_getid(1)
      window.hide()
      vim.cmd("stopinsert")
      vim.api.nvim_set_current_win(editor)

      window.ensure_visible()

      assert.is_true(window.is_visible())
      assert.equals(editor, vim.api.nvim_get_current_win())
    end)
  end)

  describe("leaving Neovim", function()
    it(":q on the last editor window closes the Claude window first and Neovim leaves", function()
      local repo = vim.fn.getcwd()
      local script = env.root .. "/child.lua"
      vim.fn.writefile({
        "package.path = '" .. repo .. "/?.lua;" .. repo .. "/lua/?.lua;" .. repo .. "/lua/?/init.lua;' .. package.path",
        "vim.opt.runtimepath:prepend('" .. repo .. "')",
        "require('claudinho.lockfile').lock_dir = '" .. env.lock_dir .. "'",
        "local config = vim.tbl_deep_extend('force', vim.deepcopy(require('claudinho.config').defaults), {",
        "  port_range = { min = 20000, max = 40000 },",
        "  terminal_cmd = [[" .. env.idle_cmd .. "]],",
        "  env = { HOME = '" .. env.home .. "', CLAUDE_CONFIG_DIR = '" .. env.config_dir .. "' },",
        "})",
        "package.loaded['claudinho'] = { state = { config = config } }",
        "local sessions = require('claudinho.sessions')",
        "sessions.setup_autocmds()",
        "assert(sessions.new())",
        "vim.cmd('stopinsert')",
        "vim.cmd('wincmd h')",
        "vim.cmd('quit')",
        "-- Reaching the next line means Neovim did not leave.",
        "local out = io.open('" .. env.root .. "/still-here', 'w'); out:write('x'); out:close()",
        "vim.cmd('cquit 3')",
      }, script)

      local result = vim
        .system({ "nvim", "--headless", "-i", "NONE", "-u", "NONE", "-c", "luafile " .. script }, {
          env = { HOME = env.home, XDG_STATE_HOME = env.root .. "/state", XDG_CONFIG_HOME = env.root .. "/xdgconfig" },
          text = true,
        })
        :wait(20000)

      assert.equals(0, result.code, (result.stderr or "") .. (result.stdout or ""))
      assert.equals(0, vim.fn.filereadable(env.root .. "/still-here"))
      assert.same({}, vim.fn.glob(env.lock_dir .. "/*.lock", false, true))
    end)
  end)
end)
