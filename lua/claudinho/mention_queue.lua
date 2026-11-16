-- Origin: coder/claudecode.nvim@d1237072, lua/claudecode/init.lua (MIT, see LICENSE)
---@brief [[
--- The @ mention queue of one server instance. A send that does not go out at once waits in `queue.mentions`, oldest
--- first. A mention leaves the queue only when a connected Claude took it, when its deadline passed while no client was
--- ready, or when the queue is cleared. Two timers move it on:
--- - `mention_timer` is the next flush, while Claude is connected: 50 ms after a send, connection_wait_delay ms after
---   Claude's handshake, or 25 ms after the previous mention went out. A flush sends only the oldest mention, so the
---   order holds, and only once some connected client is ready: it completed its handshake connection_wait_delay ms ago.
--- - `connection_timer` clears the mentions whose deadline passed, connection_timeout + connection_wait_delay ms after
---   their send, with an error. No handshake or disconnect moves a deadline. A Claude that completes its handshake less
---   than connection_timeout ms after the send, and stays connected, is ready before the deadline. While a ready client
---   is connected, no deadline clears a mention: the queue drains to it, 25 ms apart. A flush that finds no ready
---   client clears the mentions whose deadline passed meanwhile, and starts the timer again.
--- A timer's callback runs on the main loop and does nothing once its timer was stopped or replaced, so a clear cancels
--- every pending flush and timeout.
---@brief ]]

local logger = require("claudinho.logger")

local debounce_delay = 50 -- ms from a send to its flush, so a burst of sends goes out as one batch
local inter_message_delay = 25 -- ms between two mentions of a batch, so Claude is not overwhelmed

---@class ClaudinhoMentionQueue
---@field server ClaudinhoMentionServer The server instance the mentions go to
---@field config table The configuration (connection_timeout, connection_wait_delay, debouncing flags)
---@field format_path fun(file_path: string): string, boolean Formats a path as Claude receives it, and tells if it is a directory
---@field mentions ClaudinhoMention[] Queued mentions, oldest first
---@field mention_timer uv.uv_timer_t|nil The next flush
---@field connection_timer uv.uv_timer_t|nil The deadline timer: runs while the queue holds a mention. It is nil after
---  a deadline passed while a ready client was connected, until a mention is queued or a flush finds no ready client
local Queue = {}
Queue.__index = Queue

---What the queue needs from a server: `ClaudinhoServer` of server/init.lua has both.
---@class ClaudinhoMentionServer
---@field broadcast fun(self: any, method: string, params: table, on_written: (fun(written: integer))|nil): boolean
---@field get_status fun(self: any): table

local M = {}

---@param opts { server: ClaudinhoMentionServer, config: table, format_path: (fun(file_path: string): string, boolean)|nil }
---@return ClaudinhoMentionQueue
function M.new(opts)
  return setmetatable({
    server = opts.server,
    config = opts.config,
    format_path = opts.format_path or function(file_path)
      return file_path, false
    end,
    mentions = {},
    mention_timer = nil,
    connection_timer = nil,
  }, Queue)
end

---@return boolean connected Whether some client of the server completed its WebSocket handshake
function Queue:is_connected()
  local status = self.server:get_status()
  if not status.running then
    return false
  end

  -- Prefer handshake-aware check when client info is available; otherwise fall back to client_count
  if status.clients and #status.clients > 0 then
    for _, info in ipairs(status.clients) do
      -- A client that sent or answered a CLOSE frame is "closing": it keeps handshake_complete but takes no frames.
      if info.state == "connected" and info.handshake_complete == true then
        return true
      end
    end
    return false
  else
    return status.client_count and status.client_count > 0
  end
end

---@return number|nil wait Milliseconds until some connected client completed its handshake connection_wait_delay ms
---  ago: 0 when one did, nil when no connected client reports when it connected
function Queue:ready_in()
  local wait
  for _, info in ipairs(self.server:get_status().clients or {}) do
    if info.state == "connected" and info.handshake_complete == true and info.connected_at then
      local left = math.max(0, info.connected_at + self.config.connection_wait_delay - vim.loop.now())
      wait = wait and math.min(wait, left) or left
    end
  end
  return wait
end

---Stop and forget the timer self[name], if it is set.
---@param name "mention_timer"|"connection_timer"
function Queue:_stop_timer(name)
  local timer = self[name]
  if timer then
    self[name] = nil
    timer:stop()
    timer:close()
  end
end

