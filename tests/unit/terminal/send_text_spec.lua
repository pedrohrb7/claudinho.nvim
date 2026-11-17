-- Tests for terminal.send_to_terminal (#197): send raw text to the active Claude tab.
require("tests.busted_setup")
require("tests.mocks.vim")

describe("terminal.send_to_terminal (#197)", function()
  local terminal
  local chansend_calls
  local replies
  local shows
  local new_calls
  local tab
  local BUF = 4242

  local function register_buffer(bufnr, b_vars, channel)
    vim._buffers[bufnr] = { lines = {}, options = {}, b_vars = b_vars or {} }
    vim.bo[bufnr] = { channel = channel }
  end

  before_each(function()
    _G.vim = require("tests.mocks.vim")
    vim._buffers = {}
    -- The mock has no vim.bo; provide a simple table-of-tables for the fallback.
    vim.bo = {}

    vim.fn = vim.fn or {}

    chansend_calls = {}
    vim.fn.chansend = function(chan, data)
      table.insert(chansend_calls, { chan = chan, data = data })
      return type(data) == "string" and #data or 0
    end

    replies = {}
    shows = {}
    new_calls = 0
    tab = nil
    package.loaded["claudinho.logger"] = {
      debug = function() end,
      warn = function() end,
      error = function() end,
      info = function() end,
      setup = function() end,
    }
    package.loaded["claudinho.notify"] = {
      reply = function(msg)
        table.insert(replies, msg)
      end,
      error = function() end,
      info = function() end,
    }
    package.loaded["claudinho.sessions"] = {
      NO_TABS = "No Claude tabs open",
      active = function()
        return tab
      end,
      new = function()
        new_calls = new_calls + 1
      end,
      exited_message = function(s)
        return ("Claude %d has exited; run :Claudinho tab-restart %d"):format(s.number, s.number)
      end,
    }
    package.loaded["claudinho.ui.window"] = {
      show = function(opts)
        table.insert(shows, opts)
      end,
    }

    package.loaded["claudinho.terminal"] = nil
    terminal = require("claudinho.terminal")
  end)

  after_each(function()
    package.loaded["claudinho.notify"] = nil
    package.loaded["claudinho.sessions"] = nil
    package.loaded["claudinho.ui.window"] = nil
    package.loaded["claudinho.terminal"] = nil
  end)

  local function setup_with_buffer(b_vars, channel)
    register_buffer(BUF, b_vars, channel)
    tab = { number = 1, state = "running", buf = BUF }
  end

  local function warned(pattern)
    for _, m in ipairs(replies) do
      if tostring(m):match(pattern) then
        return true
      end
    end
    return false
  end

  it("sends single-line text with a trailing CR by default", function()
    setup_with_buffer({ terminal_job_id = 42 })
    local ok = terminal.send_to_terminal("hello")
    assert.is_true(ok)
    assert.are.equal(1, #chansend_calls)
    assert.are.equal(42, chansend_calls[1].chan)
    assert.are.equal("hello\r", chansend_calls[1].data)
  end)

  it("omits the CR when submit=false", function()
    setup_with_buffer({ terminal_job_id = 42 })
    local ok = terminal.send_to_terminal("hello", { submit = false })
    assert.is_true(ok)
    assert.are.equal("hello", chansend_calls[1].data)
  end)

  it("wraps multi-line text in bracketed paste then a CR", function()
    setup_with_buffer({ terminal_job_id = 42 })
    terminal.send_to_terminal("a\nb")
    assert.are.equal("\27[200~a\nb\27[201~\r", chansend_calls[1].data)
  end)

  it("wraps multi-line text in bracketed paste with no CR when submit=false", function()
    setup_with_buffer({ terminal_job_id = 42 })
    terminal.send_to_terminal("a\nb", { submit = false })
    assert.are.equal("\27[200~a\nb\27[201~", chansend_calls[1].data)
  end)

  it("normalizes CRLF to LF and wraps as a single bracketed block", function()
    setup_with_buffer({ terminal_job_id = 42 })
    terminal.send_to_terminal("a\r\nb")
    assert.are.equal("\27[200~a\nb\27[201~\r", chansend_calls[1].data)
  end)

  it("normalizes a lone CR (which would otherwise submit prematurely)", function()
    setup_with_buffer({ terminal_job_id = 42 })
    terminal.send_to_terminal("a\rb")
    assert.are.equal("\27[200~a\nb\27[201~\r", chansend_calls[1].data)
  end)

  it("returns false and sends nothing for an empty string", function()
    setup_with_buffer({ terminal_job_id = 42 })
    local ok = terminal.send_to_terminal("")
    assert.is_false(ok)
    assert.are.equal(0, #chansend_calls)
  end)

  it("returns false for non-string text", function()
    setup_with_buffer({ terminal_job_id = 42 })
    assert.is_false(terminal.send_to_terminal(nil))
    assert.is_false(terminal.send_to_terminal(123))
    assert.are.equal(0, #chansend_calls)
  end)

  it("falls back to bo.channel when terminal_job_id is absent", function()
    setup_with_buffer({}, 7) -- no terminal_job_id, channel = 7
    local ok = terminal.send_to_terminal("hi")
    assert.is_true(ok)
    assert.are.equal(7, chansend_calls[1].chan)
  end)

  it("falls back to bo.channel when terminal_job_id is 0 (recovered terminal)", function()
    setup_with_buffer({ terminal_job_id = 0 }, 99) -- job id lost on recovery, channel intact
    local ok = terminal.send_to_terminal("hi")
    assert.is_true(ok)
    assert.are.equal(99, chansend_calls[1].chan)
  end)

  it("returns false when no channel can be resolved", function()
    setup_with_buffer({}, nil) -- no job id, no channel
    local ok = terminal.send_to_terminal("hi")
    assert.is_false(ok)
    assert.are.equal(0, #chansend_calls)
    assert.is_true(warned("no terminal job channel"))
  end)

  it("treats terminal_job_id 0 as invalid", function()
    setup_with_buffer({ terminal_job_id = 0 }, nil)
    local ok = terminal.send_to_terminal("hi")
    assert.is_false(ok)
    assert.are.equal(0, #chansend_calls)
  end)

  it("replies and sends nothing without tabs", function()
    local ok = terminal.send_to_terminal("hi")
    assert.is_false(ok)
    assert.are.equal(0, #chansend_calls)
    assert.are.same({ "No Claude tabs open" }, replies)
    assert.are.equal(0, new_calls)
  end)

  it("replies and sends nothing when the active tab has exited", function()
    setup_with_buffer({ terminal_job_id = 42 })
    tab.state = "exited"
    tab.number = 3
    local ok = terminal.send_to_terminal("hi")
    assert.is_false(ok)
    assert.are.equal(0, #chansend_calls)
    assert.are.same({ "Claude 3 has exited; run :Claudinho tab-restart 3" }, replies)
  end)

  it("treats a stale (invalid) bufnr as no terminal", function()
    tab = { number = 1, state = "running", buf = BUF } -- the buffer is never registered
    local ok = terminal.send_to_terminal("hi")
    assert.is_false(ok)
    assert.are.equal(0, #chansend_calls)
    assert.is_true(warned("no Claude terminal is currently running"))
  end)

  it("replies when the channel is closed", function()
    setup_with_buffer({ terminal_job_id = 42 })
    vim.fn.chansend = function()
      return 0
    end
    local ok = terminal.send_to_terminal("hi")
    assert.is_false(ok)
    assert.is_true(warned("channel is closed"))
  end)

  it("replies when there is no text", function()
    setup_with_buffer({ terminal_job_id = 42 })
    assert.is_false(terminal.send_to_terminal(""))
    assert.is_true(warned("no text provided"))
  end)

  it("focuses the terminal after a successful send when focus=true", function()
    setup_with_buffer({ terminal_job_id = 42 })
    local ok = terminal.send_to_terminal("hi", { focus = true })
    assert.is_true(ok)
    assert.are.equal(1, #chansend_calls)
    assert.are.same({ { focus = true } }, shows)
  end)

  it("does not focus when the send fails even if focus=true", function()
    setup_with_buffer({}, nil) -- no channel -> failure
    local ok = terminal.send_to_terminal("hi", { focus = true })
    assert.is_false(ok)
    assert.are.same({}, shows)
  end)
end)
