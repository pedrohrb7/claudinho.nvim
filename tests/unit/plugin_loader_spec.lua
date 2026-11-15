-- luacheck: globals expect
require("tests.busted_setup")

describe("plugin/claudinho.lua", function()
  local saved
  local has_result
  local err_messages
  local deferred
  local setup_calls
  local main_loaded
  local notifications

  local function load_plugin()
    dofile("plugin/claudinho.lua")
  end

  before_each(function()
    saved = {
      g = vim.g,
      has = vim.fn.has,
      err = vim.api.nvim_err_writeln,
      defer_fn = vim.defer_fn,
      notify = vim.notify,
      loaded = package.loaded["claudinho"],
      notified_once = vim._notified_once,
    }
    vim._notified_once = nil
    has_result = 1
    err_messages = {}
    deferred = {}
    setup_calls = {}
    main_loaded = 0

    vim.g = {}
    vim.fn.has = function(feature)
      if feature == "nvim-0.12" then
        return has_result
      end
      return 0
    end
    vim.api.nvim_err_writeln = function(msg)
      table.insert(err_messages, msg)
    end
    vim.defer_fn = function(fn, _)
      table.insert(deferred, fn)
    end
    notifications = {}
    vim.notify = function(msg, level)
      table.insert(notifications, { msg = msg, level = level })
    end

    package.loaded["claudinho"] = nil
    package.preload["claudinho"] = function()
      main_loaded = main_loaded + 1
      return {
        setup = function(opts)
          table.insert(setup_calls, opts)
        end,
      }
    end
  end)

  after_each(function()
    vim.g = saved.g
    vim.fn.has = saved.has
    vim.api.nvim_err_writeln = saved.err
    vim.defer_fn = saved.defer_fn
    vim.notify = saved.notify
    vim._notified_once = saved.notified_once
    package.preload["claudinho"] = nil
    package.loaded["claudinho"] = saved.loaded
  end)

  it("refuses Neovim older than 0.12 without marking the plugin loaded", function()
    has_result = 0
    vim.g.claudinho_auto_setup = { auto_start = true }

    load_plugin()

    expect(#err_messages).to_be(1)
    expect(err_messages[1]).to_be("Claudinho requires Neovim >= 0.12")
    expect(vim.g.loaded_claudinho).to_be_nil()
    expect(#deferred).to_be(0)
    expect(main_loaded).to_be(0)
  end)

  it("marks the plugin loaded on Neovim 0.12", function()
    load_plugin()

    expect(vim.g.loaded_claudinho).to_be(1)
    expect(#err_messages).to_be(0)
    expect(main_loaded).to_be(1)
  end)

  it("does nothing on a second source", function()
    load_plugin()
    load_plugin()

    expect(main_loaded).to_be(1)
    expect(#err_messages).to_be(0)
  end)

  it("schedules setup with the auto_setup table", function()
    local opts = { auto_start = true }
    vim.g.claudinho_auto_setup = opts

    load_plugin()

    expect(#deferred).to_be(1)
    expect(#setup_calls).to_be(0)
    deferred[1]()
    expect(#setup_calls).to_be(1)
    expect(setup_calls[1]).to_be(opts)
  end)

  it("ignores claudecode_auto_setup alone, silently", function()
    vim.g.claudecode_auto_setup = { auto_start = true }

    load_plugin()

    expect(#deferred).to_be(0)
    expect(#err_messages).to_be(0)
    expect(#setup_calls).to_be(0)
  end)

  it("warns once and stops when claudecode.nvim is loaded", function()
    vim.g.loaded_claudecode = 1
    vim.g.claudinho_auto_setup = { auto_start = true }

    load_plugin()
    vim.g.loaded_claudinho = nil
    load_plugin()

    expect(vim.g.loaded_claudecode).to_be(1)
    expect(#notifications).to_be(1)
    expect(notifications[1].msg).to_be(require("claudinho.conflict").MESSAGE)
    expect(notifications[1].level).to_be(vim.log.levels.WARN)
    expect(#deferred).to_be(0)
    expect(main_loaded).to_be(0)
  end)

  it("does not repeat the warning on a new source", function()
    vim.g.loaded_claudecode = 1

    load_plugin()
    load_plugin()

    expect(vim.g.loaded_claudinho).to_be(1)
    expect(#notifications).to_be(1)
  end)
end)
