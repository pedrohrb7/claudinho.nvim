-- luacheck: globals expect
require("tests.busted_setup")

describe("notify", function()
  local notify
  local original_plugin
  local original_notify
  local original_notify_once
  local calls

  local function set_config(config)
    package.loaded["claudinho"] = config and { state = { config = config } } or nil
  end

  before_each(function()
    original_plugin = package.loaded["claudinho"]
    original_notify = vim.notify
    original_notify_once = vim.notify_once
    calls = {}
    vim.notify = function(msg, level, opts)
      table.insert(calls, { fn = "notify", msg = msg, level = level, opts = opts })
    end
    vim.notify_once = function(msg, level, opts)
      table.insert(calls, { fn = "notify_once", msg = msg, level = level, opts = opts })
    end
    package.loaded["claudinho.notify"] = nil
    notify = require("claudinho.notify")
  end)

  after_each(function()
    package.loaded["claudinho"] = original_plugin
    vim.notify = original_notify
    vim.notify_once = original_notify_once
    package.loaded["claudinho.notify"] = nil
  end)

  describe("info", function()
    it("shows with notify = true, level INFO and the title", function()
      set_config({ notify = true })
      notify.info("hello")
      expect(#calls).to_be(1)
      expect(calls[1].fn).to_be("notify")
      expect(calls[1].msg).to_be("hello")
      expect(calls[1].level).to_be(vim.log.levels.INFO)
      expect(calls[1].opts.title).to_be("Claudinho")
    end)

    it("shows nothing with notify = false", function()
      set_config({ notify = false })
      notify.info("hello")
      notify.info("hello", { once = true })
      expect(#calls).to_be(0)
    end)

    it("shows nothing when the plugin has no config", function()
      set_config(nil)
      notify.info("hello")
      set_config({})
      notify.info("hello")
      expect(#calls).to_be(0)
    end)

    it("only counts notify == true", function()
      set_config({ notify = "yes" })
      notify.info("hello")
      expect(#calls).to_be(0)
    end)

    it("uses notify_once with opts.once", function()
      set_config({ notify = true })
      notify.info("once", { once = true })
      expect(#calls).to_be(1)
      expect(calls[1].fn).to_be("notify_once")
      expect(calls[1].opts.title).to_be("Claudinho")
    end)

    it("uses WARN with opts.level", function()
      set_config({ notify = true })
      notify.info("careful", { level = vim.log.levels.WARN })
      expect(calls[1].level).to_be(vim.log.levels.WARN)
    end)
  end)

  describe("reply and error", function()
    local cases = {
      { name = "reply", level = "WARN" },
      { name = "error", level = "ERROR" },
    }

    for _, case in ipairs(cases) do
      it(case.name .. " always shows, with its level and the title", function()
        for _, config in ipairs({ false, { notify = false }, { notify = true } }) do
          calls = {}
          set_config(config or nil)
          notify[case.name]("msg")
          expect(#calls).to_be(1)
          expect(calls[1].fn).to_be("notify")
          expect(calls[1].msg).to_be("msg")
          expect(calls[1].level).to_be(vim.log.levels[case.level])
          expect(calls[1].opts.title).to_be("Claudinho")
        end
      end)
    end
  end)
end)
