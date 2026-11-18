-- Success criterion 5 of base-ui, measured as addendum (2) of the plan says (rules 3, 57, 61, 62): with the stub claude
-- (tests/bin/claude), which writes nothing, the plugin is the only thing that could write. After opening, using and
-- closing three tabs, `~/.claude/settings.json`, `~/.claude.json` and the `.claude/` of the project (a private HOME and
-- project) have the same SHA-256 as before, and so does everything else under them, a foreign lock file included.
-- Only the processes of the tabs get the plugin's environment. The "external claude does not connect by itself" half of
-- the criterion needs the real CLI: manual script 10 and 18.
-- Under busted's mock vim it is pending; scripts/run_integration_tests_individually.sh runs it in Neovim.
if vim == nil or vim.fn.has("nvim") ~= 1 or (vim.uv or vim.loop) == nil or vim.wait == nil or vim.system == nil then
  describe("criterion: nothing changes outside the plugin's sessions", function()
    pending("needs a real Neovim")
  end)
  return
end

describe("criterion: nothing changes outside the plugin's sessions", function()
  local criteria = require("tests.helpers.criteria")
  local ws_client = require("tests.helpers.ws_client")

  local PLUGIN_VARS = { "CLAUDE_CODE_SSE_PORT", "CLAUDINHO_PORT", "CLAUDINHO_TOKEN" }

  local ctx, sessions, work, project, saved_cwd, saved_vars, foreign, foreign_lock

  ---@param path string
  ---@param lines string[]
  local function write(path, lines)
    vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
    vim.fn.writefile(lines, path)
  end

  ---@return table state Everything under the private HOME and under the `.claude/` of the project
  local function snapshot()
    return {
      home = criteria.tree_state(ctx.env.home),
      project_claude = criteria.tree_state(project .. "/.claude"),
      settings = criteria.sha_of_file(ctx.env.home .. "/.claude/settings.json"),
      claude_json = criteria.sha_of_file(ctx.env.home .. "/.claude.json"),
    }
  end

  ---Start a plain terminal that writes its environment to a file, and read that environment.
  ---@return table<string, string> env
  local function plain_terminal_env()
    local out = work .. "/plain-terminal-env.txt"
    vim.fn.delete(out)
    local original = vim.api.nvim_get_current_win()
    vim.cmd("botright new")
    local job = vim.fn.jobstart(
      { "sh", "-c", "env > " .. out .. ".tmp && mv " .. out .. ".tmp " .. out },
      { term = true }
    )
    assert.is_true(job > 0)
    assert.is_true(vim.wait(5000, function()
      return vim.fn.filereadable(out) == 1
    end, 20))
    vim.cmd("stopinsert")
    vim.cmd("bwipeout!")
    if vim.api.nvim_win_is_valid(original) then
      vim.api.nvim_set_current_win(original)
    end
    local env = {}
    for _, line in ipairs(vim.fn.readfile(out)) do
      local key, value = line:match("^([%w_]+)=(.*)$")
      if key then
        env[key] = value
      end
    end
    return env
  end

  before_each(function()
    -- A shell that already holds these variables would hand them to every plain terminal: the criterion is about what
    -- the plugin adds, so the spec starts without them and puts them back after.
    saved_vars = {}
    for _, name in ipairs(PLUGIN_VARS) do
      saved_vars[name] = vim.env[name]
      vim.env[name] = nil
    end
    saved_cwd = vim.fn.getcwd()

    ctx = criteria.start(nil, { claude_dir_in_home = true })
    sessions = ctx.sessions
    work = vim.fn.tempname() .. "-criteria-isolation"
    project = work .. "/project"
    -- What the CLI and the user own: the settings of the user and of the project, `~/.claude.json`, and a lock file of
    -- another editor that lives (the lock of a process that runs).
    write(ctx.env.home .. "/.claude/settings.json", { '{"theme":"dark"}' })
    write(ctx.env.home .. "/.claude.json", { '{"autoConnectIde":false,"numStartups":3}' })
    write(project .. "/.claude/settings.json", { '{"permissions":{"allow":[]}}' })
    write(project .. "/.claude/settings.local.json", { "{}" })
    write(project .. "/a.txt", { "one", "two", "three" })
    write(project .. "/b.txt", { "alpha" })
    foreign = vim.system({ "sleep", "30" })
    foreign_lock = ctx.env.lock_dir .. "/54321.lock"
    write(foreign_lock, {
      vim.json.encode({ pid = foreign.pid, workspaceFolders = { project }, ideName = "Other", transport = "ws" }),
    })
    vim.cmd("cd " .. vim.fn.fnameescape(project))
    vim.cmd("edit " .. vim.fn.fnameescape(project .. "/a.txt"))
  end)

  after_each(function()
    criteria.stop(ctx)
    if foreign then
      pcall(function()
        foreign:kill(9)
      end)
    end
    vim.cmd("cd " .. vim.fn.fnameescape(saved_cwd))
    vim.fn.delete(work, "rf")
    for _, name in ipairs(PLUGIN_VARS) do
      vim.env[name] = saved_vars[name]
    end
  end)

  it("writes nothing outside its own sessions through three tabs opened, used and closed", function()
    local before = snapshot()
    assert.is_not_nil(before.settings)
    assert.is_not_nil(before.claude_json)
    assert.is_not_nil(before.home[".claude/ide/54321.lock"])

    local editor = vim.api.nvim_get_current_win()
    local first = assert(sessions.new())
    local second = assert(sessions.new())
    local third = assert(sessions.new())
    -- The plugin did write its own files meanwhile: three lock files, and settings files outside HOME and the project.
    assert.equals(4, #criteria.lock_files(ctx.env.lock_dir))
    for _, tab in ipairs({ first, second, third }) do
      assert.is_nil(tab.settings_path:find(ctx.env.home, 1, true))
      assert.is_nil(tab.settings_path:find(project, 1, true))
    end

    -- Use them: a client, a selection, an @-mention, a diff that is rejected, switching, hiding and showing.
    local client = ws_client.connect(first.lock_port, first.token)
    assert.is_true(sessions.activate(1))
    vim.api.nvim_set_current_win(editor)
    vim.api.nvim_win_set_cursor(editor, { 2, 0 })
    require("claudinho.selection").update_selection()
    assert.is_not_nil(criteria.next_of(client, "selection_changed", 1500))
    vim.cmd("Claudinho add " .. vim.fn.fnameescape(project .. "/b.txt"))
    assert.is_not_nil(criteria.next_of(client, "at_mentioned", 5000))
    client:send({
      jsonrpc = "2.0",
      id = 5,
      method = "tools/call",
      params = {
        name = "openDiff",
        arguments = {
          old_file_path = project .. "/a.txt",
          new_file_path = project .. "/a.txt",
          new_file_contents = "one\nTWO\nthree\n",
          tab_name = "isolation-diff",
        },
      },
    })
    assert.is_true(vim.wait(3000, function()
      return next(require("claudinho.diff")._get_active_diffs()) ~= nil
    end, 20))
    vim.cmd("Claudinho diff-deny")
    local reply = assert(client:next_message(3000))
    assert.equals("DIFF_REJECTED", reply.result.content[1].text)
    vim.cmd("Claudinho tab 2")
    vim.cmd("Claudinho hide")
    vim.cmd("Claudinho open")
    vim.cmd("Claudinho tab-close 3")
    vim.cmd("Claudinho kill-all")
    client:close()

    assert.same({}, sessions.state.tabs)
    local after = snapshot()
    assert.same(before, after)
    assert.equals(1, #criteria.lock_files(ctx.env.lock_dir))
    assert.equals(1, vim.fn.filereadable(foreign_lock))
    assert.equals("one", vim.fn.readfile(project .. "/a.txt")[1])
    assert.same({ "one", "two", "three" }, vim.fn.readfile(project .. "/a.txt"))
  end)

  it("keeps a foreign lock file in place when the tabs are killed", function()
    assert(sessions.new())
    assert(sessions.new())

    sessions.kill_all()

    assert.same({ "54321.lock" }, criteria.lock_files(ctx.env.lock_dir))
    assert.equals(1, vim.fn.filereadable(foreign_lock))
  end)

  it("gives the plugin's environment to the processes of the tabs only", function()
    ctx.plugin.state.config.terminal_cmd = ctx.env.idle_cmd
    local tab = assert(sessions.new())
    assert.is_true(vim.wait(5000, function()
      return require("tests.helpers.tab_env").read_env(ctx.env) ~= nil
    end, 20))
    local tab_vars = require("tests.helpers.tab_env").read_env(ctx.env)
    assert.equals(tostring(tab.lock_port), tab_vars.CLAUDE_CODE_SSE_PORT)
    assert.equals(tostring(tab.lock_port), tab_vars.CLAUDINHO_PORT)
    assert.equals(tab.token, tab_vars.CLAUDINHO_TOKEN)

    local plain = plain_terminal_env()

    for _, name in ipairs(PLUGIN_VARS) do
      assert.is_nil(plain[name], name .. " reached a plain terminal")
      assert.is_nil(vim.env[name], name .. " is in the environment of Neovim")
    end
  end)
end)
