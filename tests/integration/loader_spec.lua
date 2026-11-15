-- Real-Neovim check of the claudecode.nvim guard: a child Neovim sources plugin/claudinho.lua. Mock vim has no
-- child process to start, so under busted this is pending.
if vim == nil or vim.fn.has("nvim") ~= 1 or vim.system == nil then
  describe("claudecode.nvim guard", function()
    pending("needs a real Neovim")
  end)
  return
end

describe("claudecode.nvim guard", function()
  local root = vim.fn.getcwd()
  local script

  local function run(prelude)
    local code = table.concat({
      "vim.opt.rtp:prepend(" .. string.format("%q", root) .. ")",
      prelude,
      "vim.cmd('runtime plugin/claudinho.lua')",
      "local ok = pcall(function() require('claudinho').setup({ auto_start = false }) end)",
      "local msgs = vim.api.nvim_exec2('messages', { output = true }).output",
      "local _, count = msgs:gsub('claudecode.nvim is also loaded', '')",
      "io.stdout:write(table.concat({",
      "  'ok=' .. tostring(ok),",
      "  'count=' .. count,",
      "  'start=' .. vim.fn.exists(':ClaudeCodeStart'),",
      "}, ';'))",
    }, "\n")
    vim.fn.writefile(vim.split(code, "\n"), script)
    local res = vim
      .system({ vim.v.progpath, "--headless", "-u", "NONE", "-i", "NONE", "-l", script }, { text = true })
      :wait(30000)
    return (res.stdout or "") .. (res.stderr or "")
  end

  before_each(function()
    script = vim.fn.tempname() .. ".lua"
  end)

  after_each(function()
    vim.fn.delete(script)
  end)

  it("shows the warning once and creates no commands when claudecode.nvim is loaded", function()
    local out = run("vim.g.loaded_claudecode = 1")
    assert.is_truthy(out:find("ok=true", 1, true), out)
    assert.is_truthy(out:find("count=1", 1, true), out)
    assert.is_truthy(out:find("start=0", 1, true), out)
  end)

  it("creates the commands without claudecode.nvim", function()
    local out = run("")
    assert.is_truthy(out:find("ok=true", 1, true), out)
    assert.is_truthy(out:find("count=0", 1, true), out)
    assert.is_truthy(out:find("start=2", 1, true), out)
  end)

  it("warns once and does not set up when claudecode.nvim is on the runtimepath and setup() runs from init", function()
    local fake = vim.fn.tempname()
    vim.fn.mkdir(fake .. "/lua/claudecode", "p")
    vim.fn.mkdir(fake .. "/plugin", "p")
    vim.fn.writefile({ "return {}" }, fake .. "/lua/claudecode/init.lua")
    vim.fn.writefile({ "vim.g.loaded_claudecode = 1" }, fake .. "/plugin/claudecode.lua")
    local code = table.concat({
      "vim.opt.rtp:prepend(" .. string.format("%q", root) .. ")",
      "vim.opt.rtp:prepend(" .. string.format("%q", fake) .. ")",
      "local c = require('claudinho')",
      "c.setup({ auto_start = false })",
      "local msgs = vim.api.nvim_exec2('messages', { output = true }).output",
      "local _, count = msgs:gsub('claudecode.nvim is also loaded', '')",
      "io.stdout:write(table.concat({",
      "  'count=' .. count,",
      "  'init=' .. tostring(c.state.initialized),",
      "  'start=' .. vim.fn.exists(':ClaudeCodeStart'),",
      "}, ';'))",
    }, "\n")
    vim.fn.writefile(vim.split(code, "\n"), script)
    local res = vim
      .system({ vim.v.progpath, "--headless", "-u", "NONE", "-i", "NONE", "-l", script }, { text = true })
      :wait(30000)
    local out = (res.stdout or "") .. (res.stderr or "")
    vim.fn.delete(fake, "rf")
    assert.is_truthy(out:find("count=1", 1, true), out)
    assert.is_truthy(out:find("init=false", 1, true), out)
    assert.is_truthy(out:find("start=0", 1, true), out)
  end)
end)
