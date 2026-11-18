-- Origin: coder/claudecode.nvim@d1237072, lua/claudecode/init.lua (MIT, see LICENSE)
---@brief [[
--- The `:Claudinho` command: one command with a subcommand for everything the plugin does, its completion, and the
--- optional key mapping preset. The subcommands act on the active Claude tab (`claudinho.sessions`) and its window
--- (`claudinho.ui.window`); the ones that send something to Claude (`send`, `add`, `tree-add`, `send-text`) keep the
--- behavior of the commands they replaced.
---@brief ]]
---@module 'claudinho.commands'

local logger = require("claudinho.logger")
local notify = require("claudinho.notify")

local M = {}

---The subcommands, in the order the error and the completion list them.
---@type string[]
M.SUBCOMMANDS = {
  "toggle",
  "open",
  "hide",
  "focus",
  "new",
  "tab",
  "tab-next",
  "tab-prev",
  "tab-close",
  "tab-restart",
  "kill-all",
  "send",
  "add",
  "tree-add",
  "send-text",
  "diff-accept",
  "diff-deny",
  "close-all-diffs",
  "select-model",
}

---The key mapping preset (`keymaps.preset = true`): { lhs, mode, rhs, desc }.
---@type string[][]
M.PRESET = {
  { "<leader>ac", "n", "<cmd>Claudinho toggle<cr>", "Claudinho: toggle the Claude window" },
  { "<leader>af", "n", "<cmd>Claudinho focus<cr>", "Claudinho: focus the Claude window" },
  { "<leader>an", "n", "<cmd>Claudinho new<cr>", "Claudinho: new Claude tab" },
  { "<leader>al", "n", "<cmd>Claudinho tab-next<cr>", "Claudinho: next Claude tab" },
  { "<leader>ah", "n", "<cmd>Claudinho tab-prev<cr>", "Claudinho: previous Claude tab" },
  { "<leader>a1", "n", "<cmd>Claudinho tab 1<cr>", "Claudinho: Claude tab 1" },
  { "<leader>a2", "n", "<cmd>Claudinho tab 2<cr>", "Claudinho: Claude tab 2" },
  { "<leader>a3", "n", "<cmd>Claudinho tab 3<cr>", "Claudinho: Claude tab 3" },
  { "<leader>a4", "n", "<cmd>Claudinho tab 4<cr>", "Claudinho: Claude tab 4" },
  { "<leader>a5", "n", "<cmd>Claudinho tab 5<cr>", "Claudinho: Claude tab 5" },
  { "<leader>a6", "n", "<cmd>Claudinho tab 6<cr>", "Claudinho: Claude tab 6" },
  { "<leader>a7", "n", "<cmd>Claudinho tab 7<cr>", "Claudinho: Claude tab 7" },
  { "<leader>a8", "n", "<cmd>Claudinho tab 8<cr>", "Claudinho: Claude tab 8" },
  { "<leader>a9", "n", "<cmd>Claudinho tab 9<cr>", "Claudinho: Claude tab 9" },
  { "<leader>ax", "n", "<cmd>Claudinho tab-close<cr>", "Claudinho: close the active Claude tab" },
  { "<leader>am", "n", "<cmd>Claudinho select-model<cr>", "Claudinho: select the Claude model" },
  { "<leader>ab", "n", "<cmd>Claudinho add %<cr>", "Claudinho: add the current buffer to Claude" },
  { "<leader>as", "x", ":Claudinho send<cr>", "Claudinho: send the selection to Claude" },
  { "<leader>aa", "n", "<cmd>Claudinho diff-accept<cr>", "Claudinho: accept the diff" },
  { "<leader>ad", "n", "<cmd>Claudinho diff-deny<cr>", "Claudinho: deny the diff" },
}

---@return table sessions
local function sessions()
  return require("claudinho.sessions")
end

---@return table window
local function window()
  return require("claudinho.ui.window")
end

---Leave Visual mode before a command that moves focus, as the commands this one replaced did.
local function exit_visual()
  local mode = vim.fn.mode()
  if mode == "v" or mode == "V" or mode == "\22" then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
  end
end

---@param usage string The command line that is right, such as "tab <n>"
local function usage_error(usage)
  notify.error("[Claudinho] Usage: :Claudinho " .. usage)
end

---@param arg string|nil
---@return integer|nil n The integer the argument writes, or nil
local function to_number(arg)
  local n = arg and tonumber(arg)
  if n and n >= 1 and n % 1 == 0 then
    return n
  end
  return nil
