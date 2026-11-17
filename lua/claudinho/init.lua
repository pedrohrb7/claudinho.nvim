---@brief [[
--- Claude Code Neovim Integration
--- This plugin integrates Claude Code CLI with Neovim, enabling
--- seamless AI-assisted coding experiences directly in Neovim.
---@brief ]]

---@module 'claudinho'
local M = {}

local logger = require("claudinho.logger")

--- Current plugin version. The values come from the VERSION file at the repository root, so a release changes
--- no Lua file. Without a readable VERSION file the version is 0.0.0-unknown.
---@type ClaudinhoVersion
M.version = {
  major = 0,
  minor = 0,
  patch = 0,
  prerelease = "unknown",
  string = function(self)
    local version = string.format("%d.%d.%d", self.major, self.minor, self.patch)
    if self.prerelease then
      version = version .. "-" .. self.prerelease
    end
    return version
  end,
}

do
  local root = debug.getinfo(1, "S").source:match("^@(.-)lua[/\\]claudinho[/\\]init%.lua$")
  local file = root and io.open(root .. "VERSION", "r")
  if file then
    local text = file:read("*l") or ""
    file:close()
    local major, minor, patch, prerelease = text:match("^(%d+)%.(%d+)%.(%d+)%-?(%S*)%s*$")
    if major then
      M.version.major, M.version.minor, M.version.patch = tonumber(major), tonumber(minor), tonumber(patch)
      M.version.prerelease = prerelease ~= "" and prerelease or nil
    end
  end
end
-- Module state
---@type ClaudinhoState
M.state = {
  config = require("claudinho.config").defaults,
  initialized = false,
}

---The active tab when its process runs, else nil.
---@return ClaudinhoSession|nil
local function running_tab()
  local s = require("claudinho.sessions").active()
  if s and s.state == "running" and s.queue then
    return s
  end
  return nil
end

---Check if Claude Code is connected to the WebSocket server of the active tab
---@return boolean connected Whether Claude Code has active connections
function M.is_claude_connected()
  local s = running_tab()
  return s ~= nil and s.queue:is_connected()
end

---Fire the `User ClaudinhoSendComplete` autocmd so integrations can react after
---a send (e.g. focus an externally-managed Claude session). Fires once per file,
---synchronously on the same tick, right after the focus action.
---NOTE: the `data` field of nvim_exec_autocmds requires Neovim >= 0.8.0 (the
---plugin floor). Guarded so minimal vim stubs are a no-op, and pcall'd so a
---faulty user callback cannot break the send path or abort batch loops.
---`modeline = false` because this is a notification-only event: without it
---nvim_exec_autocmds defaults `modeline = true` and would re-process the current
---buffer's modeline on every send (re-applying options / surfacing unrelated
---modeline errors).
---@param file_path string Path Claude received (formatted/relative)
---@param start_line number|nil Start line (0-indexed for Claude), or nil
---@param end_line number|nil End line (0-indexed for Claude), or nil
---@param context string|nil Internal logging context tag
local function fire_send_complete(file_path, start_line, end_line, context)
  if not (vim.api and vim.api.nvim_exec_autocmds) then
    return
  end
  pcall(vim.api.nvim_exec_autocmds, "User", {
    pattern = "ClaudinhoSendComplete",
    modeline = false,
    data = {
      file_path = file_path,
      start_line = start_line,
      end_line = end_line,
      context = context,
    },
  })
end

---Send @ mention to the active Claude tab, handling connection state automatically. Without a tab it starts the first
---one and queues the mention there; a mention for a tab that has not connected yet waits in the queue of that tab; the
---active tab having exited, nothing is sent.
---@param file_path string The file path to send
---@param start_line number|nil Start line (0-indexed for Claude)
---@param end_line number|nil End line (0-indexed for Claude)
---@param context string|nil Context for logging
---@return boolean success Whether the operation was successful
---@return string|nil error Error message if failed
function M.send_at_mention(file_path, start_line, end_line, context)
  context = context or "command"
  local sessions = require("claudinho.sessions")

  local s = sessions.active()
  if not s then
    -- `sessions.new` already showed why when it fails.
    local new_error
    s, new_error = sessions.new()
    if not s then
      return false, new_error
    end
    local mention, format_error = s.queue:enqueue(file_path, start_line, end_line)
    if not mention then
      return false, format_error
    end
    logger.debug(context, "Queued @ mention and started Claude " .. s.number .. ": " .. mention.file_path)
    return true, nil
  end

  if s.state ~= "running" or not s.queue then
    return false, sessions.exited_message(s)
  end

  -- Check if Claude Code is connected
  if M.is_claude_connected() then
    -- Claude is connected, send immediately and ensure terminal is visible
    local success, error_msg, sent = M._broadcast_at_mention(file_path, start_line, end_line)
    if success then
      local terminal = require("claudinho.terminal")
      if M.state.config and M.state.config.focus_after_send then
        -- Open focuses the terminal without toggling/hiding if already focused
        terminal.open()
      else
        terminal.ensure_visible()
      end
      -- Fire ClaudinhoSendComplete. NOTE: in production `success` means the
      -- mention was ACCEPTED/queued, not yet delivered (delivery is debounced and
      -- failures are logged, not returned), so this is an "accepted/dispatched"
      -- signal. `sent` carries the formatted path/lines Claude received; fall back
      -- to the raw args when a caller/test stubs _broadcast_at_mention.
      sent = sent or { file_path = file_path, start_line = start_line, end_line = end_line }
      fire_send_complete(sent.file_path, sent.start_line, sent.end_line, context)
    end
    return success, error_msg
  else
    -- Claude not connected: queue the mention, with the path a connected send gives Claude, and show the window
    local mention, format_error = s.queue:enqueue(file_path, start_line, end_line)
    if not mention then
      return false, format_error
    end

    require("claudinho.terminal").open()

    logger.debug(context, "Queued @ mention for Claude " .. s.number .. ": " .. mention.file_path)

    return true, nil
  end
