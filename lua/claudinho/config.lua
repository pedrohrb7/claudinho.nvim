---@brief [[
--- Manages configuration for the Claude Code Neovim integration.
--- Provides default settings, validation, and application of user-defined configurations.
---@brief ]]
---@module 'claudinho.config'

local M = {}

---@type ClaudinhoConfig
M.defaults = {
  port_range = { min = 10000, max = 65535 },
  terminal_cmd = nil,
  env = {}, -- Custom environment variables for Claude terminal
  log_level = "info",
  track_selection = true,
  -- When true, focus Claude terminal after a successful send while connected
  focus_after_send = false,
  visual_demotion_delay_ms = 50, -- Milliseconds to wait before demoting a visual selection
  connection_wait_delay = 600, -- Milliseconds to wait after connection before sending queued @ mentions
  -- Milliseconds Claude Code has to connect for queued @ mentions. Each one leaves with an error connection_timeout +
  -- connection_wait_delay ms after its send, unless a ready Claude takes the queue first.
  connection_timeout = 10000,
  diff_opts = {
    layout = "vertical",
    open_in_new_tab = false, -- Open diff in a new tab (false = use current tab)
    keep_terminal_focus = false, -- If true, moves focus back to terminal after diff opens
    hide_terminal_in_new_tab = false, -- If true and opening in a new tab, do not show Claude terminal there
    on_new_file_reject = "keep_empty", -- "keep_empty" leaves an empty buffer; "close_window" closes the placeholder split
    auto_resize_terminal = true, -- Let the plugin manage Claude terminal width across the diff lifecycle; false = own it via ClaudinhoDiffOpened/Closed
  },
  -- `value` is passed verbatim to `claude --model`. These short aliases resolve
  -- to the latest model on the Anthropic API, so labels stay version-free to
  -- avoid going stale on every release.
  models = {
    { name = "Claude Opus (Latest)", value = "opus" },
    { name = "Claude Opus (Latest, 1M context)", value = "opus[1m]" },
    { name = "Claude Sonnet (Latest)", value = "sonnet" },
    { name = "Claude Sonnet (Latest, 1M context)", value = "sonnet[1m]" },
    { name = "Claude Haiku (Latest)", value = "haiku" },
    { name = "Default (account recommended)", value = "default" },
  },
  window = {
    layout = "right", -- "right", "bottom", "float" or "tab"
    right = {
      width = 0.30, -- fraction of the editor width, in (0, 1)
      diff_width = nil, -- nil, or a fraction in (0, 1): width while a diff is open
    },
    bottom = { height = 0.30 },
    float = { width = 0.80, height = 0.80 },
    tab_title_max = 24, -- longest tab title in the winbar, in columns
  },
  keymaps = { preset = false },
  notify = false, -- informative notifications (errors and replies always show)
  -- `auto_insert` and `fix_streamed_paste` are read as they come: absent means the behavior of today (`auto_insert`
  -- on, `fix_streamed_paste = "auto"`). Kept here instead of requiring claudinho.terminal during config.apply().
  terminal = {},
}

---@class ClaudinhoRemovedOption
---@field path string[] Path of the key in the user's config
---@field value any? When present, only this value counts as removed
---@field replace_with any? Value put in place of the key (without it, the key is dropped)
---@field message string Text of the warning, in English

