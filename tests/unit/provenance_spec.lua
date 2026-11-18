-- luacheck: globals expect
require("tests.busted_setup")

describe("provenance lines", function()
  local root = require("pl.path").abspath(debug.getinfo(1, "S").source:sub(2)):match("^(.*)/tests/unit/[^/]+$")

  -- module file (under lua/claudinho/) -> file it comes from in the upstream
  local from_upstream = {
    ["commands.lua"] = "lua/claudecode/init.lua",
    ["config.lua"] = "lua/claudecode/config.lua",
    ["diff.lua"] = "lua/claudecode/diff.lua",
    ["diff_inline.lua"] = "lua/claudecode/diff_inline.lua",
    ["health.lua"] = "lua/claudecode/health.lua",
    ["init.lua"] = "lua/claudecode/init.lua",
    ["integrations.lua"] = "lua/claudecode/integrations.lua",
    ["lockfile.lua"] = "lua/claudecode/lockfile.lua",
    ["logger.lua"] = "lua/claudecode/logger.lua",
    ["mention_queue.lua"] = "lua/claudecode/init.lua",
    ["selection.lua"] = "lua/claudecode/selection.lua",
    ["session.lua"] = "lua/claudecode/terminal.lua",
    ["terminal.lua"] = "lua/claudecode/terminal.lua",
    ["types.lua"] = "lua/claudecode/types.lua",
    ["utils.lua"] = "lua/claudecode/utils.lua",
    ["visual_commands.lua"] = "lua/claudecode/visual_commands.lua",
    ["server/client.lua"] = "lua/claudecode/server/client.lua",
    ["server/frame.lua"] = "lua/claudecode/server/frame.lua",
    ["server/handshake.lua"] = "lua/claudecode/server/handshake.lua",
    ["server/init.lua"] = "lua/claudecode/server/init.lua",
    ["server/mock.lua"] = "lua/claudecode/server/mock.lua",
    ["server/tcp.lua"] = "lua/claudecode/server/tcp.lua",
    ["server/utils.lua"] = "lua/claudecode/server/utils.lua",
    ["terminal/paste_fix.lua"] = "lua/claudecode/terminal/paste_fix.lua",
    ["tools/check_document_dirty.lua"] = "lua/claudecode/tools/check_document_dirty.lua",
    ["tools/close_all_diff_tabs.lua"] = "lua/claudecode/tools/close_all_diff_tabs.lua",
    ["tools/close_tab.lua"] = "lua/claudecode/tools/close_tab.lua",
    ["tools/get_current_selection.lua"] = "lua/claudecode/tools/get_current_selection.lua",
    ["tools/get_diagnostics.lua"] = "lua/claudecode/tools/get_diagnostics.lua",
    ["tools/get_latest_selection.lua"] = "lua/claudecode/tools/get_latest_selection.lua",
    ["tools/get_open_editors.lua"] = "lua/claudecode/tools/get_open_editors.lua",
    ["tools/get_workspace_folders.lua"] = "lua/claudecode/tools/get_workspace_folders.lua",
    ["tools/init.lua"] = "lua/claudecode/tools/init.lua",
    ["tools/open_diff.lua"] = "lua/claudecode/tools/open_diff.lua",
    ["tools/open_file.lua"] = "lua/claudecode/tools/open_file.lua",
    ["tools/save_document.lua"] = "lua/claudecode/tools/save_document.lua",
    ["ui/window.lua"] = "lua/claudecode/terminal/native.lua",
  }

  -- new modules, with no file in the upstream: no origin line
  local new_modules = {
    "conflict.lua",
    "notify.lua",
    "sessions.lua",
    "session_settings.lua",
    "sources/relay.lua",
    "sources/session_data.lua",
    "ui/tabbar.lua",
    "ui/status.lua",
    "server/http.lua",
  }

  local function first_line(path)
    local f = assert(io.open(path, "r"), "cannot open " .. path)
    local line = f:read("*l")
    f:close()
    return line
  end

  local function origin(upstream)
    return "-- Origin: coder/claudecode.nvim@d1237072, " .. upstream .. " (MIT, see LICENSE)"
  end

  local modules = {}
  for module in pairs(from_upstream) do
    table.insert(modules, module)
  end
  table.sort(modules)

  for _, module in ipairs(modules) do
    local upstream = from_upstream[module]
    it("lua/claudinho/" .. module .. " points to " .. upstream, function()
      expect(first_line(root .. "/lua/claudinho/" .. module)).to_be(origin(upstream))
    end)
  end

  it("plugin/claudinho.lua points to plugin/claudecode.lua", function()
    expect(first_line(root .. "/plugin/claudinho.lua")).to_be(origin("plugin/claudecode.lua"))
  end)

  for _, module in ipairs(new_modules) do
    it("lua/claudinho/" .. module .. " has no origin line", function()
      local line = first_line(root .. "/lua/claudinho/" .. module)
      expect(line:find("Origin: coder/claudecode.nvim", 1, true)).to_be_nil()
    end)
  end

  it("every module under lua/claudinho is in the table or in the new modules", function()
    local known = {}
    for _, module in ipairs(modules) do
      known[module] = true
    end
    for _, module in ipairs(new_modules) do
      known[module] = true
    end
    local handle = assert(io.popen("cd '" .. root .. "/lua/claudinho' && find . -name '*.lua' | sort"))
    local unknown = {}
    for path in handle:lines() do
      local module = path:gsub("^%./", "")
      if not known[module] then
        table.insert(unknown, module)
      end
    end
    handle:close()
    expect(#unknown).to_be(0)
  end)
end)
