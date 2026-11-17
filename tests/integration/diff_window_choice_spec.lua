-- Real-Neovim checks of the windows a unified diff opens and closes. Window sizes and the preview window come from
-- Neovim's own layout rules, so under busted's mock vim this is pending; scripts/run_integration_tests_individually.sh
-- runs it in Neovim.
if vim == nil or vim.fn.has("nvim") ~= 1 then
  describe("unified diff window choice", function()
    pending("needs a real Neovim")
  end)
  return
end

if vim.fn.has("nvim-0.9") ~= 1 then
  describe("unified diff window choice", function()
    pending("the unified layout needs Neovim 0.9")
  end)
  return
end

describe("unified diff window choice", function()
  local diff = require("claudinho.diff")
  local terminal = require("claudinho.terminal")
  local tools = require("claudinho.tools.init")
  local lockfile = require("claudinho.lockfile")
  local tab_env = require("tests.helpers.tab_env")
  local tab_env_dir, saved_lock_dir, saved_config
  local tab = "✻ [Claude Code] b.txt ⧉"
  local dir, path

  local function use(diff_opts, window_overrides)
    local window = vim.tbl_deep_extend("force", { layout = "right", right = { width = 0.30 } }, window_overrides or {})
    diff.setup({ window = window, diff_opts = diff_opts })
  end

  local function open_terminal()
    terminal.open()
    assert(
      vim.wait(1000, function()
        return terminal.get_active_terminal_bufnr() ~= nil
      end),
      "the Claude terminal started"
    )
    return vim.fn.bufwinid(terminal.get_active_terminal_bufnr())
  end

  local function open_diff()
    local call = tools.handle_invoke({ id = "window_choice_spec" }, {
      name = "openDiff",
      arguments = { old_file_path = path, new_file_path = path, new_file_contents = "one\nTWO\n", tab_name = tab },
    })
    assert.is_true(call._deferred, "openDiff waits for the user")
    _G.claude_deferred_responses[tostring(call.coroutine)] = function() end
    return diff._get_active_diffs()[tab].new_window
  end

  local function close_tab()
    tools.handle_invoke({ id = "window_choice_spec" }, { name = "close_tab", arguments = { tab_name = tab } })
  end

  before_each(function()
    vim.o.columns, vim.o.lines = 160, 40
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    path = dir .. "/b.txt"
    vim.fn.writefile({ "one", "two" }, path)
    tools.register_all()
    _G.claude_deferred_responses = {}
    -- The Claude terminal is a real tab, with its own private lock folder and a command that only waits.
    tab_env_dir = tab_env.new()
    saved_lock_dir = lockfile.lock_dir
    lockfile.lock_dir = tab_env_dir.lock_dir
    saved_config = require("claudinho").state.config
    require("claudinho").state.config = vim.tbl_deep_extend("force", vim.deepcopy(saved_config), {
      port_range = { min = 20000, max = 40000 },
      terminal_cmd = "sh -c 'sleep 600'",
      env = { HOME = tab_env_dir.home, CLAUDE_CONFIG_DIR = tab_env_dir.config_dir },
    })
  end)

  after_each(function()
    diff._cleanup_all_active_diffs("test cleanup")
    require("claudinho.sessions").kill_all()
    require("claudinho.ui.window").teardown()
    require("claudinho").state.config = saved_config
    lockfile.lock_dir = saved_lock_dir
    tab_env.remove(tab_env_dir)
    vim.cmd("silent! tabonly")
    vim.cmd("silent! pclose")
    vim.cmd("silent! only")
    vim.cmd("setlocal nopreviewwindow")
    vim.cmd("silent! %bwipeout!")
    vim.fn.delete(dir, "rf")
    _G.claude_deferred_responses = nil
  end)

  it("closes its new tab after close_tab when the tab has no Claude terminal", function()
    use({ layout = "unified", open_in_new_tab = true })
    open_diff()
    assert.equal(2, #vim.api.nvim_list_tabpages())

    close_tab()

    assert.equal(1, #vim.api.nvim_list_tabpages())
  end)

  it("closes its new tab after close_tab when hide_terminal_in_new_tab keeps the terminal out of it", function()
    use({ layout = "unified", open_in_new_tab = true, hide_terminal_in_new_tab = true })
    open_terminal()
    open_diff()
    assert.equal(2, #vim.api.nvim_list_tabpages())

    close_tab()

    assert.equal(1, #vim.api.nvim_list_tabpages())
  end)

  it("fills its new tab with the diff when hide_terminal_in_new_tab keeps the terminal out of it", function()
    use({ layout = "unified", open_in_new_tab = true, hide_terminal_in_new_tab = true })
    open_terminal()

    local diff_win = open_diff()

    local new_tab = diff._get_active_diffs()[tab].new_tab_number
    assert.same({ diff_win }, vim.api.nvim_tabpage_list_wins(new_tab), "the new tab holds only the diff")
    assert.equal(vim.o.columns, vim.api.nvim_win_get_width(diff_win))
  end)

  it("shows only the diff and the Claude terminal in its new tab", function()
    use({ layout = "unified", open_in_new_tab = true })
    open_terminal()
    vim.cmd("wincmd p")

    local diff_win = open_diff()

    local terminal_win = diff._get_active_diffs()[tab].terminal_win_in_new_tab
    local new_tab = diff._get_active_diffs()[tab].new_tab_number
    assert.is_not_nil(terminal_win, "the new tab shows the Claude terminal")
    local wins = vim.api.nvim_tabpage_list_wins(new_tab)
    table.sort(wins)
    local expected = { diff_win, terminal_win }
    table.sort(expected)
    assert.same(expected, wins, "the new tab holds no empty window")
  end)

  it("keeps the content a TabNew hook put in its new tab", function()
    use({ layout = "unified", open_in_new_tab = true, hide_terminal_in_new_tab = true })
    open_terminal()
    local group = vim.api.nvim_create_augroup("window_choice_spec_dashboard", { clear = true })
    vim.api.nvim_create_autocmd("TabNewEntered", {
      group = group,
      once = true,
      callback = function()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "dashboard" })
      end,
    })

    local ok, diff_win = pcall(open_diff)
    vim.api.nvim_del_augroup_by_id(group)

    assert.is_true(ok, diff_win)
    local state = diff._get_active_diffs()[tab]
    local other_lines = {}
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(state.new_tab_number)) do
      if win ~= diff_win then
        other_lines[#other_lines + 1] = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
      end
    end
    assert.same({ { "dashboard" } }, other_lines, "the hook's content keeps its window beside the diff")
  end)

  it("keeps the Claude terminal's window when its new tab holds only the terminal", function()
    use({ layout = "unified", open_in_new_tab = true })
    open_terminal()
    local terminal_buf = terminal.get_active_terminal_bufnr()
    local real_display_terminal_in_new_tab = diff._display_terminal_in_new_tab
    diff._display_terminal_in_new_tab = function()
      local original_tab = vim.api.nvim_get_current_tabpage()
      vim.cmd("tabnew")
      local terminal_win = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_buf(terminal_win, terminal_buf)
      return original_tab, terminal_win, false, vim.api.nvim_get_current_tabpage()
    end

    local ok, diff_win = pcall(open_diff)
    diff._display_terminal_in_new_tab = real_display_terminal_in_new_tab

    assert.is_true(ok, diff_win)
    local state = diff._get_active_diffs()[tab]
    assert.are_not.equal(state.terminal_win_in_new_tab, diff_win, "the diff has a window of its own")
    assert.equal(terminal_buf, vim.api.nvim_win_get_buf(state.terminal_win_in_new_tab), "the terminal keeps its window")
    assert.equal(2, #vim.api.nvim_tabpage_list_wins(state.new_tab_number))
  end)

  it("gives the diff a share of the screen when the Claude terminal is the only window", function()
    use({ layout = "unified" })
    local terminal_win = open_terminal()
    vim.cmd("only")
    assert.equal(vim.o.columns, vim.api.nvim_win_get_width(terminal_win))
    assert.is_true(vim.wo[terminal_win].winfixwidth, "the Claude window has a fixed width")

    local width = vim.api.nvim_win_get_width(open_diff())

    assert.is_true(width >= math.floor(vim.o.columns / 3) - 1, "the diff is " .. width .. " columns wide")
  end)

  it("puts the Claude terminal below the diff in its new tab with window.layout = bottom, at the full width", function()
    require("claudinho").state.config.window.layout = "bottom"
    use({ layout = "unified", open_in_new_tab = true }, { layout = "bottom", right = { diff_width = 0.20 } })
    open_terminal()
    vim.cmd("wincmd p")

    local diff_win = open_diff()

    local terminal_win = diff._get_active_diffs()[tab].terminal_win_in_new_tab
    assert.is_not_nil(terminal_win, "the new tab shows the Claude terminal")
    assert.equal(vim.o.columns, vim.api.nvim_win_get_width(terminal_win), "no width change for the bottom layout")
    assert.is_true(
      vim.api.nvim_win_get_position(terminal_win)[1] > vim.api.nvim_win_get_position(diff_win)[1],
      "the terminal is below the diff"
    )
  end)

  it("sizes a Claude terminal it splits with window.right.diff_width", function()
    use({ layout = "unified" }, { right = { diff_width = 0.20 } })
    local terminal_win = open_terminal()
    vim.cmd("only")

    open_diff()

    assert.equal(math.floor(vim.o.columns * 0.20), vim.api.nvim_win_get_width(terminal_win))
  end)

  it("sizes the Claude terminal in its new tab with window.right.diff_width", function()
    use({ layout = "unified", open_in_new_tab = true }, { right = { diff_width = 0.20 } })
    open_terminal()
    vim.cmd("wincmd p")

    open_diff()

    local terminal_win = vim.fn.bufwinid(terminal.get_active_terminal_bufnr())
    assert.are_not.equal(-1, terminal_win, "the new tab shows the Claude terminal")
    assert.equal(math.floor(vim.o.columns * 0.20), vim.api.nvim_win_get_width(terminal_win))
  end)

  it("sets no width on the Claude terminal in its new tab when auto_resize_terminal is false", function()
    use({ layout = "unified", open_in_new_tab = true, auto_resize_terminal = false })
    open_terminal()
    vim.cmd("wincmd p")
    local widths_set = {}
    local real_set_width = vim.api.nvim_win_set_width
    vim.api.nvim_win_set_width = function(win, width)
      widths_set[#widths_set + 1] = { buf = vim.api.nvim_win_get_buf(win), width = width }
      return real_set_width(win, width)
    end

    local ok, err = pcall(open_diff)
    vim.api.nvim_win_set_width = real_set_width

    assert.is_true(ok, err)
    assert.are_not.equal(-1, vim.fn.bufwinid(terminal.get_active_terminal_bufnr()), "the new tab shows the terminal")
    for _, call in ipairs(widths_set) do
      assert.are_not.equal(terminal.get_active_terminal_bufnr(), call.buf, "set the terminal to " .. call.width)
    end
  end)

  -- The user is in a tab with only the preview window, and the Claude terminal is in a later tab. The new tab goes
  -- between them, so it comes first in the window list.
  for _, case in ipairs({
    { "with window.right.diff_width", {}, { right = { diff_width = 0.5 } } },
    { "with auto_resize_terminal = false", { auto_resize_terminal = false }, {} },
  }) do
    local name, extra_diff_opts, window_overrides = case[1], case[2], case[3]
    it("keeps the width of the Claude terminal in another tab after close_tab " .. name, function()
      use(vim.tbl_extend("force", { layout = "unified", open_in_new_tab = true }, extra_diff_opts), window_overrides)
      vim.cmd("tabnew")
      local terminal_win = open_terminal()
      local terminal_width = vim.api.nvim_win_get_width(terminal_win)
      vim.cmd("tabprevious")
      vim.cmd("pedit " .. vim.fn.fnameescape(path))
      vim.cmd("wincmd P")
      vim.cmd("only")

      open_diff()
      close_tab()

      assert.equal(terminal_width, vim.api.nvim_win_get_width(terminal_win))
    end)
  end

  it("opens next to an editor window when window.right.width is not a number", function()
    use({ layout = "unified" }, { right = { width = "wide" } })
    open_terminal()
    vim.cmd("wincmd p")

    local diff_win = open_diff()

    assert.is_true(vim.api.nvim_win_is_valid(diff_win))
  end)

  it("splits the Claude terminal's window, not the preview window above it", function()
    use({ layout = "unified" })
    local terminal_win = open_terminal()
    vim.cmd("only")
    vim.cmd("pedit " .. vim.fn.fnameescape(path))
    vim.cmd("wincmd P")
    local preview_win = vim.api.nvim_get_current_win()
    local preview_width = vim.api.nvim_win_get_width(preview_win)
    local terminal_height = vim.api.nvim_win_get_height(terminal_win)

    local diff_win = open_diff()

    assert.equal(preview_width, vim.api.nvim_win_get_width(preview_win), "the preview window keeps its columns")
    assert.equal(terminal_height, vim.api.nvim_win_get_height(diff_win), "the diff gets the terminal's rows")
  end)
end)
