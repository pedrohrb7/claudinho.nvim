require("tests.busted_setup")
local temp_dir = require("tests.helpers.temp_dir")

describe("Diff in a new tab: the terminal's auto-enter handler", function()
  local open_diff_tool = require("claudinho.tools.open_diff")
  local diff = require("claudinho.diff")

  local dir, old_file, term_buf

  local layouts = { "vertical", "unified" }

  local function diff_autocmds(event)
    local found = {}
    local group = vim._autocmds["ClaudinhoMCPDiff"]
    for id, autocmd in pairs(group and group.events or {}) do
      local events = type(autocmd.events) == "table" and autocmd.events or { autocmd.events }
      for _, name in ipairs(events) do
        if name == event then
          table.insert(found, { id = id, opts = autocmd.opts })
        end
      end
    end
    return found
  end

  local function terminal_handlers()
    local found = {}
    for _, autocmd in ipairs(diff_autocmds("BufEnter")) do
      if autocmd.opts.buffer == term_buf then
        table.insert(found, autocmd)
      end
    end
    return found
  end

  local function open_diff(tab_name)
    local co = coroutine.create(function()
      open_diff_tool.handler({
        old_file_path = old_file,
        new_file_path = old_file,
        new_file_contents = "updated\n",
        tab_name = tab_name,
      })
    end)
    local ok, err = coroutine.resume(co)
    assert.is_true(ok, tostring(err))
    assert.equal("suspended", coroutine.status(co))
    return co
  end

  local function close_diff(tab_name, co)
    vim.schedule(function()
      diff._resolve_diff_as_rejected(tab_name)
    end)
    vim.wait(100, function()
      return coroutine.status(co) == "dead"
    end)
  end

  setup(function()
    dir = temp_dir.new()
    old_file = dir .. "/claudinho_new_tab_handler_old.txt"
  end)

  teardown(function()
    temp_dir.remove(dir)
  end)

  before_each(function()
    local f = assert(io.open(old_file, "w"))
    f:write("line1\nline2\n")
    f:close()

    diff._cleanup_all_active_diffs("test_setup")
    vim._autocmds = {}

    term_buf = vim.api.nvim_create_buf(false, true)
    package.loaded["claudinho.terminal"] = {
      get_active_terminal_bufnr = function()
        return term_buf
      end,
      ensure_visible = function() end,
    }
  end)

  after_each(function()
    package.loaded["claudinho.terminal"] = nil
    diff._cleanup_all_active_diffs("test_teardown")
    os.remove(old_file)
  end)

  for _, layout in ipairs(layouts) do
    describe("with layout = " .. layout, function()
      local function setup_diff(auto_insert)
        diff.setup({
          window = { layout = "right", right = { width = 0.30 } },
          terminal = { auto_insert = auto_insert },
          diff_opts = {
            layout = layout,
            open_in_new_tab = true,
            keep_terminal_focus = false,
            hide_terminal_in_new_tab = false,
          },
        })
      end

      it("is made together with a WinClosed autocmd for the window it was made for", function()
        setup_diff(true)
        local tab_name = "handler-owner-" .. layout
        local co = open_diff(tab_name)

        local state = diff._get_active_diffs()[tab_name]
        local handlers = terminal_handlers()
        local closers = diff_autocmds("WinClosed")
        assert.equal(1, #handlers)
        local for_terminal_window = {}
        for _, autocmd in ipairs(closers) do
          if autocmd.opts.pattern == tostring(state.terminal_win_in_new_tab) then
            table.insert(for_terminal_window, autocmd)
          end
        end
        assert.equal(1, #for_terminal_window)
        assert.is_true(for_terminal_window[1].opts.once)

        close_diff(tab_name, co)
      end)

      it("is deleted when the window it was made for closes", function()
        setup_diff(true)
        local tab_name = "handler-closes-" .. layout
        local co = open_diff(tab_name)
        local state = diff._get_active_diffs()[tab_name]
        local closing_win = state.terminal_win_in_new_tab

        for _, autocmd in ipairs(diff_autocmds("WinClosed")) do
          if autocmd.opts.pattern == tostring(closing_win) then
            autocmd.opts.callback({ match = tostring(closing_win) })
          end
        end

        assert.equal(0, #terminal_handlers())

        close_diff(tab_name, co)
      end)

      it("is not made with terminal.auto_insert = false", function()
        setup_diff(false)
        local tab_name = "handler-off-" .. layout
        local co = open_diff(tab_name)

        assert.equal(0, #terminal_handlers())
        for _, autocmd in ipairs(diff_autocmds("WinClosed")) do
          assert.is_nil(autocmd.opts.pattern, "no WinClosed autocmd for a terminal window")
        end

        close_diff(tab_name, co)
      end)
    end)
  end

  describe("where the terminal goes in the new tab", function()
    local expected = {
      left = { "vsplit", "wincmd H", "wincmd l" },
      right = { "vsplit", "wincmd L", "wincmd h" },
      bottom = { "split", "wincmd J", "wincmd k" },
    }

    for _, layout in ipairs({ "left", "right", "bottom" }) do
      it("follows window.layout = " .. layout, function()
        diff.setup({
          window = { layout = layout, right = { width = 0.30 }, left = { width = 0.30 } },
          terminal = { auto_insert = true },
          diff_opts = { layout = "vertical", open_in_new_tab = true, hide_terminal_in_new_tab = false },
        })
        local commands = {}
        local original_cmd = vim.cmd
        vim.cmd = function(command)
          commands[#commands + 1] = command
          return original_cmd(command)
        end
        local tab_name = "new-tab-side-" .. layout
        local ok, co = pcall(open_diff, tab_name)
        vim.cmd = original_cmd
        assert.is_true(ok, tostring(co))

        local at = {}
        for i, command in ipairs(commands) do
          at[command] = at[command] or i
        end
        local want = expected[layout]
        assert.is_truthy(at[want[1]], "missing " .. want[1])
        assert.is_truthy(at[want[2]], "missing " .. want[2])
        assert.is_truthy(at[want[3]], "missing " .. want[3])
        assert.is_true(at[want[1]] < at[want[2]] and at[want[2]] < at[want[3]])
        assert.equal(1, #terminal_handlers(), "the auto-enter handler is made for the terminal window")
        for other, cmds in pairs(expected) do
          if other ~= layout then
            assert.is_nil(at[cmds[2]], "unexpected " .. cmds[2])
          end
        end

        close_diff(tab_name, co)
      end)
    end
  end)
end)
