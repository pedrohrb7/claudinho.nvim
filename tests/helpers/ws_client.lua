--- A small WebSocket client for real-Neovim specs: it connects to 127.0.0.1 over a real socket, upgrades with the auth
--- token, sends masked text frames and collects the text frames that come back. It needs `vim.uv` (real Neovim).
local frame = require("claudinho.server.frame")
local uv = vim.uv or vim.loop

local M = {}

---@class WsClient
---@field messages string[] Text messages received, in order
---@field upgraded boolean True once the 101 reply has arrived
---@field closed boolean True once the socket ended
local Client = {}
Client.__index = Client

---Connect and upgrade. Fails the caller's spec when the server does not answer in time.
---@param port integer
---@param token string|nil Sent as x-claude-code-ide-authorization
---@param timeout_ms integer|nil Default 2000
---@return WsClient
function M.connect(port, token, timeout_ms)
  local self = setmetatable({ messages = {}, upgraded = false, closed = false, _buffer = "" }, Client)
  local handle = assert(uv.new_tcp())
  self._handle = handle

  handle:connect("127.0.0.1", port, function(err)
    assert(not err, err)
    handle:read_start(function(read_err, data)
      if read_err or not data then
        self.closed = true
        return
      end
      self:_feed(data)
    end)
    local request = "GET / HTTP/1.1\r\nHost: 127.0.0.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
      .. "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n"
      .. (token and ("x-claude-code-ide-authorization: " .. token .. "\r\n") or "")
      .. "\r\n"
    handle:write(request)
  end)

  assert(
    vim.wait(timeout_ms or 2000, function()
      return self.upgraded
    end, 10),
    "the WebSocket upgrade did not finish"
  )
  return self
end

---@param data string
function Client:_feed(data)
  self._buffer = self._buffer .. data
  if not self.upgraded then
    local header_end = self._buffer:find("\r\n\r\n", 1, true)
    if not header_end then
      return
    end
    self.upgraded = self._buffer:sub(1, 12) == "HTTP/1.1 101"
    self._buffer = self._buffer:sub(header_end + 4)
  end
  while #self._buffer > 0 do
    local parsed, consumed = frame.parse_frame(self._buffer)
    if not parsed then
      return
    end
    self._buffer = self._buffer:sub(consumed + 1)
    if parsed.opcode == frame.OPCODE.TEXT then
      table.insert(self.messages, parsed.payload)
    end
  end
end

---Send one JSON-RPC message as a masked text frame.
---@param message table|string A table is encoded as JSON
function Client:send(message)
  local text = type(message) == "string" and message or vim.json.encode(message)
  self._handle:write(frame.create_frame(frame.OPCODE.TEXT, text, true, true))
end

---Wait for the next text message after the ones already taken.
---@param timeout_ms integer|nil Default 2000
---@return table|nil decoded The JSON of the message, or nil on timeout
function Client:next_message(timeout_ms)
  self._taken = self._taken or 0
  local ok = vim.wait(timeout_ms or 2000, function()
    return #self.messages > self._taken
  end, 10)
  if not ok then
    return nil
  end
  self._taken = self._taken + 1
  return vim.json.decode(self.messages[self._taken])
end

---Number of messages received that `next_message` has not returned yet.
---@return integer
function Client:pending()
  return #self.messages - (self._taken or 0)
end

function Client:close()
  if self._handle and not self._handle:is_closing() then
    self._handle:close()
  end
end

return M
