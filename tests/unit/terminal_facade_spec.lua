--- The terminal facade: `claudinho.terminal` is the active Claude tab, seen by the code that wants "the Claude
--- terminal" (diff, selection, send). The tab registry, the window, the notifications and the paste fix are fakes.
--- The rules of `send_to_terminal` are in tests/unit/terminal/send_text_spec.lua.
require("tests.busted_setup")

describe("claudinho.terminal facade", function()
  local terminal
  local loaded_names = {
    "claudinho.terminal",
    "claudinho.sessions",
    "claudinho.ui.window",
    "claudinho.notify",
    "claudinho.terminal.paste_fix",
  }
  local saved_loaded, restore_list
  local log, tab, valid_buffers, notices

  ---Replace tbl[key] until after_each.
  local function stub(tbl, key, value)
    table.insert(restore_list, { tbl, key, tbl[key] })
    tbl[key] = value
  end

  before_each(function()
    saved_loaded, restore_list = {}, {}
    for _, name in ipairs(loaded_names) do
      saved_loaded[name] = package.loaded[name]
      package.loaded[name] = nil
    end
    log, tab, notices = {}, nil, {}
    valid_buffers = {}

    package.loaded["claudinho.sessions"] = {
      NO_TABS = "No Claude tabs open",
      active = function()
        return tab
      end,
      new = function()
        table.insert(log, "sessions.new")
      end,
    }
    package.loaded["claudinho.ui.window"] = {
      show = function(opts)
        table.insert(log, "window.show focus=" .. tostring(opts and opts.focus))
      end,
      ensure_visible = function()
        table.insert(log, "window.ensure_visible")
      end,
    }
    package.loaded["claudinho.notify"] = {
      error = function(msg)
        table.insert(notices, { "error", msg })
      end,
      reply = function(msg)
        table.insert(notices, { "reply", msg })
      end,
    }
    package.loaded["claudinho.terminal.paste_fix"] = {
      apply = function(value)
        table.insert(log, "paste_fix.apply " .. tostring(value))
      end,
    }
    stub(vim.api, "nvim_buf_is_valid", function(buf)
      return valid_buffers[buf] == true
    end)

    terminal = require("claudinho.terminal")
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

  describe("setup", function()
    it("hands fix_streamed_paste to the paste fix", function()
      terminal.setup({ fix_streamed_paste = true, auto_insert = false })

      assert.are.same({ "paste_fix.apply true" }, log)
    end)

    it("applies the paste fix with no value for a missing table", function()
      terminal.setup(nil)

      assert.are.same({ "paste_fix.apply nil" }, log)
    end)

    it("reports a table that is not one and goes on without it", function()
      terminal.setup("nope")

      assert.are.same({ { "error", "[Claudinho] claudinho.terminal.setup expects a table or nil" } }, notices)
      assert.are.same({ "paste_fix.apply nil" }, log)
    end)
  end)

  describe("get_active_terminal_bufnr", function()
    it("is nil without tabs", function()
      assert.is_nil(terminal.get_active_terminal_bufnr())
    end)

    it("is the buffer of the active tab", function()
      tab = { number = 2, state = "running", buf = 77 }
      valid_buffers[77] = true

      assert.are.equal(77, terminal.get_active_terminal_bufnr())
    end)

    it("is also the buffer of a tab that has exited, which the window still shows", function()
      tab = { number = 2, state = "exited", buf = 77 }
      valid_buffers[77] = true

      assert.are.equal(77, terminal.get_active_terminal_bufnr())
    end)

    it("is nil for a buffer that is gone", function()
      tab = { number = 1, state = "running", buf = 77 }

      assert.is_nil(terminal.get_active_terminal_bufnr())
    end)

    it("does not load the tab registry by itself", function()
      package.loaded["claudinho.sessions"] = nil

      assert.is_nil(terminal.get_active_terminal_bufnr())
      assert.is_nil(package.loaded["claudinho.sessions"])
    end)
  end)

  describe("ensure_visible", function()
    it("asks the window to come back", function()
      terminal.ensure_visible()

      assert.are.same({ "window.ensure_visible" }, log)
    end)
  end)

  describe("open", function()
    it("shows the window of the active tab and focuses it", function()
      tab = { number = 1, state = "running", buf = 5 }

      terminal.open()

      assert.are.same({ "window.show focus=true" }, log)
    end)

    it("starts the first tab without tabs", function()
      terminal.open()

      assert.are.same({ "sessions.new" }, log)
    end)
  end)

  describe("the API that left", function()
    it("has no toggles, close, providers or defaults", function()
      for _, name in ipairs({
        "simple_toggle",
        "focus_toggle",
        "toggle",
        "close",
        "toggle_open_no_focus",
        "defaults",
        "_get_managed_terminal_for_test",
      }) do
        assert.is_nil(terminal[name], name)
      end
    end)
  end)

  describe("send_to_terminal", function()
    it("replies without tabs and starts nothing", function()
      assert.is_false(terminal.send_to_terminal("hello"))

      assert.are.same({ { "reply", "No Claude tabs open" } }, notices)
      assert.are.same({}, log)
    end)
  end)
end)
