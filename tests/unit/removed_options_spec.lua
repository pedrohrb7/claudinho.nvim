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

  local NOTIFY = { notify = true }

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

  local function removed(key, text)
    return "[Claudinho] " .. key .. " was removed and is ignored." .. (text and (" " .. text) or "")
  end

  local external = "External terminals are no longer supported."
  local nothing_starts = "Nothing starts with setup(); each tab starts its own server."
  local pwd = "New tabs start in Neovim's current directory (:pwd)."
  local function entry(name, input, text)
    return { name, input, removed(name, text) }
  end

  -- The terminal and directory keys of the base UI (spec section 4, rules 71, 77 and 93 to 95).
  local base_rows = rows
  rows = {}
  for _, r in ipairs(base_rows) do
    rows[#rows + 1] = r
  end
  for _, r in ipairs({
    entry(
      "terminal.provider",
      { terminal = { provider = "auto" } },
      "Claude always runs in Neovim's terminal, in the window set by window.layout."
    ),
    entry("terminal.provider_opts", { terminal = { provider_opts = { external_terminal_cmd = "x %s" } } }, external),
    entry("terminal.external_terminal_cmd", { terminal = { external_terminal_cmd = "x %s" } }, external),
    entry("terminal.split_side", { terminal = { split_side = "left" } }, "Use window.layout instead."),
    entry(
      "terminal.split_width_percentage",
      { terminal = { split_width_percentage = 0.4 } },
      "Use window.right.width instead."
    ),
    entry(
      "terminal.diff_split_width_percentage",
      { terminal = { diff_split_width_percentage = 0.2 } },
      "Use window.right.diff_width instead."
    ),
    entry(
      "terminal.auto_close",
      { terminal = { auto_close = false } },
      "Tabs never close by themselves; use :Claudinho tab-close."
    ),
    entry("terminal.show_native_term_exit_tip", { terminal = { show_native_term_exit_tip = false } }),
    entry("auto_start", { auto_start = false }, nothing_starts),
    entry("terminal.auto_start", { terminal = { auto_start = true } }, nothing_starts),
    entry("terminal.cwd", { terminal = { cwd = "/tmp" } }, pwd),
    entry("terminal.git_repo_cwd", { terminal = { git_repo_cwd = true } }, pwd),
    entry("terminal.cwd_provider", { terminal = { cwd_provider = function() end } }, pwd),
    entry("cwd", { cwd = "/tmp" }, pwd),
    entry("git_repo_cwd", { git_repo_cwd = true }, pwd),
    entry("cwd_provider", { cwd_provider = function() end }, pwd),
  }) do
    rows[#rows + 1] = r
  end

  describe("without_removed_options", function()
    for _, row in ipairs(rows) do
      local name, input, message = row[1], row[2], row[3]

      it("warns once with the exact text and drops " .. name, function()
        local result = config.without_removed_options(input, NOTIFY)

        assert.are.same({ message }, warnings())
        assert.are.equal(vim.log.levels.WARN, notifications[1].level)
        -- The key is gone, at the depth its name says.
        local path = {}
        for part in name:gmatch("[^.]+") do
          path[#path + 1] = part
        end
        local node = result
        for i = 1, #path - 1 do
          node = node[path[i]]
        end
        assert.is_nil(node[path[#path]], name)
      end)

      it("does not change the argument for " .. name, function()
        local before = vim.deepcopy(input)
        config.without_removed_options(input, NOTIFY)
        assert.are.same(before, input)
      end)
    end

    it("does not fail on values of the wrong type", function()
      local result
      assert.has_no.errors(function()
        result = config.without_removed_options({
          queue_timeout = {},
          diff_opts = { vertical_split = "sim", show_diff_stats = {} },
        }, NOTIFY)
      end)
      assert.are.equal(3, #warnings())
      assert.is_nil(result.queue_timeout)
      assert.is_nil(result.diff_opts.vertical_split)
    end)

    it("counts false as present", function()
      config.without_removed_options({ diff_opts = { vertical_split = false } }, NOTIFY)
      assert.are.equal(1, #warnings())
    end)

    it("leaves diff_opts and terminal alone when they are not tables", function()
      local result = config.without_removed_options({ diff_opts = "x", terminal = 3 }, NOTIFY)
      assert.are.equal("x", result.diff_opts)
      assert.are.equal(3, result.terminal)
      assert.are.same({}, warnings())
    end)

    it("does not turn vertical_split or open_in_current_tab into layout or open_in_new_tab", function()
      local result = config.apply((config.without_removed_options({
        diff_opts = { vertical_split = false, open_in_current_tab = true },
      }, NOTIFY)))
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
      local input = { log_level = "debug", terminal = { auto_insert = false, custom = provider, split_side = "left" } }
      local result = config.without_removed_options(input, NOTIFY)
      assert.are.equal("debug", result.log_level)
      assert.are.equal(provider, result.terminal.custom)
      assert.is_false(result.terminal.auto_insert)
      assert.is_nil(result.terminal.split_side)
      assert.are_not.equal(input.terminal, result.terminal)
    end)

    it("warns nothing for a config without removed keys", function()
      config.without_removed_options({ log_level = "debug", diff_opts = { layout = "horizontal" } }, NOTIFY)
      config.without_removed_options(nil, NOTIFY)
      assert.are.same({}, warnings())
    end)

    it("warns once per key for repeated calls", function()
      config.without_removed_options({ queue_timeout = 1 }, NOTIFY)
      config.without_removed_options({ queue_timeout = 2 }, NOTIFY)
      assert.are.equal(1, #warnings())
    end)

    it("keeps diff_opts = 'x' failing in validation", function()
      assert.has.errors(function()
        config.apply((config.without_removed_options({ diff_opts = "x" }, NOTIFY)))
      end)
    end)

    it("supports a row with value and replace_with", function()
      table.insert(config.removed_options, {
        path = { "terminal", "legacy" },
        value = "old",
        replace_with = "native",
        message = "[Claudinho] old legacy",
      })
      local result = config.without_removed_options({ terminal = { legacy = "old" } }, NOTIFY)
      assert.are.equal("native", result.terminal.legacy)
      local other = config.without_removed_options({ terminal = { legacy = "other" } }, NOTIFY)
      assert.are.equal("other", other.terminal.legacy)
      assert.are.equal(1, #warnings())
    end)
  end)

  describe("notify and the found rows", function()
    it("warns nothing without notify = true, and drops the keys all the same", function()
      for _, opts in ipairs({ {}, { notify = false }, { notify = "yes" } }) do
        local result = config.without_removed_options({ queue_timeout = 1, terminal = { split_side = "left" } }, opts)
        assert.is_nil(result.queue_timeout)
        assert.is_nil(result.terminal.split_side)
      end
      local result = config.without_removed_options({ queue_timeout = 1 })
      assert.is_nil(result.queue_timeout)
      assert.are.same({}, warnings())
    end)

    it("returns the rows of the keys it found, in table order", function()
      local _, found =
        config.without_removed_options({ cwd = "/tmp", terminal = { split_side = "left" }, auto_start = false })
      assert.are.same(
        { { "terminal", "split_side" }, { "auto_start" }, { "cwd" } },
        { found[1].path, found[2].path, found[3].path }
      )
      assert.are.equal(removed("terminal.split_side", "Use window.layout instead."), found[1].message)
    end)

    it("returns no rows for a config without removed keys or a config that is not a table", function()
      local _, found = config.without_removed_options({ log_level = "debug" }, NOTIFY)
      assert.are.same({}, found)
      local _, none = config.without_removed_options(nil, NOTIFY)
      assert.are.same({}, none)
    end)

    it("warns once per key and per session, also for the directory keys", function()
      config.without_removed_options({ cwd = "/a", git_repo_cwd = true }, NOTIFY)
      config.without_removed_options({ cwd = "/b", git_repo_cwd = false }, NOTIFY)
      assert.are.equal(2, #warnings())
    end)
  end)

  describe("terminal keys", function()
    local snacks_opts_message = "[Claudinho] terminal.snacks_win_opts was removed and is ignored."

    it("warns once with the exact text and drops terminal.snacks_win_opts", function()
      local result = config.without_removed_options({ terminal = { snacks_win_opts = { position = "float" } } }, NOTIFY)
      assert.are.same({ snacks_opts_message }, warnings())
      assert.are.equal(vim.log.levels.WARN, notifications[1].level)
      assert.is_nil(result.terminal.snacks_win_opts)
    end)

    it("gives terminal.provider = 'snacks' the one new warning and no swap to 'native'", function()
      local result = config.without_removed_options({ terminal = { provider = "snacks" } }, NOTIFY)
      assert.are.same(
        { removed("terminal.provider", "Claude always runs in Neovim's terminal, in the window set by window.layout.") },
        warnings()
      )
      assert.is_nil(result.terminal.provider)
    end)

    it("does not change the argument", function()
      local input = { terminal = { provider = "snacks", snacks_win_opts = {} } }
      local before = vim.deepcopy(input)
      config.without_removed_options(input, NOTIFY)
      assert.are.same(before, input)
    end)

    it("counts every value of terminal.provider as removed", function()
      for _, provider in ipairs({ "auto", "native", "external", "none", "snacks" }) do
        local result, found = config.without_removed_options({ terminal = { provider = provider } }, NOTIFY)
        assert.is_nil(result.terminal.provider, provider)
        assert.are.equal(1, #found, provider)
      end
    end)

    it("does not fail on a snacks_win_opts of the wrong type", function()
      assert.has_no.errors(function()
        config.without_removed_options({ terminal = { snacks_win_opts = "x" } }, NOTIFY)
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
        notify = true,
        auto_start = false,
        queue_timeout = 5000,
        diff_opts = { vertical_split = true },
        terminal = { split_side = "left", auto_insert = false },
      }
      assert.has_no.errors(function()
        claudinho.setup(input)
      end)

      assert.are.equal(4, #warnings())
      assert.is_nil(terminal_setup_args[1].split_side)
      assert.is_false(terminal_setup_args[1].auto_insert)
      assert.is_nil(claudinho.state.config.queue_timeout)
      assert.is_nil(claudinho.state.config.auto_start)
      assert.is_nil(claudinho.state.config.diff_opts.vertical_split)
      assert.are.equal(5000, input.queue_timeout)
      assert.is_true(input.diff_opts.vertical_split)
      assert.are.equal("left", input.terminal.split_side)
    end)

    it("warns only with notify = true, and keeps the found rows for the health check either way", function()
      local claudinho = require("claudinho")
      claudinho.setup({ terminal = { provider = "snacks" }, cwd = "/tmp" })
      assert.are.same({}, warnings())
      assert.are.equal(2, #claudinho.state.removed_found)

      claudinho.setup({ notify = true, terminal = { provider = "snacks" }, cwd = "/tmp" })
      assert.are.equal(2, #warnings())
      assert.are.equal(2, #claudinho.state.removed_found)
    end)

    it("reads notify raw: a notify that is not true shows no warning", function()
      require("claudinho").setup({ notify = "yes", cwd = "/tmp" })
      assert.are.same({}, warnings())
    end)

    it("hands terminal.setup a terminal table without the removed keys", function()
      local claudinho = require("claudinho")
      assert.has_no.errors(function()
        claudinho.setup({
          notify = true,
          terminal = { provider = "snacks", snacks_win_opts = { position = "float" }, split_side = "left" },
        })
      end)
      assert.are.equal(3, #warnings())
      assert.is_nil(terminal_setup_args[1].provider)
      assert.is_nil(terminal_setup_args[1].snacks_win_opts)
      assert.is_nil(terminal_setup_args[1].split_side)
    end)

    it("does not warn for a config without removed keys", function()
      require("claudinho").setup({ notify = true })
      assert.are.same({}, warnings())
    end)

    it("keeps failing on diff_opts = 'x'", function()
      assert.has.errors(function()
        require("claudinho").setup({ diff_opts = "x" })
      end)
    end)
  end)
end)
