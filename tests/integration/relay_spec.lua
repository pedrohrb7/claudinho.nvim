-- Real-Neovim check of the relay script: `nvim --clean -l <relay> <kind>` runs as a child process against a real
-- server instance, as Claude Code runs it for the status line and the hooks.
-- Under busted's mock vim it is pending; scripts/run_integration_tests_individually.sh runs it in Neovim.
if vim == nil or vim.fn.has("nvim") ~= 1 or (vim.uv or vim.loop) == nil or vim.wait == nil or vim.system == nil then
  describe("relay script", function()
    pending("needs a real Neovim")
  end)
  return
end

describe("relay script", function()
  local uv = vim.uv or vim.loop
  local server = require("claudinho.server.init")
  local relay_path = require("claudinho.session_settings").relay_path()
  local config = { port_range = { min = 20000, max = 40000 } }
  local token = "relay-tab-token-0123456789"
  local instance, posts

  ---Run the relay as a child process. The wait is the 500 ms of the relay plus a margin.
  ---@param kind string
  ---@param env table<string, string>
  ---@param stdin string|nil
  ---@return { code: integer, stdout: string, stderr: string, ms: number }
  local function run_relay(kind, env, stdin)
    local started = uv.hrtime()
    local result = vim
      .system({ vim.v.progpath, "--clean", "-l", relay_path, kind }, {
        env = env,
        clear_env = true,
        stdin = stdin or "{}",
        text = true,
      })
      :wait(5000)
    return {
      code = result.code,
      stdout = result.stdout,
      stderr = result.stderr,
      ms = (uv.hrtime() - started) / 1e6,
    }
  end

  local function tab_env(port)
    return { CLAUDINHO_PORT = tostring(port), CLAUDINHO_TOKEN = token, HOME = vim.env.HOME }
  end

  ---A port that nothing listens on.
  local function dead_port()
    local handle = assert(uv.new_tcp())
    assert(handle:bind("127.0.0.1", 0))
    local port = handle:getsockname().port
    handle:close()
    return port
  end

  before_each(function()
    posts = {}
    instance = server.new({
      on_post = function(kind, body)
        table.insert(posts, { kind = kind, body = body })
      end,
    })
    assert(instance:start(config, token))
  end)

  after_each(function()
    instance:stop()
  end)

  local function wait_for_posts(count)
    return vim.wait(2000, function()
      return #posts >= count
    end, 5)
  end

  it("delivers the body of a hook with the tab token and prints nothing", function()
    local body = '{"session_id":"s1","permission_mode":"plan"}'

    local result = run_relay("hook", tab_env(instance.port), body)

    assert.equals(0, result.code)
    assert.equals("", result.stdout)
    assert.equals("", result.stderr)
    assert.is_true(wait_for_posts(1))
    assert.are.same({ kind = "hook", body = body }, posts[1])
  end)

  it("delivers the body of a statusline and prints an empty line", function()
    local body = '{"session_id":"s1","model":{"display_name":"Opus \xc3\xa9"}}'

    local result = run_relay("statusline", tab_env(instance.port), body)

    assert.equals(0, result.code)
    assert.equals("\n", result.stdout)
    assert.is_true(wait_for_posts(1))
    assert.are.same({ kind = "statusline", body = body }, posts[1])
  end)

  it("works with an empty PATH, since it needs only the absolute Neovim binary", function()
    local env = tab_env(instance.port)
    env.PATH = ""

    local result = run_relay("hook", env, '{"session_id":"s2"}')

    assert.equals(0, result.code)
    assert.is_true(wait_for_posts(1))
    assert.equals('{"session_id":"s2"}', posts[1].body)
  end)

  it("exits 0 and sends nothing for an unknown kind", function()
    local result = run_relay("other", tab_env(instance.port))

    assert.equals(0, result.code)
    assert.equals("", result.stdout)
    vim.wait(100)
    assert.are.same({}, posts)
  end)

  it("exits 0 with a dead port, and a statusline still prints the empty line", function()
    local env = tab_env(dead_port())

    local hook = run_relay("hook", env)
    local statusline = run_relay("statusline", env)

    assert.equals(0, hook.code)
    assert.equals("", hook.stdout)
    assert.equals("", hook.stderr)
    assert.equals(0, statusline.code)
    assert.equals("\n", statusline.stdout)
    assert.is_true(hook.ms < 2000, "took " .. hook.ms .. " ms")
  end)

  it("exits 0 without a port, and sends nothing", function()
    local result = run_relay("statusline", { HOME = vim.env.HOME })

    assert.equals(0, result.code)
    assert.equals("\n", result.stdout)
    assert.are.same({}, posts)
  end)

  it("exits 0 within the limit when a server accepts but never answers", function()
    local silent = assert(uv.new_tcp())
    assert(silent:bind("127.0.0.1", 0))
    assert(silent:listen(8, function() end))
    local port = silent:getsockname().port

    local result = run_relay("hook", tab_env(port))
    silent:close()

    assert.equals(0, result.code)
    assert.is_true(result.ms < 2000, "took " .. result.ms .. " ms")
  end)

  it("does not report a failure when the token is wrong", function()
    local env = tab_env(instance.port)
    env.CLAUDINHO_TOKEN = "wrong"

    local result = run_relay("hook", env)

    assert.equals(0, result.code)
    assert.equals("", result.stdout)
    vim.wait(100)
    assert.are.same({}, posts)
  end)

  it("runs in under 2000 ms each time (the average goes to the log)", function()
    local runs, total = 10, 0
    for _ = 1, runs do
      local result = run_relay("statusline", tab_env(instance.port), '{"session_id":"s"}')
      assert.equals(0, result.code)
      assert.is_true(result.ms < 2000, "took " .. result.ms .. " ms")
      total = total + result.ms
    end
    assert.is_true(wait_for_posts(runs))

    print(string.format("RELAY_AVG_MS=%.1f over %d runs (child process, round trip included)", total / runs, runs))
  end)
end)
