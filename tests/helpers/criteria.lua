--- Shared setup of the four success-criteria specs (`tests/integration/criteria_*_spec.lua`): the real plugin, set up
--- through `require("claudinho").setup`, with the stub `tests/bin/claude` as the Claude command and a private HOME,
--- CLAUDE_CONFIG_DIR and lock folder. It needs a real Neovim.
---
--- The stub is named by its absolute path, never by a bare `claude`: a bare name is resolved through the PATH of the
--- caller, which can put a real CLI first (see docs/backlog/bugs/2026-11-16-claude-stub-path-first-entry-integration.md).
local tab_env = require("tests.helpers.tab_env")

local M = {}

local uv = vim.uv or vim.loop

---@return string path Absolute path of tests/bin/claude, from the place of this file
function M.stub_path()
  local here = debug.getinfo(1, "S").source:sub(2)
  local path = vim.fn.fnamemodify(here, ":p:h:h") .. "/bin/claude"
  assert(not path:find("%s"), "the stub path must not hold a space: " .. path)
  assert(vim.fn.executable(path) == 1, "the stub is not executable: " .. path)
  return path
end

---@param pid integer
---@return boolean
function M.alive(pid)
  return uv.kill(pid, 0) == 0
end

---@class CriteriaContext
---@field env TabEnv
---@field sessions table
---@field plugin table
---@field saved_lock_dir string
---@field saved_plugin_loaded boolean

---Set the plugin up for one test: a private environment, fresh `claudinho.*` modules, `setup` with the stub.
---@param overrides table|nil Merged over the test configuration
---@param opts { claude_dir_in_home: boolean|nil }|nil `claude_dir_in_home` makes CLAUDE_CONFIG_DIR the `.claude` folder
---  of the private HOME, as it is for a real user, so one folder holds `settings.json`, `ide/` and the rest
---@return CriteriaContext ctx
function M.start(overrides, opts)
  local env = tab_env.new()
  if opts and opts.claude_dir_in_home then
    env.config_dir = env.home .. "/.claude"
    env.lock_dir = env.config_dir .. "/ide"
    vim.fn.mkdir(env.lock_dir, "p", tonumber("700", 8))
  end
  -- The modules of an earlier test are gone, so no state or autocmd of theirs reaches this one.
  for name in pairs(package.loaded) do
    if name == "claudinho" or name:match("^claudinho%.") then
      package.loaded[name] = nil
    end
  end
  -- lock_dir is read once when the module loads, so the spec points it at its own folder.
  require("claudinho.lockfile").lock_dir = env.lock_dir

  local plugin = require("claudinho")
  plugin.setup(vim.tbl_deep_extend("force", {
    terminal_cmd = M.stub_path(),
    port_range = { min = 20000, max = 40000 },
    -- HOME and CLAUDE_CONFIG_DIR of the test, never the real ones.
    env = { HOME = env.home, CLAUDE_CONFIG_DIR = env.config_dir },
    notify = false,
  }, overrides or {}))

  return { env = env, plugin = plugin, sessions = require("claudinho.sessions") }
end

---Undo `start`: end the tabs, stop the selection tracking and the window autocmds, remove the private folder.
---@param ctx CriteriaContext|nil
function M.stop(ctx)
  if not ctx then
    return
  end
  pcall(function()
    ctx.sessions.kill_all()
  end)
  pcall(function()
    require("claudinho.selection").disable()
  end)
  pcall(function()
    require("claudinho.ui.window").teardown()
  end)
  pcall(vim.api.nvim_del_augroup_by_name, "ClaudinhoSessions")
  vim.cmd("silent! tabonly!")
  vim.cmd("silent! only!")
  for name in pairs(package.loaded) do
    if name == "claudinho" or name:match("^claudinho%.") then
      package.loaded[name] = nil
    end
  end
  tab_env.remove(ctx.env)
end

---@param dir string
---@return string[] names The `*.lock` files of the folder, sorted
function M.lock_files(dir)
  local files = {}
  for name, kind in vim.fs.dir(dir) do
    if kind == "file" and name:match("%.lock$") then
      table.insert(files, name)
    end
  end
  table.sort(files)
  return files
end

---@param path string
---@return string|nil sha The SHA-256 of a file, nil when it does not exist
function M.sha_of_file(path)
  local file = io.open(path, "rb")
  if not file then
    return nil
  end
  local data = file:read("*a")
  file:close()
  return vim.fn.sha256(data)
end

---The state of a folder: every path under it (files and folders) with the SHA-256 of each file.
---@param dir string
---@return table<string, string> state path relative to `dir` -> sha, or "<dir>" for a folder
function M.tree_state(dir)
  local state = {}
  if vim.fn.isdirectory(dir) ~= 1 then
    return state
  end
  for name, kind in vim.fs.dir(dir, { depth = 32 }) do
    if kind == "directory" then
      state[name] = "<dir>"
    else
      state[name] = M.sha_of_file(dir .. "/" .. name) or "<unreadable>"
    end
  end
  return state
end

---@param client WsClient
---@param method string
---@param timeout_ms integer|nil Default 1500
---@return table|nil message The next message of this method, nil on timeout
function M.next_of(client, method, timeout_ms)
  local deadline = (uv.now() or 0) + (timeout_ms or 1500)
  while (uv.now() or 0) < deadline do
    local message = client:next_message(math.max(10, deadline - uv.now()))
    if not message then
      return nil
    end
    if message.method == method then
      return message
    end
  end
  return nil
end

---@param client WsClient
---@param method string
---@param wait_ms integer|nil How long to listen, default 400
---@return table[] messages Every message of this method that arrives in the window
function M.all_of(client, method, wait_ms)
  vim.wait(wait_ms or 400, function()
    return false
  end, 10)
  local found = {}
  while client:pending() > 0 do
    local message = client:next_message(10)
    if message and message.method == method then
      table.insert(found, message)
    end
  end
  return found
end

return M