---Options that were removed. Each row warns once per key and per Neovim session.
---@type ClaudinhoRemovedOption[]
M.removed_options = {
  {
    path = { "diff_opts", "vertical_split" },
    message = "[Claudinho] diff_opts.vertical_split was removed and is ignored. Use diff_opts.layout instead.",
  },
  {
    path = { "diff_opts", "open_in_current_tab" },
    message = "[Claudinho] diff_opts.open_in_current_tab was removed and is ignored. Use diff_opts.open_in_new_tab instead.",
  },
  {
    path = { "diff_opts", "auto_close_on_accept" },
    message = "[Claudinho] diff_opts.auto_close_on_accept was removed and is ignored. It had no effect.",
  },
  {
    path = { "diff_opts", "show_diff_stats" },
    message = "[Claudinho] diff_opts.show_diff_stats was removed and is ignored. It had no effect.",
  },
  {
    path = { "queue_timeout" },
    message = "[Claudinho] queue_timeout was removed and is ignored. It had no effect.",
  },
  {
    path = { "terminal", "snacks_win_opts" },
    message = "[Claudinho] terminal.snacks_win_opts was removed and is ignored.",
  },
  {
    path = { "terminal", "provider" },
    message = "[Claudinho] terminal.provider was removed and is ignored. Claude always runs in Neovim's terminal, in the window set by window.layout.",
  },
  {
    path = { "terminal", "provider_opts" },
    message = "[Claudinho] terminal.provider_opts was removed and is ignored. External terminals are no longer supported.",
  },
  {
    path = { "terminal", "external_terminal_cmd" },
    message = "[Claudinho] terminal.external_terminal_cmd was removed and is ignored. External terminals are no longer supported.",
  },
  {
    path = { "terminal", "split_side" },
    message = "[Claudinho] terminal.split_side was removed and is ignored. Use window.layout instead.",
  },
  {
    path = { "terminal", "split_width_percentage" },
    message = "[Claudinho] terminal.split_width_percentage was removed and is ignored. Use window.right.width instead.",
  },
  {
    path = { "terminal", "diff_split_width_percentage" },
    message = "[Claudinho] terminal.diff_split_width_percentage was removed and is ignored. Use window.right.diff_width instead.",
  },
  {
    path = { "terminal", "auto_close" },
    message = "[Claudinho] terminal.auto_close was removed and is ignored. Tabs never close by themselves; use :Claudinho tab-close.",
  },
  {
    path = { "terminal", "show_native_term_exit_tip" },
    message = "[Claudinho] terminal.show_native_term_exit_tip was removed and is ignored.",
  },
  {
    path = { "auto_start" },
    message = "[Claudinho] auto_start was removed and is ignored. Nothing starts with setup(); each tab starts its own server.",
  },
  {
    path = { "terminal", "auto_start" },
    message = "[Claudinho] terminal.auto_start was removed and is ignored. Nothing starts with setup(); each tab starts its own server.",
  },
  {
    path = { "terminal", "cwd" },
    message = "[Claudinho] terminal.cwd was removed and is ignored. New tabs start in Neovim's current directory (:pwd).",
  },
  {
    path = { "terminal", "git_repo_cwd" },
    message = "[Claudinho] terminal.git_repo_cwd was removed and is ignored. New tabs start in Neovim's current directory (:pwd).",
  },
  {
    path = { "terminal", "cwd_provider" },
    message = "[Claudinho] terminal.cwd_provider was removed and is ignored. New tabs start in Neovim's current directory (:pwd).",
  },
  {
    path = { "cwd" },
    message = "[Claudinho] cwd was removed and is ignored. New tabs start in Neovim's current directory (:pwd).",
  },
  {
    path = { "git_repo_cwd" },
    message = "[Claudinho] git_repo_cwd was removed and is ignored. New tabs start in Neovim's current directory (:pwd).",
  },
  {
    path = { "cwd_provider" },
    message = "[Claudinho] cwd_provider was removed and is ignored. New tabs start in Neovim's current directory (:pwd).",
  },
}

---Shallow copy of a table value; anything else is returned as is.
---@param value any
---@return any
local function copy_table(value)
  if type(value) ~= "table" then
    return value
  end
  local copy = {}
  for k, v in pairs(value) do
    copy[k] = v
  end
  return copy
end

