-- luacheck: globals expect
require("tests.busted_setup")

describe("Configuration", function()
  local config

  local function setup()
    package.loaded["claudinho.config"] = nil
    package.loaded["claudinho.terminal"] = nil

    config = require("claudinho.config")
  end

  local function teardown()
    -- Nothing to clean up for now
  end

  setup()

  it("should have default configuration", function()
    expect(config.defaults).to_be_table()
    expect(config.defaults).to_have_key("port_range")
    expect(config.defaults).to_have_key("auto_start")
    expect(config.defaults).to_have_key("log_level")
    expect(config.defaults).to_have_key("track_selection")
    expect(config.defaults).to_have_key("models")
    expect(config.defaults).to_have_key("diff_opts")
    expect(config.defaults.diff_opts).to_have_key("keep_terminal_focus")
    expect(config.defaults.diff_opts.keep_terminal_focus).to_be_false()
  end)

  it("should apply and validate user configuration", function()
    local user_config = {
      terminal_cmd = "toggleterm",
      log_level = "debug",
      track_selection = false,
      models = {
        { name = "Test Model", value = "test-model" },
      },
    }

    local final_config = config.apply(user_config)
    expect(final_config).to_be_table()
    expect(final_config.terminal_cmd).to_be("toggleterm")
    expect(final_config.log_level).to_be("debug")
    expect(final_config.track_selection).to_be_false()
    expect(final_config.env).to_be_table() -- Should inherit default empty table
  end)

  it("should not load terminal module while applying configuration", function()
    package.loaded["claudinho.terminal"] = nil

    local final_config = config.apply({ auto_start = false, log_level = "info" })

    expect(final_config.terminal).to_be_table()
    expect(final_config.terminal.provider).to_be("auto")
    expect(package.loaded["claudinho.terminal"]).to_be_nil()
  end)

  it("should reject invalid port range", function()
    local invalid_config = {
      port_range = { min = -1, max = 65536 },
      auto_start = true,
      log_level = "debug",
      track_selection = false,
    }

    local success, _ = pcall(function() -- Use _ for unused error variable
      config.validate(invalid_config)
    end)

    expect(success).to_be_false()
  end)

  it("should reject invalid log level", function()
    local invalid_config = {
      port_range = { min = 10000, max = 65535 },
      auto_start = true,
      log_level = "invalid_level",
      track_selection = false,
    }

    local success, _ = pcall(function() -- Use _ for unused error variable
      config.validate(invalid_config)
    end)

    expect(success).to_be_false()
  end)

  it("should reject invalid models configuration", function()
    local invalid_config = {
      port_range = { min = 10000, max = 65535 },
      auto_start = true,
      log_level = "debug",
      track_selection = false,
      visual_demotion_delay_ms = 50,
      diff_opts = {
        layout = "vertical",
        open_in_new_tab = false,
        keep_terminal_focus = false,
      },
      models = {}, -- Empty models array should be rejected
    }

    local success, _ = pcall(function()
      config.validate(invalid_config)
    end)

    expect(success).to_be_false()
  end)

  it("should reject models with invalid structure", function()
    local invalid_config = {
      port_range = { min = 10000, max = 65535 },
      auto_start = true,
      log_level = "debug",
      track_selection = false,
      visual_demotion_delay_ms = 50,
      diff_opts = {
        layout = "vertical",
        open_in_new_tab = false,
        keep_terminal_focus = false,
      },
      models = {
        { name = "Test Model" }, -- Missing value field
      },
    }

    local success, _ = pcall(function()
      config.validate(invalid_config)
    end)

    expect(success).to_be_false()
  end)

  it("should merge user config with defaults", function()
    local user_config = {
      auto_start = true,
      log_level = "debug",
    }

    local merged_config = config.apply(user_config)

    expect(merged_config.auto_start).to_be_true()
    expect(merged_config.log_level).to_be("debug")
    expect(merged_config.port_range.min).to_be(config.defaults.port_range.min)
    expect(merged_config.track_selection).to_be(config.defaults.track_selection)
    expect(merged_config.models).to_be_table()
  end)

  it("should accept valid keep_terminal_focus configuration", function()
    local user_config = {
      port_range = { min = 10000, max = 65535 },
      auto_start = true,
      log_level = "info",
      track_selection = true,
      visual_demotion_delay_ms = 50,
      connection_wait_delay = 200,
      connection_timeout = 10000,
      diff_opts = {
        layout = "vertical",
        open_in_new_tab = false,
        keep_terminal_focus = true,
      },
      env = {},
      models = {
        { name = "Test Model", value = "test" },
      },
    }

    local final_config = config.apply(user_config)
    expect(final_config.diff_opts.keep_terminal_focus).to_be_true()
  end)

  it("should reject invalid keep_terminal_focus configuration", function()
    local invalid_config = {
      port_range = { min = 10000, max = 65535 },
      auto_start = true,
      log_level = "info",
      track_selection = true,
      visual_demotion_delay_ms = 50,
      connection_wait_delay = 200,
      connection_timeout = 10000,
      diff_opts = {
        layout = "vertical",
        open_in_new_tab = false,
        keep_terminal_focus = "invalid", -- Should be boolean
      },
      env = {},
      models = {
        { name = "Test Model", value = "test" },
      },
    }

    local success, _ = pcall(function()
      config.validate(invalid_config)
    end)

    expect(success).to_be_false()
  end)

  it("should accept valid auto_resize_terminal configuration", function()
    local user_config = {
      port_range = { min = 10000, max = 65535 },
      auto_start = true,
      log_level = "info",
      track_selection = true,
      visual_demotion_delay_ms = 50,
      connection_wait_delay = 200,
      connection_timeout = 10000,
      diff_opts = {
        layout = "vertical",
        open_in_new_tab = false,
        keep_terminal_focus = false,
        auto_resize_terminal = false,
      },
      env = {},
      models = {
        { name = "Test Model", value = "test" },
      },
    }

    local final_config = config.apply(user_config)
    expect(final_config.diff_opts.auto_resize_terminal).to_be_false()
  end)

  it("should default auto_resize_terminal to true", function()
    local final_config = config.apply({ auto_start = true, log_level = "info" })
    expect(final_config.diff_opts.auto_resize_terminal).to_be_true()
  end)

  it("should reject invalid auto_resize_terminal configuration", function()
    local invalid_config = {
      port_range = { min = 10000, max = 65535 },
      auto_start = true,
      log_level = "info",
      track_selection = true,
      visual_demotion_delay_ms = 50,
      connection_wait_delay = 200,
      connection_timeout = 10000,
      diff_opts = {
        layout = "vertical",
        open_in_new_tab = false,
        keep_terminal_focus = false,
        auto_resize_terminal = "yes", -- Should be boolean
      },
      env = {},
      models = {
        { name = "Test Model", value = "test" },
      },
    }

    local success, _ = pcall(function()
      config.validate(invalid_config)
    end)

    expect(success).to_be_false()
  end)

  it("should accept function for external_terminal_cmd", function()
    local valid_config = {
      port_range = { min = 10000, max = 65535 },
      auto_start = true,
      log_level = "info",
      track_selection = true,
      visual_demotion_delay_ms = 50,
      connection_wait_delay = 200,
      connection_timeout = 10000,
      diff_opts = {
        layout = "vertical",
      },
      env = {},
      models = {
        { name = "Test Model", value = "test" },
      },
      terminal = {
        provider = "external",
        provider_opts = {
          external_terminal_cmd = function(cmd, env)
            return "terminal " .. cmd
          end,
        },
      },
    }

    local success, _ = pcall(function()
      config.validate(valid_config)
    end)

    expect(success).to_be_true()
  end)

  it("should accept string for external_terminal_cmd", function()
    local valid_config = {
      port_range = { min = 10000, max = 65535 },
      auto_start = true,
      log_level = "info",
      track_selection = true,
      visual_demotion_delay_ms = 50,
      connection_wait_delay = 200,
      connection_timeout = 10000,
      diff_opts = {
        layout = "vertical",
      },
      env = {},
      models = {
        { name = "Test Model", value = "test" },
      },
      terminal = {
        provider = "external",
        provider_opts = {
          external_terminal_cmd = "alacritty -e %s",
        },
      },
    }

    local success, _ = pcall(function()
      config.validate(valid_config)
    end)

    expect(success).to_be_true()
  end)

  it("should reject invalid type for external_terminal_cmd", function()
    local invalid_config = {
      port_range = { min = 10000, max = 65535 },
      auto_start = true,
      log_level = "info",
      track_selection = true,
      visual_demotion_delay_ms = 50,
      connection_wait_delay = 200,
      connection_timeout = 10000,
      diff_opts = {
        layout = "vertical",
      },
      env = {},
      models = {
        { name = "Test Model", value = "test" },
      },
      terminal = {
        provider = "external",
        provider_opts = {
          external_terminal_cmd = 123, -- Invalid: number
        },
      },
    }

    local success, err = pcall(function()
      config.validate(invalid_config)
    end)

    expect(success).to_be_false()
    expect(tostring(err)).to_match("must be a string or function")
  end)

  describe("new keys (window, keymaps, notify)", function()
    local original_notify
    local notes

    before_each(function()
      original_notify = vim.notify
      notes = {}
      vim.notify = function(msg, level, opts)
        table.insert(notes, { msg = msg, level = level, opts = opts })
      end
    end)

    after_each(function()
      vim.notify = original_notify
    end)

    it("has the defaults and raises no error", function()
      local c = config.apply({})
      expect(c.window.layout).to_be("right")
      expect(c.window.right.width).to_be(0.30)
      expect(c.window.right.diff_width).to_be_nil()
      expect(c.window.bottom.height).to_be(0.30)
      expect(c.window.float.width).to_be(0.80)
      expect(c.window.float.height).to_be(0.80)
      expect(c.window.tab_title_max).to_be(24)
      expect(c.keymaps.preset).to_be_false()
      expect(c.notify).to_be_false()
      expect(#notes).to_be(0)
    end)

    it("keeps valid user values", function()
      local c = config.apply({
        window = { layout = "float", right = { width = 0.5, diff_width = 0.6 }, tab_title_max = 10 },
        keymaps = { preset = true },
        notify = true,
      })
      expect(c.window.layout).to_be("float")
      expect(c.window.right.width).to_be(0.5)
      expect(c.window.right.diff_width).to_be(0.6)
      expect(c.window.bottom.height).to_be(0.30)
      expect(c.window.tab_title_max).to_be(10)
      expect(c.keymaps.preset).to_be_true()
      expect(c.notify).to_be_true()
      expect(#notes).to_be(0)
    end)

    it("falls back to right on an invalid layout, with the exact error", function()
      local c = config.apply({ window = { layout = "sidebar" } })
      expect(c.window.layout).to_be("right")
      expect(#notes).to_be(1)
      expect(notes[1].msg).to_be(
        '[Claudinho] window.layout = "sidebar" is not valid; using "right". Valid layouts: right, bottom, float, tab.'
      )
      expect(notes[1].level).to_be(vim.log.levels.ERROR)
      expect(notes[1].opts.title).to_be("Claudinho")
    end)

    local invalid = {
      {
        user = { window = { right = { width = 1.5 } } },
        msg = "[Claudinho] window.right.width = 1.5 is not valid; using 0.3.",
      },
      {
        user = { window = { right = { width = "wide" } } },
        msg = '[Claudinho] window.right.width = "wide" is not valid; using 0.3.',
      },
      {
        user = { window = { right = { diff_width = 0 } } },
        msg = "[Claudinho] window.right.diff_width = 0 is not valid; using nil.",
      },
      {
        user = { window = { bottom = { height = 1 } } },
        msg = "[Claudinho] window.bottom.height = 1 is not valid; using 0.3.",
      },
      {
        user = { window = { float = { width = -0.1 } } },
        msg = "[Claudinho] window.float.width = -0.1 is not valid; using 0.8.",
      },
      {
        user = { window = { float = { height = true } } },
        msg = "[Claudinho] window.float.height = true is not valid; using 0.8.",
      },
      {
        user = { window = { tab_title_max = 0 } },
        msg = "[Claudinho] window.tab_title_max = 0 is not valid; using 24.",
      },
      {
        user = { window = { tab_title_max = 2.5 } },
        msg = "[Claudinho] window.tab_title_max = 2.5 is not valid; using 24.",
      },
      {
        user = { keymaps = { preset = "yes" } },
        msg = '[Claudinho] keymaps.preset = "yes" is not valid; using false.',
      },
      { user = { notify = 1 }, msg = "[Claudinho] notify = 1 is not valid; using false." },
    }

    for i, case in ipairs(invalid) do
      it("falls back to the default with the exact error: case " .. i, function()
        local c = config.apply(case.user)
        expect(#notes).to_be(1)
        expect(notes[1].msg).to_be(case.msg)
        expect(notes[1].level).to_be(vim.log.levels.ERROR)
        expect(c.notify).to_be_false()
        expect(c.window.right.width).to_be(0.30)
        expect(c.window.bottom.height).to_be(0.30)
        expect(c.window.float.width).to_be(0.80)
        expect(c.window.float.height).to_be(0.80)
        expect(c.window.tab_title_max).to_be(24)
        expect(c.window.right.diff_width).to_be_nil()
        expect(c.keymaps.preset).to_be_false()
      end)
    end

    it("replaces a non-table window and keeps the rest of the config", function()
      local c = config.apply({ window = "x", log_level = "debug" })
      expect(c.window.layout).to_be("right")
      expect(c.log_level).to_be("debug")
      expect(#notes).to_be(1)
    end)
  end)

  teardown()
end)
