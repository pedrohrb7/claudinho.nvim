--- Health check for claudinho.nvim, run via :checkhealth claudinho
--- Verifies prerequisites (Neovim version, Claude CLI, terminal provider)
--- and reports live integration state (WebSocket server, lock file,
--- Claude connection) without launching anything.
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

---@param claudinho table The main plugin module
local function check_setup(claudinho)
  local conflict = require("claudinho.conflict")
  if not claudinho.state.initialized and conflict.detected() then
    error_(conflict.MESSAGE, { "Remove claudecode.nvim (uninstall it from your plugin manager), then restart Neovim" })
    return false
  end
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
local function check_terminal_provider(config)
  local provider = config.terminal and config.terminal.provider or "auto"
  if type(provider) == "table" then
    info("Terminal provider: custom (table)")
    return
  end

  if provider == "auto" then
    ok("Terminal provider 'auto': native terminal")
  elseif provider == "external" then
    local cmd = config.terminal.provider_opts and config.terminal.provider_opts.external_terminal_cmd
    if cmd and (type(cmd) == "function" or cmd:find("%%s")) then
      ok("Terminal provider 'external' configured")
    else
      error_("Terminal provider 'external' requires provider_opts.external_terminal_cmd containing '%s'")
    end
  else
    ok(("Terminal provider: %s"):format(provider))
  end
end

---@param claudinho table The main plugin module
local function check_server(claudinho)
  local server = require("claudinho.server.init")
  local status = server.get_status()

  if not status.running then
    warn("WebSocket server is not running", {
      "The server starts automatically when auto_start = true (default)",
      "Or start it manually with :ClaudeCodeStart",
    })
    return
  end

  ok(("WebSocket server running on port %d"):format(status.port))

  local lockfile = require("claudinho.lockfile")
  local lock_path = lockfile.lock_dir .. "/" .. tostring(status.port) .. ".lock"
  if vim.fn.filereadable(lock_path) == 1 then
    ok("Lock file present: " .. lock_path)
  else
    -- `filereadable` is 0 for a missing file, a folder, and a file that exists but cannot be read (mode 000). Only
    -- the first two are missing.
    local stat = vim.loop.fs_stat(lock_path)
    if stat and stat.type ~= "directory" then
      error_("Lock file exists but cannot be read: " .. lock_path, {
        "Claude discovers this Neovim instance through the lock file, and it must be able to read it",
        "Make the file readable by you (mode 600), or restart the integration with :ClaudeCodeStop and :ClaudeCodeStart",
      })
    else
      error_("Lock file missing: " .. lock_path, {
        "Claude discovers this Neovim instance through the lock file",
        "Restart the integration with :ClaudeCodeStop and :ClaudeCodeStart",
      })
    end
  end

  if claudinho.is_claude_connected() then
    ok(("Claude Code is connected (%d client(s))"):format(status.client_count))
  else
    info("No Claude Code client connected yet (launch one with :ClaudeCode)")
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

  if not check_setup(claudinho) then
    return
  end

  check_cli(claudinho.state.config)
  check_terminal_provider(claudinho.state.config)
  check_server(claudinho)
end

return M
