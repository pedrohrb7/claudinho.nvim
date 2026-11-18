--- Child Neovim of tests/integration/session_exit_key_spec.lua: a real :Claudinho tab whose process ends on its own,
--- driven by the main loop (timers) because a typed key only reaches Neovim when a Lua call returns to it. It prints one
--- JSON line, prefixed with RESULT:, and quits. Run as `nvim --headless --clean -c "luafile <this file>"` (not -u: the script must run after startup, or the terminal window is not focused) with the environment
--- CLAUDINHO_REPO, CLAUDINHO_SCENARIO ("key", "wipe_ended" or "wipe_running"), CLAUDINHO_TERMINAL_CMD, HOME and
--- CLAUDE_CONFIG_DIR set.
vim.opt.runtimepath:prepend(vim.env.CLAUDINHO_REPO)

local scenario = vim.env.CLAUDINHO_SCENARIO
local result = { scenario = scenario }

---@param ms integer
---@param condition fun(): boolean
---@param next_step fun(ok: boolean)
local function wait_until(ms, condition, next_step)
  local waited = 0
  local timer = vim.uv.new_timer()
  timer:start(0, 20, function()
    waited = waited + 20
    vim.schedule(function()
      if timer:is_closing() then
        return
      end
      local ok = condition()
      if ok or waited >= ms then
        timer:stop()
        timer:close()
        next_step(ok)
      end
    end)
  end)
end

local function snapshot(buf)
  local sessions = require("claudinho.sessions")
  local tab = sessions.state.tabs[1]
  result.buf_valid = vim.api.nvim_buf_is_valid(buf)
  result.tab_exists = tab ~= nil
  result.tab_state = tab and tab.state or nil
  result.tab_buf_is_buf = tab ~= nil and tab.buf == buf
  result.shown = false
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == buf then
      result.shown = true
    end
  end
  result.messages = vim.api.nvim_exec2("messages", { output = true }).output
  result.errmsg = vim.v.errmsg
  result.mode = vim.api.nvim_get_mode().mode
end

local function finish()
  io.stdout:write("RESULT:" .. vim.json.encode(result) .. "\n")
  vim.cmd("qa!")
end

require("claudinho").setup({
  terminal_cmd = vim.env.CLAUDINHO_TERMINAL_CMD,
  env = { HOME = vim.env.HOME, CLAUDE_CONFIG_DIR = vim.env.CLAUDE_CONFIG_DIR },
})
vim.cmd("Claudinho")

local sessions = require("claudinho.sessions")
wait_until(5000, function()
  local tab = sessions.state.tabs[1]
  return tab ~= nil and tab.buf ~= nil and vim.api.nvim_get_current_buf() == tab.buf
end, function(shown)
  result.terminal_current = shown
  local buf = sessions.state.tabs[1] and sessions.state.tabs[1].buf or vim.api.nvim_get_current_buf()
  result.initial_buftype = vim.bo[buf].buftype
  result.initial_mode = vim.api.nvim_get_mode().mode

  if scenario == "wipe_running" then
    local wiped, wipe_err = pcall(vim.cmd, "bwipeout! " .. buf)
    result.wipe_ok, result.wipe_error = wiped, not wiped and tostring(wipe_err) or nil
    vim.defer_fn(function()
      snapshot(buf)
      finish()
    end, 500)
    return
  end

  wait_until(8000, function()
    local tab = sessions.state.tabs[1]
    return tab ~= nil and tab.state == "exited"
  end, function(ended)
    result.reached_exited = ended
    result.mode_at_exit = vim.api.nvim_get_mode().mode
    if scenario == "wipe_ended" then
      local wiped, wipe_err = pcall(vim.cmd, "bwipeout! " .. buf)
      result.wipe_ok, result.wipe_error = wiped, not wiped and tostring(wipe_err) or nil
    else
      vim.api.nvim_input("x")
    end
    vim.defer_fn(function()
      snapshot(buf)
      finish()
    end, 700)
  end)
end)
