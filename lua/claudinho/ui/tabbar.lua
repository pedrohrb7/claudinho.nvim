---@brief [[
--- The tab bar (the winbar of the Claude window): labels, shrinking and click handling. The layout and the string are
--- pure: the tabs, the active tab, the width and the title limit come as arguments. Only `render` without arguments
--- (what the winbar expression calls) reads the tab registry and the window.
---@brief ]]
---@module 'claudinho.ui.tabbar'
local M = {}

---@class ClaudinhoTabInfo
---@field number integer
---@field title string|nil Clean title (see `clean_title`); nil shows `Claude <number>`
---@field diff boolean|nil A diff is waiting for activation
---@field exited boolean|nil The process ended

---@class ClaudinhoTabItem
---@field kind "tab"|"new"|"more_left"|"more_right"|"sep"
---@field text string Text as shown, without escapes
---@field number integer|nil
---@field active boolean|nil
---@field tab ClaudinhoTabInfo|nil
---@field limit integer|nil Title limit used for this tab

local SEP = "│"
local ELLIPSIS = "…"
local LEFT, RIGHT = "‹", "›"
local DEFAULT_MAX = 24

M.CLICK_FUNC = "ClaudinhoTabClick"

M.HIGHLIGHTS = {
  ClaudinhoTabActive = "TabLineSel",
  ClaudinhoTab = "TabLine",
  ClaudinhoTabMark = "WarningMsg",
  ClaudinhoTabExited = "Comment",
  ClaudinhoTabNew = "TabLine",
  ClaudinhoTabFill = "TabLineFill",
}

---Link the tab bar groups to standard ones; user overrides win.
function M.setup_highlights()
  for name, target in pairs(M.HIGHLIGHTS) do
    vim.api.nvim_set_hl(0, name, { link = target, default = true })
  end
end

local function trim(text)
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function width_of(text)
  return vim.fn.strdisplaywidth(text)
end

---Iterate over the characters of a UTF-8 string.
local function chars(text)
  return text:gmatch("[%z\1-\127\194-\244][\128-\191]*")
end

---A title without the status symbol Claude puts first, or nil when it is empty or generic.
---@param raw any The terminal title (`b:term_title`)
---@param ctx { cmd: string|nil }|nil `cmd` is the configured command
---@return string|nil title
function M.clean_title(raw, ctx)
  if type(raw) ~= "string" then
    return nil
  end
  local title = trim(raw)
  local first, rest = title:match("^(%S+)%s*(.*)$")
  if first and not first:find("[%w]") then
    title = trim(rest)
  end
  if title == "" or title:sub(1, 7) == "term://" then
    return nil
  end

  local lowered = title:lower()
  local generic = { ["claude code"] = true, claude = true }
  local cmd = ctx and ctx.cmd
  if type(cmd) == "string" and cmd ~= "" then
    generic[cmd:lower()] = true
    local exe = cmd:match("^%s*(%S+)")
    if exe then
      generic[exe:lower()] = true
      generic[(exe:match("([^/\\]+)$") or exe):lower()] = true
    end
  end
  if generic[lowered] then
    return nil
  end
  return title
end

