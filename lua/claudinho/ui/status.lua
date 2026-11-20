---@brief [[
--- Text of the status line of the Claude window: model, effort and permission mode of the active tab on the left (each
--- one a click region), the usage limits of the account on the right. Pure: the data, the usage value, the width and the
--- clock come as arguments; only `render` reads the editor.
---@brief ]]
---@module 'claudinho.ui.status'
local M = {}

local SEPARATOR = " \xC2\xB7 "

---Name of the global function the click regions call (installed by the window setup).
M.CLICK_FUNC = "ClaudinhoStatusClick"

---Smallest gap between the left side and the usage on the right.
M.MIN_GAP = 2

---Day names by `os.date("*t").wday` (1 = Sunday) and month names by `month`; fixed English, never `%a` or `%b`, which
---follow the locale.
M.DAYS = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }
M.MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }

---Usage highlight groups and the theme groups they link to (never a fixed color).
M.HIGHLIGHTS = { ClaudinhoUsageWarn = "DiagnosticWarn", ClaudinhoUsageError = "DiagnosticError" }

local USAGE_LABELS = { five_hour = "5h", seven_day = "7d" }
local USAGE_ORDER = { "five_hour", "seven_day" }

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

---@class ClaudinhoStatusItem
---@field id integer 1 model, 2 effort, 3 mode
---@field text string

---@class ClaudinhoUsageItem
---@field text string
---@field level string|nil Highlight group

---Items of the left side, in order, without the missing ones.
---@param data { model: string|nil, effort: string|nil, mode: string|nil }|nil
---@return ClaudinhoStatusItem[]
function M.items(data)
  data = data or {}
  local items = {}
  local function add(id, value)
    if type(value) == "string" and value ~= "" then
      items[#items + 1] = { id = id, text = value }
    end
  end
  add(1, data.model)
  add(2, data.effort)
  add(3, data.mode and M.mode_label(data.mode))
  return items
end

---@param items { text: string }[]
---@return string
local function plain(items)
  local texts = {}
  for i, item in ipairs(items) do
    texts[i] = item.text
  end
  return table.concat(texts, SEPARATOR)
end

---Join model, effort and mode, skipping what is missing. `%` is doubled for the statusline.
---@param data { model: string|nil, effort: string|nil, mode: string|nil }|nil
---@return string text Empty when there is no data
function M.text(data)
  return (plain(M.items(data)):gsub("%%", "%%%%"))
end

---Usage percentage as shown: rounded, half up.
---@param used number
---@return integer
function M.percent(used)
  return math.floor(used + 0.5)
end

---Highlight group of a rounded percentage: error from 95, warning from 80, none below.
---@param pct number
---@return string|nil
function M.level(pct)
  if pct >= 95 then
    return "ClaudinhoUsageError"
  elseif pct >= 80 then
    return "ClaudinhoUsageWarn"
  end
  return nil
end

---Local time of a reset: `HH:MM` today, `Ddd HH:MM` within 1 to 6 calendar days, `Mmm D HH:MM` from 7 days on.
---Seconds are dropped; the zone is the one of the Neovim process, the names are always English.
---@param resets_at number Epoch seconds
---@param now number Epoch seconds
---@return string
function M.format_reset(resets_at, now)
  local r = os.date("*t", math.floor(resets_at))
  local n = os.date("*t", math.floor(now))
  -- Noon on both dates keeps the day count right across a daylight saving change.
  local r_noon = os.time({ year = r.year, month = r.month, day = r.day, hour = 12 })
  local n_noon = os.time({ year = n.year, month = n.month, day = n.day, hour = 12 })
  local days = math.floor((r_noon - n_noon) / 86400 + 0.5)
  local clock = string.format("%02d:%02d", r.hour, r.min)
  if days <= 0 then
    return clock
  elseif days <= 6 then
    return string.format("%s %s", M.DAYS[r.wday], clock)
  end
  return string.format("%s %d %s", M.MONTHS[r.month], r.day, clock)
end

---Usage items in the order 5h, 7d.
---@param usage ClaudinhoUsageValue|nil
---@param now number
---@param with_reset boolean
---@param only_first boolean|nil Keep just the first present item
---@return ClaudinhoUsageItem[]
local function usage_items(usage, now, with_reset, only_first)
  local items = {}
  for _, key in ipairs(USAGE_ORDER) do
    local w = usage and usage[key]
    if type(w) == "table" and type(w.used) == "number" then
      local pct = M.percent(w.used)
      local text = string.format("%s %d%%", USAGE_LABELS[key], pct)
      if with_reset and w.resets_at then
        text = string.format("%s (%s)", text, M.format_reset(w.resets_at, now))
      end
      items[#items + 1] = { text = text, level = M.level(pct) }
      if only_first then
        break
      end
    end
  end
  return items
end

---Right side that fits: both items with the times, both without, only the first, nothing. The left side has priority
---and is never cut for the usage.
---@param left_width integer Display width of the left side, 0 when empty
---@param usage ClaudinhoUsageValue|nil
---@param width integer|nil Width of the status line; nil means no limit
---@param now number|nil Epoch seconds, default `os.time()`
---@return ClaudinhoUsageItem[]
function M.layout(left_width, usage, width, now)
  now = now or os.time()
  width = width or math.huge
  local variants = {
    usage_items(usage, now, true),
    usage_items(usage, now, false),
    usage_items(usage, now, false, true),
  }
  for _, items in ipairs(variants) do
    if #items > 0 then
      local right = vim.fn.strdisplaywidth(plain(items))
      local gap = left_width > 0 and M.MIN_GAP or 0
      if left_width + gap + right <= width then
        return items
      end
    end
  end
  return {}
end

---@param text string
---@return string
local function escape(text)
  return (text:gsub("%%", "%%%%"))
end

---Final statusline text: the left items (one click region each), `%=`, the usage items (colored, no region).
---@param data { model: string|nil, effort: string|nil, mode: string|nil }|nil
---@param usage ClaudinhoUsageValue|nil
---@param width integer|nil
---@param now number|nil
---@return string
function M.build(data, usage, width, now)
  local left = M.items(data)
  local right = M.layout(vim.fn.strdisplaywidth(plain(left)), usage, width, now)
  local left_parts = {}
  for i, item in ipairs(left) do
    left_parts[i] = string.format("%%%d@v:lua.%s@%s%%X", item.id, M.CLICK_FUNC, escape(item.text))
  end
  local right_parts = {}
  for i, item in ipairs(right) do
    local text = escape(item.text)
    right_parts[i] = item.level and string.format("%%$%s$%s%%*", item.level, text) or text
  end
  if #left_parts == 0 and #right_parts == 0 then
    return ""
  end
  local out = table.concat(left_parts, SEPARATOR)
  if #right_parts > 0 then
    out = out .. "%=" .. table.concat(right_parts, SEPARATOR)
  end
  return out
end

---Link the usage groups to theme groups. `default` keeps any definition of the user, made before or after.
function M.setup_highlights()
  for name, target in pairs(M.HIGHLIGHTS) do
    vim.api.nvim_set_hl(0, name, { link = target, default = true })
  end
end

---The status line of the window being drawn: the data of the active tab and the usage of the account. An ended tab
---keeps its last status.
---@return string
function M.render()
  local usage = require("claudinho.usage")
  local s = require("claudinho.sessions").active()
  local now = usage.now()
  local width = vim.o.laststatus == 3 and vim.o.columns or vim.api.nvim_win_get_width(vim.g.statusline_winid or 0)
  return M.build(s and s.data or nil, usage.windows(now), width, now)
end

return M
