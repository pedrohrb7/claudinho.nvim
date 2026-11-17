-- Origin: coder/claudecode.nvim@d1237072, lua/claudecode/terminal.lua (MIT, see LICENSE)
---@brief [[
--- One Claude session, the content of one tab: its own WebSocket server, lock file, settings file and terminal job.
--- `start` builds all of it or nothing, `restart` starts a session whose process ended, and `close` takes everything
--- down. Nothing here knows about windows or the tab registry: it reports changes to `claudinho.sessions` (`on_change`
--- when the status data changed, `on_exit` when the process ended) when that module exists.
---@brief ]]
---@module 'claudinho.session'

local logger = require("claudinho.logger")

local M = {}

---How long `close` waits for the job to end before it deletes the buffer anyway (neovim/neovim#42508).
M.CLOSE_WAIT_MS = 1000

---How long `close` waits for the write queues of the clients to empty, so a rejection reaches them.
M.DRAIN_MS = 200

---@param session ClaudinhoSession
---@return string
local function label(session)
  return "Claude " .. session.number
end

---Tell `claudinho.sessions` about a change. The module comes with the tab registry: without it nothing happens.
---@param method "on_change"|"on_exit"
---@param session ClaudinhoSession
local function report(method, session)
  local ok, sessions = pcall(require, "claudinho.sessions")
  if ok and type(sessions) == "table" and type(sessions[method]) == "function" then
    sessions[method](session)
  elseif not ok then
    logger.debug("session", "claudinho.sessions is not available:", tostring(sessions))
  end
end

---Builds a no_proxy value that always excludes the loopback hosts, merging the existing values (comma-separated lists,
---nils allowed) in order and without duplicates. Claude must never proxy its loopback IDE connection (issue #70 of
---the upstream).
---@param ... string|nil
---@return string
local function no_proxy_with_loopback(...)
  local entries, seen = {}, {}

  local function add_entry(entry)
    entry = entry:gsub("^%s+", ""):gsub("%s+$", "")
    if entry ~= "" and not seen[entry] then
      seen[entry] = true
      entries[#entries + 1] = entry
    end
  end

  -- select() and not ipairs over {...}, so a nil source does not cut the rest.
  for i = 1, select("#", ...) do
    local value = select(i, ...)
    if type(value) == "string" then
      for entry in value:gmatch("[^,]+") do
        add_entry(entry)
      end
    end
  end
  for _, host in ipairs({ "localhost", "127.0.0.1", "::1" }) do
    add_entry(host)
  end
  return table.concat(entries, ",")
end

---The environment of the process of one tab. It goes only in the `env` of the job, never in `vim.env` (rule 62).
---@param port integer
---@param token string
---@param config table
---@return table<string, string>
local function build_env(port, token, config)
  local env = {
    CLAUDE_CODE_SSE_PORT = tostring(port),
    ENABLE_IDE_INTEGRATION = "true",
    FORCE_CODE_TERMINAL = "true",
    CLAUDINHO_PORT = tostring(port),
    CLAUDINHO_TOKEN = token,
  }
  for key, value in pairs(config.env or {}) do
    env[key] = value
  end
  -- Last, after the user's keys: the loopback exclusion must hold whatever the user or the shell set.
  local no_proxy = no_proxy_with_loopback(os.getenv("no_proxy"), os.getenv("NO_PROXY"), env.no_proxy, env.NO_PROXY)
  env.no_proxy = no_proxy
  env.NO_PROXY = no_proxy
  return env
end

---A new session, not started. Its folder is the current folder of the window, fixed from now on (rules 4 and 8).
---@param number integer
---@param config table The plugin configuration
---@param opts { format_path: (fun(file_path: string): string, boolean)|nil }|nil
---@return ClaudinhoSession
function M.new(number, config, opts)
  local base_cmd = config.terminal_cmd
  if type(base_cmd) ~= "string" or base_cmd == "" then
    base_cmd = "claude"
  end
  return {
    number = number,
    cwd = vim.fn.getcwd(),
    base_cmd = base_cmd,
    state = "exited",
    data = {},
    pending_diffs = {},
    closing = false,
    config = config,
    format_path = opts and opts.format_path or nil,
  }
end

---Stop the server, remove the lock file and the settings file of a session, and forget them. Each step is safe to
---repeat.
---@param session ClaudinhoSession
local function release(session)
  local server = session.server
  session.server = nil
  if server then
    local ok, err = pcall(server.stop, server)
    if not ok then
      logger.error("session", "Failed to stop the server of " .. label(session) .. ": " .. tostring(err))
    end
  end

  local port = session.lock_port
  session.lock_port = nil
  if port then
    local removed, err = require("claudinho.lockfile").remove(port)
    if not removed then
      logger.debug("session", "Lock file of " .. label(session) .. " not removed:", tostring(err))
    end
  end

  require("claudinho.session_settings").remove(session)
  session.token = nil
end

---Merge what a POST brought into `session.data`. A field the POST did not carry keeps its old value (rule 52).
---@param session ClaudinhoSession
---@param kind "statusline"|"hook"
---@param body string
local function apply_post(session, kind, body)
  if session.closing then
    return
  end
  local session_data = require("claudinho.sources.session_data")
  local decoded = session_data.decode(body)
  if not decoded then
    return
  end
  local fields = kind == "hook" and session_data.from_hook(decoded) or session_data.from_statusline(decoded)
  local changed = false
  for _, key in ipairs({ "session_id", "model", "effort", "mode" }) do
    local value = fields[key]
    if value ~= nil and session.data[key] ~= value then
      session.data[key] = value
      changed = true
    end
  end
  if changed then
    report("on_change", session)
  end
end

---The process of the session ended without `close`.
---@param session ClaudinhoSession
---@param job integer
---@param code integer
local function handle_exit(session, job, code)
  if session.closing or session.job ~= job then
    return
  end
  session.state = "exited"
  session.exit_code = code
  session.job = nil
  session.pid = nil
  if session.queue then
    session.queue:clear()
  end
  -- A diff that waits for the tab to become active has no client to answer any more: it is dropped. The open ones
  -- close with the client (the server's own cleanup), and `stop` closes what that left.
  session.pending_diffs = {}
  release(session)
  report("on_exit", session)
end

---A key typed in an ended terminal must not close its buffer (rule 39): a terminal buffer with no process starts no
---terminal mode.
---@param session ClaudinhoSession
---@param buf integer
local function guard_ended_terminal(session, buf)
  vim.api.nvim_create_autocmd("TermEnter", {
    group = vim.api.nvim_create_augroup("ClaudinhoSession", { clear = false }),
    buffer = buf,
    callback = function()
      if session.state == "exited" and session.buf == buf then
        vim.schedule(function()
          if vim.api.nvim_get_current_buf() == buf then
            vim.cmd.stopinsert()
          end
        end)
      end
    end,
  })
end

---Start the session: the server, the lock file, the settings file, the buffer and the job, or nothing at all. On
---failure everything that was made is undone, in the inverse order, and the session is as before.
---@param session ClaudinhoSession
---@param extra_args string|nil Arguments for the command, with a leading space, already shell-escaped
---@return boolean ok
---@return string|nil error
function M.start(session, extra_args)
  local lockfile = require("claudinho.lockfile")
  local utils = require("claudinho.utils")
  local config = session.config

  local argv = utils.parse_command(session.base_cmd)
  if #argv == 0 or vim.fn.executable(argv[1]) ~= 1 then
    return false,
      "Could not start " .. label(session) .. ": `" .. tostring(argv[1] or session.base_cmd) .. "` is not executable"
  end

  -- What was made so far, undone in the inverse order by `undo`.
  local made = { server = nil, lock_port = nil, settings = false, buf = nil, job = nil }

  local function undo(reason)
    if made.job then
      pcall(vim.fn.jobstop, made.job)
    end
    if made.buf and vim.api.nvim_buf_is_valid(made.buf) then
      pcall(vim.api.nvim_buf_delete, made.buf, { force = true })
    end
    if made.settings then
      require("claudinho.session_settings").remove(session)
    end
    if made.lock_port then
      lockfile.remove(made.lock_port)
    end
    if made.server then
      pcall(made.server.stop, made.server)
    end
    session.token = nil
    return false, reason
  end

  local token_ok, token = pcall(lockfile.generate_auth_token)
  if not token_ok then
    return false, "Could not start " .. label(session) .. ": " .. tostring(token)
  end

  local server = require("claudinho.server.init").new({
    on_open = function()
      -- The handshake runs in a libuv callback.
      vim.schedule(function()
        if session.queue and not session.closing then
          session.queue:on_open()
        end
      end)
    end,
    on_post = function(kind, body)
      -- The route answers inside the libuv callback; the state changes on the main loop.
      vim.schedule(function()
        apply_post(session, kind, body)
      end)
    end,
  })
  local started, port = server:start(config, token)
  if not started then
    return false, "Could not start " .. label(session) .. ": " .. tostring(port)
  end
  made.server = server
  -- A started server answers with its port; the error text is only for a failed start.
  ---@cast port integer

  local lock_ok, lock_result = lockfile.create(port, token, {
    ide_name = "Neovim (Claudinho " .. session.number .. ")",
    workspace_folders = lockfile.get_workspace_folders(session.cwd),
  })
  if not lock_ok then
    return undo("Could not start " .. label(session) .. ": " .. tostring(lock_result))
  end
  made.lock_port = port

  local settings_path, settings_err = require("claudinho.session_settings").write(session)
  if not settings_path then
    return undo("Could not start " .. label(session) .. ": " .. tostring(settings_err))
  end
  made.settings = true

  -- The command is run without a shell, so a bracketed model alias such as `opus[1m]` reaches Claude as it is.
  local cmd = {}
  for _, word in ipairs(argv) do
    table.insert(cmd, word)
  end
  table.insert(cmd, "--settings")
  table.insert(cmd, settings_path)
  if extra_args and extra_args ~= "" then
    for _, word in ipairs(utils.parse_command(extra_args)) do
      table.insert(cmd, word)
    end
  end

  local buf = vim.api.nvim_create_buf(false, false)
  made.buf = buf
  vim.bo[buf].bufhidden = "hide"
  vim.b[buf].claudinho_session = session.number

  local job
  local job_opts = {
    term = true,
    cwd = session.cwd,
    env = build_env(port, token, config),
    on_exit = function(job_id, code)
      vim.schedule(function()
        handle_exit(session, job_id, code)
      end)
    end,
  }
  -- pcall runs inside the callback, because nvim_buf_call wraps a raised error with a traceback.
  local call_ok, call_err = pcall(vim.api.nvim_buf_call, buf, function()
    local job_ok, result = pcall(vim.fn.jobstart, cmd, job_opts)
    job = job_ok and result or nil
    if not job_ok then
      error(tostring(result), 0)
    end
  end)
  if not call_ok then
    return undo("Could not start " .. label(session) .. ": " .. tostring(call_err))
  end
  if type(job) ~= "number" or job <= 0 then
    return undo("Could not start " .. label(session) .. ": the command did not start")
  end
  made.job = job
  if not vim.api.nvim_buf_is_valid(buf) then
    made.buf = nil
    return undo("Could not start " .. label(session) .. ": its buffer was deleted while it started")
  end

  vim.bo[buf].filetype = "claudinho"
  guard_ended_terminal(session, buf)

  local pid_ok, pid = pcall(vim.fn.jobpid, job)
  session.buf = buf
  session.job = job
  session.pid = pid_ok and pid or nil
  session.exit_code = nil
  session.state = "running"
  session.server = server
  session.token = token
  session.lock_port = port
  local Queue = require("claudinho.mention_queue")
  session.queue = Queue.new({
    server = server --[[@as ClaudinhoMentionServer]],
    config = config,
    format_path = session.format_path,
  })
  logger.debug("session", label(session) .. " started on port " .. tostring(port) .. ", job " .. tostring(job))
  return true
end

---Start again a session whose process ended, with the same number and folder, and a new server, token, port, lock file
---and settings file. With a session id from the status data, Claude resumes it.
---@param session ClaudinhoSession
---@return boolean ok
---@return string|nil error
function M.restart(session)
  if session.state ~= "exited" then
    return false, label(session) .. " is still running"
  end
  local old_buf = session.buf
  local session_id = session.data.session_id
  local extra = session_id and (" --resume " .. vim.fn.shellescape(session_id)) or nil
  local ok, err = M.start(session, extra)
  if not ok then
    return false, err
  end
  -- The new buffer takes the old one's place in every window, and the old one goes after the new job runs.
  if old_buf and old_buf ~= session.buf and vim.api.nvim_buf_is_valid(old_buf) then
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(win) == old_buf then
        pcall(vim.api.nvim_win_set_buf, win, session.buf)
      end
    end
    pcall(vim.api.nvim_buf_delete, old_buf, { force = true })
  end
  return true
end

---Close the session: reject its diffs, stop the job, the server and the files, and delete the buffer. Calling it again
---does nothing.
---@param session ClaudinhoSession
---@param reason string|nil Why it closes, for the log and for the diffs
function M.close(session, reason)
  if session.closing then
    return
  end
  session.closing = true
  reason = reason or "session closed"

  -- The diffs that wait for the tab to become active answer "reject" now (rule 34).
  local waiting = session.pending_diffs
  session.pending_diffs = {}
  for _, pending in ipairs(waiting) do
    if type(pending.co) == "thread" and coroutine.status(pending.co) == "suspended" then
      local ok, err = coroutine.resume(pending.co, "reject")
      if not ok then
        logger.error("session", "A waiting diff of " .. label(session) .. " failed to reject: " .. tostring(err))
      end
    end
  end

  -- The open diffs: rejected through their client, then the write queues empty so the answers leave.
  local server = session.server
  if server then
    local diff = package.loaded["claudinho.diff"]
    if diff then
      for _, client in ipairs(server:get_status().clients or {}) do
        if client.handshake_complete then
          diff.close_diffs_for_client(client.id, reason)
        end
      end
    end
    server:drain(M.DRAIN_MS)
  end

  if session.queue then
    session.queue:clear()
  end

  local buf, job = session.buf, session.job
  if job and buf and vim.api.nvim_buf_is_valid(buf) then
    -- Deleting a terminal buffer while a write to its job is pending hangs Neovim (neovim/neovim#42508), so the
    -- delete waits for the job to end. jobstop gives 0 for a job that already ended: TermClose has run then.
    local ended = false
    vim.api.nvim_create_autocmd("TermClose", {
      buffer = buf,
      once = true,
      callback = function()
        ended = true
      end,
    })
    if vim.fn.jobstop(job) == 1 then
      vim.wait(M.CLOSE_WAIT_MS, function()
        return ended or not vim.api.nvim_buf_is_valid(buf)
      end, 10)
    end
  end
  session.job = nil
  session.pid = nil
  session.state = "exited"

  release(session)

  session.buf = nil
  if buf and vim.api.nvim_buf_is_valid(buf) then
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end
  logger.debug("session", label(session) .. " closed:", reason)
end

return M
