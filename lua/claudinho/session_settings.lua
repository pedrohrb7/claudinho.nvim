---@brief [[
--- The settings file of a session, passed to Claude Code with `--settings`. It holds only `statusLine` and `hooks`
--- (SessionStart, UserPromptSubmit and Stop), each one running the relay script, which posts the JSON to the server of
--- the tab. The file lives in Neovim's own temporary folder (0700, deleted when Neovim exits) with mode 0600, never in
--- `~/.claude/` or in the project's `.claude/`.
---@brief ]]
---@module 'claudinho.session_settings'
local M = {}

---Events whose hook reports `session_id` and `permission_mode`.
M.HOOK_EVENTS = { "SessionStart", "UserPromptSubmit", "Stop" }

---The absolute path of the relay script.
---@return string
function M.relay_path()
  local source = debug.getinfo(1, "S").source:gsub("^@", "")
  local path = (source:match("^(.*)/[^/]*$") or ".") .. "/sources/relay.lua"
  if path:sub(1, 1) ~= "/" then
    path = vim.fn.fnamemodify(path, ":p")
  end
  return path
end

---Build the settings table.
---@param progpath string The Neovim binary
---@param relay string The relay script
---@return table settings Exactly `statusLine` and `hooks`
function M.build(progpath, relay)
  local base = vim.fn.shellescape(progpath) .. " --clean -l " .. vim.fn.shellescape(relay)
  local hooks = {}
  for _, event in ipairs(M.HOOK_EVENTS) do
    hooks[event] = { { hooks = { { type = "command", command = base .. " hook", async = true } } } }
  end
  return {
    statusLine = { type = "command", command = base .. " statusline" },
    hooks = hooks,
  }
end

---Write the settings file of a session and record its path in `session.settings_path`.
---@param session { number: integer, settings_path: string|nil }
---@return string|nil path
---@return string|nil error
function M.write(session)
  local uv = vim.uv or vim.loop
  local path = vim.fn.tempname() .. ".claudinho-" .. session.number .. ".json"
  local ok, json = pcall(vim.json.encode, M.build(vim.v.progpath, M.relay_path()))
  if not ok or type(json) ~= "string" then
    return nil, "Failed to encode the session settings: " .. tostring(json)
  end

  -- "wx" is O_CREAT | O_EXCL: it refuses an existing file or a link at this path. 384 is 0600.
  local fd, open_err = uv.fs_open(path, "wx", 384)
  if not fd then
    return nil, "Failed to create the session settings: " .. tostring(open_err)
  end
  local pos = 0
  while pos < #json do
    local written, write_err = uv.fs_write(fd, json:sub(pos + 1), pos)
    if type(written) ~= "number" or written <= 0 then
      uv.fs_close(fd)
      uv.fs_unlink(path)
      return nil, "Failed to write the session settings: " .. tostring(write_err or "short write")
    end
    pos = pos + written
  end
  uv.fs_close(fd)

  session.settings_path = path
  return path
end

---Delete the settings file of a session. It does nothing when there is none, and it deletes only a file this module
---writes (a name ending in `.claudinho-<n>.json`).
---@param session { settings_path: string|nil }
---@return boolean removed
function M.remove(session)
  local path = session.settings_path
  session.settings_path = nil
  if type(path) ~= "string" or not path:match("%.claudinho%-%d+%.json$") then
    return false
  end
  local uv = vim.uv or vim.loop
  local removed = uv.fs_unlink(path)
  return removed and true or false
end

return M