---Cut a title to `max` display cells: the first `max - 1` cells plus an ellipsis.
---@param title string
---@param max integer
---@return string
local function truncate(title, max)
  if width_of(title) <= max then
    return title
  end
  local out, used = {}, 0
  for char in chars(title) do
    local w = width_of(char)
    if used + w > max - 1 then
      break
    end
    out[#out + 1] = char
    used = used + w
  end
  return table.concat(out) .. ELLIPSIS
end

---The marks of a tab, in order, with the highlight group of each.
---@param tab ClaudinhoTabInfo
---@return { text: string, hl: string }[]
function M.marks(tab)
  local marks = {}
  if tab.diff then
    marks[#marks + 1] = { text = " ● diff", hl = "ClaudinhoTabMark" }
  end
  if tab.exited then
    marks[#marks + 1] = { text = " [exited]", hl = "ClaudinhoTabExited" }
  end
  return marks
end

---Number and title, without the marks. A `max` below 1 leaves the title out.
local function base(tab, max)
  local title = tab.title
  if title == nil or title == "" then
    title = "Claude " .. tab.number
  end
  if max and max < 1 then
    return tostring(tab.number)
  end
  return tab.number .. " " .. (max and truncate(title, max) or title)
end

---Label of a tab: `<n> <title>` plus its marks. The number and the marks are never cut.
---@param tab ClaudinhoTabInfo
---@param max integer|nil Title limit in cells; 0 keeps only the number and the marks
---@return string label
function M.label(tab, max)
  local parts = { base(tab, max) }
  for _, mark in ipairs(M.marks(tab)) do
    parts[#parts + 1] = mark.text
  end
  return table.concat(parts)
end

---Items for the tabs lo..hi of `sorted`, with the `+` and the overflow arrows.
local function build(sorted, active, lo, hi, max)
  local items = {}
  local function add(item)
    if #items > 0 then
      items[#items + 1] = { kind = "sep", text = SEP }
    end
    items[#items + 1] = item
  end
  if lo > 1 then
    add({ kind = "more_left", text = " " .. LEFT .. " " })
  end
  for i = lo, hi do
    local tab = sorted[i]
    add({
      kind = "tab",
      text = " " .. M.label(tab, max) .. " ",
      number = tab.number,
      active = tab.number == active,
      tab = tab,
      limit = max,
    })
  end
  if hi < #sorted then
    add({ kind = "more_right", text = " " .. RIGHT .. " " })
  end
  add({ kind = "new", text = " + ", number = 0 })

  local total = 0
  for _, item in ipairs(items) do
    total = total + width_of(item.text)
  end
  return items, total
end

---Lay out the tab bar. Tabs go in ascending order, separated by `│`, with the `+` last. When they do not fit, the
---title limit shrinks one cell at a time down to 0 (number and marks only); if they still do not fit, the active tab
---and the `+` stay and neighbours are added, right then left, while they fit, with `‹` and `›` for what is out.
---@param tabs ClaudinhoTabInfo[]
---@param active integer|nil Number of the active tab
---@param width integer Cells available
---@param max integer|nil Title limit (default 24)
---@return ClaudinhoTabItem[] items
function M.layout(tabs, active, width, max)
  local sorted = {}
  for i, tab in ipairs(tabs or {}) do
    sorted[i] = tab
  end
  table.sort(sorted, function(a, b)
    return a.number < b.number
  end)
  max = max or DEFAULT_MAX

  for limit = max, 0, -1 do
    local items, total = build(sorted, active, 1, #sorted, limit)
    if total <= width then
      return items
    end
  end
  if #sorted == 0 then
    return (build(sorted, active, 1, 0, 0))
  end

  local index = 1
  for i, tab in ipairs(sorted) do
    if tab.number == active then
      index = i
    end
  end
  local lo, hi = index, index
  local best = build(sorted, active, lo, hi, 0)
  local grew = true
  while grew do
    grew = false
    for _, side in ipairs({ "right", "left" }) do
      local nlo, nhi = lo, hi
      if side == "right" and hi < #sorted then
        nhi = hi + 1
      elseif side == "left" and lo > 1 then
        nlo = lo - 1
      end
      if nlo ~= lo or nhi ~= hi then
        local items, total = build(sorted, active, nlo, nhi, 0)
        if total <= width then
          lo, hi, best, grew = nlo, nhi, items, true
        end
      end
    end
  end
  return best
end

local function escape(text)
  return (text:gsub("%%", "%%%%"))
end

---The tabs of the registry as bar data, with the width of the window being drawn and the title limit of the config.
---@return ClaudinhoTabInfo[] tabs
---@return integer|nil active
---@return integer width
---@return integer max
local function live()
  local sessions = require("claudinho.sessions")
  local tabs = {}
  for n, s in pairs(sessions.state.tabs) do
    tabs[#tabs + 1] = { number = n, title = s.title, diff = #s.pending_diffs > 0, exited = s.state == "exited" }
  end
  local plugin = package.loaded["claudinho"]
  local config = type(plugin) == "table" and type(plugin.state) == "table" and plugin.state.config or nil
  local window = (config or require("claudinho.config").defaults).window
  local win = vim.g.statusline_winid
  if type(win) ~= "number" or win == 0 or not vim.api.nvim_win_is_valid(win) then
    win = 0
  end
  return tabs, sessions.state.active, vim.api.nvim_win_get_width(win), window.tab_title_max
end

---Build the winbar string, with a click region per tab and for the `+`. Without arguments (the winbar expression
---calls it so) the data comes from the tab registry and the window being drawn.
---@param tabs ClaudinhoTabInfo[]|nil
---@param active integer|nil
---@param width integer|nil
---@param max integer|nil
---@return string winbar
function M.render(tabs, active, width, max)
  if tabs == nil then
    tabs, active, width, max = live()
  end
  ---@cast width integer
  local out = {}
  local function click(n)
    return "%" .. n .. "@v:lua." .. M.CLICK_FUNC .. "@"
  end
  for _, item in ipairs(M.layout(tabs, active, width, max)) do
    if item.kind == "tab" then
      local hl = item.active and "ClaudinhoTabActive" or "ClaudinhoTab"
      local parts = { click(item.number), "%#", hl, "# ", escape(base(item.tab, item.limit)) }
      for _, mark in ipairs(M.marks(item.tab)) do
        parts[#parts + 1] = "%#" .. mark.hl .. "#" .. mark.text
      end
      parts[#parts + 1] = "%#" .. hl .. "# %X"
      out[#out + 1] = table.concat(parts)
    elseif item.kind == "new" then
      out[#out + 1] = click(0) .. "%#ClaudinhoTabNew#" .. item.text .. "%X"
    elseif item.kind == "sep" then
      out[#out + 1] = "%#ClaudinhoTabFill#" .. item.text
    else
      out[#out + 1] = "%#ClaudinhoTabFill#" .. item.text
    end
  end
  out[#out + 1] = "%#ClaudinhoTabFill#"
  return table.concat(out)
end

---Click handler of the winbar regions: the left button only. `minwid` 0 is the `+`.
---@param minwid integer
---@param _clicks integer
---@param button string
---@param _mods string
function M.click(minwid, _clicks, button, _mods)
  if button ~= "l" then
    return
  end
  local sessions = require("claudinho.sessions")
  if minwid == 0 then
    sessions.new()
  else
    sessions.activate(minwid)
  end
end

---Expose the click handler as the global the winbar regions call. Called once by the window code.
function M.install_click_handler()
  _G[M.CLICK_FUNC] = M.click
end

return M