---Returns a copy of the config without the removed options, and the rows that were found in it.
---Warns once per key and per session, only when `opts.notify` is true (the caller reads it raw from the user's config,
---before `apply`). Never changes the argument and never raises, whatever the type of the values.
---@param user_config table|nil
---@param opts { notify: boolean? }|nil
---@return table config
---@return ClaudinhoRemovedOption[] found The rows of the removed keys the user's config has, in table order
function M.without_removed_options(user_config, opts)
  if type(user_config) ~= "table" then
    return user_config or {}, {}
  end
  local warn = type(opts) == "table" and opts.notify == true

  local result = copy_table(user_config)
  result.diff_opts = copy_table(user_config.diff_opts)
  result.terminal = copy_table(user_config.terminal)

  local found = {}
  for _, row in ipairs(M.removed_options) do
    -- Walk to the table that holds the last key of the path.
    local parent = result
    for i = 1, #row.path - 1 do
      parent = type(parent) == "table" and parent[row.path[i]] or nil
    end
    local key = row.path[#row.path]
    if type(parent) == "table" then
      local current = parent[key]
      if current ~= nil and (row.value == nil or current == row.value) then
        parent[key] = row.replace_with
        found[#found + 1] = row
        if warn then
          vim.notify_once(row.message, vim.log.levels.WARN, { title = "Claudinho" })
        end
      end
    end
  end

  return result, found
end

---Validates the provided configuration table.
---Throws an error if any validation fails.
---@param config table The configuration table to validate.
---@return boolean true if the configuration is valid.
function M.validate(config)
  assert(
    type(config.port_range) == "table"
      and type(config.port_range.min) == "number"
      and type(config.port_range.max) == "number"
      and config.port_range.min > 0
      and config.port_range.max <= 65535
      and config.port_range.min <= config.port_range.max,
    "Invalid port range"
  )

  assert(config.terminal_cmd == nil or type(config.terminal_cmd) == "string", "terminal_cmd must be nil or a string")

  -- Validate terminal config
  assert(type(config.terminal) == "table", "terminal must be a table")

  local valid_log_levels = { "trace", "debug", "info", "warn", "error" }
  local is_valid_log_level = false
  for _, level in ipairs(valid_log_levels) do
    if config.log_level == level then
      is_valid_log_level = true
      break
    end
  end
  assert(is_valid_log_level, "log_level must be one of: " .. table.concat(valid_log_levels, ", "))

  assert(type(config.track_selection) == "boolean", "track_selection must be a boolean")
  -- Allow absence in direct validate() calls; apply() supplies default
  if config.focus_after_send ~= nil then
    assert(type(config.focus_after_send) == "boolean", "focus_after_send must be a boolean")
  end

  assert(
    type(config.visual_demotion_delay_ms) == "number" and config.visual_demotion_delay_ms >= 0,
    "visual_demotion_delay_ms must be a non-negative number"
  )

  assert(
    type(config.connection_wait_delay) == "number" and config.connection_wait_delay >= 0,
    "connection_wait_delay must be a non-negative number"
  )

  assert(
    type(config.connection_timeout) == "number" and config.connection_timeout > 0,
    "connection_timeout must be a positive number"
  )

  assert(type(config.diff_opts) == "table", "diff_opts must be a table")
  -- New diff options (optional validation to allow backward compatibility)
  if config.diff_opts.layout ~= nil then
    assert(
      config.diff_opts.layout == "vertical"
        or config.diff_opts.layout == "horizontal"
        or config.diff_opts.layout == "unified",
      "diff_opts.layout must be 'vertical', 'horizontal', or 'unified'"
    )
  end
  if config.diff_opts.open_in_new_tab ~= nil then
    assert(type(config.diff_opts.open_in_new_tab) == "boolean", "diff_opts.open_in_new_tab must be a boolean")
  end
  if config.diff_opts.keep_terminal_focus ~= nil then
    assert(type(config.diff_opts.keep_terminal_focus) == "boolean", "diff_opts.keep_terminal_focus must be a boolean")
  end
  if config.diff_opts.hide_terminal_in_new_tab ~= nil then
    assert(
      type(config.diff_opts.hide_terminal_in_new_tab) == "boolean",
      "diff_opts.hide_terminal_in_new_tab must be a boolean"
    )
  end
  if config.diff_opts.on_new_file_reject ~= nil then
    assert(
      type(config.diff_opts.on_new_file_reject) == "string"
        and (
          config.diff_opts.on_new_file_reject == "keep_empty" or config.diff_opts.on_new_file_reject == "close_window"
        ),
      "diff_opts.on_new_file_reject must be 'keep_empty' or 'close_window'"
    )
  end
  if config.diff_opts.auto_resize_terminal ~= nil then
    assert(type(config.diff_opts.auto_resize_terminal) == "boolean", "diff_opts.auto_resize_terminal must be a boolean")
  end

  -- Validate env
  assert(type(config.env) == "table", "env must be a table")
  for key, value in pairs(config.env) do
    assert(type(key) == "string", "env keys must be strings")
    assert(type(value) == "string", "env values must be strings")
  end

  -- Validate models
  assert(type(config.models) == "table", "models must be a table")
  assert(#config.models > 0, "models must not be empty")

  for i, model in ipairs(config.models) do
    assert(type(model) == "table", "models[" .. i .. "] must be a table")
    assert(type(model.name) == "string" and model.name ~= "", "models[" .. i .. "].name must be a non-empty string")
    assert(type(model.value) == "string" and model.value ~= "", "models[" .. i .. "].value must be a non-empty string")
  end

  return true
end

local VALID_LAYOUTS = { "right", "bottom", "float", "tab" }

---Text of a value in an error message: strings quoted, the rest as tostring.
---@param value any
---@return string
local function show(value)
  if type(value) == "string" then
    return '"' .. value .. '"'
  end
  return tostring(value)
end

---@param value any
---@return boolean
local function is_fraction(value)
  return type(value) == "number" and value > 0 and value < 1
end

---@param value any
---@return boolean
local function is_boolean(value)
  return type(value) == "boolean"
end

---@param value any
---@return boolean
local function is_positive_integer(value)
  return type(value) == "number" and value >= 1 and value % 1 == 0
end

---Checks the keys added by the base UI (window, keymaps, notify). A bad value does not raise: it falls back to the
---default and reports an error naming the key, the value and the valid ones. Mutates `config`.
---@param config table
function M.normalize_new_keys(config)
  local defaults = M.defaults
  local notify = require("claudinho.notify")

  ---Replaces a bad table with a copy of the default, with the error of the key.
  local function ensure_table(parent, key, path, default)
    if type(parent[key]) ~= "table" then
      if parent[key] ~= nil then
        notify.error(
          "[Claudinho] " .. path .. " = " .. show(parent[key]) .. " is not valid; using the default " .. path .. "."
        )
      end
      parent[key] = vim.deepcopy(default)
    end
    return parent[key]
  end

  local function check(parent, key, path, default, valid)
    local value = parent[key]
    if value == nil and default ~= nil then
      parent[key] = default
    elseif value ~= nil and not valid(value) then
      notify.error("[Claudinho] " .. path .. " = " .. show(value) .. " is not valid; using " .. show(default) .. ".")
      parent[key] = default
    end
  end

  local window = ensure_table(config, "window", "window", defaults.window)
  local d = defaults.window

  if window.layout == nil then
    window.layout = d.layout
  else
    local ok = false
    for _, layout in ipairs(VALID_LAYOUTS) do
      ok = ok or window.layout == layout
    end
    if not ok then
      notify.error(
        "[Claudinho] window.layout = "
          .. show(window.layout)
          .. ' is not valid; using "right". Valid layouts: '
          .. table.concat(VALID_LAYOUTS, ", ")
          .. "."
      )
      window.layout = d.layout
    end
  end

  local right = ensure_table(window, "right", "window.right", d.right)
  check(right, "width", "window.right.width", d.right.width, is_fraction)
  if right.diff_width ~= nil and not is_fraction(right.diff_width) then
    notify.error("[Claudinho] window.right.diff_width = " .. show(right.diff_width) .. " is not valid; using nil.")
    right.diff_width = nil
  end

  local bottom = ensure_table(window, "bottom", "window.bottom", d.bottom)
  check(bottom, "height", "window.bottom.height", d.bottom.height, is_fraction)

  local float = ensure_table(window, "float", "window.float", d.float)
  check(float, "width", "window.float.width", d.float.width, is_fraction)
  check(float, "height", "window.float.height", d.float.height, is_fraction)

  check(window, "tab_title_max", "window.tab_title_max", d.tab_title_max, is_positive_integer)

  local keymaps = ensure_table(config, "keymaps", "keymaps", defaults.keymaps)
  check(keymaps, "preset", "keymaps.preset", defaults.keymaps.preset, is_boolean)

  check(config, "notify", "notify", defaults.notify, is_boolean)
end

---Applies user configuration on top of default settings and validates the result.
---@param user_config table|nil The user-provided configuration table.
---@return ClaudinhoConfig config The final, validated configuration table.
function M.apply(user_config)
  local config = vim.deepcopy(M.defaults)

  if user_config then
    -- Use vim.tbl_deep_extend if available, otherwise simple merge
    if vim.tbl_deep_extend then
      config = vim.tbl_deep_extend("force", config, user_config)
    else
      -- Simple fallback for testing environment
      for k, v in pairs(user_config) do
        config[k] = v
      end
    end
  end

  M.normalize_new_keys(config)
  M.validate(config)

  return config
end

return M