end

---Set up the plugin with user configuration. It starts no server, no process and no lock file: the first tab does.
---@param opts PartialClaudinhoConfig|nil Optional configuration table to override defaults.
---@return table module The plugin module
function M.setup(opts)
  opts = opts or {}
  -- claudecode.nvim installed: both plugins run, and the warning follows the user's own `notify = true`.
  require("claudinho.conflict").warn(opts.notify == true)

  local config = require("claudinho.config")
  -- `notify` is read raw, before `apply`: the warnings of the removed keys follow the user's own `notify = true`.
  local found
  opts, found = config.without_removed_options(opts, { notify = opts.notify == true })
  M.state.removed_found = found

  M.state.config = config.apply(opts)
  -- vim.g.claudinho_user_config is no longer needed as config values are passed directly.

  logger.setup(M.state.config)

  require("claudinho.terminal").setup(M.state.config.terminal)

  local diff = require("claudinho.diff")
  diff.setup(M.state.config)

  local sessions = require("claudinho.sessions")
  if M.state.config.track_selection then
    -- The router sends to the active tab only, so no tab means nothing is sent, and the selection stays known for the
    -- first one.
    require("claudinho.selection").enable(sessions.router, M.state.config.visual_demotion_delay_ms)
  end
  sessions.setup_autocmds()

  require("claudinho.commands").setup(M.state.config)

  M.state.initialized = true
  return M
end

---Choose a model from `config.models` and use it: `/model <value>` for the running active tab, a new tab started with
---`--model <value>` without tabs. The active tab having exited, nothing is done and the reply says so.
function M.open_with_model()
  local sessions = require("claudinho.sessions")
  local models = M.state.config.models

  if not models or #models == 0 then
    logger.error("command", "No models configured for selection")
    return
  end

  local active = sessions.active()
  if active and active.state ~= "running" then
    require("claudinho.notify").reply(sessions.exited_message(active))
    return
  end

  vim.ui.select(models, {
    prompt = "Select Claude model:",
    format_item = function(item)
      return item.name
    end,
  }, function(choice)
    if not choice then
      return -- User cancelled
    end

    if not choice.value or type(choice.value) ~= "string" then
      logger.error("command", "Invalid model value selected")
      return
    end

    -- The tab may have changed while the choice was open.
    local tab = sessions.active()
    if not tab then
      sessions.new(" --model " .. vim.fn.shellescape(choice.value))
    elseif tab.state ~= "running" then
      require("claudinho.notify").reply(sessions.exited_message(tab))
    else
      require("claudinho.terminal").send_to_terminal("/model " .. choice.value)
    end
  end)
end

---Get version information
---@return { version: string, major: integer, minor: integer, patch: integer, prerelease: string|nil }
function M.get_version()
  return {
    version = M.version:string(),
    major = M.version.major,
    minor = M.version.minor,
    patch = M.version.patch,
    prerelease = M.version.prerelease,
  }
end

---Format file path for at mention (exposed for testing)
---@param file_path string The file path to format
---@return string formatted_path The formatted path
---@return boolean is_directory Whether the path is a directory
function M._format_path_for_at_mention(file_path)
  -- Input validation
  if not file_path or type(file_path) ~= "string" or file_path == "" then
    error("format_path_for_at_mention: file_path must be a non-empty string")
  end

  -- Only check path existence in production (not tests)
  -- This allows tests to work with mock paths while still providing validation in real usage
  if not package.loaded["busted"] then
    if vim.fn.filereadable(file_path) == 0 and vim.fn.isdirectory(file_path) == 0 then
      error("format_path_for_at_mention: path does not exist: " .. file_path)
    end
  end

  -- Send the absolute path. A path made relative to Neovim's cwd names a different file
  -- when Claude's cwd differs (a tab started before a :cd, a CLI started elsewhere) or after a :cd,
  -- and a text-prefix cwd match cut /work/foobar to "ar".
  -- :p makes the path absolute for this platform. It reads a leading ~ as ~user, and the
  -- callers expand ~/ first, so a leading ~ here is part of a file name in the cwd.
  local input = file_path:sub(1, 1) == "~" and ("./" .. file_path) or file_path
  local formatted_path = vim.fn.fnamemodify(input, ":p")
  local is_windows = vim.fn.has("win32") == 1
  local is_directory = vim.fn.isdirectory(formatted_path) == 1
  if is_directory and not formatted_path:match(is_windows and "[/\\]$" or "/$") then
    formatted_path = formatted_path .. "/"
  end
  assert(is_windows or formatted_path:sub(1, 1) == "/", "expected an absolute path, got: " .. formatted_path)

  return formatted_path, is_directory
