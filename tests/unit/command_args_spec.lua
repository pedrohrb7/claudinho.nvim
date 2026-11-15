require("tests.busted_setup")
require("tests.mocks.vim")

describe("ClaudeCode command arguments with a mock vim", function()
  local claudinho
  local mock_server
  local mock_lockfile
  local mock_selection
  local executed_commands
  local original_require

  before_each(function()
    executed_commands = {}
    local terminal_jobs = {}

    -- Mock vim.fn.termopen to capture actual commands and properly simulate terminal lifecycle
    vim.fn.termopen = function(cmd, opts)
      local job_id = 123 + #terminal_jobs
      table.insert(executed_commands, {
        cmd = cmd,
        opts = opts,
      })

      -- Store the job for cleanup
      table.insert(terminal_jobs, {
        id = job_id,
        on_exit = opts and opts.on_exit,
      })

      -- In headless test mode, immediately schedule the terminal exit
      -- This simulates the terminal closing right away to prevent hanging
      if opts and opts.on_exit then
        vim.schedule(function()
          opts.on_exit(job_id, 0, "exit")
        end)
      end

      return job_id
    end

    vim.fn.mode = function()
      return "n"
    end

    vim.o = {
      columns = 120,
      lines = 30,
    }

    vim.api.nvim_feedkeys = function() end
    vim.api.nvim_replace_termcodes = function(str)
      return str
    end
    local create_user_command_calls = {}
    vim.api.nvim_create_user_command = setmetatable({
      calls = create_user_command_calls,
    }, {
      __call = function(self, ...)
        table.insert(create_user_command_calls, { vals = { ... } })
      end,
    })
    vim.api.nvim_create_autocmd = function() end
    vim.api.nvim_create_augroup = function()
      return 1
    end
    vim.api.nvim_get_current_win = function()
      return 1
    end
    vim.api.nvim_set_current_win = function() end
    vim.api.nvim_win_set_height = function() end
    vim.api.nvim_win_call = function(winid, func)
      func()
    end
    vim.api.nvim_get_current_buf = function()
      return 1
    end
    vim.api.nvim_win_close = function() end
    -- Buffers left by earlier tests stay invalid, so the provider never adopts a stale terminal.
    local stale_bufs = {}
    for bufnr in pairs(vim._buffers) do
      stale_bufs[bufnr] = true
    end
    vim.api.nvim_buf_is_valid = function(bufnr)
      return vim._buffers[bufnr] ~= nil and not stale_bufs[bufnr]
    end
    vim.api.nvim_win_is_valid = function()
      return true
    end
    vim.api.nvim_list_wins = function()
      return { 1 }
    end
    vim.api.nvim_win_get_buf = function()
      return 1
    end
    vim.api.nvim_list_bufs = function()
      return { 1 }
    end
    vim.api.nvim_buf_get_option = function()
      return "terminal"
    end
    vim.api.nvim_buf_get_name = function()
      return "terminal://claude"
    end
    vim.cmd = function() end
    vim.bo = setmetatable({}, {
      __index = function()
        return {}
      end,
      __newindex = function() end,
    })
    vim.schedule = function(func)
      func()
    end

    -- Mock vim.notify to prevent terminal notifications in headless mode
    vim.notify = function() end

    mock_server = {
      start = function()
        return true, 12345
      end,
      stop = function()
        return true
      end,
      state = { port = 12345 },
    }

    mock_lockfile = {
      create = function()
        return true, "/mock/path"
      end,
      remove = function()
        return true
      end,
    }

    mock_selection = {
      enable = function() end,
      disable = function() end,
    }

    original_require = _G.require
    _G.require = function(mod)
      if mod == "claudinho.server.init" then
        return mock_server
      elseif mod == "claudinho.lockfile" then
        return mock_lockfile
      elseif mod == "claudinho.selection" then
        return mock_selection
      elseif mod == "claudinho.config" then
        return {
          without_removed_options = function(opts)
            return opts
          end,
          apply = function(opts)
            return vim.tbl_deep_extend("force", {
              port_range = { min = 10000, max = 65535 },
              auto_start = false,
              terminal_cmd = nil,
              log_level = "info",
              track_selection = true,
              visual_demotion_delay_ms = 50,
              diff_opts = {
                layout = "vertical",
                open_in_new_tab = true,
                keep_terminal_focus = false,
              },
            }, opts or {})
          end,
        }
      elseif mod == "claudinho.diff" then
        return {
          setup = function() end,
        }
      elseif mod == "claudinho.logger" then
        return {
          setup = function() end,
          debug = function() end,
          error = function() end,
          warn = function() end,
        }
      else
        return original_require(mod)
      end
    end

    -- Clear package cache to ensure fresh requires
    package.loaded["claudinho"] = nil
    package.loaded["claudinho.terminal"] = nil
    package.loaded["claudinho.terminal.native"] = nil
    claudinho = require("claudinho")
  end)

  after_each(function()
    -- CRITICAL: Add explicit cleanup to prevent hanging
    if claudinho and claudinho.state and claudinho.state.server then
      -- Clean up global deferred responses that prevent garbage collection
      if _G.claude_deferred_responses then
        _G.claude_deferred_responses = {}
      end

      -- Stop the server and selection tracking explicitly
      local selection_ok, selection = pcall(require, "claudinho.selection")
      if selection_ok and selection.disable then
        selection.disable()
      end

      if claudinho.stop then
        claudinho.stop()
      end
    end

    _G.require = original_require
    package.loaded["claudinho"] = nil
    package.loaded["claudinho.terminal"] = nil
    package.loaded["claudinho.terminal.native"] = nil
  end)

  describe("with native terminal provider", function()
    it("should execute terminal command with appended arguments", function()
      claudinho.setup({
        auto_start = false,
        terminal_cmd = "test_claude_cmd",
        terminal = { provider = "native" },
      })

      -- Find and execute the ClaudeCode command
      local command_handler
      for _, call in ipairs(vim.api.nvim_create_user_command.calls) do
        if call.vals[1] == "ClaudeCode" then
          command_handler = call.vals[2]
          break
        end
      end

      assert.is_function(command_handler, "ClaudeCode command handler should exist")

      command_handler({ args = "--resume --verbose" })

      -- Verify the command was called with arguments
      assert.is_true(#executed_commands > 0, "No terminal commands were executed")
      local last_cmd = executed_commands[#executed_commands]

      -- For native terminal, cmd should be a table
      if type(last_cmd.cmd) == "table" then
        local cmd_string = table.concat(last_cmd.cmd, " ")
        assert.is_true(cmd_string:find("test_claude_cmd") ~= nil, "Base command not found in: " .. cmd_string)
        assert.is_true(cmd_string:find("--resume") ~= nil, "Arguments not found in: " .. cmd_string)
        assert.is_true(cmd_string:find("--verbose") ~= nil, "Arguments not found in: " .. cmd_string)
      else
        assert.is_true(last_cmd.cmd:find("test_claude_cmd") ~= nil, "Base command not found")
        assert.is_true(last_cmd.cmd:find("--resume") ~= nil, "Arguments not found")
        assert.is_true(last_cmd.cmd:find("--verbose") ~= nil, "Arguments not found")
      end
    end)

    it("should work with default claude command and arguments", function()
      claudinho.setup({
        auto_start = false,
        terminal = { provider = "native" },
      })

      local command_handler
      for _, call in ipairs(vim.api.nvim_create_user_command.calls) do
        if call.vals[1] == "ClaudeCodeOpen" then
          command_handler = call.vals[2]
          break
        end
      end

      command_handler({ args = "--help" })

      assert.is_true(#executed_commands > 0, "No terminal commands were executed")
      local last_cmd = executed_commands[#executed_commands]

      local cmd_string = type(last_cmd.cmd) == "table" and table.concat(last_cmd.cmd, " ") or last_cmd.cmd
      assert.is_true(cmd_string:find("claude") ~= nil, "Default claude command not found")
      assert.is_true(cmd_string:find("--help") ~= nil, "Arguments not found")
    end)

    it("should handle empty arguments gracefully", function()
      claudinho.setup({
        auto_start = false,
        terminal_cmd = "claude",
        terminal = { provider = "native" },
      })

      local command_handler
      for _, call in ipairs(vim.api.nvim_create_user_command.calls) do
        if call.vals[1] == "ClaudeCode" then
          command_handler = call.vals[2]
          break
        end
      end

      command_handler({ args = "" })

      assert.is_true(#executed_commands > 0, "No terminal commands were executed")
      local last_cmd = executed_commands[#executed_commands]

      local cmd_string = type(last_cmd.cmd) == "table" and table.concat(last_cmd.cmd, " ") or last_cmd.cmd
      assert.is_true(
        cmd_string == "claude" or cmd_string:find("^claude$") ~= nil,
        "Command should be just 'claude' without extra arguments"
      )
    end)
  end)

  describe("edge cases", function()
    it("should handle special characters in arguments", function()
      claudinho.setup({
        auto_start = false,
        terminal_cmd = "claude",
        terminal = { provider = "native" },
      })

      local command_handler
      for _, call in ipairs(vim.api.nvim_create_user_command.calls) do
        if call.vals[1] == "ClaudeCode" then
          command_handler = call.vals[2]
          break
        end
      end

      command_handler({ args = "--message='hello world' --path=/tmp/test" })

      assert.is_true(#executed_commands > 0, "No terminal commands were executed")
      local last_cmd = executed_commands[#executed_commands]

      -- The native provider parses the command into an argv table via
      -- utils.shell_split, so a quoted argument with a space survives as a single
      -- entry (surrounding quotes are consumed, like a real shell) instead of
      -- being mangled into "--message='hello" and "world'".
      assert.is_table(last_cmd.cmd, "Native provider should pass an argv table")
      local has_message, has_path = false, false
      for _, arg in ipairs(last_cmd.cmd) do
        if arg == "--message=hello world" then
          has_message = true
        elseif arg == "--path=/tmp/test" then
          has_path = true
        end
      end
      assert.is_true(has_message, "Quoted argument with space should be a single argv entry")
      assert.is_true(has_path, "Path argument not preserved")
    end)

    it("should handle very long argument strings", function()
      claudinho.setup({
        auto_start = false,
        terminal_cmd = "claude",
        terminal = { provider = "native" },
      })

      local long_args = string.rep("--flag ", 50) .. "--final"

      local command_handler
      for _, call in ipairs(vim.api.nvim_create_user_command.calls) do
        if call.vals[1] == "ClaudeCode" then
          command_handler = call.vals[2]
          break
        end
      end

      command_handler({ args = long_args })

      assert.is_true(#executed_commands > 0, "No terminal commands were executed")
      local last_cmd = executed_commands[#executed_commands]

      local cmd_string = type(last_cmd.cmd) == "table" and table.concat(last_cmd.cmd, " ") or last_cmd.cmd
      assert.is_true(cmd_string:find("--final") ~= nil, "Long arguments not preserved")
    end)
  end)

  describe("backward compatibility", function()
    it("should not break existing calls without arguments", function()
      claudinho.setup({
        auto_start = false,
        terminal_cmd = "claude",
        terminal = { provider = "native" },
      })

      local command_handler
      for _, call in ipairs(vim.api.nvim_create_user_command.calls) do
        if call.vals[1] == "ClaudeCode" then
          command_handler = call.vals[2]
          break
        end
      end

      command_handler({})

      assert.is_true(#executed_commands > 0, "No terminal commands were executed")
      local last_cmd = executed_commands[#executed_commands]

      local cmd_string = type(last_cmd.cmd) == "table" and table.concat(last_cmd.cmd, " ") or last_cmd.cmd
      assert.is_true(cmd_string == "claude" or cmd_string:find("^claude$") ~= nil, "Should work exactly as before")
    end)

    it("should maintain existing ClaudeCodeClose command functionality", function()
      claudinho.setup({ auto_start = false })

      local close_command_found = false
      for _, call in ipairs(vim.api.nvim_create_user_command.calls) do
        if call.vals[1] == "ClaudeCodeClose" then
          close_command_found = true
          local config = call.vals[3]
          assert.is_nil(config.nargs, "ClaudeCodeClose should not accept arguments")
          break
        end
      end

      assert.is_true(close_command_found, "ClaudeCodeClose command should still be registered")
    end)

    it("should pass cwd in termopen opts when terminal.cwd is set", function()
      claudinho.setup({
        auto_start = false,
        terminal = { provider = "native", cwd = "/mock/repo" },
      })

      local handler
      for _, call in ipairs(vim.api.nvim_create_user_command.calls) do
        if call.vals[1] == "ClaudeCode" then
          handler = call.vals[2]
          break
        end
      end
      assert.is_function(handler)

      handler({})
      assert.is_true(#executed_commands > 0, "No terminal commands were executed")
      local last = executed_commands[#executed_commands]
      assert.is_table(last.opts, "termopen options missing")
      assert.are.equal("/mock/repo", last.opts.cwd)
    end)

    it("should support cwd_provider function for working directory", function()
      claudinho.setup({
        auto_start = false,
        terminal = {
          provider = "native",
          cwd_provider = function(ctx)
            return "/from/provider"
          end,
        },
      })

      local handler
      for _, call in ipairs(vim.api.nvim_create_user_command.calls) do
        if call.vals[1] == "ClaudeCode" then
          handler = call.vals[2]
          break
        end
      end
      assert.is_function(handler)

      handler({})
      assert.is_true(#executed_commands > 0, "No terminal commands were executed")
      local last = executed_commands[#executed_commands]
      assert.is_table(last.opts, "termopen options missing")
      assert.are.equal("/from/provider", last.opts.cwd)
    end)
  end)
end)
