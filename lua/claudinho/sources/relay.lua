---@brief [[
--- Relay script of a session: Claude Code runs it as the status line command and as a hook command, as
--- `nvim --clean -l <this file> <kind>`. It reads the JSON from stdin and posts it to the WebSocket server of its own
--- tab (`POST /claudinho/<kind>`, with the tab token), so the plugin learns the model, the effort and the mode.
---
--- It never fails: whatever happens, it exits with 0, and a `hook` writes nothing to stdout or stderr. It needs only the
--- Neovim that runs it (no other dependency). The tab's port and token come from `CLAUDINHO_PORT` and
--- `CLAUDINHO_TOKEN`, which only the process of the tab has.
---@brief ]]
---@module 'claudinho.sources.relay'
local M = {}

---The routes the server answers (server/http.lua).
M.KINDS = { statusline = true, hook = true }

---Longest wait for the answer, in milliseconds.
M.TIMEOUT_MS = 500

---Parse the port from the environment.
---@param value string|nil
---@return integer|nil port An integer from 1 to 65535, or nil
function M.parse_port(value)
  local port = tonumber(value)
  if not port or port ~= math.floor(port) or port < 1 or port > 65535 then
    return nil
  end
  return port
end

---Build the bytes of the POST. `Content-Length` counts bytes, not characters.
---@param kind string "statusline" or "hook"
---@param body string
---@param token string|nil The tab token; without one the header is left out
---@return string request
function M.build_request(kind, body, token)
  local lines = {
    "POST /claudinho/" .. kind .. " HTTP/1.1",
    "Host: 127.0.0.1",
    "Content-Type: application/json",
    "Content-Length: " .. #body,
    "Connection: close",
  }
  if token and token ~= "" then
    table.insert(lines, "X-Claudinho-Token: " .. token)
  end
  return table.concat(lines, "\r\n") .. "\r\n\r\n" .. body
end

---Connect to the tab server, send the request and wait for the answer or the end of the socket.
---@param port integer
---@param request string
---@return boolean done True when the server answered or closed in time
local function send(port, request)
  local uv = vim.uv or vim.loop
  local handle = uv.new_tcp()
  if not handle then
    return false
  end
  local done = false
  local function finish()
    done = true
  end
  handle:connect("127.0.0.1", port, function(connect_err)
    if connect_err then
      return finish()
    end
    handle:read_start(function(read_err, data)
      if read_err or data == nil then
        finish()
      end
    end)
    handle:write(request, function(write_err)
      if write_err then
        finish()
      end
    end)
  end)
  vim.wait(M.TIMEOUT_MS, function()
    return done
  end, 2)
  if not handle:is_closing() then
    handle:close()
  end
  return done
end

---@class ClaudinhoRelayDeps
---@field getenv fun(name: string): string|nil
---@field read_stdin fun(): string|nil
---@field write_stdout fun(text: string)
---@field send fun(port: integer, request: string): boolean

---@return ClaudinhoRelayDeps
local function default_deps()
  return {
    getenv = os.getenv,
    read_stdin = function()
      return io.read("*a")
    end,
    write_stdout = function(text)
      io.stdout:write(text)
      io.stdout:flush()
    end,
    send = send,
  }
end

---Run the relay once.
---@param kind string|nil "statusline" or "hook"; anything else does nothing
---@param deps ClaudinhoRelayDeps|nil Replaced in tests
---@return integer exit_code Always 0
function M.main(kind, deps)
  local merged = default_deps()
  for name, fn in pairs(deps or {}) do
    merged[name] = fn
  end
  deps = merged
  pcall(function()
    if not M.KINDS[kind] then
      return
    end
    local body = deps.read_stdin() or ""
    -- The status line shows what the command prints: an empty line, even when the relay fails after this point.
    if kind == "statusline" then
      deps.write_stdout("\n")
    end
    local port = M.parse_port(deps.getenv("CLAUDINHO_PORT"))
    if not port then
      return
    end
    deps.send(port, M.build_request(kind, body, deps.getenv("CLAUDINHO_TOKEN")))
  end)
  return 0
end

-- Run by `nvim --clean -l <this file> <kind>`: `...` is nil there and the argument is in `_G.arg[1]`. A `require`
-- gets the module name in `...` and only returns the module.
if select("#", ...) == 0 and _G.arg then
  os.exit(M.main(_G.arg[1]))
end

return M
