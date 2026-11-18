-- Origin: coder/claudecode.nvim@d1237072, lua/claudecode/server/init.lua (MIT, see LICENSE)
---@brief WebSocket server for Claude Code Neovim integration
local claudinho_main = require("claudinho") -- Added for version access
local logger = require("claudinho.logger")
local tcp_server = require("claudinho.server.tcp")
local tools = require("claudinho.tools.init") -- Added: Require the tools module
local utils = require("claudinho.utils")

local MCP_PROTOCOL_VERSION = "2024-11-05"

-- Neovim 0.10 renamed vim.tbl_islist to vim.islist.
local islist = vim.islist or vim.tbl_islist

local M = {}

---@class ClaudinhoServer
---@field id integer Unique in this Neovim (1, 2, ...)
---@field port integer|nil
---@field auth_token string|nil
---@field tcp TCPServer|nil The object of server/tcp.lua
---@field ping_timer uv.uv_timer_t|nil
---@field deferred table<string, true> Keys this instance put in _G.claude_deferred_responses
---@field handlers table<string, function> JSON-RPC handlers by method name
---@field on_open fun(client: WebSocketClient)|nil A client finished its WebSocket handshake
---@field on_disconnect fun(client: WebSocketClient)|nil
---@field on_post fun(kind: "statusline"|"hook", body: string)|nil Used by the HTTP routes (Task 3)
local Server = {}
Server.__index = Server

local next_id = 0
---@type table<integer, ClaudinhoServer> The running instances by id, for M.for_client
local running = {}

---Create a server instance. It listens only after :start.
---@param opts { on_open: function|nil, on_disconnect: function|nil, on_post: function|nil }|nil
---@return ClaudinhoServer
function M.new(opts)
  opts = opts or {}
  next_id = next_id + 1
  return setmetatable({
    id = next_id,
    port = nil,
    auth_token = nil,
    tcp = nil,
    ping_timer = nil,
    deferred = {},
    handlers = {},
    on_open = opts.on_open,
    on_disconnect = opts.on_disconnect,
    on_post = opts.on_post,
  }, Server)
end

---The running instance that owns the client, by the mark the TCP layer put on it at accept.
---@param client table|nil
---@return ClaudinhoServer|nil
function M.for_client(client)
  if type(client) ~= "table" or client.server_id == nil then
    return nil
  end
  return running[client.server_id]
end

