-- Dump the screen of the active tab's Claude terminal into a TUI fixture.
--
-- Origin of the fixtures: tests/fixtures/tui/<claude version>/ holds screens of the Claude Code TUI, one per file.
-- The ones in tests/fixtures/tui/2.1.328/ were measured on Claude Code 2.1.328 (spec of the status-interativo
-- feature, section 11, docs/features/status-interativo/spec.md); the others are captured with this script.
-- Fixtures keep the real bytes of the screen, notably U+00A0 after the prompt character, and use "-" for dashes.
--
-- Capture a new screen:
--   1. Open a real claudinho session (a scratch folder with git and any file, no secrets on the screen).
--   2. Bring the TUI to the wanted state (a dialog, a mode, text typed in the prompt, ...).
--   3. Run, from any window of that tab:  :luafile scripts/dump_tui_screen.lua
--      It asks for the fixture name (an empty answer cancels). To skip the prompt, pass the name through the chunk:
--        :lua loadfile("scripts/dump_tui_screen.lua")("<name>")
--      The last 120 lines of the active tab's Claude buffer go to tests/fixtures/tui/<claude version>/<name>.txt;
--      <claude version> comes from `claude --version`. An existing file is never overwritten.
--   4. Review the file by hand before committing it.
--
-- The script only reads the buffer: it sends nothing to the terminal.

local MAX_LINES = 120

local function repo_root()
  local source = debug.getinfo(1, "S").source
  if source:sub(1, 1) == "@" then
    return vim.fn.fnamemodify(source:sub(2), ":p:h:h")
  end
  return vim.fn.getcwd()
end

-- The name comes from the chunk argument (`loadfile(...)("<name>")`); :luafile takes none, so it is asked for.
local name = select(1, ...)
if name == nil then
  name = vim.trim(vim.fn.input("Fixture name: "))
  if name == "" then
    vim.notify("dump_tui_screen: cancelled, no name given")
    return
  end
end
if type(name) ~= "string" or not name:match("^[%w_%-]+$") then
  vim.notify("dump_tui_screen: the name takes letters, digits, _ and -", vim.log.levels.ERROR)
  return
end

local terminal = require("claudinho.terminal")
local config = require("claudinho.config").current() or {}
local cmd = type(config.terminal_cmd) == "string" and config.terminal_cmd ~= "" and config.terminal_cmd or "claude"
local exe = vim.split(cmd, "%s+", { trimempty = true })[1] or "claude"

local buf = terminal.get_active_terminal_bufnr()
if not buf or not vim.api.nvim_buf_is_valid(buf) then
  vim.notify("dump_tui_screen: no Claude terminal in the active tab", vim.log.levels.ERROR)
  return
end

local ok, output = pcall(vim.fn.system, { exe, "--version" })
local version = ok and vim.v.shell_error == 0 and output:match("(%d+%.%d+%.%d+)") or nil
if not version then
  vim.notify("dump_tui_screen: cannot read the version from `" .. exe .. " --version`", vim.log.levels.ERROR)
  return
end

local dir = repo_root() .. "/tests/fixtures/tui/" .. version
local path = dir .. "/" .. name .. ".txt"
if vim.uv.fs_stat(path) then
  vim.notify("dump_tui_screen: " .. path .. " exists; refusing to overwrite", vim.log.levels.ERROR)
  return
end

local count = vim.api.nvim_buf_line_count(buf)
local lines = vim.api.nvim_buf_get_lines(buf, math.max(0, count - MAX_LINES), count, false)
-- The terminal buffer is padded with blank lines below the screen; drop the trailing ones.
while #lines > 0 and lines[#lines]:match("^%s*$") do
  lines[#lines] = nil
end

vim.fn.mkdir(dir, "p")
local written = vim.fn.writefile(lines, path)
if written ~= 0 then
  vim.notify("dump_tui_screen: could not write " .. path, vim.log.levels.ERROR)
  return
end
vim.notify(("dump_tui_screen: wrote %d lines to %s"):format(#lines, path))
