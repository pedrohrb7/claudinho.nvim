---@brief [[
--- Text of the status line of the Claude window: model, effort and permission mode of the active tab. Pure: the data
--- comes as an argument.
---@brief ]]
---@module 'claudinho.ui.status'
local M = {}

local SEPARATOR = " \xC2\xB7 "

---What each `permission_mode` shows. `manual` is defensive: the hooks send the Manual mode as `default`.
M.MODES = {
  default = "manual",
  manual = "manual",
  plan = "plan",
  auto = "auto",
  acceptEdits = "accept edits",
  dontAsk = "don't ask",
  bypassPermissions = "bypass permissions",
}

---Text of a permission mode; an unknown value is shown as it came.
---@param mode string
---@return string
function M.mode_label(mode)
  return M.MODES[mode] or mode
end

---Join model, effort and mode, skipping what is missing. `%` is doubled for the statusline.
---@param data { model: string|nil, effort: string|nil, mode: string|nil }|nil
---@return string text Empty when there is no data
function M.text(data)
  data = data or {}
  local items = {}
  local function add(value)
    if type(value) == "string" and value ~= "" then
      items[#items + 1] = value
    end
  end
  add(data.model)
  add(data.effort)
  add(data.mode and M.mode_label(data.mode))
  return (table.concat(items, SEPARATOR):gsub("%%", "%%%%"))
end

return M