---Start listening
---@param config ClaudinhoConfig Configuration options
---@param auth_token string|nil The authentication token for validating connections
---@return boolean success Whether server started successfully
---@return number|string port_or_error Port number or error message
function Server:start(config, auth_token)
  if self.tcp then
    return false, "Server already running"
  end

  self.auth_token = auth_token

  -- Log authentication state
  if auth_token then
    logger.debug("server", "Starting WebSocket server with authentication enabled")
    logger.debug("server", "Auth token length:", #auth_token)
  else
    logger.debug("server", "Starting WebSocket server WITHOUT authentication (insecure)")
  end

  self:register_handlers()

  tools.setup(self)

  local callbacks = {
    on_message = function(client, message)
      self:_handle_message(client, message)
    end,
    on_post = function(kind, body)
      if self.on_post then
        self.on_post(kind, body)
      end
    end,
    on_connect = function(client)
      -- This runs at the TCP accept, before the handshake, so the token has not been checked yet.
      if self.auth_token then
        logger.debug("server", "WebSocket client connected, awaiting authentication:", client.id)
      else
        logger.debug("server", "WebSocket client connected (no auth):", client.id)
      end
    end,
    on_open = function(client)
      -- With a token, the handshake has passed the token check by now, so the client is authenticated.
      if self.auth_token then
        logger.debug("server", "Authenticated WebSocket client connected:", client.id)
      end

      -- The client completed its WebSocket handshake, so the owner (a tab) can flush its queued @ mentions.
      if self.on_open then
        self.on_open(client)
      end
    end,
    on_disconnect = function(client, code, reason)
      logger.debug(
        "server",
        "WebSocket client disconnected:",
        client.id,
        "(code:",
        code,
        ", reason:",
        (reason or "N/A") .. ")"
      )

      -- Close diffs this client opened but never resolved (issue #248) -- only if
      -- the diff module is in use. Scheduled, because this runs in a libuv callback. A client without a completed
      -- handshake ran no tool, so it owns no diff.
      local diff = package.loaded["claudinho.diff"]
      if diff and client.handshake_complete then
        local client_id = client.id
        vim.schedule(function()
          utils.when_windows_allowed(function()
            diff.close_diffs_for_client(client_id, "client disconnected")
          end)
        end)
      end

      if self.on_disconnect then
        self.on_disconnect(client)
      end
    end,
    on_error = function(error_msg)
      logger.one_line("error", "server", error_msg)
    end,
  }

  local tcp, error_msg = tcp_server.create_server(config, callbacks, self.auth_token, self.id)
  if not tcp then
    return false, error_msg or "Unknown server creation error"
  end

  self.tcp = tcp
  self.port = tcp.port
  running[self.id] = self

  self.ping_timer = tcp_server.start_ping_timer(tcp, 30000) -- Start ping timer to keep connections alive

  return true, tcp.port
end

---Stop the server. It touches only its own deferred responses and the diffs of its own clients.
---@return boolean success Whether server stopped successfully
---@return string|nil error_message Error message if any
function Server:stop()
  if not self.tcp then
    return false, "Server not running"
  end

  if self.ping_timer then
    self.ping_timer:stop()
    self.ping_timer:close()
    self.ping_timer = nil
  end

  -- Reject the still-pending diffs of this server's clients before teardown -- stop_server bypasses on_disconnect
  -- (#248). Pending only, so saved-but-unflushed edits survive; only if the diff module is in use, and while clients
  -- can still receive DIFF_REJECTED. A client without a handshake ran no tool, so it owns no diff.
  local diff = package.loaded["claudinho.diff"]
  if diff then
    for _, client in pairs(self.tcp.clients) do
      if client.handshake_complete then
        diff.close_diffs_for_client(client.id, "server stopping")
      end
    end
  end

  tcp_server.stop_server(self.tcp)

  -- CRITICAL: drop this instance's deferred responses to prevent memory leaks and hanging. Another instance's stay.
  if _G.claude_deferred_responses then
    for key in pairs(self.deferred) do
      _G.claude_deferred_responses[key] = nil
    end
  end
  self.deferred = {}

  running[self.id] = nil
  self.tcp = nil
  self.port = nil
  self.auth_token = nil
  return true
end

---Wait until the write queue of every client is empty.
---@param timeout_ms integer|nil How long to wait at most (default 1000)
---@return boolean drained True when every queue was empty before the timeout
function Server:drain(timeout_ms)
  local function empty()
    if not self.tcp then
      return true
    end
    for _, client in pairs(self.tcp.clients) do
      local handle = client.tcp_handle
      if handle and not handle:is_closing() and handle:get_write_queue_size() > 0 then
        return false
      end
    end
    return true
  end
  if empty() then
    return true
  end
  vim.wait(timeout_ms or 1000, empty, 10)
  return empty()
end

---Handle incoming WebSocket message
---@param client table The client that sent the message
---@param message string The JSON-RPC message
function Server:_handle_message(client, message)
  local success, parsed = pcall(vim.json.decode, message)
  if not success then
    self:send_response(client, nil, nil, {
      code = -32700,
      message = "Parse error",
      data = "Invalid JSON",
    })
    return
  end

  if type(parsed) ~= "table" or parsed.jsonrpc ~= "2.0" then
    local request_id = type(parsed) == "table" and parsed.id or nil
    self:send_response(client, request_id, nil, {
      code = -32600,
      message = "Invalid Request",
      data = "Not a valid JSON-RPC 2.0 request",
    })
    return
  end

  if parsed.id then
    self:_handle_request(client, parsed)
  else
    self:_handle_notification(client, parsed)
  end
end

---Handle JSON-RPC request (requires response)
---@param client table The client that sent the request
---@param request table The parsed JSON-RPC request
function Server:_handle_request(client, request)
  local method = request.method
  local params = request.params or {}
  local id = request.id

  local handler = self.handlers[method]
  if not handler then
    self:send_response(client, id, nil, {
      code = -32601,
      message = "Method not found",
      data = "Unknown method: " .. tostring(method),
    })
    return
  end

  local success, result, error_data = pcall(handler, client, params)
  if success then
    -- Check if this is a deferred response (blocking tool)
    if result and result._deferred then
      logger.debug("server", "Handler returned deferred response - storing for later")
      -- Store the request info for later response
      local deferred_info = {
        client = result.client,
        id = id,
        coroutine = result.coroutine,
        method = method,
        params = result.params,
      }
      -- Set up the completion callback
      self:_setup_deferred_response(deferred_info)
      return -- Don't send response now
    end

    if error_data then
      self:send_response(client, id, nil, error_data)
    else
      self:send_response(client, id, result, nil)
    end
  else
    self:send_response(client, id, nil, {
      code = -32603,
      message = "Internal error",
      data = tostring(result), -- result contains error message when pcall fails
    })
  end
end

-- Add a unique module ID to detect reloading
local module_instance_id = math.random(10000, 99999)
logger.debug("server", "Server module loaded with instance ID:", module_instance_id)

---@param deferred_info table
function Server:_setup_deferred_response(deferred_info)
  local co = deferred_info.coroutine
  local key = tostring(co)

  logger.debug("server", "Setting up deferred response for coroutine:", key)
  logger.debug("server", "Storage happening in module instance:", module_instance_id)

  -- The answer leaves through the instance that took the request, so it reaches the client that asked.
  local response_sender = function(result)
    logger.debug("server", "Deferred response triggered for coroutine:", key)
    self.deferred[key] = nil

    if result and result.content then
      -- MCP-compliant response
      self:send_response(deferred_info.client, deferred_info.id, result, nil)
    elseif result and result.error then
      -- Error response
      self:send_response(deferred_info.client, deferred_info.id, nil, result.error)
    else
      -- Fallback error
      self:send_response(deferred_info.client, deferred_info.id, nil, {
        code = -32603,
        message = "Internal error",
        data = "Deferred response completed with unexpected format",
      })
    end
  end

  -- Store the response sender in a global location that won't be affected by module reloading
  if not _G.claude_deferred_responses then
    _G.claude_deferred_responses = {}
  end
  _G.claude_deferred_responses[key] = response_sender
  self.deferred[key] = true

  logger.debug("server", "Stored response sender in global table for coroutine:", key)
end

---Handle JSON-RPC notification (no response)
---@param client table The client that sent the notification
---@param notification table The parsed JSON-RPC notification
function Server:_handle_notification(client, notification)
  local method = notification.method
  local params = notification.params or {}

  local handler = self.handlers[method]
  if handler then
    pcall(handler, client, params)
  end
end

---@param value any
---@return string size Byte length of a string, entry count of a table, otherwise the type name
local function describe_size(value)
  if type(value) == "string" then
    return #value .. " bytes"
  elseif type(value) ~= "table" then
    return type(value)
  end
  local count = 0
  for _ in pairs(value) do
    count = count + 1
  end
  return count .. " entries"
end

---Summarize tool arguments or a tool result for debug logs. Values can hold file contents (openDiff's
---new_file_contents) or selected text, and debug logs reach :messages, so only key names and sizes are kept.
---@param value any
---@return string summary For example `{new_file_contents=120 bytes, tab_name=18 bytes}`
local function describe_fields(value)
  if type(value) ~= "table" then
    return describe_size(value)
  end
  local fields = {}
  for key, field in pairs(value) do
    table.insert(fields, tostring(key) .. "=" .. describe_size(field))
  end
  table.sort(fields)
  return "{" .. table.concat(fields, ", ") .. "}"
end

---Register message handlers for the server
function Server:register_handlers()
  self.handlers = {
    ["initialize"] = function(client, params)
      return {
        protocolVersion = MCP_PROTOCOL_VERSION,
        capabilities = {
          logging = vim.empty_dict(), -- Ensure this is an object {} not an array []
          prompts = { listChanged = true },
          tools = { listChanged = true },
        },
        serverInfo = {
          name = "claudinho-nvim",
          version = claudinho_main.version:string(),
        },
      }
    end,

    ["notifications/initialized"] = function(client, params) -- Added handler for initialized notification
    end,

    ["prompts/list"] = function(client, params) -- Added handler for prompts/list
      return {
        prompts = {}, -- This will be encoded as an empty JSON array
      }
    end,

    ["tools/list"] = function(client, params)
      return {
        tools = tools.get_tool_list(),
      }
    end,

    ["tools/call"] = function(client, params)
      local invalid
      -- A request without params arrives as a plain {}, which islist counts as a list, like []. A JSON {} carries the
      -- empty-dict mark and passes.
      if type(params) ~= "table" or islist(params) then
        invalid = "params (an object is required)"
      elseif type(params.name) ~= "string" then
        invalid = "name (a string is required)"
      elseif params.arguments ~= nil and (type(params.arguments) ~= "table" or islist(params.arguments)) then
        invalid = "arguments (an object is required)"
      end
      if invalid then
        logger.debug("server", "Rejected tools/call:", invalid)
        return nil,
          {
            code = tools.ERROR_CODES.INVALID_PARAMS,
            message = "Invalid params",
            data = "Missing or invalid parameter: " .. invalid,
          }
      end

      logger.debug("server", "Received tools/call:", params.name, "arguments:", describe_fields(params.arguments))
      local result_or_error_table = tools.handle_invoke(client, params)

      -- Check if this is a deferred response (blocking tool)
      if result_or_error_table and result_or_error_table._deferred then
        logger.debug("server", "Tool is blocking - setting up deferred response")
        -- Return the deferred response directly - _handle_request will process it
        return result_or_error_table
      end

      local err = result_or_error_table.error
      local outcome = err and ("error " .. tostring(err.code) .. " " .. tostring(err.message))
        or ("result " .. describe_fields(result_or_error_table.result))
      logger.debug("server", "Response - tools/call", params.name .. ":", outcome)

      if result_or_error_table.error then
        return nil, result_or_error_table.error
      elseif result_or_error_table.result then
        return result_or_error_table.result, nil
      else
        -- Should not happen if tools.handle_invoke behaves correctly
        return nil,
          {
            code = -32603,
            message = "Internal error",
            data = "Tool handler returned unexpected format",
          }
      end
    end,
  }
end

---Send a message to a client
---@param client table The client to send to
---@param method string The method name
---@param params table|nil The parameters to send
---@return boolean success Whether message was sent successfully
function Server:send(client, method, params)
  if not self.tcp then
    return false
  end

  local message = {
    jsonrpc = "2.0",
    method = method,
    params = params or vim.empty_dict(),
  }

  local json_message = vim.json.encode(message)
  tcp_server.send_to_client(self.tcp, client.id, json_message)
  return true
end

---Send a response to a client
---@param client WebSocketClient The client to send to
---@param id number|string|nil The request ID to respond to
---@param result any|nil The result data if successful
---@param error_data table|nil The error data if failed
---@return boolean success Whether response was sent successfully
function Server:send_response(client, id, result, error_data)
  if not self.tcp then
    return false
  end

  local response = {
    jsonrpc = "2.0",
    -- JSON-RPC requires "id": null when the request id is unknown. A Lua nil would drop the field.
    id = id == nil and vim.NIL or id,
  }

  if error_data then
    response.error = error_data
  else
    response.result = result
  end

  local json_response = vim.json.encode(response)
  tcp_server.send_to_client(self.tcp, client.id, json_response)
  return true
end

---Broadcast a message to all connected clients
---@param method string The method name
---@param params table|nil The parameters to send
---@param on_written fun(written: integer)|nil When a connected client took the message: called once after the writes
---  finished, with how many succeeded (see tcp.lua broadcast)
---@return boolean success Whether a connected client took the message
function Server:broadcast(method, params, on_written)
  if not self.tcp then
    return false
  end

  local message = {
    jsonrpc = "2.0",
    method = method,
    params = params or vim.empty_dict(),
  }

  local json_message = vim.json.encode(message)
  return tcp_server.broadcast(self.tcp, json_message, on_written) > 0
end

---Get server status information
---@return table status Server status information
function Server:get_status()
  if not self.tcp then
    return {
      running = false,
      port = nil,
      client_count = 0,
    }
  end

  return {
    running = true,
    port = self.port,
    client_count = tcp_server.get_client_count(self.tcp),
    clients = tcp_server.get_clients_info(self.tcp),
  }
end

-- The module-level functions below serve the single-session callers until Task 12. They act on a default instance made
-- at first use. Its entry points go through the module functions, so a caller that replaces `server.broadcast`,
-- `server.send_response` or `server._handle_message` still sees every call of the default instance.
---@type ClaudinhoServer|nil
local default_instance

---@return ClaudinhoServer
local function default()
  if not default_instance then
    local instance = M.new()
    for _, name in ipairs({ "send", "send_response", "broadcast", "_handle_message", "_handle_request" }) do
      instance[name] = function(_, ...)
        return M[name](...)
      end
    end
    default_instance = instance
  end
  return default_instance
end

-- The old module state, as a view of the default instance: `server` is its TCP object.
local state_fields = { server = "tcp", port = "port", auth_token = "auth_token", handlers = "handlers" }

---@class ServerState
---@field server table|nil The TCP server object of the default instance
---@field port number|nil
---@field auth_token string|nil
---@field handlers table Message handlers by method name
M.state = setmetatable({}, {
  __index = function(_, key)
    local field = state_fields[key]
    if field then
      return default()[field]
    end
    return nil
  end,
  __newindex = function(state, key, value)
    local field = state_fields[key]
    if field then
      default()[field] = value
    else
      rawset(state, key, value)
    end
  end,
})

---Start the default instance
---@param config ClaudinhoConfig
---@param auth_token string|nil
---@return boolean success
---@return number|string port_or_error
function M.start(config, auth_token)
  return Server.start(default(), config, auth_token)
end

---Stop the default instance
---@return boolean success
---@return string|nil error_message
function M.stop()
  return Server.stop(default())
end

function M.register_handlers()
  Server.register_handlers(default())
end

---@param client table
---@param message string
function M._handle_message(client, message)
  Server._handle_message(default(), client, message)
end

---@param client table
---@param request table
function M._handle_request(client, request)
  Server._handle_request(default(), client, request)
end

---@param client table
---@param notification table
function M._handle_notification(client, notification)
  Server._handle_notification(default(), client, notification)
end

---@param deferred_info table
function M._setup_deferred_response(deferred_info)
  Server._setup_deferred_response(default(), deferred_info)
end

---@param client table
---@param method string
---@param params table|nil
---@return boolean
function M.send(client, method, params)
  return Server.send(default(), client, method, params)
end

---@param client WebSocketClient
---@param id number|string|nil
---@param result any|nil
---@param error_data table|nil
---@return boolean
function M.send_response(client, id, result, error_data)
  return Server.send_response(default(), client, id, result, error_data)
end

---@param method string
---@param params table|nil
---@param on_written fun(written: integer)|nil
---@return boolean
function M.broadcast(method, params, on_written)
  return Server.broadcast(default(), method, params, on_written)
end

---@return table
function M.get_status()
  return Server.get_status(default())
end

return M
