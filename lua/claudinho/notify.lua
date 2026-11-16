---@brief [[
--- User notifications of the plugin, in three classes: informative (off unless `notify = true`), reply to a command
--- that did not do what was asked (always, WARN) and error (always, ERROR). The logger is separate: it is diagnostic
--- output, not a notification.
---@brief ]]
---@module 'claudinho.notify'

local M = {}

M.TITLE = "Claudinho"

---True when the user turned informative notifications on (`notify = true`).
---Reads the config of the running plugin without loading it: an unloaded plugin has no config, so it is off.
---@return boolean
local function enabled()
  local plugin = package.loaded["claudinho"]
  local config = type(plugin) == "table" and type(plugin.state) == "table" and plugin.state.config or nil
  return type(config) == "table" and config.notify == true
end

---Informative notification. Shown only with `notify = true`.
---@param msg string
---@param opts { once: boolean?, level: integer? }? `once` shows the message once per session; `level` replaces INFO
function M.info(msg, opts)
  if not enabled() then
    return
  end
  opts = opts or {}
  local level = opts.level or vim.log.levels.INFO
  if opts.once then
    vim.notify_once(msg, level, { title = M.TITLE })
  else
    vim.notify(msg, level, { title = M.TITLE })
  end
end

---Reply to a command that did not do what was asked. Always shown, WARN.
---@param msg string
function M.reply(msg)
  vim.notify(msg, vim.log.levels.WARN, { title = M.TITLE })
end

---Error. Always shown, ERROR.
---@param msg string
function M.error(msg)
  vim.notify(msg, vim.log.levels.ERROR, { title = M.TITLE })
end

return M
