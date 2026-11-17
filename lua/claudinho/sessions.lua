---@brief [[
--- The Claude tabs: the registry of sessions, which one is active, who a selection or a client belongs to, and how
--- they all end. A tab is a `claudinho.session`; this module owns the numbers, the active tab and the order of the
--- bar, and tells the window to redraw. It does not draw anything itself.
---@brief ]]
---@module 'claudinho.sessions'

local logger = require("claudinho.logger")
local notify = require("claudinho.notify")

local M = {}

---@type ClaudinhoSessionsState
M.state = { tabs = {}, active = nil, by_server = {} }

local AUGROUP = "ClaudinhoSessions"

---The reply of a command that needs a tab when there is none.
M.NO_TABS = "No Claude tabs open"

---The reply of a send to a tab whose process ended (spec section 4).
---@param s ClaudinhoSession
---@return string
function M.exited_message(s)
  return ("Claude %d has exited; run :Claudinho tab-restart %d"):format(s.number, s.number)
end

---@param n integer
---@return string
local function label(n)
  return "Claude " .. n
end

---The window module (Task 10). Without it nothing is drawn.
---@return table|nil
local function window()
  local ok, win = pcall(require, "claudinho.ui.window")
  if ok and type(win) == "table" then
    return win
  end
  return nil
end

---Ask the window to draw the bar and the status line again. The window knows whether it is visible.
local function redraw()
  local win = window()
  if win and type(win.refresh) == "function" then
    win.refresh()
  end
end

