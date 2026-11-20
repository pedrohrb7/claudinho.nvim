---@brief [[
--- The one usage value of the plugin (the 5 hour and 7 day limits of the account). Claude Code sends it in the status
--- line JSON of every session, and it is the same for all of them, so the plugin keeps a single copy here: the last one
--- that arrived, from any tab. The plugin never computes usage; it only drops a window whose reset time has passed.
---
--- The value lives only in memory: it never goes to disk, a log, a lock file or another session. Closing tabs or
--- killing the sessions does not touch it; `stop()` (VimLeavePre) only stops the clock.
---
--- The clock is a repeating `vim.uv` timer that compares the wall clock with each `resets_at`. A one-shot timer until
--- the reset would drift after a suspend, because libuv timers use the monotonic clock, which does not advance while
--- the computer sleeps.
---@brief ]]

---@class ClaudinhoUsageValue
---@field five_hour ClaudinhoUsageWindow|nil
---@field seven_day ClaudinhoUsageWindow|nil

local M = {}

M.TICK_MS = 500

---@type { value: ClaudinhoUsageValue|nil, timer: uv.uv_timer_t|nil }
M.state = { value = nil, timer = nil }

local KEYS = { "five_hour", "seven_day" }

---Wall clock in seconds with a fraction. Replaceable in tests.
---@return number
function M.now()
  local t = vim.uv.clock_gettime("realtime")
  return t.sec + t.nsec / 1e9
end

---Creates the clock timer. Replaceable in tests.
---@return uv.uv_timer_t|nil
function M.new_timer()
  return vim.uv.new_timer()
end

---@param a ClaudinhoUsageWindow|nil
---@param b ClaudinhoUsageWindow|nil
---@return boolean
local function same_window(a, b)
  if a == nil or b == nil then
    return a == b
  end
  return a.used == b.used and a.resets_at == b.resets_at
end

---@param a ClaudinhoUsageValue|nil
---@param b ClaudinhoUsageValue|nil
---@return boolean
local function same_value(a, b)
  if a == nil or b == nil then
    return a == b
  end
  for _, key in ipairs(KEYS) do
    if not same_window(a[key], b[key]) then
      return false
    end
  end
  return true
end

---@param value ClaudinhoUsageValue|nil
---@param now number
---@return boolean
local function has_future_reset(value, now)
  if value == nil then
    return false
  end
  for _, key in ipairs(KEYS) do
    local w = value[key]
    if w and w.resets_at and w.resets_at > now then
      return true
    end
  end
  return false
end

local function stop_timer()
  local timer = M.state.timer
  M.state.timer = nil
  if timer then
    pcall(timer.stop, timer)
    if not timer:is_closing() then
      timer:close()
    end
  end
end

---One clock tick: drops the windows that expired and redraws when one did.
local function tick()
  local value = M.state.value
  local now = M.now()
  local expired = false
  if value then
    for _, key in ipairs(KEYS) do
      local w = value[key]
      if w and w.resets_at and w.resets_at <= now then
        value[key] = nil
        expired = true
      end
    end
  end
  if expired then
    vim.schedule(function()
      require("claudinho.ui.window").refresh()
    end)
  end
  if not has_future_reset(value, now) then
    stop_timer()
  end
end

local function arm()
  if M.state.timer or not has_future_reset(M.state.value, M.now()) then
    return
  end
  local timer = M.new_timer()
  if not timer then
    return
  end
  M.state.timer = timer
  timer:start(M.TICK_MS, M.TICK_MS, tick)
end

---Replaces the whole value (a window missing from the new value is gone) and arms or stops the clock.
---`nil` means "absent in this POST": the value stays.
---@param value ClaudinhoUsageValue|nil
---@return boolean changed
function M.update(value)
  if value == nil then
    return false
  end
  local copy = {}
  for _, key in ipairs(KEYS) do
    local w = value[key]
    if w then
      copy[key] = { used = w.used, resets_at = w.resets_at }
    end
  end
  local changed = not same_value(M.state.value, copy)
  M.state.value = copy
  if has_future_reset(copy, M.now()) then
    arm()
  else
    stop_timer()
  end
  return changed
end

---The windows still valid at `now`: those without `resets_at` or with `resets_at > now`.
---@param now number|nil Epoch seconds; defaults to the wall clock
---@return ClaudinhoUsageValue
function M.windows(now)
  now = now or M.now()
  local out = {}
  local value = M.state.value
  if value then
    for _, key in ipairs(KEYS) do
      local w = value[key]
      if w and (w.resets_at == nil or w.resets_at > now) then
        out[key] = w
      end
    end
  end
  return out
end

---Stops the clock (VimLeavePre). The value stays.
function M.stop()
  stop_timer()
end

---Only for tests: stops the clock and clears the value.
function M.reset()
  stop_timer()
  M.state.value = nil
end

return M
