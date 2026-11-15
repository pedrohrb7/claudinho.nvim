local M = {}

M.MESSAGE = "[Claudinho] claudecode.nvim is also loaded, and the two plugins cannot run together. "
  .. "Claudinho is disabled; remove claudecode.nvim to use it."

---Pure detection, no warning. True when claudecode.nvim is loaded (vim.g.loaded_claudecode is set) or is on the
---runtimepath (lua/claudecode/init.lua), which also covers setup() running from init.lua before its plugin/ file.
---A minimal stub without vim.g or vim.api.nvim_get_runtime_file counts as no conflict.
---@return boolean
function M.detected()
  if vim.g and vim.g.loaded_claudecode then
    return true
  end
  if vim.api and vim.api.nvim_get_runtime_file then
    local found = vim.api.nvim_get_runtime_file("lua/claudecode/init.lua", false)
    return type(found) == "table" and #found > 0
  end
  return false
end

---True when claudecode.nvim is loaded or on the runtimepath (see `detected`); warns once per session.
---@return boolean
function M.check()
  if not M.detected() then
    return false
  end
  vim.notify_once(M.MESSAGE, vim.log.levels.WARN)
  return true
end

return M