end
---Test helper functions (exposed for testing)
---@param file_path string
---@param start_line number|nil
---@param end_line number|nil
---@return boolean success
---@return string|nil error
function M._broadcast_at_mention(file_path, start_line, end_line)
  local sessions = require("claudinho.sessions")
  local s = sessions.active()
  if not s then
    return false, sessions.NO_TABS
  end
  if s.state ~= "running" or not s.queue then
    return false, sessions.exited_message(s)
  end

  return s.queue:send(file_path, start_line, end_line)
end

function M._add_paths_to_claude(file_paths, options)
  options = options or {}
  local delay = options.delay or 0
  local show_summary = options.show_summary ~= false
  local context = options.context or "command"
  local batch_size = options.batch_size or 10
  local max_files = options.max_files or 100

  if not file_paths or #file_paths == 0 then
    return 0, 0
  end

  if #file_paths > max_files then
    logger.warn(context, string.format("Too many files selected (%d), limiting to %d", #file_paths, max_files))
    local limited_paths = {}
    for i = 1, max_files do
      limited_paths[i] = file_paths[i]
    end
    file_paths = limited_paths
  end

  local success_count = 0
  local total_count = #file_paths

  if delay > 0 then
    local function send_batch(start_index)
      if start_index > total_count then
        if show_summary then
          local message = success_count == 1 and "Added 1 file to Claude context"
            or string.format("Added %d files to Claude context", success_count)
          if total_count > success_count then
            message = message .. string.format(" (%d failed)", total_count - success_count)
          end

          if total_count > success_count then
            if success_count > 0 then
              logger.warn(context, message)
            else
              logger.error(context, message)
            end
          elseif success_count > 0 then
            logger.info(context, message)
          else
            logger.debug(context, message)
          end
        end
        return
      end

      -- Process a batch of files
      local end_index = math.min(start_index + batch_size - 1, total_count)
      local batch_success = 0

      for i = start_index, end_index do
        local file_path = file_paths[i]
        local success, error_msg = M._broadcast_at_mention(file_path)
        if success then
          success_count = success_count + 1
          batch_success = batch_success + 1
        else
          logger.error(context, "Failed to add file: " .. file_path .. " - " .. (error_msg or "unknown error"))
        end
      end

      logger.debug(
        context,
        string.format(
          "Processed batch %d-%d: %d/%d successful",
          start_index,
          end_index,
          batch_success,
          end_index - start_index + 1
        )
      )

      if end_index < total_count then
        vim.defer_fn(function()
          send_batch(end_index + 1)
        end, delay)
      else
        if show_summary then
          local message = success_count == 1 and "Added 1 file to Claude context"
            or string.format("Added %d files to Claude context", success_count)
          if total_count > success_count then
            message = message .. string.format(" (%d failed)", total_count - success_count)
          end

          if total_count > success_count then
            if success_count > 0 then
              logger.warn(context, message)
            else
              logger.error(context, message)
            end
          elseif success_count > 0 then
            logger.info(context, message)
          else
            logger.debug(context, message)
          end
        end
      end
    end

    send_batch(1)
  else
    local progress_interval = math.max(1, math.floor(total_count / 10))

    for i, file_path in ipairs(file_paths) do
      local success, error_msg = M._broadcast_at_mention(file_path)
      if success then
        success_count = success_count + 1
      else
        logger.error(context, "Failed to add file: " .. file_path .. " - " .. (error_msg or "unknown error"))
      end

      if total_count > 20 and i % progress_interval == 0 then
        logger.debug(
          context,
          string.format("Progress: %d/%d files processed (%d successful)", i, total_count, success_count)
        )
      end
    end

    if show_summary then
      local message = success_count == 1 and "Added 1 file to Claude context"
        or string.format("Added %d files to Claude context", success_count)
      if total_count > success_count then
        message = message .. string.format(" (%d failed)", total_count - success_count)
      end

      if total_count > success_count then
        if success_count > 0 then
          logger.warn(context, message)
        else
          logger.error(context, message)
        end
      elseif success_count > 0 then
        logger.info(context, message)
      else
        logger.debug(context, message)
      end
    end
  end

  return success_count, total_count
end

return M
