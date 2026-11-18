-- Success criterion 4 of base-ui (rule 46): leaving Neovim leaves nothing behind. A child Neovim runs three tabs (the
-- stub claude) and a diff that waits in the background; each way out (`:qa`, `:wqa`, `:q` on the last window) ends with
-- exit code 0 and no prompt, the diff answered DIFF_REJECTED before its client's socket closed, no process of the
-- tabs, no lock file and no settings file left.
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

  for _, scenario in ipairs({ "qa", "wqa", "quit_last" }) do
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

      -- A diff for tab 1 while tab 3 is active waits in the background.
      client = ws_client.connect(info.tabs[1].port, info.tabs[1].token)
      local target = env.root .. "/note.txt"
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
        "the diff did not wait in the background"
      )

      local go = assert(io.open(env.root .. "/go", "w"))
      go:close()
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
