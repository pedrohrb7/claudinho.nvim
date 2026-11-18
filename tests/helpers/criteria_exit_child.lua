--- Child Neovim of tests/integration/criteria_exit_spec.lua: the real plugin with three tabs (the stub `claude` as the
--- command), driven from the main loop by files in a folder shared with the spec. Run as
--- `nvim --headless --clean -i NONE -c "luafile <this file>"` with a cleared environment that holds CLAUDINHO_REPO,
--- CLAUDINHO_ROOT, CLAUDINHO_SCENARIO (a key of `M.SCENARIOS` below), CLAUDINHO_TERMINAL_CMD, HOME, CLAUDE_CONFIG_DIR
--- and TMPDIR.
---
--- Files in CLAUDINHO_ROOT: `info.json` (written when the three tabs run: ports, tokens, pids, settings paths),
--- `pending` (written once a diff waits: in tab 1 in the background, or open in tab 3, the active one) and `go<N>`
--- (written by the spec: run step N of the scenario). A step that Neovim cancels (E37, E162, E948) writes
--- `step<N>.json` (the error, the state and job of each tab, the diffs, the file on disk) and the child waits for the
--- next `go`. A step that leaves ends the process. Reaching the line after a step that must leave writes `still-here`
--- and quits with code 3.
vim.opt.runtimepath:prepend(vim.env.CLAUDINHO_REPO)

local root = vim.env.CLAUDINHO_ROOT
local scenario_name = vim.env.CLAUDINHO_SCENARIO

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

local note = root .. "/note.txt"
vim.fn.writefile({ "one" }, note)

---The file of the editor window, changed, as the user leaves it.
---@return integer buf
local function edit_changed_note()
  vim.cmd("edit " .. vim.fn.fnameescape(note))
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one", "changed" })
  return vim.api.nvim_get_current_buf()
end

---A buffer with changes that Neovim writes through BufWriteCmd, as oil.nvim and fugitive do.
local function edit_acwrite()
  vim.cmd("edit " .. vim.fn.fnameescape(note))
  vim.bo.buftype = "acwrite"
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = 0,
    callback = function(args)
      vim.fn.writefile(vim.api.nvim_buf_get_lines(args.buf, 0, -1, false), note)
      vim.bo[args.buf].modified = false
    end,
  })
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one", "changed" })
end

---@class ExitStep
---@field cmd string Ex command, run in the editor window unless `anywhere`
---@field cancelled boolean|nil Neovim must refuse: the child writes `step<N>.json` and waits for the next `go`
---@field anywhere boolean|nil Run in the window that is current (the diff window, say)

---@class ExitScenario
---@field before_tabs fun()|nil
---@field after_tabs fun()|nil
---@field steps ExitStep[]
---@field diff_active boolean|nil The diff is open in tab 3, the active tab (the spec connects its client there)
local SCENARIOS = {
  -- Nothing holds changes: the exit goes on at once.
  qa = { steps = { { cmd = "qa" } } },
  quit_last = { steps = { { cmd = "quit" } } },
  -- A file with changes that is older than the tabs: `:wqa` writes it and stops once with E948, then leaves.
  wqa = { before_tabs = edit_changed_note, steps = { { cmd = "wqa", cancelled = true }, { cmd = "wqa" } } },
  -- The file comes after the terminals, so it is written after their jobs were looked at.
  wqa_file_after_tabs = {
    after_tabs = edit_changed_note,
    steps = { { cmd = "wqa", cancelled = true }, { cmd = "wqa" } },
  },
  xa = { after_tabs = edit_changed_note, steps = { { cmd = "xa", cancelled = true }, { cmd = "xa" } } },
  -- A write that spins the loop (a formatter on save, say).
  wqa_slow_write = {
    after_tabs = function()
      vim.api.nvim_create_autocmd("BufWritePre", {
        callback = function()
          vim.wait(50)
        end,
      })
      edit_changed_note()
    end,
    steps = { { cmd = "wqa", cancelled = true }, { cmd = "wqa" } },
  },
  wqa_acwrite = { after_tabs = edit_acwrite, steps = { { cmd = "wqa", cancelled = true }, { cmd = "wqa" } } },
  -- A diff is open in the active tab and its proposal buffer has changes: `:wqa` must not accept it.
  wqa_open_diff = {
    diff_active = true,
    after_tabs = edit_changed_note,
    steps = { { cmd = "wqa", cancelled = true }, { cmd = "wqa" } },
  },
  -- `:qa` and `:q` are cancelled by the changes, and `:qa!` leaves with them.
  cancelled_qa = {
    before_tabs = edit_changed_note,
    steps = { { cmd = "qa", cancelled = true }, { cmd = "qa!" } },
  },
  cancelled_quit_last = {
    before_tabs = edit_changed_note,
    steps = { { cmd = "quit", cancelled = true }, { cmd = "qa!" } },
  },
  -- Changes in a prompt buffer count for Neovim too.
  cancelled_prompt = {
    after_tabs = function()
      local buf = vim.api.nvim_create_buf(true, false)
      vim.bo[buf].buftype = "prompt"
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "typed" })
      vim.bo[buf].modified = true
    end,
    steps = { { cmd = "qa", cancelled = true }, { cmd = "qa!" } },
  },
  qa_bang = { before_tabs = edit_changed_note, steps = { { cmd = "qa!" } } },
  wqa_bang = { before_tabs = edit_changed_note, steps = { { cmd = "wqa!" } } },
  -- A terminal of the user's own that still runs: `:qa` leaves, and VimLeavePre ends the tabs.
  foreign_terminal_qa = {
    after_tabs = function()
      vim.cmd("new")
      vim.fn.jobstart({ "sleep", "30" }, { term = true })
      vim.cmd("stopinsert")
    end,
    steps = { { cmd = "qa" } },
  },
}

