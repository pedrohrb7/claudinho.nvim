require("tests.busted_setup")
require("tests.mocks.vim")

describe("removed options", function()
  local config
  local notifications

  local function warnings()
    local messages = {}
    for _, n in ipairs(notifications) do
      if n.level == vim.log.levels.WARN then
        table.insert(messages, n.msg)
      end
    end
    return messages
  end

  local saved_notify = vim.notify
  local saved_notified_once = vim._notified_once

  before_each(function()
    package.loaded["claudinho.config"] = nil
    config = require("claudinho.config")
    notifications = {}
    vim._notified_once = nil
    vim.notify = function(msg, level)
      table.insert(notifications, { msg = msg, level = level })
    end
  end)

  after_each(function()
    vim.notify = saved_notify
    vim._notified_once = saved_notified_once
  end)

  local rows = {
    {
      "diff_opts.vertical_split",
      { diff_opts = { vertical_split = false } },
      "[Claudinho] diff_opts.vertical_split was removed and is ignored. Use diff_opts.layout instead.",
    },
    {
      "diff_opts.open_in_current_tab",
      { diff_opts = { open_in_current_tab = true } },
      "[Claudinho] diff_opts.open_in_current_tab was removed and is ignored. Use diff_opts.open_in_new_tab instead.",
    },
    {
      "diff_opts.auto_close_on_accept",
      { diff_opts = { auto_close_on_accept = true } },
      "[Claudinho] diff_opts.auto_close_on_accept was removed and is ignored. It had no effect.",
    },
    {
      "diff_opts.show_diff_stats",
      { diff_opts = { show_diff_stats = true } },
      "[Claudinho] diff_opts.show_diff_stats was removed and is ignored. It had no effect.",
    },
    {
      "queue_timeout",
      { queue_timeout = 5000 },
      "[Claudinho] queue_timeout was removed and is ignored. It had no effect.",
    },
  }

  describe("without_removed_options", function()
    for _, row in ipairs(rows) do
      local name, input, message = row[1], row[2], row[3]

      it("warns once with the exact text and drops " .. name, function()
        local result = config.without_removed_options(input)

        assert.are.same({ message }, warnings())
        assert.are.equal(vim.log.levels.WARN, notifications[1].level)
        if input.diff_opts then
          assert.is_nil(result.diff_opts[next(input.diff_opts)])
        else
          assert.is_nil(result[next(input)])
        end
      end)

      it("does not change the argument for " .. name, function()
        local before = vim.deepcopy(input)
        config.without_removed_options(input)
        assert.are.same(before, input)
      end)
    end

    it("does not fail on values of the wrong type", function()
      local result
      assert.has_no.errors(function()
        result = config.without_removed_options({
          queue_timeout = {},
          diff_opts = { vertical_split = "sim", show_diff_stats = {} },
        })
      end)
      assert.are.equal(3, #warnings())
      assert.is_nil(result.queue_timeout)
      assert.is_nil(result.diff_opts.vertical_split)
    end)

    it("counts false as present", function()
      config.without_removed_options({ diff_opts = { vertical_split = false } })
      assert.are.equal(1, #warnings())
    end)

    it("leaves diff_opts and terminal alone when they are not tables", function()
      local result = config.without_removed_options({ diff_opts = "x", terminal = 3 })
      assert.are.equal("x", result.diff_opts)
      assert.are.equal(3, result.terminal)
      assert.are.same({}, warnings())
    end)

    it("does not turn vertical_split or open_in_current_tab into layout or open_in_new_tab", function()
      local result = config.apply(config.without_removed_options({
        diff_opts = { vertical_split = false, open_in_current_tab = true },
      }))
      assert.are.equal("vertical", result.diff_opts.layout)
      assert.is_false(result.diff_opts.open_in_new_tab)
    end)

    it("does not copy the removed keys into the defaults or accept them as set", function()
      assert.is_nil(config.defaults.queue_timeout)
      assert.is_nil(config.defaults.diff_opts.vertical_split)
      assert.is_nil(config.defaults.diff_opts.open_in_current_tab)
      assert.is_nil(config.defaults.diff_opts.auto_close_on_accept)
      assert.is_nil(config.defaults.diff_opts.show_diff_stats)
    end)

    it("keeps the rest of the config, functions included", function()
      local provider = function() end
      local input = { log_level = "debug", terminal = { cwd_provider = provider, split_side = "left" } }
      local result = config.without_removed_options(input)
      assert.are.equal("debug", result.log_level)
      assert.are.equal(provider, result.terminal.cwd_provider)
      assert.are.equal("left", result.terminal.split_side)
      assert.are_not.equal(input.terminal, result.terminal)
    end)

    it("warns nothing for a config without removed keys", function()
      config.without_removed_options({ log_level = "debug", diff_opts = { layout = "horizontal" } })
      config.without_removed_options(nil)
      assert.are.same({}, warnings())
    end)

    it("warns once per key for repeated calls", function()
      config.without_removed_options({ queue_timeout = 1 })
      config.without_removed_options({ queue_timeout = 2 })
      assert.are.equal(1, #warnings())
    end)

    it("keeps diff_opts = 'x' failing in validation", function()
      assert.has.errors(function()
        config.apply(config.without_removed_options({ diff_opts = "x" }))
      end)
    end)

    it("supports a row with value and replace_with", function()
      table.insert(config.removed_options, {
        path = { "terminal", "provider" },
        value = "old",
        replace_with = "native",
        message = "[Claudinho] old provider",
      })
      local result = config.without_removed_options({ terminal = { provider = "old" } })
      assert.are.equal("native", result.terminal.provider)
      local other = config.without_removed_options({ terminal = { provider = "external" } })
      assert.are.equal("external", other.terminal.provider)
      assert.are.equal(1, #warnings())
    end)
  end)

  describe("terminal keys", function()
    local snacks_opts_message = "[Claudinho] terminal.snacks_win_opts was removed and is ignored."
    local snacks_provider_message = '[Claudinho] terminal.provider = "snacks" was removed. Using the native terminal.'

    it("warns once with the exact text and drops terminal.snacks_win_opts", function()
      local result = config.without_removed_options({ terminal = { snacks_win_opts = { position = "float" } } })
      assert.are.same({ snacks_opts_message }, warnings())
      assert.are.equal(vim.log.levels.WARN, notifications[1].level)
      assert.is_nil(result.terminal.snacks_win_opts)
    end)

    it("warns once with the exact text and swaps provider = 'snacks' for 'native'", function()
      local result = config.without_removed_options({ terminal = { provider = "snacks" } })
      assert.are.same({ snacks_provider_message }, warnings())
      assert.are.equal(vim.log.levels.WARN, notifications[1].level)
      assert.are.equal("native", result.terminal.provider)
    end)

    it("does not change the argument", function()
      local input = { terminal = { provider = "snacks", snacks_win_opts = {} } }
      local before = vim.deepcopy(input)
      config.without_removed_options(input)
      assert.are.same(before, input)
    end)

    it("does not warn for the other providers", function()
      for _, provider in ipairs({ "auto", "native", "external", "none" }) do
        local result = config.without_removed_options({ terminal = { provider = provider } })
        assert.are.equal(provider, result.terminal.provider)
      end
      assert.are.same({}, warnings())
    end)

    it("does not fail on a snacks_win_opts of the wrong type", function()
      assert.has_no.errors(function()
        config.without_removed_options({ terminal = { snacks_win_opts = "x" } })
      end)
      assert.are.equal(1, #warnings())
    end)
  end)

  describe("init.setup", function()
    local saved_require = _G.require
    local terminal_setup_args

    before_each(function()
      terminal_setup_args = nil
      package.loaded["claudinho"] = nil
      _G.require = function(mod)
        if mod == "claudinho.terminal" then
          return {
            setup = function(...)
              terminal_setup_args = { ... }
            end,
          }
        end
        return saved_require(mod)
      end
    end)

    after_each(function()
      _G.require = saved_require
      package.loaded["claudinho"] = nil
    end)

    it("passes the copy on and keeps the rest of the config", function()
      local claudinho = require("claudinho")
      local input = {
        auto_start = false,
        queue_timeout = 5000,
        diff_opts = { vertical_split = true },
        terminal = { split_side = "left" },
      }
      assert.has_no.errors(function()
        claudinho.setup(input)
      end)

      assert.are.equal(2, #warnings())
      assert.are.equal("left", terminal_setup_args[1].split_side)
      assert.is_nil(claudinho.state.config.queue_timeout)
      assert.is_nil(claudinho.state.config.diff_opts.vertical_split)
      assert.are.equal(5000, input.queue_timeout)
      assert.is_true(input.diff_opts.vertical_split)
    end)

    it("hands terminal.setup provider = native and no snacks_win_opts", function()
      local claudinho = require("claudinho")
      assert.has_no.errors(function()
        claudinho.setup({
          auto_start = false,
          terminal = { provider = "snacks", snacks_win_opts = { position = "float" }, split_side = "left" },
        })
      end)
      assert.are.equal(2, #warnings())
      assert.are.equal("native", terminal_setup_args[1].provider)
      assert.is_nil(terminal_setup_args[1].snacks_win_opts)
      assert.are.equal("left", terminal_setup_args[1].split_side)
    end)

    it("does not warn for a config without removed keys", function()
      require("claudinho").setup({ auto_start = false })
      assert.are.same({}, warnings())
    end)

    it("keeps failing on diff_opts = 'x'", function()
      assert.has.errors(function()
        require("claudinho").setup({ auto_start = false, diff_opts = "x" })
      end)
    end)
  end)
end)
