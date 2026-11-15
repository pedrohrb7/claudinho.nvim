require("tests.busted_setup")
require("tests.mocks.vim")

describe("focus_after_send behavior", function()
  local saved_require
  local claudinho

  local mock_terminal
  local mock_logger
  local mock_server_facade

  local function setup_mocks(focus_after_send)
    mock_terminal = {
      setup = function() end,
      open = spy.new(function() end),
      ensure_visible = spy.new(function() end),
    }

    mock_logger = {
      setup = function() end,
      debug = function() end,
      info = function() end,
      warn = function() end,
      error = function() end,
    }

    mock_server_facade = {
      broadcast = spy.new(function()
        return true
      end),
    }

    local mock_config = {
      without_removed_options = function(o)
        return o
      end,
      apply = function()
        -- Return only fields used in this test path
        return {
          auto_start = false,
          terminal_cmd = nil,
          env = {},
          log_level = "info",
          track_selection = false,
          focus_after_send = focus_after_send,
          diff_opts = {
            layout = "vertical",
            open_in_new_tab = false,
            keep_terminal_focus = false,
            on_new_file_reject = "keep_empty",
          },
          models = { { name = "Claude Sonnet 4 (Latest)", value = "sonnet" } },
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
  end

  local function teardown_mocks()
    _G.require = saved_require
    package.loaded["claudinho"] = nil
    package.loaded["claudinho.config"] = nil
    package.loaded["claudinho.logger"] = nil
    package.loaded["claudinho.diff"] = nil
    package.loaded["claudinho.terminal"] = nil
    package.loaded["claudinho.server.init"] = nil
  end

  after_each(function()
    teardown_mocks()
  end)

  it("focuses terminal with open() when enabled", function()
    setup_mocks(true)

    claudinho = require("claudinho")
    claudinho.setup({})

    -- Mark server as present and stub low-level broadcast to succeed
    claudinho.state.server = mock_server_facade
    claudinho._broadcast_at_mention = spy.new(function()
      return true, nil
    end)

    -- Act
    local ok, err = claudinho.send_at_mention("/tmp/file.lua", nil, nil, "test")
    assert.is_true(ok)
    assert.is_nil(err)

    -- Assert focus behavior
    assert.spy(mock_terminal.open).was_called()
    assert.spy(mock_terminal.ensure_visible).was_not_called()
  end)

  it("only ensures visibility when disabled (default)", function()
    setup_mocks(false)

    claudinho = require("claudinho")
    claudinho.setup({})

    claudinho.state.server = mock_server_facade
    claudinho._broadcast_at_mention = spy.new(function()
      return true, nil
    end)

    local ok, err = claudinho.send_at_mention("/tmp/file.lua", nil, nil, "test")
    assert.is_true(ok)
    assert.is_nil(err)

    assert.spy(mock_terminal.ensure_visible).was_called()
    assert.spy(mock_terminal.open).was_not_called()
  end)
end)