end

---A number that names no tab: the error lists the tabs there are.
---@param arg string
local function unknown_tab(arg)
  notify.error(("[Claudinho] No Claude tab %s. Open tabs: %s"):format(arg, table.concat(sessions().numbers(), ", ")))
end

---The tab a numbered subcommand acts on. Replies or errors, and returns nil, when there is none.
---@param arg string The number as typed
---@return integer|nil n
local function existing_tab(arg)
  local n = to_number(arg)
  if not sessions().active() then
    notify.reply(sessions().NO_TABS)
    return nil
  end
  if not n or not sessions().state.tabs[n] then
    unknown_tab(arg)
    return nil
  end
  return n
end

---Add the files to the context of Claude, one @-mention each.
---@param file_paths table List of file paths to add
---@param options table|nil Optional settings: { delay?: number, show_summary?: boolean, context?: string }
---@return number success_count Number of successfully added files
---@return number total_count Total number of files attempted
local function add_paths_to_claude(file_paths, options)
  options = options or {}
  local delay = options.delay or 0
  local show_summary = options.show_summary ~= false
  local context = options.context or "command"

  if not file_paths or #file_paths == 0 then
    return 0, 0
  end

  local send_at_mention = function(file_path)
    return require("claudinho").send_at_mention(file_path, nil, nil, context)
  end

  local success_count = 0
  local total_count = #file_paths

  local function summarize()
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

  if delay > 0 then
    local function send_files_sequentially(index)
      if index > total_count then
        if show_summary then
          summarize()
        end
        return
      end

      local file_path = file_paths[index]
      local success, error_msg, start_failed = send_at_mention(file_path)
      if success then
        success_count = success_count + 1
      elseif start_failed then
        -- Claude did not start and `sessions.new` showed why: the other files would fail the same way.
        return
      else
        logger.error(context, "Failed to add file: " .. file_path .. " - " .. (error_msg or "unknown error"))
      end

      if index < total_count then
        vim.defer_fn(function()
          send_files_sequentially(index + 1)
        end, delay)
      elseif show_summary then
        summarize()
      end
    end

    send_files_sequentially(1)
  else
    for _, file_path in ipairs(file_paths) do
      local success, error_msg, start_failed = send_at_mention(file_path)
      if success then
        success_count = success_count + 1
      elseif start_failed then
        return success_count, total_count
      else
        logger.error(context, "Failed to add file: " .. file_path .. " - " .. (error_msg or "unknown error"))
      end
    end

    if show_summary and success_count > 0 then
      local message = success_count == 1 and "Added 1 file to Claude context"
        or string.format("Added %d files to Claude context", success_count)
      if total_count > success_count then
        message = message .. string.format(" (%d failed)", total_count - success_count)
      end
      logger.debug(context, message)
    end
  end

  return success_count, total_count
end

