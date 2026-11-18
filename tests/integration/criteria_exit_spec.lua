-- Success criterion 4 of base-ui (rule 46): leaving Neovim leaves nothing behind. A child Neovim runs three tabs (the
-- stub claude) and a diff that waits (in the background, or open in the active tab); each way out (`:qa`, `:q` on the
-- last window, `:qa!`, `:wqa!`, and `:wqa` or `:xa` once the files are written) ends with exit code 0 and no prompt,
-- the diff answered DIFF_REJECTED before its client's socket closed, no process of the tabs, no lock file and no
-- settings file left. A way out that Neovim cancels (changes to keep: E37, E162, E948) leaves the tabs running and
-- the diff pending, and the next command leaves.
-- The scenarios are in tests/helpers/criteria_exit_child.lua.
-- Under busted's mock vim it is pending; scripts/run_integration_tests_individually.sh runs it in Neovim.
if vim == nil or vim.fn.has("nvim") ~= 1 or (vim.uv or vim.loop) == nil or vim.wait == nil or vim.system == nil then
  describe("criterion: leaving Neovim leaves nothing behind", function()
    pending("needs a real Neovim")
  end)
  return
end

describe("criterion: leaving Neovim leaves nothing behind", function()
  local criteria = require("tests.helpers.criteria")
  local tab_env = require("tests.helpers.tab_env")
  local ws_client = require("tests.helpers.ws_client")

  local repo = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")
  local child_script = repo .. "/tests/helpers/criteria_exit_child.lua"

  local env, tmp, child, client

  ---@param name string
  ---@return boolean
  local function exists(name)
    return vim.uv.fs_stat(env.root .. "/" .. name) ~= nil
  end

  ---@param name string
  ---@return table
  local function read_json(name)
    local file = assert(io.open(env.root .. "/" .. name, "r"))
    local data = file:read("*a")
    file:close()
    return vim.json.decode(data)
  end

  ---@param tmp_dir string
  ---@return string[] files The session settings files in a folder, at any depth
  local function settings_files(tmp_dir)
    return vim.fn.globpath(tmp_dir, "**/*.claudinho-*.json", false, true)
  end

  before_each(function()
    env = tab_env.new()
    tmp = env.root .. "/tmp"
    vim.fn.mkdir(tmp, "p")
  end)

  after_each(function()
    if client then
      client:close()
      client = nil
    end
    if child then
      -- A child that still runs here failed to leave.
      pcall(function()
        child:kill(9)
      end)
      child = nil
    end
    tab_env.remove(env)
  end)

  local E_JOB = { "E948" }
  local E_ANY = { "E37", "E162", "E948" }

  ---@class ExitCase
  ---@field name string The scenario of the child
  ---@field errors string[][] The errors of its cancelled steps, in order: one of each list
  ---@field diff_active boolean|nil

  ---@type ExitCase[]
  local cases = {
    { name = "qa", errors = {} },
    { name = "quit_last", errors = {} },
    { name = "qa_bang", errors = {} },
    { name = "wqa_bang", errors = {} },
    { name = "foreign_terminal_qa", errors = {} },
    { name = "cancelled_qa", errors = { E_ANY } },
    { name = "cancelled_quit_last", errors = { E_ANY } },
    { name = "cancelled_prompt", errors = { E_ANY } },
    { name = "wqa", errors = { E_JOB } },
    { name = "wqa_file_after_tabs", errors = { E_JOB } },
    { name = "xa", errors = { E_JOB } },
    { name = "wqa_slow_write", errors = { E_JOB } },
    { name = "wqa_acwrite", errors = { E_JOB } },
    { name = "wqa_open_diff", errors = { E_ANY }, diff_active = true },
  }

  ---@param text string|nil
  ---@param candidates string[]
  ---@return boolean
  local function names_one_of(text, candidates)
    for _, code in ipairs(candidates) do
      if tostring(text):find(code, 1, true) then
        return true
      end
    end
    return false
  end

  for _, case in ipairs(cases) do
    local scenario = case.name
    it(("leaves cleanly with %s"):format(scenario), function()
      child = vim.system({ vim.v.progpath, "--headless", "--clean", "-i", "NONE", "-c", "luafile " .. child_script }, {
        clear_env = true,
        text = true,
        env = {
          PATH = vim.env.PATH,
          HOME = env.home,
          CLAUDE_CONFIG_DIR = env.config_dir,
          TMPDIR = tmp,
          XDG_STATE_HOME = env.root .. "/state",
          XDG_CONFIG_HOME = env.root .. "/xdgconfig",
          XDG_DATA_HOME = env.root .. "/xdgdata",
          CLAUDINHO_REPO = repo,
          CLAUDINHO_ROOT = env.root,
          CLAUDINHO_SCENARIO = scenario,
          CLAUDINHO_TERMINAL_CMD = criteria.stub_path(),
        },
      })

      assert.is_true(
        vim.wait(8000, function()
          return exists("info.json") or child:is_closing()
        end, 20),
        "the child did not start its tabs"
      )
      local info = read_json("info.json")
      assert.equals(3, #info.tabs)
      for _, tab in ipairs(info.tabs) do
        assert.is_true(criteria.alive(tab.pid))
        assert.equals(1, vim.fn.filereadable(tab.settings_path))
      end
      assert.equals(3, #criteria.lock_files(env.lock_dir))
      assert.equals(3, #settings_files(tmp))

      -- A diff for tab 1 while tab 3 is active waits in the background; with `diff_active` it is tab 3's own, and open.
      local diff_tab = case.diff_active and info.tabs[3] or info.tabs[1]
      client = ws_client.connect(diff_tab.port, diff_tab.token)
      local target = env.root .. "/note.txt"
      if case.diff_active then
        -- The file of the changes is another one: a diff does not open over a buffer with changes.
        target = env.root .. "/other.txt"
        vim.fn.writefile({ "one" }, target)
      end
      client:send({
        jsonrpc = "2.0",
        id = 11,
        method = "tools/call",
        params = {
          name = "openDiff",
          arguments = {
            old_file_path = target,
            new_file_path = target,
            new_file_contents = "one\nTWO\n",
            tab_name = "pending-diff",
          },
        },
      })
      assert.is_true(
        vim.wait(3000, function()
          return exists("pending")
        end, 20),
        "the diff did not wait"
      )

      local function touch(name)
        local file = assert(io.open(env.root .. "/" .. name, "w"))
        file:close()
      end

      -- Each way out that Neovim cancels: it is still here, and so is everything of the tabs and the diff.
      for step, candidates in ipairs(case.errors) do
        touch("go" .. step)
        assert.is_true(
          vim.wait(8000, function()
            return exists("step" .. step .. ".json")
          end, 20),
          "Neovim did not report the cancelled exit"
        )
        local cancelled = read_json("step" .. step .. ".json")
        assert.is_false(cancelled.left, "the exit was not cancelled")
        assert.is_true(names_one_of(cancelled.error, candidates), tostring(cancelled.error))
        assert.same({ "running", "running", "running" }, cancelled.states)
        assert.same({ true, true, true }, cancelled.jobs_running)
        for _, tab in ipairs(info.tabs) do
          assert.is_true(criteria.alive(tab.pid), "a cancelled exit stopped a process")
        end
        assert.equals(3, #criteria.lock_files(env.lock_dir))
        if case.diff_active then
          assert.same({ "pending" }, cancelled.diffs, "a cancelled exit accepted or dropped the open diff")
        else
          assert.equals(1, cancelled.pending, "the waiting diff was rejected by a cancelled exit")
        end
        assert.is_false(client.closed)
        assert.equals(0, #client.messages, "the client of the diff was answered")
        if names_one_of(cancelled.error, E_JOB) and not case.diff_active and scenario ~= "cancelled_prompt" then
          -- `:wqa` and `:xa` wrote the file before they stopped.
          assert.same({ "one", "changed" }, cancelled.note)
        end
      end
      touch("go" .. (#case.errors + 1))
      local result = child:wait(15000)

      -- Neovim left by itself, with no prompt in the way.
      assert.is_false(exists("still-here"), "Neovim did not leave")
      assert.equals(0, result.code, (result.stderr or "") .. (result.stdout or ""))
      -- The client of the waiting diff got its answer, and it was in before the socket closed.
      assert.is_true(vim.wait(3000, function()
        return client.closed
      end, 20))
      local rejected
      for _, raw in ipairs(client.messages) do
        local message = vim.json.decode(raw)
        if message.id == 11 then
          rejected = message
        end
      end
      assert.is_not_nil(rejected, "no answer reached the client of the waiting diff")
      assert.equals("DIFF_REJECTED", rejected.result.content[1].text)

      for _, tab in ipairs(info.tabs) do
        assert.is_true(
          vim.wait(3000, function()
            return not criteria.alive(tab.pid)
          end, 20),
          "the process of a tab outlived Neovim"
        )
      end
      assert.same({}, criteria.lock_files(env.lock_dir))
      assert.same({}, settings_files(tmp))
      -- Nothing else was written under the private CLAUDE_CONFIG_DIR and HOME.
      assert.same({ "ide" }, vim.fn.readdir(env.config_dir))
      assert.same({}, vim.fn.readdir(env.home))
    end)
  end
end)
