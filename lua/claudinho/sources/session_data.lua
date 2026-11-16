---@brief [[
--- Reads the JSON that Claude Code sends to the status line command and to the hooks, and keeps only what the plugin
--- shows: the session id, the model, the effort and the permission mode. A field that is missing, has the wrong type
--- or is new never raises an error; what is missing is simply left out.
---@brief ]]
---@module 'claudinho.sources.session_data'
local M = {}

---@class ClaudinhoStatuslineData
---@field session_id string|nil
---@field model string|nil Label such as "Opus 5.5"
---@field effort string|nil

---@class ClaudinhoHookData
---@field session_id string|nil
---@field mode string|nil The raw `permission_mode`

---Decode a JSON body. Invalid JSON, or JSON that is not an object, gives nil.
---@param body any
---@return table|nil data
function M.decode(body)
  if type(body) ~= "string" or body == "" then
    return nil
  end
  local ok, data = pcall(vim.json.decode, body)
  if not ok or type(data) ~= "table" or data[1] ~= nil then
    return nil
  end
  return data
end

---Return a non-empty string, or nil.
---@param value any
---@return string|nil
local function str(value)
  if type(value) == "string" and value ~= "" then
    return value
  end
  return nil
end

---Version and family found in a model id, or nil when the id has an unknown shape.
---@param id string
---@return string|nil family Lowercase family ("opus")
---@return string|nil version "5.5" or "5"
local function parse_id(id)
  local start = id:find("claude-", 1, true)
  if not start then
    return nil
  end
  local rest = id:sub(start + #"claude-")
  rest = rest:gsub("@.*$", ""):gsub("%[.-%]$", ""):gsub("%-v%d+:%d+$", ""):gsub("%-%d%d%d%d%d%d%d%d$", "")

  local parts = {}
  for part in rest:gmatch("[^-]+") do
    parts[#parts + 1] = part
  end

  -- claude-<family>-<major>[-<minor>]
  if parts[1] and parts[1]:match("^%a+$") and parts[2] and parts[2]:match("^%d+$") then
    if #parts == 2 then
      return parts[1], parts[2]
    end
    if #parts == 3 and parts[3]:match("^%d+$") then
      return parts[1], parts[2] .. "." .. parts[3]
    end
    return nil
  end

  -- claude-<major>[-<minor>]-<family>
  if parts[1] and parts[1]:match("^%d+$") then
    if #parts == 2 and parts[2]:match("^%a+$") then
      return parts[2], parts[1]
    end
    if #parts == 3 and parts[2]:match("^%d+$") and parts[3]:match("^%a+$") then
      return parts[3], parts[1] .. "." .. parts[2]
    end
  end
  return nil
end

---Label of a model: the display name when it has a version, else the version taken from the id.
---@param model any `{ id?, display_name? }`
---@return string|nil label
function M.model_label(model)
  if type(model) ~= "table" then
    return nil
  end
  local display = str(model.display_name)
  local id = str(model.id)

  if display and display:find("%d") then
    return display
  end
  if id then
    local family, version = parse_id(id)
    if family then
      local name = display or (family:sub(1, 1):upper() .. family:sub(2))
      return name .. " " .. version
    end
  end
  return display
end

---Data of one status line JSON.
---@param t table|nil
---@return ClaudinhoStatuslineData data
function M.from_statusline(t)
  t = type(t) == "table" and t or {}
  local effort = type(t.effort) == "table" and t.effort.level or nil
  return {
    session_id = str(t.session_id),
    model = M.model_label(t.model),
    effort = str(effort),
  }
end

---Data of one hook JSON.
---@param t table|nil
---@return ClaudinhoHookData data
function M.from_hook(t)
  t = type(t) == "table" and t or {}
  return {
    session_id = str(t.session_id),
    mode = str(t.permission_mode),
  }
end

return M
