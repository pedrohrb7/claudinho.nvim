-- Origin: coder/claudecode.nvim@d1237072, lua/claudecode/health.lua (MIT, see LICENSE)
--- Health check for claudinho.nvim, run via :checkhealth claudinho
--- Verifies prerequisites (Neovim version, Claude CLI) and reports the live
--- state of each Claude tab (process, WebSocket server, lock file) without
--- launching anything.
---@module 'claudinho.health'
local M = {}

-- vim.health gained start/ok/warn/error in Neovim 0.10; older versions use report_* variants.
local health = vim.health or require("health")
local start = health.start or health.report_start
local ok = health.ok or health.report_ok
local warn = health.warn or health.report_warn
local error_ = health.error or health.report_error
local info = health.info or health.report_info or ok

---Extracts the executable (first token) from a command string.
---@param cmd string
---@return string executable
local function executable_of(cmd)
  assert(type(cmd) == "string" and cmd ~= "", "cmd must be a non-empty string")
  return cmd:match("^(%S+)") or cmd
end

local function check_neovim()
  if vim.fn.has("nvim-0.12") == 1 then
    ok("Neovim >= 0.12")
  else
    error_("Neovim >= 0.12 is required")
  end
end

---WARN when claudecode.nvim is installed, with or without `setup()`. Both plugins run.
local function check_conflict()
  local reason
  if vim.g and vim.g.loaded_claudecode then
    reason = "claudecode.nvim is loaded (g:loaded_claudecode is set)"
  elseif require("claudinho.conflict").detected() then
    reason = "claudecode.nvim is installed (lua/claudecode/init.lua is on the runtimepath)"
  else
    return
  end
  warn(reason, {
    "Both plugins run, but Claudinho replaces it. Remove claudecode.nvim from your plugin manager and restart Neovim.",
  })
end

---@param claudinho table The main plugin module
local function check_setup(claudinho)
  if claudinho.state.initialized then
    ok("claudinho.nvim " .. claudinho.version:string() .. " is set up")
    return true
  end
  error_("setup() has not been called", { 'Call require("claudinho").setup() (or use your plugin manager\'s opts)' })
  return false
end

---@param config table The merged plugin config
local function check_cli(config)
  local terminal_cmd = config.terminal_cmd
  local cmd = (terminal_cmd and terminal_cmd ~= "") and terminal_cmd or "claude"
  local exe = executable_of(cmd)

  if vim.fn.executable(exe) ~= 1 then
    error_(("Claude CLI not found: '%s' is not executable"):format(exe), {
      "Install Claude Code: https://docs.anthropic.com/en/docs/claude-code",
      "Or set `terminal_cmd` in setup() to the full path of the CLI",
    })
    return
  end

  ok(("Claude CLI found: %s (%s)"):format(exe, vim.fn.exepath(exe)))

  local version_ok, output = pcall(vim.fn.system, { exe, "--version" })
  if version_ok and vim.v.shell_error == 0 then
    info("CLI version: " .. vim.trim(output))
  else
    warn(("'%s --version' failed; the configured command may not be the Claude CLI"):format(exe))
  end
end

---@param config table The merged plugin config
local function check_notify(config)
  if config.notify ~= true then
    info("Informative notifications are off (notify = false)")
  end
end

---One WARN per removed key that the user's config still has (found by the last `setup()`), with the text of the
---warning that `notify = true` shows.
---@param claudinho table The main plugin module
local function check_removed_options(claudinho)
  for _, row in ipairs(claudinho.state.removed_found or {}) do
    warn((row.message:gsub("^%[Claudinho%] ", "")))
  end
end

---The lock file of a running tab: present, or why it is not.
---@param n integer The tab number
---@param port integer
---@param lock_path string
local function check_lock_file(n, port, lock_path)
  if vim.fn.filereadable(lock_path) == 1 then
    return
  end
  -- `filereadable` is 0 for a missing file, a folder, and a file that exists but cannot be read (mode 000). Only the
  -- first two are missing.
  local stat = vim.loop.fs_stat(lock_path)
  if stat and stat.type ~= "directory" then
    error_(("Claude %d: the lock file exists but cannot be read: %s"):format(n, lock_path), {
      "Claude discovers this Neovim instance through the lock file, and it must be able to read it",
      ("Make the file readable by you (mode 600), or restart the tab with :Claudinho tab-close %d and :Claudinho new"):format(
        n
      ),
    })
  else
    error_(("Claude %d: the lock file is missing: %s (port %d)"):format(n, lock_path, port), {
      "Claude discovers this Neovim instance through the lock file",
      ("Close the tab with :Claudinho tab-close %d and open another with :Claudinho new"):format(n),
    })
  end
end

---One line per tab: its process, port, clients and lock file.
local function check_tabs()
  local sessions = require("claudinho.sessions")
  local state = sessions.state
  local numbers = sessions.numbers()

  if #numbers == 0 then
    info("No Claude tabs open")
    return
  end

  local lockfile = require("claudinho.lockfile")
  for _, n in ipairs(numbers) do
    local s = state.tabs[n]
    if s.state ~= "running" then
      info(("Claude %d: exited (code %s)"):format(n, tostring(s.exit_code)))
    else
      local status = s.server and s.server:get_status() or { client_count = 0 }
      local port = s.lock_port or status.port
      local lock_path = lockfile.lock_dir .. "/" .. tostring(port) .. ".lock"
      ok(
        ("Claude %d: running, port %s, %d client(s), lock file %s"):format(
          n,
          tostring(port),
          status.client_count or 0,
          lock_path
        )
      )
      check_lock_file(n, port, lock_path)
    end
  end
end

function M.check()
  start("claudinho.nvim")

  check_neovim()

  local loaded, claudinho = pcall(require, "claudinho")
  if not loaded then
    error_("Could not load claudinho module: " .. tostring(claudinho))
    return
  end

  check_conflict()

  if not check_setup(claudinho) then
    return
  end

  check_cli(claudinho.state.config)
  check_notify(claudinho.state.config)
  check_removed_options(claudinho)
  check_tabs()
end

return M
