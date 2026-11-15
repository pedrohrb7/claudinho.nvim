require("tests.busted_setup")

describe(".luacov", function()
  local function copy(list)
    local result = {}
    for key, value in pairs(list) do
      result[key] = value
    end
    return result
  end

  ---@param typed string what `pwd` prints
  ---@param resolved string what `pwd -P` prints
  ---@return table runner
  local function load_runner(typed, resolved)
    local chunk = assert(loadfile(".luacov"))
    local outputs = { ["pwd"] = typed, ["pwd -P"] = resolved }
    local env = setmetatable({
      -- No TMPDIR: an exclude built from it falls back to /tmp on every host, where the /tmp cases catch it.
      os = {
        getenv = function()
          return nil
        end,
      },
      io = {
        popen = function(command)
          local line = assert(outputs[command], "unexpected command: " .. command)
          return {
            read = function(_, format)
              assert(format == nil or format == "*l" or format == "l", "reads one line, not " .. tostring(format))
              return line
            end,
            close = function()
              return true
            end,
          }
        end,
      },
    }, { __index = _G })
    setfenv(chunk, env)

    local configuration = {}
    for key, value in pairs(chunk()) do
      configuration[key] = type(value) == "table" and copy(value) or value
    end
    configuration.exclude = configuration.exclude or {}

    -- runner.load_config keeps a config that is already loaded, as it is in a coverage run, so use a fresh copy.
    local runner = assert(loadfile(assert(package.searchpath("luacov.runner", package.path))))()
    runner.load_config(configuration)
    return runner
  end

  ---@param runner table
  ---@param root string the checkout folder the paths are under
  local function assert_plugin_only(runner, root)
    assert.is_true(runner.file_included(root .. "/plugin/claudinho.lua"))
    assert.is_true(runner.file_included(root .. "/lua/claudinho/init.lua"))
    assert.is_true(runner.file_included(root .. "/lua/claudinho/server/client.lua"))
    assert.is_true(runner.file_included(root .. "/lua/claudinho/a/b/c.lua"))
    assert.is_false(runner.file_included(root .. "/tests/busted_setup.lua"))
    assert.is_false(runner.file_included(root .. "/tests/mocks/vim.lua"))
    assert.is_false(runner.file_included(root .. "/fixtures/nvim/init.lua"))
    assert.is_false(runner.file_included(root .. "/.luarocks/share/lua/5.1/busted/init.lua"))
    assert.is_false(runner.file_included(root .. "/plugins/claudinho.lua"))
    assert.is_false(runner.file_included(root .. "/lua/claudinho-extra/init.lua"))
  end

  it("keeps plugin files and drops tests and rocks of a checkout under a folder ending in plugin", function()
    local root = "/w/xplugin/claudinho.nvim"
    local runner = load_runner(root, root)

    assert_plugin_only(runner, root)
    assert.is_true(runner.file_included("plugin/claudinho.lua"))
    assert.is_true(runner.file_included("lua/claudinho/init.lua"))
    assert.is_true(runner.file_included("lua/claudinho/a/b/c.lua"))
    assert.is_false(runner.file_included("tests/unit/diff_spec.lua"))
    assert.is_false(runner.file_included("plugins/claudinho.lua"))
    assert.is_false(runner.file_included("lua/claudinho-extra/init.lua"))
  end)

  it("keeps plugin files by the folder as typed and with symlinks resolved", function()
    local typed = "/home/u/link"
    local resolved = "/data/real/claudinho.nvim"
    local runner = load_runner(typed, resolved)

    assert_plugin_only(runner, typed)
    assert_plugin_only(runner, resolved)
  end)

  it("keeps plugin files of a checkout in CI's folder", function()
    local root = "/home/runner/work/claudinho.nvim/claudinho.nvim"

    assert_plugin_only(load_runner(root, root), root)
  end)

  it("keeps the files of a checkout in a folder named like a temp folder", function()
    local root = "/tmp/claudinho.Ab1234"

    assert_plugin_only(load_runner(root, root), root)
  end)

  it("keeps the files of a checkout that a symlink points to in a folder named like a temp folder", function()
    local typed = "/home/u/link"
    local resolved = "/tmp/claudinho.Ab1234"
    local runner = load_runner(typed, resolved)

    assert_plugin_only(runner, typed)
    assert_plugin_only(runner, resolved)
  end)

  it("takes a folder name's pattern characters literally", function()
    local root = "/w/my-check.out+1%/claude-code.nvim"
    local runner = load_runner(root, root)

    assert_plugin_only(runner, root)
    assert.is_false(runner.file_included("/w/my-checkXout+1%/claude-code.nvim/plugin/claudinho.lua"))
    assert.is_false(runner.file_included("/w/my-check.out+1%/claude-code.nvimX/plugin/claudinho.lua"))
  end)

  it("does not match a path that has the checkout folder somewhere in the middle", function()
    local root = "/home/u/claudinho.nvim"
    local runner = load_runner(root, root)

    assert.is_false(runner.file_included("/mnt" .. root .. "/plugin/claudinho.lua"))
    assert.is_false(runner.file_included("/mnt" .. root .. "/lua/claudinho/init.lua"))
  end)

  it("does not match plugin files outside the checkout, at any depth", function()
    local root = "/w/claudinho.nvim"
    local runner = load_runner(root, root)

    for _, outside in ipairs({
      "/outside/plugin/claudinho.lua",
      "/outside/lua/claudinho/init.lua",
      "/outside/lua/claudinho/server/client.lua",
      "/outside/lua/claudinho/a/b/c.lua",
      "/tmp/claudinho.Ab1234/lua/claudinho/init.lua",
      "/var/folders/ab/T/claudinho.Ab1234/lua/claudinho/init.lua",
    }) do
      assert.is_false(runner.file_included(outside), outside)
    end
  end)
end)