---The tab numbers, in order.
---@return integer[]
local function numbers()
  local list = {}
  for n in pairs(M.state.tabs) do
    list[#list + 1] = n
  end
  table.sort(list)
  return list
end

---@return integer The lowest number from 1 that no tab has
local function free_number()
  local n = 1
  while M.state.tabs[n] do
    n = n + 1
  end
  return n
end

---The configuration of the running plugin, or the defaults before `setup`.
---@return ClaudinhoConfig
local function plugin_config()
  local plugin = package.loaded["claudinho"]
  local config = type(plugin) == "table" and type(plugin.state) == "table" and plugin.state.config or nil
  return config or require("claudinho.config").defaults
end

---The path format of an @-mention, as the plugin does it, read when used because setup and tests replace it.
---@param file_path string
---@return string formatted
---@return boolean is_dir
local function format_path(file_path)
  local plugin = package.loaded["claudinho"]
  if type(plugin) == "table" and type(plugin._format_path_for_at_mention) == "function" then
    return plugin._format_path_for_at_mention(file_path)
  end
  return file_path, false
end

---Map the server of a tab to its number, so a client is found back (rule 63).
---@param s ClaudinhoSession
local function register_server(s)
  for id, n in pairs(M.state.by_server) do
    if n == s.number then
      M.state.by_server[id] = nil
    end
  end
  if s.server and s.server.id ~= nil then
    M.state.by_server[s.server.id] = s.number
  end
end

---@param s ClaudinhoSession
---@return boolean
local function owns(s)
  return type(s) == "table" and M.state.tabs[s.number] == s
end

---Resume the coroutine of a waiting diff. The tool call it belongs to has already been answered "deferred" by the
---server, so when the handler ends on this resume (a rejected diff, or a diff that resolved at once) the response goes
---out through the sender the server left for it. A handler that yields again waits for the user, as `openDiff` does.
---@param co thread
---@param verdict "open"|"reject"
---@return boolean ok
---@return any err
local function resume_waiting(co, verdict)
  local ok, value, err = coroutine.resume(co, verdict)
  if coroutine.status(co) == "dead" then
    local senders = _G.claude_deferred_responses
    local key = tostring(co)
    local send = type(senders) == "table" and senders[key] or nil
    if send then
      senders[key] = nil
      local response = require("claudinho.tools.init").build_response(ok, value, err)
      send(response.error and response or response.result)
    end
  end
  return ok, ok and nil or value
end

---Answer "reject" to the diffs of a tab that wait for it to become active, and forget them.
---@param s ClaudinhoSession
---@return integer count
local function reject_waiting(s)
  local waiting = s.pending_diffs
  s.pending_diffs = {}
  local count = 0
  for _, pending in ipairs(waiting) do
    if type(pending.co) == "thread" and coroutine.status(pending.co) == "suspended" then
      local ok, err = resume_waiting(pending.co, "reject")
      if ok then
        count = count + 1
      else
        logger.error("sessions", "A waiting diff of " .. label(s.number) .. " failed to reject: " .. tostring(err))
      end
    end
  end
  return count
end

---Resume, in the order they arrived, the diffs that waited for this tab to become active (rule 31).
---@param s ClaudinhoSession
local function open_pending(s)
  while s.pending_diffs[1] do
    local pending = table.remove(s.pending_diffs, 1)
    if type(pending.co) == "thread" and coroutine.status(pending.co) == "suspended" then
      local ok, err = resume_waiting(pending.co, "open")
      if not ok then
        logger.error("sessions", "A pending diff of " .. label(s.number) .. " failed to open: " .. tostring(err))
      end
    end
  end
end

---Make a tab the active one: the selection goes to it, its waiting diffs open, the bar is drawn again.
---@param n integer
local function set_active(n)
  local s = M.state.tabs[n]
  local previous = M.state.active
  M.state.active = n
  if previous ~= n then
    -- A module that is not loaded has no selection to send.
    local selection = package.loaded["claudinho.selection"]
    if type(selection) == "table" and type(selection.resend_latest) == "function" then
      selection.resend_latest()
    end
  end
  open_pending(s)
  redraw()
end

---Start a new tab with the lowest free number, in the current folder of the window. On success it becomes the active
---tab and the window shows it. On failure nothing is left and the error is shown.
---@param extra_args string|nil Arguments for the command, with a leading space, already shell-escaped
---@return ClaudinhoSession|nil session
---@return string|nil error
function M.new(extra_args)
  local n = free_number()
  local s = require("claudinho.session").new(n, plugin_config(), { format_path = format_path })
  local ok, err = require("claudinho.session").start(s, extra_args)
  if not ok then
    err = err or ("Could not start " .. label(n))
    notify.error(err)
    return nil, err
  end
  M.state.tabs[n] = s
  register_server(s)
  set_active(n)
  local win = window()
  if win and type(win.show) == "function" then
    win.show({ focus = true })
  end
  return s
end

---Make tab `n` the active one.
---@param n integer
---@return boolean ok
---@return string|nil error
function M.activate(n)
  if not M.state.tabs[n] then
    local err = "No " .. label(tonumber(n) or 0)
    notify.reply(err)
    return false, err
  end
  if M.state.active == n then
    redraw()
    return true
  end
  set_active(n)
  return true
end

---Make the tab after (`step` 1) or before (`step` -1) the active one active, going round. With one tab or none, nothing.
---@param step integer
local function move(step)
  local list = numbers()
  if #list <= 1 then
    return
  end
  local index = 1
  for i, n in ipairs(list) do
    if n == M.state.active then
      index = i
      break
    end
  end
  set_active(list[(index - 1 + step) % #list + 1])
end

function M.next()
  move(1)
end

function M.prev()
  move(-1)
end

---Close tab `n`: its diffs, process, server and files end, and the bar loses it. The tab with the next higher number
---becomes active, else the next lower one; with none left the window closes.
---@param n integer
---@return boolean ok
---@return string|nil error
function M.close(n)
  local s = M.state.tabs[n]
  if not s then
    local err = "No " .. label(tonumber(n) or 0)
    notify.reply(err)
    return false, err
  end
  if s.closing then
    return true
  end
  -- The neighbour that takes over: the next higher number, else the next lower one.
  local after, before
  for _, number in ipairs(numbers()) do
    if number > n and not after then
      after = number
    elseif number < n then
      before = number
    end
  end
  local next_active = after or before

  -- The window stops showing the buffer that is about to go, and shows the neighbour's.
  local win = window()
  if win and type(win.release) == "function" and M.state.active == n then
    local neighbour = next_active and M.state.tabs[next_active]
    win.release(s.buf, neighbour and neighbour.buf or nil)
  end

  require("claudinho.session").close(s, "tab closed")
  M.state.tabs[n] = nil
  for id, number in pairs(M.state.by_server) do
    if number == n then
      M.state.by_server[id] = nil
    end
  end

  if M.state.active == n then
    if next_active then
      set_active(next_active)
    else
      M.state.active = nil
      if win and type(win.close) == "function" then
        win.close()
      end
    end
  else
    redraw()
  end
  return true
end

---Start again a tab whose process ended.
---@param n integer|nil
---@return boolean ok
---@return string|nil error
function M.restart(n)
  if type(n) ~= "number" then
    local err = "tab-restart needs a tab number"
    notify.reply(err)
    return false, err
  end
  local s = M.state.tabs[n]
  if not s then
    local err = "No " .. label(n)
    notify.reply(err)
    return false, err
  end
  -- The new buffer takes the old one's place in the window, which `winfixbuf` would refuse.
  local win = window()
  if win and type(win.unlock) == "function" then
    win.unlock()
  end
  local ok, err = require("claudinho.session").restart(s)
  if not ok then
    redraw()
    err = err or ("Could not start " .. label(n))
    if s.state == "running" then
      notify.reply(err)
    else
      notify.error(err)
    end
    return false, err
  end
  register_server(s)
  redraw()
  return true
end

---Answer "reject" to the diffs that wait for a tab to become active, in every tab. The open diffs are not touched.
---@param _reason string|nil Why, for the caller's log
---@return integer count
function M.reject_all_pending(_reason)
  local count = 0
  for _, n in ipairs(numbers()) do
    count = count + reject_waiting(M.state.tabs[n])
  end
  if count > 0 then
    redraw()
  end
  return count
end

---Decide what an `openDiff` of a client does now (rules 31 and 32). A client of the active tab, or of no tab, goes on
---at once. A client of a tab in the background is put in the tab's list, the bar marks it, one notification says so,
---and the tool call waits (it must run in a coroutine) until the tab is activated ("open") or the diff is dropped
---("reject").
---@param client table|nil
---@param params { tab_name: string, new_file_path: string }
---@return "open"|"reject" verdict
function M.gate_diff(client, params)
  local s = M.for_client(client)
  if not s or M.state.active == s.number or s.closing then
    return "open"
  end
  local co, is_main = coroutine.running()
  if not co or is_main then
    return "open"
  end
  local path = params.new_file_path
  s.pending_diffs[#s.pending_diffs + 1] = { tab_name = params.tab_name, path = path, co = co }
  notify.info(("%s: pending diff for %s"):format(label(s.number), vim.fn.fnamemodify(path, ":~:.")))
  redraw()
  return coroutine.yield() == "reject" and "reject" or "open"
end

---Reject every diff, open and waiting, and wait for the answers to leave the servers. The sessions stay alive.
---@param reason string
local function reject_diffs(reason)
  local diff = package.loaded["claudinho.diff"]
  if type(diff) == "table" and type(diff.close_pending_diffs) == "function" then
    diff.close_pending_diffs(reason)
  end
  M.reject_all_pending(reason)
  local drain_ms = require("claudinho.session").DRAIN_MS
  for _, n in ipairs(numbers()) do
    local server = M.state.tabs[n].server
    if server then
      server:drain(drain_ms)
    end
  end
end

---End every tab: the diffs are rejected, the servers drained, the sessions closed and the window closed. It touches
---only the tabs of this module (rule 61).
function M.kill_all()
  reject_diffs("all tabs closed")
  -- The window lets go of the buffer it shows first: a buffer fixed to a window would stop its deletion.
  local win = window()
  local active = M.active()
  if win and active and type(win.release) == "function" then
    win.release(active.buf, nil)
  end
  local session = require("claudinho.session")
  for _, n in ipairs(numbers()) do
    session.close(M.state.tabs[n], "all tabs closed")
  end
  M.state.tabs = {}
  M.state.by_server = {}
  M.state.active = nil
  if win and type(win.close) == "function" then
    win.close()
  end
end

---@return ClaudinhoSession|nil The active tab
function M.active()
  if M.state.active then
    return M.state.tabs[M.state.active]
  end
  return nil
end

---The tab that owns the server a client connected to. A client from outside, connected through `/ide`, counts as the
---tab's (rule 63).
---@param client table|nil
---@return ClaudinhoSession|nil
function M.for_client(client)
  local server = require("claudinho.server.init").for_client(client)
  if not server then
    return nil
  end
  local n = M.state.by_server[server.id]
  return n and M.state.tabs[n] or nil
end

---The status data of a tab changed.
---@param s ClaudinhoSession
function M.on_change(s)
  if owns(s) then
    redraw()
  end
end

---The process of a tab ended without `close`.
---@param s ClaudinhoSession
function M.on_exit(s)
  if not owns(s) then
    return
  end
  for id, number in pairs(M.state.by_server) do
    if number == s.number then
      M.state.by_server[id] = nil
    end
  end
  notify.info(label(s.number) .. " exited")
  redraw()
end

---What the selection tracking sends through: only the server of the active tab, when it runs. Anything else gets
---`false`, and the selection stays known for the next tab (rule 29).
---@type ClaudinhoSelectionRouter
M.router = {
  broadcast = function(method, params, on_written)
    local s = M.active()
    if s and s.state == "running" and s.server then
      return s.server:broadcast(method, params, on_written)
    end
    return false
  end,
}

---The tab whose buffer is `buf`.
---@param buf integer
---@return integer|nil
local function tab_of_buffer(buf)
  for n, s in pairs(M.state.tabs) do
    if s.buf == buf then
      return n
    end
  end
  return nil
end

---The autocmds that end the tabs with Neovim and with their buffers (rule 46). Calling it again replaces them.
function M.setup_autocmds()
  local group = vim.api.nvim_create_augroup(AUGROUP, { clear = true })
  -- `ExitPre` comes before Neovim leaves, while the sessions are alive: the diffs answer and the writes go out.
  vim.api.nvim_create_autocmd("ExitPre", {
    group = group,
    callback = function()
      reject_diffs("Neovim exiting")
    end,
  })
  -- The rest of the end: processes, servers, lock files and settings files.
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      M.kill_all()
    end,
  })
  -- `:bdelete` or `:bwipeout` of the buffer of a tab closes the tab; `closing` stops the loop when `close` itself
  -- deletes the buffer.
  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = group,
    callback = function(args)
      local n = tab_of_buffer(args.buf)
      if n and not M.state.tabs[n].closing then
        M.close(n)
      end
    end,
  })
end

return M
