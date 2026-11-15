-- luacheck: globals expect
require("tests.busted_setup")
require("tests.mocks.vim")

describe("claudinho.conflict", function()
  local conflict
  local saved
  local notifications
  local calls

  before_each(function()
    saved = {
      g = vim.g,
      notify = vim.notify,
      notified_once = vim._notified_once,
      api = {
        nvim_get_runtime_file = vim.api.nvim_get_runtime_file,
        nvim_create_user_command = vim.api.nvim_create_user_command,
        nvim_create_autocmd = vim.api.nvim_create_autocmd,
        nvim_create_augroup = vim.api.nvim_create_augroup,
      },
      loaded = {
        claudinho = package.loaded["claudinho"],
        conflict = package.loaded["claudinho.conflict"],
        config = package.loaded["claudinho.config"],
        terminal = package.loaded["claudinho.terminal"],
        server = package.loaded["claudinho.server.init"],
      },
    }
    vim.g = {}
    vim._notified_once = nil
    notifications = {}
    calls = {}
    vim.notify = function(msg, level)
      table.insert(notifications, { msg = msg, level = level })
    end
    package.loaded["claudinho.conflict"] = nil
    conflict = require("claudinho.conflict")
  end)

  after_each(function()
    vim.g = saved.g
    vim.notify = saved.notify
    vim._notified_once = saved.notified_once
    vim.api.nvim_get_runtime_file = saved.api.nvim_get_runtime_file
    for name, fn in pairs(saved.api) do
      vim.api[name] = fn
    end
    package.loaded["claudinho"] = saved.loaded.claudinho
    package.loaded["claudinho.conflict"] = saved.loaded.conflict
    package.loaded["claudinho.config"] = saved.loaded.config
    package.loaded["claudinho.terminal"] = saved.loaded.terminal
    package.loaded["claudinho.server.init"] = saved.loaded.server
  end)

  it("reports no conflict without loaded_claudecode", function()
    expect(conflict.check()).to_be_false()
    expect(#notifications).to_be(0)
  end)

  it("reports a conflict and warns once with loaded_claudecode", function()
    vim.g.loaded_claudecode = 1

    expect(conflict.check()).to_be_true()
    expect(conflict.check()).to_be_true()

    expect(#notifications).to_be(1)
    expect(notifications[1].msg).to_be(conflict.MESSAGE)
    expect(notifications[1].level).to_be(vim.log.levels.WARN)
  end)

  it("reports a conflict and warns once when claudecode.nvim is on the runtimepath", function()
    vim.api.nvim_get_runtime_file = function(name, all)
      expect(name).to_be("lua/claudecode/init.lua")
      expect(all).to_be_false()
      return { "/pack/claudecode.nvim/lua/claudecode/init.lua" }
    end

    expect(conflict.detected()).to_be_true()
    expect(#notifications).to_be(0)
    expect(conflict.check()).to_be_true()
    expect(conflict.check()).to_be_true()

    expect(#notifications).to_be(1)
    expect(notifications[1].msg).to_be(conflict.MESSAGE)
  end)

  it("reports no conflict when the runtimepath has no claudecode.nvim", function()
    vim.api.nvim_get_runtime_file = function()
      return {}
    end

    expect(conflict.check()).to_be_false()
    expect(#notifications).to_be(0)
  end)

  it("counts a stub without nvim_get_runtime_file as no conflict", function()
    vim.api.nvim_get_runtime_file = nil

    expect(conflict.check()).to_be_false()
    expect(#notifications).to_be(0)
  end)

  it("counts a missing vim.g as no conflict", function()
    vim.g = nil

    expect(conflict.check()).to_be_false()
    expect(#notifications).to_be(0)
  end)

  describe("init.setup", function()
    local function stub_dependencies()
      package.loaded["claudinho.config"] = {
        defaults = {},
        without_removed_options = function(o)
          return o
        end,
        apply = function()
          table.insert(calls, "config.apply")
          return {}
        end,
      }
      package.loaded["claudinho.terminal"] = {
        setup = function()
          table.insert(calls, "terminal.setup")
        end,
      }
      package.loaded["claudinho.server.init"] = {
        start = function()
          table.insert(calls, "server.start")
          return true, 1
        end,
      }
      for _, name in ipairs({ "nvim_create_user_command", "nvim_create_autocmd", "nvim_create_augroup" }) do
        vim.api[name] = function()
          table.insert(calls, name)
          return 1
        end
      end
    end

    it("does nothing when claudecode.nvim is loaded", function()
      vim.g.loaded_claudecode = 1
      stub_dependencies()
      package.loaded["claudinho"] = nil
      local claudinho = require("claudinho")

      local result = claudinho.setup({ auto_start = true })

      expect(result).to_be(claudinho)
      expect(#calls).to_be(0)
      expect(claudinho.state.initialized).to_be_false()
      expect(#notifications).to_be(1)
      expect(notifications[1].msg).to_be(conflict.MESSAGE)
    end)

    it("sets up normally without a conflict", function()
      stub_dependencies()
      package.loaded["claudinho"] = nil
      local claudinho = require("claudinho")

      claudinho.setup({ auto_start = false })

      expect(calls[1]).to_be("config.apply")
      expect(claudinho.state.initialized).to_be_true()
      for _, n in ipairs(notifications) do
        expect(n.msg == conflict.MESSAGE).to_be_false()
      end
    end)
  end)
end)
