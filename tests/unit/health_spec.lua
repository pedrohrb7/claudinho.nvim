-- luacheck: globals expect
require("tests.busted_setup")

describe("health", function()
  local health
  local reports

  -- State the stubs expose to the module under test
  local fake_state
  local tabs
  local executables
  local lock_readable
  local lock_stat
  local real_fs_stat

  local function record(level)
    return function(msg)
      table.insert(reports, { level = level, msg = msg })
    end
  end

  local function has_report(level, pattern)
    for _, r in ipairs(reports) do
      if r.level == level and r.msg:find(pattern) then
        return true
      end
    end
    return false
  end

  before_each(function()
    reports = {}
    executables = { claude = true }
    lock_readable = true
    lock_stat = nil
    -- One running tab, as a session holds it: port, server with its status, exit code.
    tabs = {
      [1] = {
        number = 1,
        state = "running",
        lock_port = 12345,
        server = {
          get_status = function()
            return { running = true, port = 12345, client_count = 1 }
          end,
        },
      },
    }
    fake_state = {
      initialized = true,
      config = { terminal_cmd = nil, notify = true },
    }

    vim.health = {
      start = record("start"),
      ok = record("ok"),
      warn = record("warn"),
      error = record("error"),
      info = record("info"),
    }
    vim.trim = vim.trim or function(s)
      return s:match("^%s*(.-)%s*$")
    end
    vim.v = vim.v or {}
    vim.v.shell_error = 0
    vim.fn.executable = function(exe)
      return executables[exe] and 1 or 0
    end
    vim.fn.exepath = function(exe)
      return "/usr/bin/" .. exe
    end
    vim.fn.system = function(_)
      return "1.0.0 (Claude Code)\n"
    end
    vim.fn.filereadable = function(_)
      return lock_readable and 1 or 0
    end
    -- What fs_stat finds at the lock path: nil for nothing, or a table with the type of the entry.
    vim.loop = vim.loop or {}
    real_fs_stat = vim.loop.fs_stat
    vim.loop.fs_stat = function(_)
      return lock_stat
    end

    package.loaded["claudinho"] = {
      version = {
        string = function()
          return "0.2.0"
        end,
      },
      state = fake_state,
    }
    package.loaded["claudinho.sessions"] = { state = { tabs = tabs } }
    package.loaded["claudinho.lockfile"] = { lock_dir = "/tmp/claude/ide" }

    package.loaded["claudinho.health"] = nil
    health = require("claudinho.health")
  end)

  after_each(function()
    vim.loop.fs_stat = real_fs_stat
    package.loaded["claudinho"] = nil
    package.loaded["claudinho.sessions"] = nil
    package.loaded["claudinho.lockfile"] = nil
    package.loaded["claudinho.health"] = nil
  end)

  it("reports all-ok for a healthy setup", function()
    health.check()

    expect(has_report("ok", "Neovim")).to_be_true()
    expect(has_report("ok", "is set up")).to_be_true()
    expect(has_report("ok", "Claude CLI found")).to_be_true()
    expect(has_report("ok", "Claude 1: running, port 12345, 1 client%(s%), lock file /tmp/claude/ide/12345.lock")).to_be_true()
    expect(has_report("error", ".")).to_be_false()
    expect(has_report("warn", ".")).to_be_false()
  end)

  it("errors when setup() was not called and stops early", function()
    fake_state.initialized = false

    health.check()

    expect(has_report("error", "setup%(%) has not been called")).to_be_true()
    expect(has_report("ok", "Claude CLI found")).to_be_false()
  end)

  it("reports the claudecode.nvim conflict instead of a missing setup()", function()
    fake_state.initialized = false
    local saved_g = vim.g
    vim.g = { loaded_claudecode = 1 }
    package.loaded["claudinho.conflict"] = nil

    health.check()
    vim.g = saved_g
    package.loaded["claudinho.conflict"] = nil

    expect(has_report("error", "claudecode.nvim is also loaded")).to_be_true()
    expect(has_report("error", "has not been called")).to_be_false()
    expect(has_report("ok", "Claude CLI found")).to_be_false()
  end)

  it("errors when the Claude CLI is missing", function()
    executables = {}

    health.check()

    expect(has_report("error", "Claude CLI not found")).to_be_true()
  end)

  it("resolves the executable from a custom terminal_cmd", function()
    fake_state.config.terminal_cmd = "/opt/claude/bin/claude --flag"
    executables["/opt/claude/bin/claude"] = true

    health.check()

    expect(has_report("ok", "Claude CLI found: /opt/claude/bin/claude")).to_be_true()
  end)

  it("reports no tabs as information, not as a problem", function()
    tabs[1] = nil

    health.check()

    expect(has_report("info", "No Claude tabs open")).to_be_true()
    expect(has_report("error", ".")).to_be_false()
    expect(has_report("warn", ".")).to_be_false()
  end)

  it("errors when the lock file of a running tab is missing", function()
    lock_readable = false

    health.check()

    expect(has_report("error", "Claude 1: the lock file is missing: /tmp/claude/ide/12345.lock")).to_be_true()
    expect(has_report("error", "exists but cannot be read")).to_be_false()
  end)

  it("says that a lock file that exists but cannot be read cannot be read, not that it is missing", function()
    lock_readable = false
    lock_stat = { type = "file" }

    health.check()

    expect(has_report("error", "Claude 1: the lock file exists but cannot be read: /tmp/claude/ide/12345.lock")).to_be_true()
    expect(has_report("error", "lock file is missing")).to_be_false()
  end)

  it("reports a folder at the lock path as a missing lock file", function()
    lock_readable = false
    lock_stat = { type = "directory" }

    health.check()

    expect(has_report("error", "the lock file is missing")).to_be_true()
    expect(has_report("error", "exists but cannot be read")).to_be_false()
  end)

  it("reports a line per tab, in order, with the exit code of an ended one", function()
    tabs[3] = { number = 3, state = "exited", exit_code = 2 }
    tabs[2] = {
      number = 2,
      state = "running",
      server = {
        get_status = function()
          return { running = true, port = 23456, client_count = 0 }
        end,
      },
    }

    health.check()

    local tab_lines = {}
    for _, report in ipairs(reports) do
      if report.msg:find("^Claude %d") and not report.msg:find("CLI") then
        table.insert(tab_lines, report.msg)
      end
    end
    assert.are.same({
      "Claude 1: running, port 12345, 1 client(s), lock file /tmp/claude/ide/12345.lock",
      "Claude 2: running, port 23456, 0 client(s), lock file /tmp/claude/ide/23456.lock",
      "Claude 3: exited (code 2)",
    }, tab_lines)
  end)

  it("tells that informative notifications are off", function()
    fake_state.config.notify = false

    health.check()

    expect(has_report("info", "Informative notifications are off %(notify = false%)")).to_be_true()
  end)

  it("says nothing about notifications when they are on", function()
    health.check()

    expect(has_report("info", "Informative notifications")).to_be_false()
  end)

  it("no longer reports a terminal provider", function()
    health.check()

    expect(has_report("ok", "Terminal provider")).to_be_false()
    expect(has_report("error", "Terminal provider")).to_be_false()
  end)

  describe("Neovim version", function()
    local real_has

    before_each(function()
      real_has = vim.fn.has
    end)

    after_each(function()
      vim.fn.has = real_has
    end)

    it("is ok when Neovim 0.12 is available", function()
      vim.fn.has = function(feature)
        return feature == "nvim-0.12" and 1 or 0
      end

      health.check()

      expect(has_report("ok", "Neovim >= 0%.12")).to_be_true()
    end)

    it("errors when Neovim is older than 0.12", function()
      vim.fn.has = function()
        return 0
      end

      health.check()

      expect(has_report("error", "Neovim >= 0%.12 is required")).to_be_true()
    end)
  end)
end)
