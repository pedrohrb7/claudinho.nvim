--- A fake active Claude tab for the specs of code that sends @-mentions through the tab registry.
---
--- `install` replaces `claudinho.sessions` with a registry that holds one running tab. The tab owns a real
--- `claudinho.mention_queue`, so the specs keep checking what the queue does. Its server is the table in `tab.server`,
--- which a spec may replace at any time (`tab.server = nil` is "no server running"): `broadcast(method, params,
--- on_written)` is called without a self, as the specs always did, and `get_status` is `tab.status`. The configuration
--- of the queue is the one in `claudinho.state.config` when it is read, so a spec that replaces it is heard.
local M = {}

---@class ActiveTabFake
---@field number integer
---@field state "running"|"exited"
---@field server table|nil Has `broadcast(method, params, on_written)`; nil means no server is running
---@field status fun(): table What the server reports as its status
---@field queue ClaudinhoMentionQueue
---@field closed boolean True before the tab exists: `active()` finds none until `new()` is called
---@field new_calls integer

local saved_sessions

---The plugin module, as `claudinho` or as `claudinho.init` (a spec may load either).
---@return table|nil
local function plugin()
  return package.loaded["claudinho"] or package.loaded["claudinho.init"]
end

---@param opts { server: table|nil, status: (fun(): table)|nil, closed: boolean|nil }|nil
---@return ActiveTabFake tab
function M.install(opts)
  opts = opts or {}
  saved_sessions = package.loaded["claudinho.sessions"]

  local tab = {
    number = 1,
    state = "running",
    server = opts.server,
    status = opts.status or function()
      return { running = true, client_count = 1 }
    end,
    closed = opts.closed == true,
    new_calls = 0,
  }

  local adapter = {
    broadcast = function(_, method, params, on_written)
      if not tab.server then
        return false
      end
      return tab.server.broadcast(method, params, on_written)
    end,
    get_status = function()
      if not tab.server then
        return { running = false, port = nil, client_count = 0 }
      end
      return tab.status()
    end,
  }

  local config = setmetatable({}, {
    __index = function(_, key)
      local module = plugin()
      local current = type(module) == "table" and module.state and module.state.config or nil
      return current and current[key]
    end,
  })

  tab.queue = require("claudinho.mention_queue").new({
    server = adapter,
    config = config,
    format_path = function(file_path)
      return plugin()._format_path_for_at_mention(file_path)
    end,
  })

  package.loaded["claudinho.sessions"] = {
    NO_TABS = "No Claude tabs open",
    active = function()
      return not tab.closed and tab or nil
    end,
    new = function()
      tab.new_calls = tab.new_calls + 1
      tab.closed = false
      return tab
    end,
    exited_message = function(s)
      return ("Claude %d has exited; run :Claudinho tab-restart %d"):format(s.number, s.number)
    end,
  }
  return tab
end

---Put the registry back, and stop the timers of the queue.
---@param tab ActiveTabFake|nil
function M.uninstall(tab)
  if tab then
    tab.queue:clear()
  end
  package.loaded["claudinho.sessions"] = saved_sessions
  saved_sessions = nil
end

return M
