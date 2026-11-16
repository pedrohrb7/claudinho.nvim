---@brief HTTP POST routes of the server: the relay of a session posts the status line and the hook JSON here.
--- A POST client never becomes a WebSocket client. The answer goes out from the libuv callback, with no
--- `vim.schedule`, so the relay ends fast while Neovim is busy; `on_post` is the only thing the caller schedules.
local client_manager = require("claudinho.server.client")
local utils = require("claudinho.server.utils")

local M = {}

M.MAX_HEADER_BYTES = 8 * 1024
M.MAX_BODY_BYTES = 1024 * 1024
M.TOKEN_HEADER = "x-claudinho-token"

---@type table<string, "statusline"|"hook">
local ROUTES = {
  ["/claudinho/statusline"] = "statusline",
  ["/claudinho/hook"] = "hook",
}

local STATUS_TEXT = {
  [204] = "No Content",
  [400] = "Bad Request",
  [401] = "Unauthorized",
  [404] = "Not Found",
  [413] = "Payload Too Large",
}

---@class HttpContext
---@field token string|nil Token the request must carry; nil accepts any request (a server started without one)
---@field on_post fun(kind: "statusline"|"hook", body: string)|nil
---@field on_done fun(client: WebSocketClient)|nil Called once the client has its answer and the socket is closing

---Build an HTTP response. A 204 has no body and no length.
---@param status integer
---@return string
function M.create_response(status)
  local lines = { "HTTP/1.1 " .. status .. " " .. (STATUS_TEXT[status] or "Error"), "Connection: close" }
  if status ~= 204 then
    local message = STATUS_TEXT[status] or "Error"
    table.insert(lines, "Content-Type: text/plain")
    table.insert(lines, "Content-Length: " .. #message)
    table.insert(lines, "")
    table.insert(lines, message)
    return table.concat(lines, "\r\n")
  end
  table.insert(lines, "")
  table.insert(lines, "")
  return table.concat(lines, "\r\n")
end

---Write the answer and close the socket once it is written. Nothing more is read from the client.
---@param client WebSocketClient
---@param ctx HttpContext
---@param status integer
local function finish(client, ctx, status)
  client.buffer = ""
  client.state = "closing"
  client.http = { done = true }
  local function close()
    if not client.tcp_handle:is_closing() then
      client.tcp_handle:close()
    end
  end
  local queued = client_manager.write(client, M.create_response(status), close)
  if not queued then
    close()
  end
  if ctx.on_done then
    ctx.on_done(client)
  end
end

---Take the bytes that `client.buffer` holds so far. Call it on each read of an HTTP client.
---@param client WebSocketClient
---@param ctx HttpContext
function M.handle(client, ctx)
  local state = client.http
  if state and state.done then
    client.buffer = ""
    return
  end

  if not state then
    local header_end = client.buffer:find("\r\n\r\n", 1, true)
    if not header_end then
      if #client.buffer > M.MAX_HEADER_BYTES then
        finish(client, ctx, 400)
      end
      return
    end
    if header_end + 3 > M.MAX_HEADER_BYTES then
      finish(client, ctx, 400)
      return
    end

    local head = client.buffer:sub(1, header_end + 3)
    local method, path = head:match("^(%S+)%s+(%S+)%s+HTTP/1%.[01]\r\n")
    local kind = method == "POST" and ROUTES[path] or nil
    if not kind then
      finish(client, ctx, 404)
      return
    end

    local headers = utils.parse_http_headers(head)
    if ctx.token and not utils.constant_time_compare(headers[M.TOKEN_HEADER], ctx.token) then
      finish(client, ctx, 401)
      return
    end

    local length_text = headers["content-length"]
    if not length_text or not length_text:match("^%d+$") then
      finish(client, ctx, 400)
      return
    end
    local length = tonumber(length_text)
    if length > M.MAX_BODY_BYTES then
      finish(client, ctx, 413)
      return
    end

    state = { kind = kind, length = length, body_start = header_end + 4 }
    client.http = state
  end

  if #client.buffer - state.body_start + 1 < state.length then
    return
  end

  local body = client.buffer:sub(state.body_start, state.body_start + state.length - 1)
  local kind = state.kind
  finish(client, ctx, 204)
  if ctx.on_post then
    -- A failing callback must not break the connection handler: the answer is out already.
    pcall(ctx.on_post, kind, body)
  end
end

return M
