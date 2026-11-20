require("tests.busted_setup")

describe("ui.status", function()
  local status

  before_each(function()
    package.loaded["claudinho.ui.status"] = nil
    status = require("claudinho.ui.status")
  end)

  it("joins model, effort and mode in this order", function()
    assert.equals(
      "Opus 5.5 \xC2\xB7 high \xC2\xB7 plan",
      status.text({ mode = "plan", effort = "high", model = "Opus 5.5" })
    )
  end)

  it("skips a missing item without a stray separator", function()
    assert.equals("Opus 5.5 \xC2\xB7 plan", status.text({ model = "Opus 5.5", mode = "plan" }))
    assert.equals("high \xC2\xB7 plan", status.text({ effort = "high", mode = "plan" }))
    assert.equals("Opus 5.5", status.text({ model = "Opus 5.5" }))
    assert.equals("high", status.text({ effort = "high" }))
  end)

  it("is empty without data", function()
    assert.equals("", status.text({}))
    assert.equals("", status.text(nil))
  end)

  describe("modes", function()
    local cases = {
      { "default", "manual" },
      { "manual", "manual" },
      { "plan", "plan" },
      { "auto", "auto" },
      { "acceptEdits", "accept edits" },
      { "dontAsk", "don't ask" },
      { "bypassPermissions", "bypass permissions" },
    }
    for _, case in ipairs(cases) do
      local mode, shown = case[1], case[2]
      it(mode .. " shows " .. shown, function()
        assert.equals(shown, status.text({ mode = mode }))
      end)
    end

    it("shows an unknown mode as it came", function()
      assert.equals("futureMode", status.text({ mode = "futureMode" }))
    end)
  end)

  it("doubles % for the statusline", function()
    assert.equals("100%% model", status.text({ model = "100% model" }))
  end)

  describe("items", function()
    it("gives ids 1, 2 and 3 only to the present items", function()
      assert.same(
        { { id = 1, text = "Opus" }, { id = 2, text = "high" }, { id = 3, text = "plan" } },
        status.items({ model = "Opus", effort = "high", mode = "plan" })
      )
      assert.same(
        { { id = 1, text = "Opus" }, { id = 3, text = "plan" } },
        status.items({ model = "Opus", mode = "plan" })
      )
      assert.same({ { id = 2, text = "high" } }, status.items({ effort = "high" }))
      assert.same({}, status.items(nil))
    end)
  end)

  describe("percent and level", function()
    it("rounds half up", function()
      local cases = { { 23.5, 24 }, { 79.4, 79 }, { 79.5, 80 }, { 94.4, 94 }, { 94.5, 95 }, { 0, 0 }, { 103, 103 } }
      for _, c in ipairs(cases) do
        assert.equals(c[2], status.percent(c[1]), tostring(c[1]))
      end
    end)

    it("picks the group at the limits", function()
      assert.is_nil(status.level(79))
      assert.equals("ClaudinhoUsageWarn", status.level(80))
      assert.equals("ClaudinhoUsageWarn", status.level(94))
      assert.equals("ClaudinhoUsageError", status.level(95))
      assert.equals("ClaudinhoUsageError", status.level(100))
    end)
  end)

  describe("format_reset", function()
    local ok_ffi, ffi = pcall(require, "ffi")
    local old_tz = os.getenv("TZ")
    local old_locale

    local function set_tz(tz)
      ffi.cdef("int setenv(const char *, const char *, int); int unsetenv(const char *); void tzset(void);")
      if tz then
        ffi.C.setenv("TZ", tz, 1)
      else
        ffi.C.unsetenv("TZ")
      end
      ffi.C.tzset()
    end

    local function at(tz, y, mo, d, h, mi, sec)
      set_tz(tz)
      return os.time({ year = y, month = mo, day = d, hour = h, min = mi, sec = sec or 0 })
    end

    before_each(function()
      old_locale = os.setlocale(nil, "time")
    end)

    after_each(function()
      if ok_ffi then
        set_tz(old_tz)
      end
      os.setlocale(old_locale, "time")
    end)

    if not ok_ffi then
      pending("needs LuaJIT ffi to change TZ")
      return
    end

    it("shows only the time for today", function()
      local now = at("America/Sao_Paulo", 2026, 11, 20, 9, 0)
      assert.equals("14:30", status.format_reset(at("America/Sao_Paulo", 2026, 11, 20, 14, 30), now))
    end)

    it("drops the seconds", function()
      local now = at("America/Sao_Paulo", 2026, 11, 20, 9, 0)
      assert.equals("09:05", status.format_reset(at("America/Sao_Paulo", 2026, 11, 20, 9, 5, 59), now))
    end)

    it("adds the day name for tomorrow after midnight and up to 6 days", function()
      local now = at("America/Sao_Paulo", 2026, 11, 20, 23, 0)
      assert.equals("Sat 01:30", status.format_reset(at("America/Sao_Paulo", 2026, 11, 21, 1, 30), now))
      assert.equals("Thu 09:00", status.format_reset(at("America/Sao_Paulo", 2026, 11, 26, 9, 0), now))
    end)

    it("adds the month and day from 7 days on", function()
      local now = at("America/Sao_Paulo", 2026, 11, 20, 9, 0)
      assert.equals("Nov 27 09:00", status.format_reset(at("America/Sao_Paulo", 2026, 11, 27, 9, 0), now))
      assert.equals("Dec 2 18:00", status.format_reset(at("America/Sao_Paulo", 2026, 12, 2, 18, 0), now))
    end)

    it("counts calendar days across the daylight saving change", function()
      local now = at("America/New_York", 2026, 11, 1, 0, 30)
      -- 2026-11-01 is the end of daylight saving: the day has 25 hours.
      assert.equals("Mon 00:10", status.format_reset(at("America/New_York", 2026, 11, 2, 0, 10), now))
      assert.equals("Nov 8 00:10", status.format_reset(at("America/New_York", 2026, 11, 8, 0, 10), now))
    end)

    it("uses English names whatever the locale", function()
      local now = at("America/Sao_Paulo", 2026, 11, 20, 9, 0)
      local reset = at("America/Sao_Paulo", 2026, 11, 23, 9, 0)
      for _, locale in ipairs({ "pt_BR.UTF-8", "de_DE.UTF-8", "en_US.utf8" }) do
        os.setlocale(locale, "time")
        assert.equals("Mon 09:00", status.format_reset(reset, now))
      end
    end)
  end)

  describe("layout", function()
    local usage = {
      five_hour = { used = 23, resets_at = 1000 },
      seven_day = { used = 41, resets_at = 1000 },
    }
    local function texts(items)
      local out = {}
      for i, item in ipairs(items) do
        out[i] = item.text
      end
      return out
    end

    -- With resets_at 1000 and now 0 the times are "00:16" or similar in some zone: compare by shape.
    local now = 1000 - 60

    it("keeps both items with the times when they fit", function()
      local out = texts(status.layout(0, usage, 200, now))
      assert.equals(2, #out)
      assert.truthy(out[1]:match("^5h 23%% %(%d%d:%d%d%)$"))
      assert.truthy(out[2]:match("^7d 41%% %(%d%d:%d%d%)$"))
    end)

    it("drops the times, then the 7d, then everything", function()
      assert.same({ "5h 23%", "7d 41%" }, texts(status.layout(0, usage, 14 + 3 + 6, now)))
      assert.same({ "5h 23%" }, texts(status.layout(0, usage, 12, now)))
      assert.same({ "5h 23%" }, texts(status.layout(0, usage, 6, now)))
      assert.same({}, texts(status.layout(0, usage, 5, now)))
    end)

    it("fits exactly at the border with the minimum gap", function()
      -- "5h 23%" is 6 cells; left 10 + gap 2 + 6 = 18
      assert.same({ "5h 23%" }, texts(status.layout(10, usage, 18, now)))
      assert.same({}, texts(status.layout(10, usage, 17, now)))
    end)

    it("never gives the left side up for the usage", function()
      assert.same({}, texts(status.layout(50, usage, 40, now)))
    end)

    it("keeps the single present item when only the 7d came", function()
      local only = { seven_day = { used = 41 } }
      assert.same({ "7d 41%" }, texts(status.layout(0, only, 10, now)))
    end)

    it("is empty without usage", function()
      assert.same({}, status.layout(0, nil, 200, now))
      assert.same({}, status.layout(0, {}, 200, now))
    end)
  end)

  describe("build", function()
    local now = 1000
    local data = { model = "Opus 5.5", effort = "high", mode = "plan" }

    it("wraps each left item in a click region, the separator outside", function()
      local c = "v:lua." .. status.CLICK_FUNC
      assert.equals(
        "%1@" .. c .. "@Opus 5.5%X \xC2\xB7 %2@" .. c .. "@high%X \xC2\xB7 %3@" .. c .. "@plan%X",
        status.build(data, nil, 200, now)
      )
    end)

    it("omits the region of a missing item and the stray separator", function()
      local c = "v:lua." .. status.CLICK_FUNC
      assert.equals(
        "%1@" .. c .. "@Opus%X \xC2\xB7 %3@" .. c .. "@plan%X",
        status.build({ model = "Opus", mode = "plan" }, nil, 200, now)
      )
    end)

    it("doubles % in the regions", function()
      assert.truthy(status.build({ model = "100% model" }, nil, 200, now):find("@100%% model%X", 1, true))
    end)

    it("puts the usage after %= without regions and colors only the item", function()
      local out = status.build({ model = "Opus" }, { five_hour = { used = 23 }, seven_day = { used = 82 } }, 200, now)
      assert.truthy(out:find("%=5h 23%% \xC2\xB7 %$ClaudinhoUsageWarn$7d 82%%%*", 1, true))
      assert.is_nil(out:match("%%=.*%%%d@"))
    end)

    it("colors each item by its own level", function()
      local out = status.build(nil, { five_hour = { used = 96 }, seven_day = { used = 10 } }, 200, now)
      assert.equals("%=%$ClaudinhoUsageError$5h 96%%%* \xC2\xB7 7d 10%%", out)
    end)

    it("shows an item without the time when resets_at is missing", function()
      assert.equals("%=5h 23%%", status.build(nil, { five_hour = { used = 23 } }, 200, now))
    end)

    it("shows only the right side without a left side", function()
      assert.equals("%=7d 41%%", status.build(nil, { seven_day = { used = 41 } }, 200, now))
    end)

    it("is empty without a left side and without usage", function()
      assert.equals("", status.build(nil, nil, 200, now))
      assert.equals("", status.build({}, {}, 200, now))
    end)

    it("drops the usage in a narrow window and keeps the left side", function()
      local c = "v:lua." .. status.CLICK_FUNC
      local out = status.build({ model = "Opus 5.5" }, { five_hour = { used = 23 } }, 10, now)
      assert.equals("%1@" .. c .. "@Opus 5.5%X", out)
    end)
  end)

  describe("setup_highlights", function()
    it("links the groups to the theme groups with default", function()
      vim._highlights = nil
      status.setup_highlights()
      assert.same({ link = "DiagnosticWarn", default = true }, vim._highlights.ClaudinhoUsageWarn.opts)
      assert.same({ link = "DiagnosticError", default = true }, vim._highlights.ClaudinhoUsageError.opts)
    end)
  end)

  describe("render", function()
    before_each(function()
      package.loaded["claudinho.usage"] = {
        now = function()
          return 0
        end,
        windows = function()
          return {}
        end,
      }
    end)

    after_each(function()
      package.loaded["claudinho.sessions"] = nil
      package.loaded["claudinho.usage"] = nil
    end)

    it("shows the data of the active tab", function()
      package.loaded["claudinho.sessions"] = {
        active = function()
          return { data = { model = "Opus 5.5", mode = "plan" } }
        end,
      }
      local out = status.render()
      assert.truthy(out:find("@Opus 5.5%X", 1, true))
      assert.truthy(out:find("@plan%X", 1, true))
    end)

    it("adds the usage and shows it for an ended or empty tab too", function()
      package.loaded["claudinho.sessions"] = {
        active = function()
          return nil
        end,
      }
      package.loaded["claudinho.usage"] = {
        now = function()
          return 0
        end,
        windows = function()
          return { five_hour = { used = 23 } }
        end,
      }
      assert.equals("%=5h 23%%", status.render())
    end)

    it("is empty without an active tab", function()
      package.loaded["claudinho.sessions"] = {
        active = function()
          return nil
        end,
      }
      assert.equals("", status.render())
    end)
  end)
end)
