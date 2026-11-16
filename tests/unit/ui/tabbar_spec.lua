require("tests.busted_setup")

describe("ui.tabbar", function()
  local tabbar

  before_each(function()
    package.loaded["claudinho.ui.tabbar"] = nil
    package.loaded["claudinho.sessions"] = nil
    tabbar = require("claudinho.ui.tabbar")
  end)

  local function width(items)
    local total = 0
    for _, item in ipairs(items) do
      total = total + vim.fn.strdisplaywidth(item.text)
    end
    return total
  end

  local function kinds(items)
    local out = {}
    for _, item in ipairs(items) do
      if item.kind ~= "sep" then
        out[#out + 1] = item.kind == "tab" and item.number or item.kind
      end
    end
    return out
  end

  local function find(items, number)
    for _, item in ipairs(items) do
      if item.kind == "tab" and item.number == number then
        return item
      end
    end
  end

  describe("clean_title()", function()
    it("drops the status symbol", function()
      assert.equals("Fix login bug", tabbar.clean_title("\xE2\x9C\xB3 Fix login bug"))
      assert.equals("Fix login bug", tabbar.clean_title("  \xE2\x9C\xBB Fix login bug  "))
      assert.equals("Fix login bug", tabbar.clean_title("\xC2\xB7 Fix login bug"))
    end)

    it("drops a braille spinner", function()
      assert.equals("Fix login bug", tabbar.clean_title("\xE2\xA0\x8B Fix login bug"))
      assert.equals("Fix login bug", tabbar.clean_title("\xE2\xA0\xBF Fix login bug"))
    end)

    it("keeps a first token that has a letter or a digit", function()
      assert.equals("Fix login bug", tabbar.clean_title("Fix login bug"))
      assert.equals("2fa setup", tabbar.clean_title("2fa setup"))
    end)

    it("is nil for generic titles", function()
      assert.is_nil(tabbar.clean_title("\xE2\x9C\xB3 Claude Code"))
      assert.is_nil(tabbar.clean_title("claude"))
      assert.is_nil(tabbar.clean_title("CLAUDE CODE"))
      assert.is_nil(tabbar.clean_title("term://~/proj//123:claude"))
    end)

    it("is nil for the configured command and its executable name", function()
      local ctx = { cmd = "/usr/local/bin/my-claude --verbose" }
      assert.is_nil(tabbar.clean_title("/usr/local/bin/my-claude --verbose", ctx))
      assert.is_nil(tabbar.clean_title("my-claude", ctx))
      assert.is_nil(tabbar.clean_title("\xE2\x9C\xB3 My-Claude", ctx))
      assert.equals("my-claude notes", tabbar.clean_title("my-claude notes", ctx))
    end)

    it("is nil when empty or not a string", function()
      assert.is_nil(tabbar.clean_title(""))
      assert.is_nil(tabbar.clean_title("   "))
      assert.is_nil(tabbar.clean_title("\xE2\x9C\xB3"))
      assert.is_nil(tabbar.clean_title(nil))
    end)
  end)

  describe("label()", function()
    it("shows number, title and the diff mark", function()
      assert.equals(
        "1 Fix login bug \xE2\x97\x8F diff",
        tabbar.label({ number = 1, title = "Fix login bug", diff = true }, 24)
      )
    end)

    it("shows the exited mark", function()
      assert.equals("3 Refactor [exited]", tabbar.label({ number = 3, title = "Refactor", exited = true }, 24))
    end)

    it("shows both marks, diff first", function()
      assert.equals(
        "3 Refactor \xE2\x97\x8F diff [exited]",
        tabbar.label({ number = 3, title = "Refactor", diff = true, exited = true }, 24)
      )
    end)

    it("uses Claude <n> without a title", function()
      assert.equals("2 Claude 2", tabbar.label({ number = 2 }, 24))
    end)

    it("cuts a long title with an ellipsis at the limit", function()
      local title = string.rep("a", 30)
      local label = tabbar.label({ number = 1, title = title }, 24)
      assert.equals("1 " .. string.rep("a", 23) .. "\xE2\x80\xA6", label)
    end)

    it("does not cut a title that fits", function()
      assert.equals("1 " .. string.rep("a", 24), tabbar.label({ number = 1, title = string.rep("a", 24) }, 24))
    end)

    it("keeps only number and marks at limit 0", function()
      assert.equals(
        "4 \xE2\x97\x8F diff [exited]",
        tabbar.label({ number = 4, title = "x", diff = true, exited = true }, 0)
      )
    end)

    it("never cuts the marks", function()
      local label = tabbar.label({ number = 12, title = string.rep("b", 40), diff = true, exited = true }, 5)
      assert.equals("12 bbbb\xE2\x80\xA6 \xE2\x97\x8F diff [exited]", label)
    end)
  end)

  describe("layout()", function()
    local tabs = {
      { number = 3, title = "Third" },
      { number = 1, title = "First" },
      { number = 2, title = "Second" },
    }

    it("orders the tabs ascending with the + last", function()
      assert.same({ 1, 2, 3, "new" }, kinds(tabbar.layout(tabs, 2, 200, 24)))
    end)

    it("separates items with the box bar", function()
      local items = tabbar.layout(tabs, 1, 200, 24)
      assert.equals("tab", items[1].kind)
      assert.equals("sep", items[2].kind)
      assert.equals("\xE2\x94\x82", items[2].text)
      assert.equals("new", items[#items].kind)
    end)

    it("marks the active tab only", function()
      local items = tabbar.layout(tabs, 2, 200, 24)
      assert.is_false(find(items, 1).active)
      assert.is_true(find(items, 2).active)
      assert.is_false(find(items, 3).active)
    end)

    it("shows only the + without tabs", function()
      assert.same({ "new" }, kinds(tabbar.layout({}, nil, 20, 24)))
    end)

    it("shrinks the title limit of every tab until it fits", function()
      local long = {
        { number = 1, title = string.rep("a", 24) },
        { number = 2, title = string.rep("b", 24) },
      }
      local full = width(tabbar.layout(long, 1, 1000, 24))
      local items = tabbar.layout(long, 1, full - 10, 24)

      assert.is_true(width(items) <= full - 10)
      assert.same({ 1, 2, "new" }, kinds(items))
      assert.equals(find(items, 1).limit, find(items, 2).limit)
      assert.is_true(find(items, 1).limit < 24)
    end)

    it("shrinks down to the numbers only", function()
      local long = {
        { number = 1, title = string.rep("a", 24), diff = true },
        { number = 2, title = string.rep("b", 24) },
      }
      local numbers_only = width(tabbar.layout(long, 1, 1000, 0))

      local items = tabbar.layout(long, 1, numbers_only, 24)

      assert.equals(0, find(items, 1).limit)
      assert.equals(0, find(items, 2).limit)
      assert.equals(" 1 \xE2\x97\x8F diff ", find(items, 1).text)
      assert.equals(" 2 ", find(items, 2).text)
    end)

    it("keeps the active tab and the + in a tiny window, with arrows", function()
      local many = {}
      for n = 1, 6 do
        many[n] = { number = n, title = "t" .. n }
      end
      local items = tabbar.layout(many, 4, 1, 24)

      assert.same({ "more_left", 4, "more_right", "new" }, kinds(items))
      assert.is_true(find(items, 4).active)
    end)

    it("adds neighbours alternating, right first, while they fit", function()
      local many = {}
      for n = 1, 6 do
        many[n] = { number = n, title = "t" .. n }
      end
      -- Tab 3 alone with both arrows and the + is 15 cells; each added tab costs 4. Right (4) fits, left (2) does not.
      local items = tabbar.layout(many, 3, 19, 24)

      assert.same({ "more_left", 3, 4, "more_right", "new" }, kinds(items))
      assert.is_true(width(items) <= 19)

      assert.same({ 1, 2, 3, 4, "more_right", "new" }, kinds(tabbar.layout(many, 3, 23, 24)))
    end)

    it("shows no left arrow when the first tab is visible", function()
      local many = {}
      for n = 1, 6 do
        many[n] = { number = n, title = "t" .. n }
      end
      local items = tabbar.layout(many, 1, 1, 24)
      assert.same({ 1, "more_right", "new" }, kinds(items))
    end)

    it("falls back to the first tab when the active one is unknown", function()
      local items = tabbar.layout({ { number = 5 }, { number = 6 } }, 99, 1, 24)
      assert.same({ 5, "more_right", "new" }, kinds(items))
    end)

    it("never cuts a mark in the numbers-only form", function()
      local items = tabbar.layout({ { number = 1, title = "x", exited = true } }, 1, 1, 24)
      assert.equals(" 1 [exited] ", find(items, 1).text)
    end)
  end)

  describe("render()", function()
    local tabs = {
      { number = 1, title = "Fix login bug", diff = true },
      { number = 2, title = "100% done", exited = true },
    }

    it("makes a click region per tab and for the +", function()
      local bar = tabbar.render(tabs, 1, 200, 24)

      assert.is_truthy(bar:find("%1@v:lua.ClaudinhoTabClick@", 1, true))
      assert.is_truthy(bar:find("%2@v:lua.ClaudinhoTabClick@", 1, true))
      assert.is_truthy(bar:find("%0@v:lua.ClaudinhoTabClick@%#ClaudinhoTabNew# + %X", 1, true))
    end)

    it("highlights the active tab and the others differently", function()
      local bar = tabbar.render(tabs, 2, 200, 24)

      assert.is_truthy(bar:find("%2@v:lua.ClaudinhoTabClick@%#ClaudinhoTabActive# 2", 1, true))
      assert.is_truthy(bar:find("%1@v:lua.ClaudinhoTabClick@%#ClaudinhoTab# 1", 1, true))
    end)

    it("highlights the marks with their own groups", function()
      local bar = tabbar.render(tabs, 1, 200, 24)

      assert.is_truthy(bar:find("%#ClaudinhoTabMark# \xE2\x97\x8F diff", 1, true))
      assert.is_truthy(bar:find("%#ClaudinhoTabExited# [exited]", 1, true))
    end)

    it("escapes % in titles", function()
      assert.is_truthy(tabbar.render(tabs, 1, 200, 24):find("100%% done", 1, true))
    end)

    it("ends with the fill group and keeps the + in a tiny window", function()
      local bar = tabbar.render(tabs, 1, 1, 24)
      assert.is_truthy(bar:find("%0@v:lua.ClaudinhoTabClick@", 1, true))
      assert.equals("%#ClaudinhoTabFill#", bar:sub(-#"%#ClaudinhoTabFill#"))
    end)

    it("keeps no state between calls", function()
      assert.equals(tabbar.render(tabs, 1, 80, 24), tabbar.render(tabs, 1, 80, 24))
    end)
  end)

  describe("click()", function()
    local sessions

    before_each(function()
      sessions = { new = spy.new(function() end), activate = spy.new(function() end) }
      package.loaded["claudinho.sessions"] = sessions
    end)

    after_each(function()
      package.loaded["claudinho.sessions"] = nil
    end)

    it("activates the tab on a left click", function()
      tabbar.click(2, 1, "l", "    ")
      assert.spy(sessions.activate).was.called_with(2)
      assert.spy(sessions.new).was_not.called()
    end)

    it("opens a new tab on a left click on the +", function()
      tabbar.click(0, 1, "l", "    ")
      assert.spy(sessions.new).was.called()
      assert.spy(sessions.activate).was_not.called()
    end)

    it("ignores the other buttons", function()
      tabbar.click(2, 1, "r", "    ")
      tabbar.click(0, 1, "m", "    ")
      assert.spy(sessions.new).was_not.called()
      assert.spy(sessions.activate).was_not.called()
    end)

    it("installs the global the winbar calls", function()
      local before = _G.ClaudinhoTabClick
      tabbar.install_click_handler()
      assert.equals(tabbar.click, _G.ClaudinhoTabClick)
      _G.ClaudinhoTabClick = before
    end)
  end)

  describe("setup_highlights()", function()
    it("links every group to a standard one with default", function()
      local calls = {}
      local original = vim.api.nvim_set_hl
      vim.api.nvim_set_hl = function(_, name, opts)
        calls[name] = opts
      end

      tabbar.setup_highlights()
      vim.api.nvim_set_hl = original

      assert.same({ link = "TabLineSel", default = true }, calls.ClaudinhoTabActive)
      assert.same({ link = "WarningMsg", default = true }, calls.ClaudinhoTabMark)
      assert.same({ link = "Comment", default = true }, calls.ClaudinhoTabExited)
      assert.same({ link = "TabLineFill", default = true }, calls.ClaudinhoTabFill)
    end)
  end)
end)
