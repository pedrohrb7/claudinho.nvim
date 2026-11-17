require("tests.busted_setup")
require("tests.mocks.vim")

describe("Claudinho add command", function()
  local claudinho
  local commands
  local tab
  local active_tab = require("tests.helpers.active_tab")
  local mock_server
  local mock_logger
  local saved_require = _G.require

  local function setup_mocks()
    mock_server = {
      broadcast = spy.new(function()
        return true
      end),
    }

    mock_logger = {
      setup = function() end,
      debug = spy.new(function() end),
      error = spy.new(function() end),
      warn = spy.new(function() end),
    }

    -- Override vim.fn functions for our specific tests
    vim.fn.expand = spy.new(function(path)
      if path == "~/test.lua" then
        return "/home/user/test.lua"
      elseif path == "./relative.lua" then
        return "/current/dir/relative.lua"
      elseif path == "%" or path == "%:p" then
        return "/current/dir/buffer.lua"
      end
      return path
    end)

    vim.fn.filereadable = spy.new(function(path)
      if
        path == "/existing/file.lua"
        or path == "/home/user/test.lua"
        or path == "/current/dir/relative.lua"
        or path == "/current/dir/buffer.lua"
      then
        return 1
      end
      return 0
    end)

    vim.fn.isdirectory = spy.new(function(path)
      if path == "/existing/dir" then
        return 1
      end
      return 0
    end)

    vim.fn.getcwd = function()
      return "/current/dir"
    end

    vim.fn.getbufinfo = function(bufnr)
      return { { windows = { 1 } } }
    end

    vim.api.nvim_create_user_command = spy.new(function() end)
    vim.api.nvim_buf_get_name = function()
      return "test.lua"
    end

    vim.bo = { filetype = "lua" }
    vim.notify = spy.new(function() end)

    _G.require = function(mod)
      if mod == "claudinho.utils" then
        -- Tilde-only expansion mock: expand a leading `~`, otherwise return the
        -- path unchanged. Crucially preserves literal `$` (TanStack `$param` files).
        return {
          expand_tilde = function(path)
            if path == "~/test.lua" then
              return "/home/user/test.lua"
            end
            return path
          end,
        }
      elseif mod == "claudinho.logger" then
        return mock_logger
      elseif mod == "claudinho.config" then
        return {
          without_removed_options = function(o)
            return o
          end,
          apply = function(opts)
            return opts or {}
          end,
        }
      elseif mod == "claudinho.diff" then
        return {
          setup = function() end,
        }
      elseif mod == "claudinho.terminal" then
        return {
          setup = function() end,
          open = spy.new(function() end),
          toggle_open_no_focus = spy.new(function() end),
          ensure_visible = spy.new(function() end),
          get_active_terminal_bufnr = function()
            return 1
          end,
          simple_toggle = spy.new(function() end),
        }
      elseif mod == "claudinho.visual_commands" then
        return {
          create_visual_command_wrapper = function(normal_handler, visual_handler)
            return normal_handler
          end,
        }
      else
        return saved_require(mod)
      end
    end
  end

  before_each(function()
    setup_mocks()

    -- Clear package cache to ensure fresh require
    package.loaded["claudinho"] = nil
    package.loaded["claudinho.commands"] = nil
    package.loaded["claudinho.config"] = nil
    package.loaded["claudinho.logger"] = nil
    package.loaded["claudinho.diff"] = nil
    package.loaded["claudinho.visual_commands"] = nil
    package.loaded["claudinho.terminal"] = nil
    package.loaded["claudinho.utils"] = nil

    claudinho = require("claudinho")
    commands = require("claudinho.commands")

    -- The active tab, whose queue broadcasts to the mock server
    tab = active_tab.install({ server = mock_server })
  end)

  after_each(function()
    active_tab.uninstall(tab)
    _G.require = saved_require
    package.loaded["claudinho"] = nil
    package.loaded["claudinho.commands"] = nil
  end)

  ---The handler of :Claudinho, called as `:Claudinho add <args>`.
  ---The command reads `opts.fargs`; tests pass `{ args = "..." }`, so derive `fargs` by a plain whitespace split. Tests
  ---can also pass `fargs` (the arguments after `add`) directly.
  ---@return function handler
  local function add_handler()
    local raw_handler
    for _, call in ipairs(vim.api.nvim_create_user_command.calls) do
      if call.vals[1] == "Claudinho" then
        raw_handler = call.vals[2]
        break
      end
    end

    assert.is_function(raw_handler, "Command handler should be a function")

    return function(opts)
      local rest = opts.fargs
      if rest == nil and opts.args ~= nil then
        rest = opts.args == "" and {} or vim.split(opts.args, "%s+")
      end
      opts.fargs = { "add", unpack(rest or {}) }
      return raw_handler(opts)
    end
  end

  describe("command registration", function()
    it("should register the Claudinho command during setup, with file completion for add", function()
      commands.setup({})

      local found = false
      for _, call in ipairs(vim.api.nvim_create_user_command.calls) do
        if call.vals[1] == "Claudinho" then
          found = true

          local config = call.vals[3]
          assert.is_equal("*", config.nargs)
          assert.is_function(config.complete)
          assert.is_string(config.desc)
          break
        end
      end

      assert.is_true(found, "Claudinho command was not registered")
    end)

    it("should complete the files of the second word of add", function()
      local real_getcompletion = vim.fn.getcompletion
      finally(function()
        vim.fn.getcompletion = real_getcompletion
      end)
      vim.fn.getcompletion = function(lead, kind)
        assert.is_equal("/ex", lead)
        assert.is_equal("file", kind)
        return { "/existing/file.lua" }
      end

      assert.same({ "/existing/file.lua" }, commands.complete("/ex", "Claudinho add /ex", 17))
    end)
  end)

  describe("command execution", function()
    local command_handler

    before_each(function()
      commands.setup({})
      command_handler = add_handler()
    end)

    describe("validation", function()
      it("should start the first tab and queue the file when there is no tab", function()
        tab.closed = true
        claudinho.state.config = { connection_timeout = 10000, connection_wait_delay = 600 }

        command_handler({ args = "/existing/file.lua" })

        assert.is_equal(1, tab.new_calls)
        assert.is_equal(1, #tab.queue.mentions)
        assert.is_equal("/existing/file.lua", tab.queue.mentions[1].file_path)
        assert.spy(mock_logger.error).was_not_called()
        assert.spy(mock_server.broadcast).was_not_called()
      end)

      it("should send nothing to a tab that has exited and say so", function()
        tab.state = "exited"

        command_handler({ args = "/existing/file.lua" })

        assert.spy(mock_logger.error).was_called()
        assert.is_equal(
          "Claudinho add: Claude 1 has exited; run :Claudinho tab-restart 1",
          mock_logger.error.calls[1].vals[2]
        )
        assert.spy(mock_server.broadcast).was_not_called()
      end)

      it("should error when no file path is provided", function()
        command_handler({ args = "" })

        assert.spy(mock_logger.error).was_called()
      end)

      it("should error when file does not exist", function()
        command_handler({ args = "/nonexistent/file.lua" })

        assert.spy(mock_logger.error).was_called()
      end)
    end)

    describe("path handling", function()
      it("should expand tilde paths", function()
        command_handler({ args = "~/test.lua" })

        assert.spy(mock_server.broadcast).was_called_with("at_mentioned", {
          filePath = "/home/user/test.lua",
          lineStart = nil,
          lineEnd = nil,
        }, match._)
      end)

      it("should handle absolute paths", function()
        command_handler({ args = "/existing/file.lua" })

        assert.spy(mock_server.broadcast).was_called()
      end)

      it("should preserve a literal $ in the path (e.g. TanStack $param files)", function()
        -- Regression for the bug where vim.fn.expand treated `$post` as an
        -- undefined env var and stripped it, breaking :Claudinho add on paths
        -- like src/routes/$post.tsx.
        vim.fn.filereadable = spy.new(function(path)
          return path == "/current/dir/src/routes/$post.tsx" and 1 or 0
        end)

        command_handler({ args = "/current/dir/src/routes/$post.tsx" })

        assert.spy(mock_server.broadcast).was_called_with("at_mentioned", {
          filePath = "/current/dir/src/routes/$post.tsx",
          lineStart = nil,
          lineEnd = nil,
        }, match._)
        assert.spy(mock_logger.error).was_not_called()
      end)

      it("should expand the current-buffer token `%` (the documented 'add current buffer' keymap)", function()
        -- `:Claudinho add %` (README keymap) must resolve `%` to the current
        -- buffer path via vim.fn.expand, NOT be left as the literal "%" -- which
        -- a tilde-only expansion would do, breaking the workflow.
        command_handler({ args = "%" })

        assert.spy(vim.fn.expand).was_called_with("%")
        assert.spy(mock_server.broadcast).was_called()
        assert.spy(mock_logger.error).was_not_called()
      end)
    end)

    describe("broadcasting", function()
      it("should broadcast existing file successfully", function()
        command_handler({ args = "/existing/file.lua" })

        assert.spy(mock_server.broadcast).was_called_with("at_mentioned", {
          filePath = "/existing/file.lua",
          lineStart = nil,
          lineEnd = nil,
        }, match._)
        assert.spy(mock_logger.debug).was_called()
      end)

      it("should broadcast existing directory successfully", function()
        command_handler({ args = "/existing/dir" })

        assert.spy(mock_server.broadcast).was_called_with("at_mentioned", {
          filePath = "/existing/dir/",
          lineStart = nil,
          lineEnd = nil,
        }, match._)
        assert.spy(mock_logger.debug).was_called()
      end)

      it("should handle broadcast failure", function()
        mock_server.broadcast = spy.new(function()
          return false
        end)

        command_handler({ args = "/existing/file.lua" })

        assert.spy(mock_logger.error).was_called()
      end)
    end)

    describe("path formatting", function()
      it("should handle file broadcasting correctly", function()
        -- Set up a file that exists
        vim.fn.filereadable = spy.new(function(path)
          return path == "/current/dir/src/test.lua" and 1 or 0
        end)

        command_handler({ args = "/current/dir/src/test.lua" })

        assert.spy(mock_server.broadcast).was_called_with("at_mentioned", match.is_table(), match._)
        assert.spy(mock_logger.debug).was_called()
      end)

      it("should add trailing slash for directories", function()
        command_handler({ args = "/existing/dir" })

        assert.spy(mock_server.broadcast).was_called_with("at_mentioned", {
          filePath = "/existing/dir/",
          lineStart = nil,
          lineEnd = nil,
        }, match._)
      end)
    end)

    describe("line number conversion", function()
      it("should convert 1-indexed user input to 0-indexed for Claude", function()
        command_handler({ args = "/existing/file.lua 1 3" })

        assert.spy(mock_server.broadcast).was_called_with("at_mentioned", {
          filePath = "/existing/file.lua",
          lineStart = 0,
          lineEnd = 2,
        }, match._)
      end)
    end)

    describe("line range functionality", function()
      describe("argument parsing", function()
        it("should parse single file path correctly", function()
          command_handler({ args = "/existing/file.lua" })

          assert.spy(mock_server.broadcast).was_called_with("at_mentioned", {
            filePath = "/existing/file.lua",
            lineStart = nil,
            lineEnd = nil,
          }, match._)
        end)

        it("should parse file path with start line", function()
          command_handler({ args = "/existing/file.lua 50" })

          assert.spy(mock_server.broadcast).was_called_with("at_mentioned", {
            filePath = "/existing/file.lua",
            lineStart = 49,
            lineEnd = nil,
          }, match._)
        end)

        it("should parse file path with start and end lines", function()
          command_handler({ args = "/existing/file.lua 50 100" })

          assert.spy(mock_server.broadcast).was_called_with("at_mentioned", {
            filePath = "/existing/file.lua",
            lineStart = 49,
            lineEnd = 99,
          }, match._)
        end)

        it("should handle a path containing spaces (Neovim-expanded `%`)", function()
          vim.fn.filereadable = spy.new(function(path)
            return path == "/existing/my file.lua" and 1 or 0
          end)

          command_handler({ args = "/existing/my\\ file.lua", fargs = { "/existing/my file.lua" } })

          assert.spy(mock_server.broadcast).was_called_with("at_mentioned", {
            filePath = "/existing/my file.lua",
            lineStart = nil,
            lineEnd = nil,
          }, match._)
          assert.spy(mock_logger.error).was_not_called()
        end)

        it("should handle a path with spaces plus line numbers", function()
          vim.fn.filereadable = spy.new(function(path)
            return path == "/existing/my file.lua" and 1 or 0
          end)

          command_handler({ args = "/existing/my\\ file.lua 10 20", fargs = { "/existing/my file.lua", "10", "20" } })

          assert.spy(mock_server.broadcast).was_called_with("at_mentioned", {
            filePath = "/existing/my file.lua",
            lineStart = 9,
            lineEnd = 19,
          }, match._)
          assert.spy(mock_logger.error).was_not_called()
        end)
      end)

      describe("line number validation", function()
        it("should error on invalid start line number", function()
          command_handler({ args = "/existing/file.lua abc" })

          assert.spy(mock_logger.error).was_called()
          assert.spy(mock_server.broadcast).was_not_called()
        end)

        it("should error on invalid end line number", function()
          command_handler({ args = "/existing/file.lua 50 xyz" })

          assert.spy(mock_logger.error).was_called()
          assert.spy(mock_server.broadcast).was_not_called()
        end)

        it("should error on negative start line", function()
          command_handler({ args = "/existing/file.lua -5" })

          assert.spy(mock_logger.error).was_called()
          assert.spy(mock_server.broadcast).was_not_called()
        end)

        it("should error on negative end line", function()
          command_handler({ args = "/existing/file.lua 10 -20" })

          assert.spy(mock_logger.error).was_called()
          assert.spy(mock_server.broadcast).was_not_called()
        end)

        it("should error on zero line numbers", function()
          command_handler({ args = "/existing/file.lua 0 10" })

          assert.spy(mock_logger.error).was_called()
          assert.spy(mock_server.broadcast).was_not_called()
        end)

        it("should error when start line > end line", function()
          command_handler({ args = "/existing/file.lua 100 50" })

          assert.spy(mock_logger.error).was_called()
          assert.spy(mock_server.broadcast).was_not_called()
        end)

        it("should error on too many arguments", function()
          command_handler({ args = "/existing/file.lua 10 20 30" })

          assert.spy(mock_logger.error).was_called()
          assert.spy(mock_server.broadcast).was_not_called()
        end)
      end)

      describe("directory handling with line numbers", function()
        it("should ignore line numbers for directories and warn", function()
          command_handler({ args = "/existing/dir 50 100" })

          assert.spy(mock_server.broadcast).was_called_with("at_mentioned", {
            filePath = "/existing/dir/",
            lineStart = nil,
            lineEnd = nil,
          }, match._)
          assert.spy(mock_logger.debug).was_called()
        end)
      end)

      describe("valid line range scenarios", function()
        it("should handle start line equal to end line", function()
          command_handler({ args = "/existing/file.lua 50 50" })

          assert.spy(mock_server.broadcast).was_called_with("at_mentioned", {
            filePath = "/existing/file.lua",
            lineStart = 49,
            lineEnd = 49, -- 50 - 1 (converted to 0-indexed)
          }, match._)
        end)

        it("should handle large line numbers", function()
          command_handler({ args = "/existing/file.lua 1000 2000" })

          assert.spy(mock_server.broadcast).was_called_with("at_mentioned", {
            filePath = "/existing/file.lua",
            lineStart = 999,
            lineEnd = 1999,
          }, match._)
        end)

        it("should handle single line specification", function()
          command_handler({ args = "/existing/file.lua 42" })

          assert.spy(mock_server.broadcast).was_called_with("at_mentioned", {
            filePath = "/existing/file.lua",
            lineStart = 41,
            lineEnd = nil,
          }, match._)
        end)
      end)

      describe("path expansion with line ranges", function()
        it("should expand tilde paths with line numbers", function()
          command_handler({ args = "~/test.lua 10 20" })

          assert.spy(mock_server.broadcast).was_called_with("at_mentioned", {
            filePath = "/home/user/test.lua",
            lineStart = 9,
            lineEnd = 19,
          }, match._)
        end)

        it("should send an in-cwd path as its absolute path with line numbers", function()
          command_handler({ args = "/current/dir/relative.lua 5" })

          assert.spy(mock_server.broadcast).was_called_with("at_mentioned", {
            filePath = "/current/dir/relative.lua",
            lineStart = 4,
            lineEnd = nil,
          }, match._)
        end)
      end)
    end)
  end)

  describe("integration with broadcast functions", function()
    it("should use the extracted broadcast_at_mention function", function()
      -- This test ensures that the command uses the centralized function
      -- rather than duplicating broadcast logic
      commands.setup({})
      local command_handler = add_handler()

      -- Mock the _format_path_for_at_mention function to verify it's called
      local original_format = claudinho._format_path_for_at_mention
      claudinho._format_path_for_at_mention = spy.new(function(path)
        return path, false
      end)

      command_handler({ args = "/existing/file.lua", fargs = { "/existing/file.lua" } })

      assert.spy(claudinho._format_path_for_at_mention).was_called()
      assert.spy(mock_server.broadcast).was_called()

      -- Restore original function
      claudinho._format_path_for_at_mention = original_format
    end)
  end)
end)
