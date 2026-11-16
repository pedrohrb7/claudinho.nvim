--- The settings file of a session: its content (only statusLine and the three hooks), the shell escaping of the
--- commands, the file mode and the place of the file, and its removal. The file system is a fake that records calls.
require("tests.busted_setup")

describe("session_settings", function()
  local session_settings
  local saved, calls, files

  ---Shell quoting as Neovim's shellescape() does on Unix.
  local function shellescape(text)
    return "'" .. text:gsub("'", "'\\''") .. "'"
  end

  before_each(function()
    saved = {
      uv = vim.uv,
      json = vim.json,
      v = vim.v,
      shellescape = vim.fn.shellescape,
      tempname = vim.fn.tempname,
    }
    calls, files = {}, {}
    vim.v = { progpath = "/opt/my nvim/bin/nvim" }
    vim.fn.shellescape = shellescape
    vim.fn.tempname = function()
      return "/tmp/nvim.user/AbC123/0"
    end
    vim.json = {
      encode = function(value)
        calls.encoded = value
        return '{"fake":"json"}'
      end,
    }
    vim.uv = {
      fs_open = function(path, flags, mode)
        table.insert(calls, { "open", path, flags, mode })
        if files[path] then
          return nil, "EEXIST: file already exists: " .. path
        end
        files[path] = ""
        return 7
      end,
      fs_write = function(fd, data, offset)
        table.insert(calls, { "write", fd, data, offset })
        local path = next(files)
        files[path] = files[path] .. data
        return #data
      end,
      fs_close = function(fd)
        table.insert(calls, { "close", fd })
        return true
      end,
      fs_unlink = function(path)
        table.insert(calls, { "unlink", path })
        if not files[path] then
          return nil, "ENOENT"
        end
        files[path] = nil
        return true
      end,
    }
    package.loaded["claudinho.session_settings"] = nil
    session_settings = require("claudinho.session_settings")
  end)

  after_each(function()
    vim.uv, vim.json, vim.v = saved.uv, saved.json, saved.v
    vim.fn.shellescape, vim.fn.tempname = saved.shellescape, saved.tempname
  end)

  describe("build()", function()
    it("holds exactly statusLine and hooks, with the three events", function()
      local settings = session_settings.build("/bin/nvim", "/plug/relay.lua")

      local keys = {}
      for key in pairs(settings) do
        table.insert(keys, key)
      end
      table.sort(keys)
      assert.are.same({ "hooks", "statusLine" }, keys)
      local events = {}
      for event in pairs(settings.hooks) do
        table.insert(events, event)
      end
      table.sort(events)
      assert.are.same({ "SessionStart", "Stop", "UserPromptSubmit" }, events)
    end)

    it("runs the relay as the status line command", function()
      local settings = session_settings.build("/bin/nvim", "/plug/relay.lua")

      assert.are.same({
        type = "command",
        command = "'/bin/nvim' --clean -l '/plug/relay.lua' statusline",
      }, settings.statusLine)
    end)

    it("runs the relay as an async command hook for each event", function()
      local settings = session_settings.build("/bin/nvim", "/plug/relay.lua")

      for _, event in ipairs({ "SessionStart", "UserPromptSubmit", "Stop" }) do
        assert.are.same({
          {
            hooks = {
              { type = "command", command = "'/bin/nvim' --clean -l '/plug/relay.lua' hook", async = true },
            },
          },
        }, settings.hooks[event])
      end
    end)

    it("escapes a program path and a relay path with spaces and quotes", function()
      local settings = session_settings.build("/opt/my nvim/nvim", "/home/it's me/relay.lua")

      assert.equals(
        "'/opt/my nvim/nvim' --clean -l '/home/it'\\''s me/relay.lua' statusline",
        settings.statusLine.command
      )
    end)
  end)

  describe("relay_path()", function()
    it("is the absolute path of sources/relay.lua next to the module", function()
      local path = session_settings.relay_path()

      assert.is_true(path:sub(1, 1) == "/")
      assert.is_true(path:match("/lua/claudinho/sources/relay%.lua$") ~= nil, path)
      assert.is_not_nil(io.open(path, "r"))
    end)
  end)

  describe("write()", function()
    it("creates a 0600 file in Neovim's temporary folder, with the session number in the name", function()
      local session = { number = 3 }

      local path = session_settings.write(session)

      assert.equals("/tmp/nvim.user/AbC123/0.claudinho-3.json", path)
      assert.equals(path, session.settings_path)
      assert.are.same({ "open", path, "wx", 384 }, calls[1])
      assert.equals('{"fake":"json"}', files[path])
    end)

    it("encodes the settings built from the Neovim binary and the relay", function()
      session_settings.write({ number = 1 })

      local expected = session_settings.build("/opt/my nvim/bin/nvim", session_settings.relay_path())
      assert.are.same(expected, calls.encoded)
    end)

    it("writes nothing outside the temporary folder", function()
      session_settings.write({ number = 1 })

      for _, call in ipairs(calls) do
        if call[1] == "open" then
          assert.equals("/tmp/nvim.user/AbC123/", call[2]:sub(1, 22))
        end
      end
    end)

    it("returns nil and an error when the file cannot be created, and sets no path", function()
      files["/tmp/nvim.user/AbC123/0.claudinho-2.json"] = "taken"
      local session = { number = 2 }

      local path, err = session_settings.write(session)

      assert.is_nil(path)
      assert.is_truthy(err:find("Failed to create the session settings", 1, true))
      assert.is_nil(session.settings_path)
    end)
  end)

  describe("remove()", function()
    it("deletes the file and clears the path", function()
      local session = { number = 1 }
      local path = session_settings.write(session)

      assert.is_true(session_settings.remove(session))

      assert.is_nil(files[path])
      assert.is_nil(session.settings_path)
    end)

    it("does nothing when there is no file", function()
      assert.is_false(session_settings.remove({}))
    end)

    it("never deletes a file that is not a session settings file", function()
      files["/home/user/.claude/settings.json"] = "{}"
      local session = { settings_path = "/home/user/.claude/settings.json" }

      assert.is_false(session_settings.remove(session))

      assert.equals("{}", files["/home/user/.claude/settings.json"])
    end)
  end)
end)
