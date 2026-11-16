--- The environment of a session test in a real Neovim: a private CLAUDE_CONFIG_DIR and HOME, and a test command that
--- stands in for `claude`. The command writes the environment of its process to a file and idles for 30 seconds at most
--- (so a process that no test stops still ends), and a second command ends at once with a given exit code.
--- It needs a real Neovim (`vim.fn.mkdir`, `vim.fn.tempname`); nothing here touches the real `~/.claude`.
local M = {}

---@class TabEnv
---@field root string The private folder of the test
---@field config_dir string CLAUDE_CONFIG_DIR of the test
---@field lock_dir string The `ide` folder under it
---@field home string HOME of the test
---@field env_file string Where the idle command writes its environment
---@field idle_cmd string `terminal_cmd` of a session that idles
---@field exit_cmd fun(code: integer): string `terminal_cmd` of a session that ends at once

---@return TabEnv
function M.new()
  local root = vim.fn.tempname() .. "-claudinho-tab"
  local config_dir = root .. "/config"
  local home = root .. "/home"
  local lock_dir = config_dir .. "/ide"
  vim.fn.mkdir(lock_dir, "p", tonumber("700", 8))
  vim.fn.mkdir(home, "p", tonumber("700", 8))
  local env_file = root .. "/env.txt"
  -- The paths come from tempname(): no space and no quote. The file is written in one step, so a reader never sees
  -- half of it.
  local idle =
    string.format("sh -c 'env > %s.tmp && mv %s.tmp %s; exec sleep 30' claude-test", env_file, env_file, env_file)
  return {
    root = root,
    config_dir = config_dir,
    lock_dir = lock_dir,
    home = home,
    env_file = env_file,
    idle_cmd = idle,
    exit_cmd = function(code)
      return string.format("sh -c 'exit %d' claude-test", code)
    end,
  }
end

---Read the environment that the idle command wrote, as a table.
---@param tab_env TabEnv
---@return table<string, string>|nil env nil while the file does not exist yet
function M.read_env(tab_env)
  local file = io.open(tab_env.env_file, "r")
  if not file then
    return nil
  end
  local env = {}
  for line in file:lines() do
    local key, value = line:match("^([%w_]+)=(.*)$")
    if key then
      env[key] = value
    end
  end
  file:close()
  return env
end

---@param tab_env TabEnv|nil
function M.remove(tab_env)
  if tab_env then
    vim.fn.delete(tab_env.root, "rf")
  end
end

return M