---Classify tree/explorer buffers by FILETYPE only. Matching the buffer name (an absolute path) misfires on ordinary
---files whose path merely contains a substring like "neo-tree"/"NvimTree" (issue #289). The downstream extractors
---(integrations.get_selected_files_from_tree / visual_commands.get_tree_state) are filetype-only, so a name-only
---match could never extract anyway.
---@param filetype string
---@return boolean
local function is_tree_filetype(filetype)
  return filetype == "NvimTree"
    or filetype == "neo-tree"
    or filetype == "oil"
    or filetype == "minifiles"
    or filetype == "netrw"
end

---`:Claudinho send` outside Visual mode: the files of a tree buffer, or the selection or the range of the buffer.
---@param opts table The command's options
local function handle_send_normal(opts)
  local current_ft = (vim.bo and vim.bo.filetype) or ""

  if is_tree_filetype(current_ft) then
    local integrations = require("claudinho.integrations")
    local files, error = integrations.get_selected_files_from_tree()

    if error then
      logger.error("command", "Claudinho send->TreeAdd: " .. error)
      return
    end

    if not files or #files == 0 then
      logger.warn("command", "Claudinho send->TreeAdd: No files selected")
      return
    end

    add_paths_to_claude(files, { context = "Claudinho send->TreeAdd" })

    return
  end

  local selection_module_ok, selection_module = pcall(require, "claudinho.selection")
  if selection_module_ok then
    -- Pass range information if available (for :'<,'> commands)
    local line1, line2 = nil, nil
    if opts and opts.range and opts.range > 0 then
      line1, line2 = opts.line1, opts.line2
    end
    local sent_successfully = selection_module.send_at_mention_for_visual_selection(line1, line2)
    if sent_successfully then
      -- Exit any potential visual mode (for consistency)
      pcall(function()
        if vim.api and vim.api.nvim_feedkeys then
          local esc = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
          vim.api.nvim_feedkeys(esc, "i", true)
        end
      end)
    end
  else
    logger.error("command", "Claudinho send: Failed to load selection module.")
  end
end

---`:Claudinho send` from Visual mode, after the mode was left and the selection captured.
---@param visual_data table|nil
local function handle_send_visual(visual_data)
  local current_ft = (vim.bo and vim.bo.filetype) or ""

  if is_tree_filetype(current_ft) then
    local integrations = require("claudinho.integrations")
    local visual_cmd_module = require("claudinho.visual_commands")
    local files, error

    -- For mini.files, try to get the range from visual marks for accuracy
    if current_ft == "minifiles" then
      local start_line = vim.fn.line("'<")
      local end_line = vim.fn.line("'>")

      if start_line > 0 and end_line > 0 and start_line <= end_line then
        files, error = integrations._get_mini_files_selection_with_range(start_line, end_line)
      else
        -- If range invalid, try visual selection fallback (uses pre-captured visual_data)
        files, error = visual_cmd_module.get_files_from_visual_selection(visual_data)
      end
    else
      -- Use visual selection-aware extraction for tree buffers (neo-tree, nvim-tree, oil)
      files, error = visual_cmd_module.get_files_from_visual_selection(visual_data)
      if (not files or #files == 0) and not error then
        -- Fallback: try generic selection if visual data was unavailable
        files, error = integrations.get_selected_files_from_tree()
      end
    end

    if error then
      logger.error("command", "Claudinho send_visual->TreeAdd: " .. error)
      return
    end

    if not files or #files == 0 then
      logger.warn("command", "Claudinho send_visual->TreeAdd: No files selected")
      return
    end

    add_paths_to_claude(files, { context = "Claudinho send_visual->TreeAdd" })
    return
  end

  -- Fall back to old visual selection logic for non-tree buffers
  if visual_data then
    local visual_commands = require("claudinho.visual_commands")
    local files, error = visual_commands.get_files_from_visual_selection(visual_data)

    if not error and files and #files > 0 then
      local success_count = add_paths_to_claude(files, {
        delay = 10,
        context = "Claudinho send_visual",
        show_summary = false,
      })
      if success_count > 0 then
        local message = success_count == 1 and "Added 1 file to Claude context from visual selection"
          or string.format("Added %d files to Claude context from visual selection", success_count)
        logger.debug("command", message)
      end
      return
    end
  end

  -- Handle regular text selection using range from visual mode
  local selection_module_ok, selection_module = pcall(require, "claudinho.selection")
  if not selection_module_ok then
    return
  end

  -- Use the marks left by visual mode instead of trying to get current visual selection
  local line1, line2 = vim.fn.line("'<"), vim.fn.line("'>")
  if line1 and line2 and line1 > 0 and line2 > 0 then
    selection_module.send_at_mention_for_visual_selection(line1, line2)
  else
    selection_module.send_at_mention_for_visual_selection()
  end
end

---`:Claudinho tree-add` outside Visual mode: the selected files of the tree explorer.
local function handle_tree_add_normal()
  local integrations = require("claudinho.integrations")
  local files, error = integrations.get_selected_files_from_tree()

  if error then
    logger.error("command", "Claudinho tree-add: " .. error)
    return
  end

  if not files or #files == 0 then
    logger.warn("command", "Claudinho tree-add: No files selected")
    return
  end

  -- Use connection-aware broadcasting for each file
  local success_count = 0
  local total_count = #files

  for _, file_path in ipairs(files) do
    local success, error_msg, start_failed =
      require("claudinho").send_at_mention(file_path, nil, nil, "Claudinho tree-add")
    if success then
      success_count = success_count + 1
    elseif start_failed then
      return
    else
      logger.error(
        "command",
        "Claudinho tree-add: Failed to add file: " .. file_path .. " - " .. (error_msg or "unknown error")
      )
    end
  end

  if success_count == 0 then
    logger.error("command", "Claudinho tree-add: Failed to add any files")
  elseif success_count < total_count then
    local message = string.format("Added %d/%d files to Claude context", success_count, total_count)
    logger.debug("command", message)
  else
    local message = success_count == 1 and "Added 1 file to Claude context"
      or string.format("Added %d files to Claude context", success_count)
    logger.debug("command", message)
  end
end

---`:Claudinho tree-add` from Visual mode, after the mode was left and the selection captured.
---@param visual_data table|nil
local function handle_tree_add_visual(visual_data)
  local visual_cmd_module = require("claudinho.visual_commands")
  local files, error = visual_cmd_module.get_files_from_visual_selection(visual_data)

  if error then
    logger.error("command", "Claudinho tree-add_visual: " .. error)
    return
  end

  if not files or #files == 0 then
    logger.warn("command", "Claudinho tree-add_visual: No files selected in visual range")
    return
  end

  -- Use connection-aware broadcasting for each file
  local success_count = 0
  local total_count = #files

  for _, file_path in ipairs(files) do
    local success, error_msg, start_failed =
      require("claudinho").send_at_mention(file_path, nil, nil, "Claudinho tree-add_visual")
    if success then
      success_count = success_count + 1
    elseif start_failed then
      return
    else
      logger.error(
        "command",
        "Claudinho tree-add_visual: Failed to add file: " .. file_path .. " - " .. (error_msg or "unknown error")
      )
    end
  end

  if success_count > 0 then
    local message = success_count == 1 and "Added 1 file to Claude context from visual selection"
      or string.format("Added %d files to Claude context from visual selection", success_count)
    logger.debug("command", message)

    if success_count < total_count then
      logger.warn("command", string.format("Added %d/%d files from visual selection", success_count, total_count))
    end
  else
    logger.error("command", "Claudinho tree-add_visual: Failed to add any files from visual selection")
  end
end

---`:Claudinho close-all-diffs`: reject the pending diffs (the open ones and the ones waiting for their tab), close the
---rejected ones, and close the accepted ones once the file or its buffer holds the accepted text.
local function close_all_diffs()
  -- A status="saved" diff holds the user's :w'd edits in its proposed buffer
  -- until the file holds them, so only close_saved_diffs, which first moves
  -- them into the file's buffer, may close it.
  local diff = require("claudinho.diff")
  local pending = diff.close_pending_diffs("user command")
  pending = pending + sessions().reject_all_pending("user command")
  local rejected = diff.close_rejected_diffs("user command")
  local saved, unsaved, kept = diff.close_saved_diffs("user command")
  if pending > 0 then
    notify.info(("Closed %d pending Claude diff(s)"):format(pending))
  end
  if rejected > 0 then
    notify.info(("Closed %d rejected Claude diff(s)"):format(rejected))
  end
  if saved > #unsaved then
    notify.info(("Closed %d accepted Claude diff(s). Their files hold the accepted text."):format(saved - #unsaved))
  end
  for _, entry in ipairs(unsaved) do
    local msg = ("The accepted Claude edits for %s are in its buffer, not saved: "):format(
      vim.fn.fnamemodify(entry.path, ":~:.")
    )
    if entry.fileencoding then
      msg = msg .. (":set fileencoding=utf-8 (%s cannot hold them), then "):format(entry.fileencoding)
    end
    notify.reply(msg .. ("%s writes them, :e! drops them"):format(entry.write))
  end
  for _, entry in ipairs(kept) do
    notify.reply(("Kept the accepted Claude diff for %s: %s"):format(vim.fn.fnamemodify(entry.path, ":~:."), entry.why))
  end
  if pending + rejected + saved + #kept == 0 then
    notify.reply("No Claude diffs to close")
  end
end

---`:Claudinho add <file> [start] [end]`.
---@param opts table The command's options
local function add(opts)
  if not opts.fargs[2] then
    logger.error("command", "Claudinho add: No file path provided")
    return
  end

  local args = { unpack(opts.fargs, 2) }
  local file_path = args[1]
  local start_line = args[2] and tonumber(args[2]) or nil
  local end_line = args[3] and tonumber(args[3]) or nil

  if #args > 3 then
    logger.error(
      "command",
      "Claudinho add: Too many arguments. Usage: Claudinho add <file-path> [start-line] [end-line]"
    )
    return
  end

  if args[2] and not start_line then
    logger.error("command", "Claudinho add: Invalid start line number: " .. args[2])
    return
  end

  if args[3] and not end_line then
    logger.error("command", "Claudinho add: Invalid end line number: " .. args[3])
    return
  end

  if start_line and start_line < 1 then
    logger.error("command", "Claudinho add: Start line must be positive: " .. start_line)
    return
  end

  if end_line and end_line < 1 then
    logger.error("command", "Claudinho add: End line must be positive: " .. end_line)
    return
  end

  if start_line and end_line and start_line > end_line then
    logger.error("command", "Claudinho add: Start line (" .. start_line .. ") must be <= end line (" .. end_line .. ")")
    return
  end

  -- Resolve the path argument. Vim's current/alternate-file tokens (`%`,
  -- `%:p`, `#`, `<cfile>`, ...) must still be expanded -- `:Claudinho add %`
  -- is the documented "add current buffer" keymap (README). But a plain
  -- filesystem path must NOT go through `vim.fn.expand`, which treats `$name`
  -- as an environment variable and strips undefined ones -- mangling literal
  -- `$` in paths (e.g. TanStack Router `$param` files like `src/routes/$post.tsx`)
  -- so the existence check below would fail. So: expand() only the special
  -- token forms; otherwise expand just a leading `~` and leave `$` intact.
  if file_path:match("^[%%#<]") then
    file_path = vim.fn.expand(file_path)
  else
    file_path = require("claudinho.utils").expand_tilde(file_path)
  end
  if vim.fn.filereadable(file_path) == 0 and vim.fn.isdirectory(file_path) == 0 then
    logger.error("command", "Claudinho add: File or directory does not exist: " .. file_path)
    return
  end

  local claude_start_line = start_line and (start_line - 1) or nil
  local claude_end_line = end_line and (end_line - 1) or nil

  local success, error_msg =
    require("claudinho").send_at_mention(file_path, claude_start_line, claude_end_line, "Claudinho add")
  if not success then
    logger.error("command", "Claudinho add: " .. (error_msg or "Failed to add file"))
  else
    local message = "Claudinho add: Successfully added " .. file_path
    if start_line or end_line then
      if start_line and end_line then
        message = message .. " (lines " .. start_line .. "-" .. end_line .. ")"
      elseif start_line then
        message = message .. " (from line " .. start_line .. ")"
      end
    end
    logger.debug("command", message)
  end
end

---One function per subcommand: `(opts, bang)`, where `opts` are the options Neovim gave the command and `bang` says
---whether the command had a `!` (or the subcommand is `send-text!`).
---@type table<string, fun(opts: table, bang: boolean)>
local handlers = {}

function handlers.toggle()
  exit_visual()
  if sessions().active() then
    window().toggle()
  else
    sessions().new()
  end
end

function handlers.open()
  if sessions().active() then
    window().show({ focus = true })
  else
    sessions().new()
  end
end

function handlers.hide()
  if not sessions().active() then
    notify.reply(sessions().NO_TABS)
    return
  end
  window().hide()
end

function handlers.focus()
  exit_visual()
  if sessions().active() then
    window().focus()
  else
    sessions().new()
  end
end

function handlers.new()
  sessions().new()
end

handlers["tab"] = function(opts)
  local arg = opts.fargs[2]
  if not arg or #opts.fargs > 2 then
    usage_error("tab <n>")
    return
  end
  local n = existing_tab(arg)
  if n and sessions().activate(n) then
    window().show({ focus = false })
  end
end

handlers["tab-next"] = function()
  if not sessions().active() then
    notify.reply(sessions().NO_TABS)
    return
  end
  sessions().next()
  window().show({ focus = false })
end

handlers["tab-prev"] = function()
  if not sessions().active() then
    notify.reply(sessions().NO_TABS)
    return
  end
  sessions().prev()
  window().show({ focus = false })
end

handlers["tab-close"] = function(opts)
  local arg = opts.fargs[2]
  if #opts.fargs > 2 then
    usage_error("tab-close [n]")
    return
  end
  if not sessions().active() then
    notify.reply(sessions().NO_TABS)
    return
  end
  local n = sessions().state.active
  if arg then
    n = existing_tab(arg)
  end
  if n then
    sessions().close(n)
  end
end

handlers["tab-restart"] = function(opts)
  local arg = opts.fargs[2]
  if not arg or #opts.fargs > 2 then
    usage_error("tab-restart <n>")
    return
  end
  local n = existing_tab(arg)
  if n then
    sessions().restart(n)
  end
end

handlers["kill-all"] = function()
  sessions().kill_all()
end

function handlers.send(opts)
  local visual_commands = require("claudinho.visual_commands")
  visual_commands.create_visual_command_wrapper(handle_send_normal, handle_send_visual)(opts)
end

handlers["add"] = add

handlers["tree-add"] = function(opts)
  local visual_commands = require("claudinho.visual_commands")
  visual_commands.create_visual_command_wrapper(handle_tree_add_normal, handle_tree_add_visual)(opts)
end

handlers["send-text"] = function(opts, bang)
  local text = (opts.args or ""):match("^%S+%s*(.*)$")
  if not text or text == "" then
    usage_error("send-text <text>")
    return
  end
  -- Bang (`:Claudinho! send-text`, or `send-text!`) inserts the text without submitting it.
  require("claudinho.terminal").send_to_terminal(text, { submit = not bang })
end

handlers["diff-accept"] = function()
  require("claudinho.diff").accept_current_diff()
end

handlers["diff-deny"] = function()
  require("claudinho.diff").deny_current_diff()
end

handlers["close-all-diffs"] = close_all_diffs

handlers["select-model"] = function()
  require("claudinho").open_with_model()
end

---Run `:Claudinho`. Without a subcommand it is `toggle`.
---@param opts table The options of `nvim_create_user_command`: `fargs`, `args`, `bang`, `range`, `line1`, `line2`
function M.run(opts)
  local sub = opts.fargs and opts.fargs[1] or nil
  local bang = opts.bang == true
  if sub == nil then
    sub = "toggle"
  elseif sub == "send-text!" then
    sub, bang = "send-text", true
  end
  local handler = handlers[sub]
  if not handler then
    notify.error(("[Claudinho] Unknown subcommand '%s'. Valid: %s"):format(sub, table.concat(M.SUBCOMMANDS, ", ")))
    return
  end
  handler(opts, bang)
end

---Complete `:Claudinho`: the subcommands, the numbers of the tabs for `tab`, `tab-close` and `tab-restart`, and the
---files for `add`.
---@param arg_lead string The word being completed
---@param cmd_line string The whole command line
---@param cursor_pos integer|nil
---@return string[]
function M.complete(arg_lead, cmd_line, cursor_pos)
  local before = cursor_pos and cmd_line:sub(1, cursor_pos) or cmd_line
  local rest = before:match("Claudinho!?%s+(.*)$") or ""
  local words = {}
  for word in rest:gmatch("%S+") do
    words[#words + 1] = word
  end
  -- The word under the cursor is not complete yet unless the line ends in a space.
  local index = rest:match("%s$") and #words + 1 or math.max(#words, 1)

  local matches = {}
  if index == 1 then
    for _, name in ipairs(M.SUBCOMMANDS) do
      if name:sub(1, #arg_lead) == arg_lead then
        matches[#matches + 1] = name
      end
    end
  elseif index == 2 then
    local sub = words[1]
    if sub == "tab" or sub == "tab-close" or sub == "tab-restart" then
      for _, n in ipairs(sessions().numbers()) do
        local text = tostring(n)
        if text:sub(1, #arg_lead) == arg_lead then
          matches[#matches + 1] = text
        end
      end
    elseif sub == "add" then
      matches = vim.fn.getcompletion(arg_lead, "file")
    end
  end
  return matches
end

---Map the preset keys (`keymaps.preset = true`). A key that already has a mapping is left alone, with an informative
---notice; a key the preset mapped itself earlier (the same description) is mapped again without one.
---@param config table|nil The merged plugin configuration
function M.apply_preset(config)
  if not (config and config.keymaps and config.keymaps.preset == true) then
    return
  end
  for _, key in ipairs(M.PRESET) do
    local lhs, mode, rhs, desc = key[1], key[2], key[3], key[4]
    local existing = vim.fn.maparg(lhs, mode, false, true)
    local taken = type(existing) == "table" and next(existing) ~= nil and existing.desc ~= desc
    if taken then
      notify.info(("[Claudinho] keymaps.preset left %s alone: it is already mapped."):format(lhs), { once = true })
    else
      vim.keymap.set(mode, lhs, rhs, { desc = desc })
    end
  end
end

---Create `:Claudinho` and, with `keymaps.preset`, the preset keys.
---@param config table|nil The merged plugin configuration
function M.setup(config)
  vim.api.nvim_create_user_command("Claudinho", M.run, {
    nargs = "*",
    range = true,
    bang = true,
    complete = M.complete,
    desc = "Claudinho: the Claude window and its tabs (" .. table.concat(M.SUBCOMMANDS, ", ") .. ")",
  })
  M.apply_preset(config)
end

return M
