require("tests.busted_setup")
require("tests.mocks.vim")

-- #228 (b): send_at_mention fires `User ClaudinhoSendComplete` on a successful
-- connected send, carrying the formatted path/lines Claude received. It does NOT
-- fire when the broadcast was not successful (and, by design, not on the queued
-- disconnected path — that delivery is debounced and never re-enters send_at_mention).
describe("ClaudinhoSendComplete event (#228)", function()
  local saved_require
  local claudinho
  local mock_terminal
  local saved_fn
  local tab
  local active_tab = require("tests.helpers.active_tab")

  local function setup_mocks()
    mock_terminal = {
      setup = function() end,
      open = spy.new(function() end),
      ensure_visible = spy.new(function() end),
    }
    local mock_logger = {
      setup = function() end,
      debug = function() end,
      info = function() end,
      warn = function() end,
      error = function() end,
    }
    local mock_config = {
      without_removed_options = function(o)
        return o
      end,
      apply = function()
        return {
          auto_start = false,
          terminal_cmd = nil,
          env = {},
          log_level = "info",
          track_selection = false,
          focus_after_send = false,
          diff_opts = {
            layout = "vertical",
            open_in_new_tab = false,
            keep_terminal_focus = false,
            on_new_file_reject = "keep_empty",
          },
          models = { { name = "Test", value = "test" } },
        }
      end,
    }

    saved_require = _G.require
    _G.require = function(mod)
      if mod == "claudinho.config" then
        return mock_config
      elseif mod == "claudinho.logger" then
        return mock_logger
      elseif mod == "claudinho.diff" then
        return { setup = function() end }
      elseif mod == "claudinho.terminal" then
        return mock_terminal
      elseif mod == "claudinho.server.init" then
        return {
          get_status = function()
            return { running = true, client_count = 1 }
          end,
        }
      else
        return saved_require(mod)
      end
    end

    claudinho = require("claudinho")
    claudinho.state.config = mock_config.apply()
    tab = active_tab.install({
      server = {
        broadcast = function()
          return true
        end,
      },
    })
  end

  before_each(function()
    _G.vim._exec_autocmds = {}
    saved_fn = { getcwd = _G.vim.fn.getcwd, isdirectory = _G.vim.fn.isdirectory }
  end)

  after_each(function()
    active_tab.uninstall(tab)
    tab = nil
    if saved_fn then
      _G.vim.fn.getcwd = saved_fn.getcwd
      _G.vim.fn.isdirectory = saved_fn.isdirectory
    end
    if saved_require then
      _G.require = saved_require
    end
    package.loaded["claudinho"] = nil
    package.loaded["claudinho.config"] = nil
    package.loaded["claudinho.logger"] = nil
    package.loaded["claudinho.diff"] = nil
    package.loaded["claudinho.terminal"] = nil
    package.loaded["claudinho.server.init"] = nil
  end)

  -- Search by pattern (never absolute index/count): mock state can carry entries
  -- from earlier specs in the shared busted process; we reset in before_each but
  -- assert on the LAST matching ClaudinhoSendComplete event regardless.
  local function last_send_complete()
    local found
    for _, e in ipairs(_G.vim._exec_autocmds or {}) do
      if e.event == "User" and e.opts and e.opts.pattern == "ClaudinhoSendComplete" then
        found = e
      end
    end
    return found
  end

  it("fires with the formatted payload returned by _broadcast_at_mention", function()
    setup_mocks()
    claudinho._broadcast_at_mention = function()
      return true, nil, { file_path = "src/foo.lua", start_line = 2, end_line = 4 }
    end

    local ok = claudinho.send_at_mention("/abs/src/foo.lua", 2, 4, "Claudinho send")
    assert.is_true(ok)

    local ev = last_send_complete()
    assert.is_not_nil(ev)
    assert.is_equal("src/foo.lua", ev.opts.data.file_path)
    assert.is_equal(2, ev.opts.data.start_line)
    assert.is_equal(4, ev.opts.data.end_line)
    assert.is_equal("Claudinho send", ev.opts.data.context)
    -- notification-only event must not re-process the buffer's modeline (#228 review)
    assert.is_false(ev.opts.modeline)
  end)

  it("falls back to the raw args when no payload is returned", function()
    setup_mocks()
    claudinho._broadcast_at_mention = function()
      return true, nil
    end

    claudinho.send_at_mention("/abs/bar.lua", nil, nil, "ctx")

    local ev = last_send_complete()
    assert.is_not_nil(ev)
    assert.is_equal("/abs/bar.lua", ev.opts.data.file_path)
    assert.is_nil(ev.opts.data.start_line)
    assert.is_nil(ev.opts.data.end_line)
    assert.is_equal("ctx", ev.opts.data.context)
  end)

  it("does not fire when the broadcast was not successful", function()
    setup_mocks()
    claudinho._broadcast_at_mention = function()
      return false, "broadcast failed"
    end

    claudinho.send_at_mention("/abs/baz.lua", 1, 2, "Claudinho send")

    assert.is_nil(last_send_complete())
  end)

  -- Drive the REAL _broadcast_at_mention (NOT stubbed) so the payload's formatted
  -- path / directory-adjusted lines are actually exercised. This is what locks in
  -- the headline behavior: the event reports what Claude received, not the raw args.
  it("reports the absolute formatted path (real _broadcast_at_mention)", function()
    setup_mocks()
    _G.vim.fn.getcwd = function()
      return "/Users/test/project"
    end
    _G.vim.fn.isdirectory = function()
      return 0
    end

    claudinho.send_at_mention("/Users/test/project/src/foo.lua", 2, 4, "Claudinho send")

    local ev = last_send_complete()
    assert.is_not_nil(ev)
    assert.is_equal("/Users/test/project/src/foo.lua", ev.opts.data.file_path)
    assert.is_equal(2, ev.opts.data.start_line)
    assert.is_equal(4, ev.opts.data.end_line)
  end)

  it("nulls line numbers for a directory send (real _broadcast_at_mention)", function()
    setup_mocks()
    _G.vim.fn.getcwd = function()
      return "/Users/test/project"
    end
    _G.vim.fn.isdirectory = function()
      return 1
    end

    claudinho.send_at_mention("/Users/test/project/lua", 2, 4, "Claudinho send")

    local ev = last_send_complete()
    assert.is_not_nil(ev)
    assert.is_equal("/Users/test/project/lua/", ev.opts.data.file_path)
    assert.is_nil(ev.opts.data.start_line)
    assert.is_nil(ev.opts.data.end_line)
  end)
end)
