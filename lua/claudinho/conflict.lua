local M = {}

M.MESSAGE = "[Claudinho] claudecode.nvim is also installed. "
  .. "Both plugins run, but Claudinho replaces it: remove claudecode.nvim."

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

---Warns that claudecode.nvim is installed, once per session and only with `notify = true`. The caller passes the
---flag because `setup` runs it before the config is applied. Both plugins keep running.
---@param notify_enabled boolean|nil The user's own `notify = true`
---@return boolean detected Whether claudecode.nvim is installed
function M.warn(notify_enabled)
  if not M.detected() then
    return false
  end
  if notify_enabled == true then
    vim.notify_once(M.MESSAGE, vim.log.levels.WARN, { title = "Claudinho" })
  end
  return true
end

return M
