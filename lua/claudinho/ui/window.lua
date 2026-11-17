-- Origin: coder/claudecode.nvim@d1237072, lua/claudecode/terminal/native.lua (MIT, see LICENSE)
---@brief [[
--- The Claude window: one per Neovim (rule 16). It shows the terminal buffer of the active tab, with the tab bar in
--- its winbar and the status of the tab in its statusline, in the layout of `config.window.layout` (`right`, `bottom`,
--- `float` or `tab`). Hiding it never ends a session (rule 23). `claudinho.sessions` tells it to `show`, `refresh`,
--- `release` and `close`; the window never owns a tab.
---@brief ]]
---@module 'claudinho.ui.window'

local logger = require("claudinho.logger")

local M = {}

---@type ClaudinhoWindowState
M.state = { win = nil, tabpage = nil, hidden_by_diff = false }

local AUGROUP = "ClaudinhoWindow"
local ready = false
local LAYOUTS = { right = true, bottom = true, float = true, tab = true }
local WINBAR = "%!v:lua.require'claudinho.ui.tabbar'.render()"
local STATUSLINE = "%!v:lua.require'claudinho.ui.status'.render()"

-- Geometry (pure) -----------------------------------------------------------------------------------------------

---@class ClaudinhoWindowEnv
---@field columns integer
---@field lines integer
---@field cmdheight integer|nil
---@field top integer|nil Rows taken above the editor area (the tabline)
---@field status integer|nil Rows taken below it (a global or always-shown statusline)

---@class ClaudinhoWindowGeometry
---@field width integer|nil
---@field height integer|nil
---@field row integer|nil
---@field col integer|nil

---@param value number
---@param low integer
---@param high integer
---@return integer
local function clamp(value, low, high)
  return math.max(low, math.min(high, value))
end

---Size and place of the window for a layout. `right` and `bottom` take their share of the whole screen, `float` is
---centered in the editor area (the screen less the command line, the tabline and the statusline), and `tab` takes the
---whole tab and needs no size.
---@param layout string
---@param env ClaudinhoWindowEnv
---@param window_config ClaudinhoWindowConfig
---@return ClaudinhoWindowGeometry
function M.geometry(layout, env, window_config)
  if layout == "bottom" then
    return { height = math.max(1, math.floor(env.lines * window_config.bottom.height)) }
  elseif layout == "float" then
    local top = env.top or 0
    local rows = math.max(1, env.lines - (env.cmdheight or 0) - top - (env.status or 0))
    local width = clamp(math.floor(env.columns * window_config.float.width), 1, env.columns)
    local height = clamp(math.floor(rows * window_config.float.height), 1, rows)
    return {
      width = width,
      height = height,
      col = math.floor((env.columns - width) / 2),
      row = top + math.floor((rows - height) / 2),
    }
  elseif layout == "tab" then
    return {}
  end
  return { width = math.max(1, math.floor(env.columns * window_config.right.width)) }
end

-- Helpers -------------------------------------------------------------------------------------------------------

---The configuration of the running plugin, or the defaults before `setup`.
---@return ClaudinhoConfig
local function plugin_config()
  local plugin = package.loaded["claudinho"]
  local config = type(plugin) == "table" and type(plugin.state) == "table" and plugin.state.config or nil
  return config or require("claudinho.config").defaults
end

---@return ClaudinhoWindowConfig
local function window_config()
  return plugin_config().window or require("claudinho.config").defaults.window
end

---The layout in use; an invalid value counts as `right` (the config already reported it).
---@return string
local function layout()
  local name = window_config().layout
  return LAYOUTS[name] and name or "right"
end