---Run fn on the main loop after delay ms, as the timer self[name], unless that timer is stopped or replaced first. A
---timer of that name that still runs is stopped.
---@param name "mention_timer"|"connection_timer"
---@param delay number Milliseconds
---@param fn function
function Queue:_start_timer(name, delay, fn)
  self:_stop_timer(name)
  local timer = assert(vim.loop.new_timer(), "cannot create the @ mention " .. name)
  self[name] = timer
  timer:start(delay, 0, function()
    vim.schedule(function()
      if self[name] == timer then
        self:_stop_timer(name)
        fn()
      end
    end)
  end)
end

---Clear the mention queue and stop its timers
function Queue:clear()
  if #self.mentions > 0 then
    logger.debug("queue", "Clearing " .. #self.mentions .. " queued @ mentions")
  end
  self.mentions = {}
  self:_stop_timer("mention_timer")
  self:_stop_timer("connection_timer")
end

---Clear the queued mentions whose deadline passed, with an error, then wait for the deadline of the oldest one left.
---The connection_timer callback: the timer may fire for a mention that went out since, and then clears nothing.
---While a ready client is connected, it clears nothing and stops: the queue drains to that client, and a flush that
---finds no ready client calls it again.
function Queue:_expire()
  if self:ready_in() == 0 then
    -- A flush must be due, so that the drain goes on, or finds the client gone and calls this again. The handshake's
    -- own flush can come later than this: Neovim runs the scheduled callbacks in order, late when its loop was busy.
    self:_schedule_flush(inter_message_delay)
    return
  end
  local queue = self.mentions
  local now = vim.loop.now()
  local expired = 0
  -- Deadlines grow with the queue order, so the mentions whose deadline passed are the oldest ones.
  while expired < #queue and queue[expired + 1].deadline <= now do
    expired = expired + 1
  end
  if expired > 0 then
    if self:is_connected() then
      logger.error(
        "queue",
        "Send timeout - clearing " .. expired .. " queued @ mentions that the connected Claude did not take in time"
      )
    else
      logger.error("queue", "Connection timeout - clearing " .. expired .. " queued @ mentions")
    end
    for _ = 1, expired do
      table.remove(queue, 1)
    end
  end
  if #queue == 0 then
    self:clear()
  else
    self:_start_timer("connection_timer", queue[1].deadline - now, function()
      self:_expire()
    end)
  end
end

---A server broadcast callback that shows an error when no write of the mention succeeded: the connection failed after
---the client took the frame, so Claude did not get it. It runs in a libuv callback, and logger schedules the message.
---@param component string The logger component
---@param file_path string
---@return fun(written: integer)
local function report_unwritten(component, file_path)
  return function(written)
    if written == 0 then
      logger.error(component, "Claude's connection failed while the @ mention " .. file_path .. " was sent")
    end
  end
end

---Send the oldest queued mention to Claude, then schedule the next one.
function Queue:flush()
  local queue = self.mentions
  if #queue == 0 then
    self:_schedule_flush(debounce_delay)
    return
  end
  -- A mention goes out only once some connected client has been connected for connection_wait_delay ms. The broadcast
  -- then reaches every connected client, also one that connected later. Another client's handshake cannot postpone it.
  local wait = self:ready_in()
  if wait and wait > 0 then
    -- A ready client that took the queue may have left: the mentions whose deadline passed meanwhile leave now.
    self:_expire()
    if #self.mentions > 0 then
      self:_start_timer("mention_timer", wait, function()
        self:flush()
      end)
    end
    return
  end

  local mention = queue[1]
  local params = { filePath = mention.file_path, lineStart = mention.start_line, lineEnd = mention.end_line }
  if not self.server:broadcast("at_mentioned", params, report_unwritten("queue", mention.file_path)) then
    -- No connected client took the frame, as Claude went away since this flush was scheduled. The mention waits for
    -- Claude's next handshake, or for its deadline. One that passed while a ready client took the queue leaves now.
    logger.debug("queue", "No connected client took queued @ mention: " .. mention.file_path)
    self:_expire()
    return
  end
  table.remove(queue, 1)
  logger.debug("queue", "Sent queued @ mention: " .. mention.file_path)
  self:_schedule_flush(inter_message_delay)
end

---Keep the queue moving. While Claude is connected, a flush is due: in delay ms, unless one is due already. An empty
---queue stops both timers.
---@param delay number Milliseconds to the flush when Claude is connected and no flush is due yet
function Queue:_schedule_flush(delay)
  if #self.mentions == 0 then
    self:_stop_timer("mention_timer")
    self:_stop_timer("connection_timer")
  elseif self:is_connected() and not self.mention_timer then
    self:_start_timer("mention_timer", delay, function()
      self:flush()
    end)
  end
end

---Claude completed its WebSocket handshake (the server's on_open callback): a flush is due in connection_wait_delay ms
---unless one is due already. A flush sends the oldest mention only once some connected client has been connected for
---connection_wait_delay ms, and otherwise waits for that moment (see flush).
function Queue:on_open()
  self:_schedule_flush(self.config.connection_wait_delay)
end

---Add a formatted mention to the queue.
---@param file_path string The file path to mention, formatted as Claude receives it
---@param start_line number|nil Optional start line
---@param end_line number|nil Optional end line
function Queue:_queue(file_path, start_line, end_line)
  -- Claude has connection_timeout ms to complete its handshake, and connection_wait_delay ms after it to get ready.
  local timeout = self.config.connection_timeout + self.config.connection_wait_delay
  local deadline = vim.loop.now() + timeout
  table.insert(
    self.mentions,
    { file_path = file_path, start_line = start_line, end_line = end_line, deadline = deadline }
  )
  logger.debug("queue", "Queued @ mention: " .. file_path .. " (queue size: " .. #self.mentions .. ")")
  if not self.connection_timer then
    self:_start_timer("connection_timer", timeout, function()
      self:_expire()
    end)
  end
  self:_schedule_flush(debounce_delay)
end

---Format a mention the way Claude receives it: an absolute path, and no line numbers for a directory.
---@param file_path string
---@param start_line number|nil
---@param end_line number|nil
---@return table|nil mention `file_path`, `start_line`, `end_line` and `is_directory`, or nil for a bad path
---@return string|nil error Why the path is bad
function Queue:_format(file_path, start_line, end_line)
  local format_success, formatted_path, is_directory = pcall(self.format_path, file_path)
  if not format_success then
    return nil, formatted_path -- the error message
  end

  if is_directory and (start_line or end_line) then
    logger.debug("command", "Line numbers ignored for directory: " .. formatted_path)
    start_line = nil
    end_line = nil
  end
  return { file_path = formatted_path, start_line = start_line, end_line = end_line, is_directory = is_directory }
end

---Queue a mention for Claude, with the path a connected send gives Claude. Nothing is sent now.
---@param file_path string
---@param start_line number|nil
---@param end_line number|nil
---@return table|nil mention The queued mention (`file_path`, `start_line`, `end_line`, `is_directory`), nil on error
---@return string|nil error Why the path is bad
function Queue:enqueue(file_path, start_line, end_line)
  local mention, format_error = self:_format(file_path, start_line, end_line)
  if not mention then
    return nil, format_error
  end
  self:_queue(mention.file_path, mention.start_line, mention.end_line)
  return mention
end

---Send a mention to Claude: at once when debouncing is off and no older mention waits, otherwise through the queue.
---@param file_path string
---@param start_line number|nil
---@param end_line number|nil
---@return boolean success
---@return string|nil error
---@return table|nil sent What Claude received (`file_path`, `start_line`, `end_line`), with the formatted path and the
---  directory-adjusted lines
function Queue:send(file_path, start_line, end_line)
  local mention, format_error = self:_format(file_path, start_line, end_line)
  if not mention then
    return false, format_error
  end
  local formatted_path, is_directory = mention.file_path, mention.is_directory
  start_line, end_line = mention.start_line, mention.end_line

  local params = {
    filePath = formatted_path,
    lineStart = start_line,
    lineEnd = end_line,
  }

  -- What Claude actually received, so the ClaudinhoSendComplete event payload reflects the formatted path and the
  -- directory-adjusted line numbers rather than the raw caller arguments.
  local sent = {
    file_path = formatted_path,
    start_line = start_line,
    end_line = end_line,
  }

  -- For tests or when explicitly configured, broadcast immediately without queuing, unless older mentions still wait
  -- in the queue: this one must not overtake them.
  local config = self.config
  local immediate = (config and config.disable_broadcast_debouncing)
    or (package.loaded["busted"] and not (config and config.enable_broadcast_debouncing_in_tests))
  if immediate and #self.mentions == 0 then
    local broadcast_success = self.server:broadcast("at_mentioned", params, report_unwritten("command", formatted_path))
    if broadcast_success then
      return true, nil, sent
    else
      local error_msg = "Failed to broadcast " .. (is_directory and "directory" or "file") .. " " .. formatted_path
      logger.error("command", error_msg)
      return false, error_msg
    end
  end

  -- Use the queue for debounced broadcasting
  self:_queue(formatted_path, start_line, end_line)

  -- Always return success since we're queuing the message. The queue sends it to a connected Claude, or shows an
  -- error when no ready Claude took it by its deadline, connection_timeout + connection_wait_delay ms after the send.
  return true, nil, sent
end

return M
