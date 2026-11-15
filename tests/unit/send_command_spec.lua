require("tests.busted_setup")
require("tests.mocks.vim")

describe("ClaudeCodeSend Command Range Functionality", function()
  local claudinho
  local mock_selection_module
  local mock_server
  local mock_terminal
  local command_callback
  local original_require

  before_each(function()
    -- Reset package cache
    package.loaded["claudinho"] = nil
    package.loaded["claudinho.selection"] = nil
    package.loaded["claudinho.terminal"] = nil
    package.loaded["claudinho.server.init"] = nil
    package.loaded["claudinho.lockfile"] = nil
    package.loaded["claudinho.config"] = nil
    package.loaded["claudinho.logger"] = nil
    package.loaded["claudinho.diff"] = nil

    -- Mock vim API
    _G.vim = {
      api = {
        nvim_create_user_command = spy.new(function(name, callback, opts)
          if name == "ClaudeCodeSend" then
            command_callback = callback
          end
        end),
        nvim_create_augroup = spy.new(function()
          return "test_group"
        end),
        nvim_create_autocmd = spy.new(function()
          return 1
        end),
        nvim_feedkeys = spy.new(function() end),
        nvim_replace_termcodes = spy.new(function(str)
          return str
        end),
      },
      notify = spy.new(function() end),
      log = { levels = { ERROR = 1, WARN = 2, INFO = 3 } },
      deepcopy = function(t)
        return t
      end,
      tbl_deep_extend = function(behavior, ...)
        local result = {}
        for _, tbl in ipairs({ ... }) do
          for k, v in pairs(tbl) do
            result[k] = v
          end
        end
        return result
      end,
      fn = {
        mode = spy.new(function()
          return "n"
        end),
      },
    }

    -- Mock selection module
    mock_selection_module = {
      send_at_mention_for_visual_selection = spy.new(function(line1, line2)
        mock_selection_module.last_call = { line1 = line1, line2 = line2 }
        return true
      end),
    }

    -- Mock terminal module
    mock_terminal = {
      open = spy.new(function() end),
      ensure_visible = spy.new(function() end),
    }

    -- Mock server
    mock_server = {
      start = function()
        return true, 12345
      end,
      stop = function()
        return true
      end,
    }

    -- Mock other modules
    local mock_lockfile = {
      create = function()
        return true, "/mock/path"
      end,
      remove = function()
        return true
      end,
    }

    local mock_config = {
      without_removed_options = function(o)
        return o
      end,
      apply = function(opts)
        return {
          auto_start = false,
          track_selection = true,
          visual_demotion_delay_ms = 200,
          log_level = "info",
        }
      end,
    }

    local mock_logger = {
      setup = function() end,
      debug = function() end,
      error = function() end,
      warn = function() end,
    }

    local mock_diff = {
      setup = function() end,
    }

    -- Setup require mocks BEFORE requiring claudinho
    original_require = _G.require
    _G.require = function(module_name)
      if module_name == "claudinho.selection" then
        return mock_selection_module
      elseif module_name == "claudinho.terminal" then
        return mock_terminal
      elseif module_name == "claudinho.server.init" then
        return mock_server
      elseif module_name == "claudinho.lockfile" then
        return mock_lockfile
      elseif module_name == "claudinho.config" then
        return mock_config
      elseif module_name == "claudinho.logger" then
        return mock_logger
      elseif module_name == "claudinho.diff" then
        return mock_diff
      else
        return original_require(module_name)
      end
    end

    -- Load and setup claudinho
    claudinho = require("claudinho")
    claudinho.setup({})

    -- Manually set server state for testing
    claudinho.state.server = mock_server
    claudinho.state.port = 12345
  end)

  after_each(function()
    -- Restore original require
    _G.require = original_require
  end)

  describe("ClaudeCodeSend command", function()
    it("should be registered with range support", function()
      assert.spy(_G.vim.api.nvim_create_user_command).was_called()

      -- Find the ClaudeCodeSend command call
      local calls = _G.vim.api.nvim_create_user_command.calls
      local claudinho_send_call = nil
      for _, call in ipairs(calls) do
        if call.vals[1] == "ClaudeCodeSend" then
          claudinho_send_call = call
          break
        end
      end

      assert(claudinho_send_call ~= nil, "ClaudeCodeSend command should be registered")
      assert(claudinho_send_call.vals[3].range == true, "ClaudeCodeSend should support ranges")
    end)

    it("should pass range information to selection module when range is provided", function()
      assert(command_callback ~= nil, "Command callback should be set")

      -- Simulate command called with range
      local opts = {
        range = 2,
        line1 = 5,
        line2 = 8,
      }

      command_callback(opts)

      assert.spy(mock_selection_module.send_at_mention_for_visual_selection).was_called()
      assert(mock_selection_module.last_call.line1 == 5)
      assert(mock_selection_module.last_call.line2 == 8)
    end)

    it("should not pass range information when range is 0", function()
      assert(command_callback ~= nil, "Command callback should be set")

      -- Simulate command called without range
      local opts = {
        range = 0,
        line1 = 1,
        line2 = 1,
      }

      command_callback(opts)

      assert.spy(mock_selection_module.send_at_mention_for_visual_selection).was_called()
      assert(mock_selection_module.last_call.line1 == nil)
      assert(mock_selection_module.last_call.line2 == nil)
    end)

    it("should not pass range information when range is nil", function()
      assert(command_callback ~= nil, "Command callback should be set")

      -- Simulate command called without range
      local opts = {}

      command_callback(opts)

      assert.spy(mock_selection_module.send_at_mention_for_visual_selection).was_called()
      assert(mock_selection_module.last_call.line1 == nil)
      assert(mock_selection_module.last_call.line2 == nil)
    end)

    it("should exit visual mode on successful send", function()
      assert(command_callback ~= nil, "Command callback should be set")

      local opts = {
        range = 2,
        line1 = 5,
        line2 = 8,
      }

      command_callback(opts)

      assert.spy(_G.vim.api.nvim_feedkeys).was_called()
      -- Terminal should not be automatically opened
      assert.spy(mock_terminal.open).was_not_called()
    end)

    it("should handle server not running", function()
      assert(command_callback ~= nil, "Command callback should be set")

      -- Simulate server not running
      claudinho.state.server = nil

      local opts = {
        range = 2,
        line1 = 5,
        line2 = 8,
      }

      command_callback(opts)

      -- The command should call the selection module, which will handle the error
      assert.spy(mock_selection_module.send_at_mention_for_visual_selection).was_called()
    end)

    it("should handle selection module failure", function()
      assert(command_callback ~= nil, "Command callback should be set")

      -- Mock selection module to return false
      mock_selection_module.send_at_mention_for_visual_selection = spy.new(function()
        return false
      end)

      local opts = {
        range = 2,
        line1 = 5,
        line2 = 8,
      }

      command_callback(opts)

      assert.spy(mock_selection_module.send_at_mention_for_visual_selection).was_called()
      -- Should not exit visual mode or focus terminal on failure
      assert.spy(_G.vim.api.nvim_feedkeys).was_not_called()
      assert.spy(mock_terminal.open).was_not_called()
    end)
  end)
end)