---@type ExitScenario
local scenario = assert(SCENARIOS[scenario_name], "unknown scenario " .. tostring(scenario_name))

if scenario.before_tabs then
  scenario.before_tabs()
else
  vim.cmd("edit " .. vim.fn.fnameescape(note))
end
local editor = vim.api.nvim_get_current_win()

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
if scenario.after_tabs then
  vim.api.nvim_set_current_win(editor)
  scenario.after_tabs()
  editor = vim.api.nvim_get_current_win()
end
write("info.json", vim.json.encode(info))

---@return string[] The status of every diff the diff module holds
local function diff_statuses()
  local diff = package.loaded["claudinho.diff"]
  local statuses = {}
  if diff and diff._get_active_diffs then
    for _, data in pairs(diff._get_active_diffs()) do
      statuses[#statuses + 1] = data.status
    end
  end
  table.sort(statuses)
  return statuses
end

---What the spec looks at after a step that Neovim refused.
---@param ok boolean
---@param err any
---@return string json
local function report(ok, err)
  local states, jobs_running = {}, {}
  for number = 1, 3 do
    local tab = sessions.state.tabs[number]
    states[number] = tab and tab.state or "gone"
    jobs_running[number] = tab ~= nil and tab.job ~= nil and vim.fn.jobwait({ tab.job }, 0)[1] == -1
  end
  local first_tab = sessions.state.tabs[1]
  local lines = vim.fn.filereadable(note) == 1 and vim.fn.readfile(note) or {}
  return vim.json.encode({
    left = ok,
    error = err and tostring(err) or nil,
    pending = first_tab and #first_tab.pending_diffs or 0,
    diffs = diff_statuses(),
    states = states,
    jobs_running = jobs_running,
    note = lines,
  })
end

local timer = assert(vim.uv.new_timer())
local wrote_pending = false
local step = 0
timer:start(
  0,
  20,
  vim.schedule_wrap(function()
    if not wrote_pending then
      local first = sessions.state.tabs[1]
      local waiting = scenario.diff_active and #diff_statuses() > 0 or (first and #first.pending_diffs > 0)
      if waiting then
        wrote_pending = true
        write("pending", "1")
      end
    end
    if not exists("go" .. (step + 1)) then
      return
    end
    step = step + 1
    local current = scenario.steps[step]
    -- The user types an Ex command in Normal mode, not in the terminal of a tab.
    vim.cmd("stopinsert")
    if not current.anywhere and vim.api.nvim_win_is_valid(editor) then
      vim.api.nvim_set_current_win(editor)
    end
    local ok, err = pcall(vim.cmd, current.cmd)
    if current.cancelled then
      -- Neovim is still here: tell the spec and wait for its next `go`.
      write("step" .. step .. ".json", report(ok, err))
      return
    end
    -- Reaching this line means Neovim did not leave.
    timer:stop()
    timer:close()
    write("still-here", report(ok, err))
    vim.cmd("cquit 3")
  end)
)
