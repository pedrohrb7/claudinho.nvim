-- Regression check of rules 39 and 40: a key typed in the terminal of a tab whose process ended leaves the buffer and
-- the tab alone (the tab stays, exited), and wiping the buffer of a tab closes the tab without Neovim's E937 ("Attempt
-- to delete a buffer that is in use"). A typed key reaches Neovim only when the running Lua call returns to its main
-- loop, so each scenario runs in a child Neovim (tests/helpers/exit_key_child.lua) that prints what it saw.
-- Under busted's mock vim it is pending; scripts/run_integration_tests_individually.sh runs it in Neovim.
if vim == nil or vim.fn.has("nvim") ~= 1 or (vim.uv or vim.loop) == nil or vim.wait == nil or vim.system == nil then
  describe("session exit key", function()
    pending("needs a real Neovim")
  end)
  return
end

describe("session exit key", function()
  local tab_env = require("tests.helpers.tab_env")
  local repo = vim.fn.getcwd()
  local env

  before_each(function()
    env = tab_env.new()
  end)

  after_each(function()
    tab_env.remove(env)
  end)

  ---Run one scenario in a child Neovim.
  ---@param scenario string
  ---@param terminal_cmd string
  ---@return table result What the child saw
  local function run_child(scenario, terminal_cmd)
    local child_env = {
      CLAUDINHO_REPO = repo,
      CLAUDINHO_SCENARIO = scenario,
      CLAUDINHO_TERMINAL_CMD = terminal_cmd,
      HOME = env.home,
      CLAUDE_CONFIG_DIR = env.config_dir,
      XDG_STATE_HOME = env.root .. "/state",
      XDG_CONFIG_HOME = env.root .. "/xdg_config",
      VIMINIT = "",
    }
    local done = vim
      .system({
        vim.v.progpath,
        "--headless",
        "--clean",
        "-i",
        "NONE",
        "-c",
        "luafile " .. vim.fn.fnameescape(repo .. "/tests/helpers/exit_key_child.lua"),
      }, { text = true, env = child_env, timeout = 10000 })
      :wait()
    local line = (done.stdout or ""):match("RESULT:(%b{})")
    assert.is_truthy(line, "the child printed no result: " .. (done.stdout or "") .. (done.stderr or ""))
    return vim.json.decode(line)
  end

  ---@param result table
  local function assert_no_e937(result)
    assert.is_nil(result.wipe_error, "the wipe failed: " .. tostring(result.wipe_error))
    assert.is_nil(result.messages:find("E937", 1, true), "E937 in :messages: " .. result.messages)
    assert.is_nil(result.messages:find("Error in BufWipeout", 1, true), "BufWipeout error: " .. result.messages)
    assert.is_nil(result.errmsg:find("E937", 1, true), "E937 in v:errmsg: " .. result.errmsg)
  end

  local short_lived = "sh -c 'sleep 1; exit 0' claude-test"

  it("keeps the buffer, the tab and the window when a key is typed in an ended terminal in terminal mode", function()
    local result = run_child("key", short_lived)

    assert.equals("terminal", result.initial_buftype)
    assert.is_true(result.terminal_current, "the terminal of the tab is not the current buffer")
    assert.is_true(result.reached_exited, "the tab never became exited")
    -- Terminal mode while the process runs; once it ended, the guard has left it for normal mode (rules 39 and 40).
    assert.equals("t", result.initial_mode)
    assert.equals("nt", result.mode_at_exit)
    assert.is_true(result.buf_valid, "the key wiped the buffer of the ended terminal")
    assert.is_true(result.tab_exists, "the key closed the tab")
    assert.equals("exited", result.tab_state)
    assert.is_true(result.tab_buf_is_buf)
    assert.is_true(result.shown, "no window shows the ended terminal any more")
    assert_no_e937(result)
  end)

  it("closes the tab of a wiped ended terminal without E937", function()
    local result = run_child("wipe_ended", short_lived)

    assert.is_true(result.reached_exited, "the tab never became exited")
    assert.is_false(result.buf_valid)
    assert.is_false(result.tab_exists, "wiping the buffer must close the tab")
    assert_no_e937(result)
  end)

  it("closes the tab of a wiped running terminal without E937", function()
    local result = run_child("wipe_running", "sh -c 'sleep 20' claude-test")

    assert.is_false(result.buf_valid)
    assert.is_false(result.tab_exists, "wiping the buffer must close the tab")
    assert_no_e937(result)
  end)
end)
