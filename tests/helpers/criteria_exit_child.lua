--- Child Neovim of tests/integration/criteria_exit_spec.lua: the real plugin with three tabs (the stub `claude` as the
--- command), driven from the main loop by files in a folder shared with the spec. Run as
--- `nvim --headless --clean -i NONE -c "luafile <this file>"` with a cleared environment that holds CLAUDINHO_REPO,
--- CLAUDINHO_ROOT, CLAUDINHO_SCENARIO ("qa", "wqa" or "quit_last"), CLAUDINHO_TERMINAL_CMD, HOME, CLAUDE_CONFIG_DIR and
--- TMPDIR.
---
--- Files in CLAUDINHO_ROOT: `info.json` (written when the three tabs run: ports, tokens, pids, settings paths),
--- `pending` (written once tab 1 holds a waiting diff) and `go` (written by the spec: run the exit command). Reaching
--- the line after the exit command writes `still-here`; the spec reads the exit code of the process.
vim.opt.runtimepath:prepend(vim.env.CLAUDINHO_REPO)

local root = vim.env.CLAUDINHO_ROOT
local scenario = vim.env.CLAUDINHO_SCENARIO

---@param name string
---@param text string
local function write(name, text)
  local file = assert(io.open(root .. "/" .. name, "w"))
  file:write(text)
  file:close()
end

---@param name string
---@return boolean
local function exists(name)
  return vim.uv.fs_stat(root .. "/" .. name) ~= nil
end

local plugin = require("claudinho")
plugin.setup({
  terminal_cmd = vim.env.CLAUDINHO_TERMINAL_CMD,
  port_range = { min = 20000, max = 40000 },
  env = { HOME = vim.env.HOME, CLAUDE_CONFIG_DIR = vim.env.CLAUDE_CONFIG_DIR },
  notify = false,
})
local sessions = require("claudinho.sessions")

-- A file the editor window shows. With :wqa it is modified, so the command has something to write.
local note = root .. "/note.txt"
vim.fn.writefile({ "one" }, note)
vim.cmd("edit " .. vim.fn.fnameescape(note))
local editor = vim.api.nvim_get_current_win()
if scenario == "wqa" then
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one", "changed" })
end

local info = { tabs = {} }
for number = 1, 3 do
  local tab = assert(sessions.new())
  info.tabs[number] = {
    port = tab.lock_port,
    token = tab.token,
    pid = vim.b[tab.buf].terminal_job_pid,
    settings_path = tab.settings_path,
  }
end
write("info.json", vim.json.encode(info))

local timer = assert(vim.uv.new_timer())
local wrote_pending = false
local went = false
timer:start(
  0,
  20,
  vim.schedule_wrap(function()
    if went then
      return
    end
    local first = sessions.state.tabs[1]
    if not wrote_pending and first and #first.pending_diffs > 0 then
      wrote_pending = true
      write("pending", tostring(#first.pending_diffs))
    end
    if not exists("go") then
      return
    end
    went = true
    timer:stop()
    timer:close()
    -- The user types an Ex command in Normal mode, not in the terminal of a tab.
    vim.cmd("stopinsert")
    if scenario == "quit_last" then
      -- The Claude window is on the right, so the editor window is the last one besides it.
      vim.api.nvim_set_current_win(editor)
      vim.cmd("quit")
    elseif scenario == "wqa" then
      vim.cmd("wqa")
    else
      vim.cmd("qa")
    end
    -- Reaching this line means Neovim did not leave.
    write("still-here", "x")
    vim.cmd("cquit 3")
  end)
)
