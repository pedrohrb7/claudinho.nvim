--- A raw HTTP POST for real-Neovim specs: it connects to 127.0.0.1, writes the request bytes and waits until the
--- server has answered and closed the socket. It needs `vim.uv` (real Neovim).
local uv = vim.uv or vim.loop

local M = {}

---@class HttpPostResult
---@field status integer|nil Status of the answer, nil when none came
---@field raw string Everything the server sent
---@field closed boolean True when the server closed the socket
---@field elapsed_ms number Time from the write to the end of the socket

---Build the request text of a POST.
---@param path string
---@param body string
---@param headers table<string, string>|nil Extra headers; `Content-Length` is added unless given
---@return string
function M.build(path, body, headers)
  headers = headers or {}
  local lines = { "POST " .. path .. " HTTP/1.1", "Host: 127.0.0.1" }
  local has_length = false
  for name, value in pairs(headers) do
    table.insert(lines, name .. ": " .. value)
    has_length = has_length or name:lower() == "content-length"
  end
  if not has_length then
    table.insert(lines, "Content-Length: " .. #body)
  end
  return table.concat(lines, "\r\n") .. "\r\n\r\n" .. body
end

---Send bytes and wait for the socket to end.
---@param port integer
---@param request string Raw bytes to write
---@param timeout_ms integer|nil Default 2000
---@return HttpPostResult
function M.send(port, request, timeout_ms)
  local result = { raw = "", closed = false, elapsed_ms = 0 }
  local handle = assert(uv.new_tcp())
  local started
  handle:connect("127.0.0.1", port, function(err)
    assert(not err, err)
    started = uv.hrtime()
    handle:read_start(function(read_err, data)
      if read_err or not data then
        result.closed = true
        result.elapsed_ms = (uv.hrtime() - started) / 1e6
        return
      end
      result.raw = result.raw .. data
    end)
    handle:write(request)
  end)
  vim.wait(timeout_ms or 2000, function()
    return result.closed
  end, 5)
  if not handle:is_closing() then
    handle:close()
  end
  result.status = tonumber(result.raw:match("^HTTP/1%.1 (%d+)"))
  return result
end

---POST a body to a route.
---@param port integer
---@param path string
---@param body string
---@param headers table<string, string>|nil
---@return HttpPostResult
function M.post(port, path, body, headers)
  return M.send(port, M.build(path, body, headers))
end

return M
