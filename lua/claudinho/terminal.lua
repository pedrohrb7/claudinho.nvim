--- The terminal of the active Claude tab, seen from the rest of the plugin. Each tab is a `claudinho.session` shown in
--- `claudinho.ui.window`; this module is only a facade over them, for the code (diff, selection, send) that wants "the
--- Claude terminal" and does not care which tab it is.
--- @module 'claudinho.terminal'

local M = {}

---Configures the terminal: the streamed-paste shim (#161), a no-op on Neovim >= 0.12.2. `terminal.auto_insert` is read
---from the configuration of each tab by the window.
---@param term_config { fix_streamed_paste?: boolean|"auto", auto_insert?: boolean }|nil The `terminal` table of the merged configuration (only these keys are read)
function M.setup(term_config)
  if term_config ~= nil and type(term_config) ~= "table" then
    require("claudinho.notify").error("[Claudinho] claudinho.terminal.setup expects a table or nil")
    term_config = nil
  end
  require("claudinho.terminal.paste_fix").apply(term_config and term_config.fix_streamed_paste)
end

---The buffer of the active tab: the terminal of its Claude, running or ended.
---@return number|nil bufnr The buffer, or nil without tabs
function M.get_active_terminal_bufnr()
  local sessions = package.loaded["claudinho.sessions"]
  if type(sessions) ~= "table" then
    return nil
  end
  local s = sessions.active()
  if s and s.buf and vim.api.nvim_buf_is_valid(s.buf) then
    return s.buf
  end
  return nil
end

---Bring the window back, without taking the focus, when it was hidden. A diff that closes calls this.
function M.ensure_visible()
  require("claudinho.ui.window").ensure_visible()
end

---Show the window with the active tab and focus it. Without tabs, start the first one.
function M.open()
  local sessions = require("claudinho.sessions")
  if sessions.active() then
    require("claudinho.ui.window").show({ focus = true })
  else
    sessions.new()
  end
end

---Sends raw text to the job of the active tab, as if it were typed at the prompt. By default a trailing carriage return
---submits the line. It does not start a tab: without one, or when the active tab has exited, it replies and returns
---false.
---
---Multi-line text is wrapped in bracketed-paste markers (ESC[200~ ... ESC[201~) so embedded newlines arrive as one
---literal pasted block rather than several premature submits; the submit carriage return is sent after the closing
---marker so it still triggers submission. `chansend` writes straight to the PTY and bypasses `vim.paste`, so the
---`fix_streamed_paste` shim is irrelevant here. `:Claudinho send-text` is a thin wrapper around this.
---@param text string The text to send. Must be a non-empty string.
---@param opts { submit?: boolean, focus?: boolean }? `submit` (default true) appends a carriage return so Claude submits the line; `focus` (default false) focuses the terminal after a successful send.
---@return boolean success Whether the text was written to a terminal channel.
function M.send_to_terminal(text, opts)
  local logger = require("claudinho.logger")
  local notify = require("claudinho.notify")
  local sessions = require("claudinho.sessions")

  if type(text) ~= "string" or text == "" then
    notify.reply("Cannot send text: no text provided")
    return false
  end

  opts = opts or {}
  local submit = opts.submit ~= false

  local s = sessions.active()
  if not s then
    notify.reply(sessions.NO_TABS)
    return false
  end
  if s.state ~= "running" then
    notify.reply(sessions.exited_message(s))
    return false
  end

  local bufnr = M.get_active_terminal_bufnr()
  if not bufnr then
    notify.reply("Cannot send text: no Claude terminal is currently running.")
    return false
  end

  -- termopen() sets both b:terminal_job_id and the 'channel' option to the job id. The 'channel'
  -- fallback covers a Neovim that stops setting b:terminal_job_id, which is deprecated.
  local chan = vim.b[bufnr] and vim.b[bufnr].terminal_job_id
  if not chan or chan == 0 then
    chan = vim.bo[bufnr].channel
  end
  if not chan or chan == 0 then
    notify.reply("Cannot send text: no terminal job channel for buffer " .. tostring(bufnr))
    return false
  end

  -- Normalize line endings so the ONLY submit byte is the trailing CR added below.
  -- A bare "\r" is Enter at Claude's prompt, so any interior CR (e.g. CRLF or old-Mac
  -- text from a programmatic caller) would otherwise fire one or more premature submits
  -- -- the exact failure mode the bracketed-paste wrapping exists to prevent.
  local normalized = (text:gsub("\r\n", "\n"):gsub("\r", "\n"))

  local payload = normalized
  if string.find(normalized, "\n", 1, true) then
    -- Multi-line: bracketed paste so the newlines arrive as one literal block.
    payload = "\27[200~" .. normalized .. "\27[201~"
  end
  if submit then
    payload = payload .. "\r"
  end

  -- chansend can reject (0 bytes) or error if the channel is closed. Honor that instead of reporting a false success.
  local ok_send, written = pcall(vim.fn.chansend, chan, payload)
  if not ok_send or written == 0 then
    notify.reply("Cannot send text: the Claude terminal channel is closed (the process may have exited).")
    return false
  end
  logger.debug(
    "terminal",
    string.format(
      "send_to_terminal: wrote %d byte(s) to channel %s (submit=%s)",
      #payload,
      tostring(chan),
      tostring(submit)
    )
  )

  if opts.focus then
    M.open()
  end

  return true
end

return M