---@return ClaudinhoWindowEnv
local function current_env()
  local tabline = (vim.o.showtabline == 2 or (vim.o.showtabline == 1 and #vim.api.nvim_list_tabpages() > 1)) and 1 or 0
  local laststatus = vim.o.laststatus
  local status = 0
  if laststatus >= 2 then
    status = 1
  elseif laststatus == 1 and #vim.api.nvim_tabpage_list_wins(0) > 1 then
    status = 1
  end
  return { columns = vim.o.columns, lines = vim.o.lines, cmdheight = vim.o.cmdheight, top = tabline, status = status }
end

---The tab registry, loaded when used (it requires this module back).
---@return table
local function sessions()
  return require("claudinho.sessions")
end

---@return ClaudinhoSession|nil
local function active_session()
  local s = sessions().active()
  if s and s.buf and vim.api.nvim_buf_is_valid(s.buf) then
    return s
  end
  return nil
end

---The window, when it still exists. A window closed in any way (`:q`, `<C-w>c`, `:tabclose`) is a hidden one.
---@return integer|nil
local function valid_win()
  local win = M.state.win
  if win and vim.api.nvim_win_is_valid(win) then
    return win
  end
  M.state.win = nil
  M.state.tabpage = nil
  return nil
end

---@param win integer
---@param name string
---@param value any
local function set_wo(win, name, value)
  pcall(vim.api.nvim_set_option_value, name, value, { scope = "local", win = win })
end

---The local options of the window. They follow the buffer in Neovim, so they are applied again after every swap.
---@param win integer
local function apply_options(win)
  set_wo(win, "winbar", WINBAR)
  set_wo(win, "statusline", STATUSLINE)
  set_wo(win, "number", false)
  set_wo(win, "relativenumber", false)
  set_wo(win, "signcolumn", "no")
  set_wo(win, "foldcolumn", "0")
  set_wo(win, "winfixbuf", true)
end

---Put a buffer in the window. `winfixbuf` is off only for this swap, which is the plugin's own.
---@param win integer
---@param buf integer
local function set_buffer(win, buf)
  if vim.api.nvim_win_get_buf(win) ~= buf then
    set_wo(win, "winfixbuf", false)
    local ok, err = pcall(vim.api.nvim_win_set_buf, win, buf)
    if not ok then
      logger.error("window", "Cannot show the buffer of the active tab: " .. tostring(err))
    end
  end
  apply_options(win)
end

---Draw the winbar and the statusline of the window again, at once.
---@param win integer
local function redraw(win)
  local ok = pcall(vim.api.nvim__redraw, { win = win, winbar = true, statusline = true })
  if not ok then
    pcall(vim.cmd, "redrawstatus!")
  end
end

---@param win integer
---@return boolean
local function is_float(win)
  return vim.api.nvim_win_get_config(win).relative ~= ""
end

---Close a window the plugin owns. When it is the only window of the only Neovim tab, an empty tab opens first, so
---closing never ends Neovim.
---@param win integer
local function close_win(win)
  if not vim.api.nvim_win_is_valid(win) then
    return
  end
  if not is_float(win) and #vim.api.nvim_list_tabpages() == 1 then
    local count = 0
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(vim.api.nvim_win_get_tabpage(win))) do
      if not is_float(w) then
        count = count + 1
      end
    end
    if count <= 1 then
      vim.cmd("tabnew")
    end
  end
  local ok, err = pcall(vim.api.nvim_win_hide, win)
  if not ok then
    logger.error("window", "Cannot hide the Claude window: " .. tostring(err))
  end
end

---Open the window in the current layout, showing `buf`.
---@param buf integer
---@param focus boolean
---@return integer win
local function open_window(buf, focus)
  local name = layout()
  local geometry = M.geometry(name, current_env(), window_config())
  local origin_tab = vim.api.nvim_get_current_tabpage()
  local win
  if name == "float" then
    win = vim.api.nvim_open_win(buf, focus, {
      relative = "editor",
      width = geometry.width,
      height = geometry.height,
      row = geometry.row,
      col = geometry.col,
    })
  elseif name == "tab" then
    vim.cmd("tabnew")
    win = vim.api.nvim_get_current_win()
    -- The empty buffer that `tabnew` made goes when the terminal takes its place.
    vim.bo[vim.api.nvim_win_get_buf(win)].bufhidden = "wipe"
  elseif name == "bottom" then
    win = vim.api.nvim_open_win(buf, focus, { split = "below", win = -1, height = geometry.height })
    set_wo(win, "winfixheight", true)
  else
    win = vim.api.nvim_open_win(buf, focus, { split = "right", win = -1, width = geometry.width })
    set_wo(win, "winfixwidth", true)
  end
  M.state.win = win
  M.state.tabpage = vim.api.nvim_win_get_tabpage(win)
  set_buffer(win, buf)
  if name == "tab" and not focus and vim.api.nvim_tabpage_is_valid(origin_tab) then
    vim.api.nvim_set_current_tabpage(origin_tab)
  end
  return win
end

-- Public --------------------------------------------------------------------------------------------------------

---@return boolean visible A window shows the active tab (in any Neovim tab)
function M.is_visible()
  return valid_win() ~= nil
end

---@return boolean focused The cursor is in the Claude window
function M.is_focused()
  local win = valid_win()
  return win ~= nil and win == vim.api.nvim_get_current_win()
end

---@return integer|nil win
function M.win()
  return valid_win()
end

---Show the window with the active tab: only focus it when it is visible in the current Neovim tab, move it here when
---it is visible in another one (in the `tab` layout, go to its tab), open it when hidden. With `focus` and a running
---tab, `terminal.auto_insert` enters terminal mode (rule 24).
---@param opts { focus: boolean|nil }|nil
---@return boolean shown
function M.show(opts)
  opts = opts or {}
  M.setup()
  local s = active_session()
  if not s then
    return false
  end
  M.state.hidden_by_diff = false
  local focus = opts.focus == true

  local win = valid_win()
  if win and vim.api.nvim_win_get_tabpage(win) ~= vim.api.nvim_get_current_tabpage() then
    if layout() == "tab" then
      local origin_tab = vim.api.nvim_get_current_tabpage()
      vim.api.nvim_set_current_tabpage(vim.api.nvim_win_get_tabpage(win))
      if not focus then
        vim.api.nvim_set_current_tabpage(origin_tab)
      end
    else
      close_win(win)
      M.state.win = nil
      win = nil
    end
  end
  if not win then
    win = open_window(s.buf, focus)
  else
    set_buffer(win, s.buf)
  end

  if focus then
    vim.api.nvim_set_current_win(win)
    local terminal = s.config and s.config.terminal
    if s.state == "running" and not (terminal and terminal.auto_insert == false) then
      vim.cmd("startinsert")
    end
  end
  redraw(win)
  return true
end

---Hide the window. The sessions go on (rule 23).
function M.hide()
  local win = valid_win()
  if win then
    M.state.hidden_by_diff = false
    M.state.win = nil
    M.state.tabpage = nil
    close_win(win)
  end
end

---Hide the window for good: the last tab closed, or Neovim is leaving.
function M.close()
  M.state.hidden_by_diff = false
  M.hide()
end

---Hide when the window is in the current Neovim tab, show and focus otherwise (rule 19).
---@return boolean shown
function M.toggle()
  local win = valid_win()
  if win and vim.api.nvim_win_get_tabpage(win) == vim.api.nvim_get_current_tabpage() then
    M.hide()
    return false
  end
  return M.show({ focus = true })
end

---Show and focus the window; when it is already visible, just focus (rule 20).
---@return boolean shown
function M.open()
  return M.show({ focus = true })
end

---Show and focus when the window is hidden or out of focus; hide it when it has the focus (rule 22).
---@return boolean shown
function M.focus()
  if M.is_focused() then
    M.hide()
    return false
  end
  return M.show({ focus = true })
end

---Called by the diff when it closes: bring the window back when it was hidden, without taking focus, except when a
---diff hid it (rule 25), which only `toggle`, `open` or `focus` undo.
function M.ensure_visible()
  if M.state.hidden_by_diff or valid_win() then
    return
  end
  if sessions().active() then
    M.show({ focus = false })
  end
end

---Show the buffer of the active tab, apply the options again and draw the bar and the status. Called after the active
---tab, a title or the status changed. Without a visible window it only makes sure the autocmds exist.
function M.refresh()
  M.setup()
  local win = valid_win()
  if not win then
    return
  end
  local s = active_session()
  if s then
    set_buffer(win, s.buf)
  end
  redraw(win)
end

---Free the window of a buffer that is about to be deleted: it shows `fallback` (the buffer of the next tab), or closes
---when there is none. Deleting a buffer that a `winfixbuf` window shows would fail or close the window.
---@param buf integer|nil
---@param fallback integer|nil
function M.release(buf, fallback)
  local win = valid_win()
  if not win or not buf or vim.api.nvim_win_get_buf(win) ~= buf then
    return
  end
  if fallback and vim.api.nvim_buf_is_valid(fallback) then
    set_buffer(win, fallback)
  else
    M.close()
  end
end

---Let the plugin swap the buffer of the window (a restart puts a new buffer in it). `refresh` locks it again.
function M.unlock()
  local win = valid_win()
  if win then
    set_wo(win, "winfixbuf", false)
  end
end

---A tab's terminal title changed: keep the clean title and draw the bar again.
---@param buf integer
function M.update_title(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  for _, s in pairs(sessions().state.tabs) do
    if s.buf == buf then
      local ok, raw = pcall(function()
        return vim.b[buf].term_title
      end)
      s.title = ok and require("claudinho.ui.tabbar").clean_title(raw, { cmd = s.base_cmd }) or nil
      local win = valid_win()
      if win then
        redraw(win)
      end
      return
    end
  end
end

---Make the float fit the editor again after the screen changed size.
function M.resize()
  local win = valid_win()
  if not win or layout() ~= "float" then
    return
  end
  local geometry = M.geometry("float", current_env(), window_config())
  pcall(vim.api.nvim_win_set_config, win, {
    relative = "editor",
    width = geometry.width,
    height = geometry.height,
    row = geometry.row,
    col = geometry.col,
  })
end

---Whether another window than `current` and the Claude window shows an ordinary file, in any Neovim tab.
---@param current integer
---@return boolean
local function has_other_window(current)
  local claude = valid_win()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if win ~= current and win ~= claude and not is_float(win) then
      return true
    end
  end
  return false
end

---Link the tab bar groups, install the click handler and register the autocmds, once. `show` and `refresh` call it, so
---the title of a tab is followed from the moment its session exists.
function M.setup()
  if ready then
    return
  end
  ready = true
  local tabbar = require("claudinho.ui.tabbar")
  tabbar.setup_highlights()
  tabbar.install_click_handler()

  local group = vim.api.nvim_create_augroup(AUGROUP, { clear = true })
  -- A colorscheme that clears the highlights drops the default links.
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      tabbar.setup_highlights()
    end,
  })
  vim.api.nvim_create_autocmd("VimResized", {
    group = group,
    callback = function()
      M.resize()
    end,
  })
  -- `:q` on the last editor window: the Claude window goes first, so Neovim leaves and the exit rule applies (46).
  vim.api.nvim_create_autocmd("QuitPre", {
    group = group,
    callback = function()
      local win = valid_win()
      local current = vim.api.nvim_get_current_win()
      if win and win ~= current and not has_other_window(current) then
        M.close()
      end
    end,
  })
  -- A diff must not sit under a float (rule 25).
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "ClaudinhoDiffOpened",
    callback = function()
      local win = valid_win()
      if win and layout() == "float" then
        M.hide()
        M.state.hidden_by_diff = true
      end
    end,
  })
  -- The title comes with an OSC 0 or 2 sequence; Neovim stores it in `b:term_title` after the event.
  vim.api.nvim_create_autocmd("TermRequest", {
    group = group,
    callback = function(args)
      local sequence = type(args.data) == "table" and args.data.sequence or nil
      if type(sequence) ~= "string" or not sequence:find("^\27%][02];") then
        return
      end
      local buf = args.buf
      vim.schedule(function()
        M.update_title(buf)
      end)
    end,
  })
end

---Remove the autocmds and forget the window; `setup` works again afterwards. For tests and for a reload.
function M.teardown()
  pcall(vim.api.nvim_del_augroup_by_name, AUGROUP)
  ready = false
  M.state = { win = nil, tabpage = nil, hidden_by_diff = false }
end

return M
