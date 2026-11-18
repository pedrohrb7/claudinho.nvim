--- The `:Claudinho` command: each subcommand of the table in the spec (section 10), with no tabs, a missing tab number,
--- wrong use and the right use; the unknown subcommands (`layout` included); `:Claudinho!` and `send-text!`;
--- `select-model` in its three states; the completion; and that no `:ClaudeCode*` command is created any more. The tab
--- registry, the window, the diff module, the terminal facade, the plugin module and the notifications are fakes that
--- record what the command asks of them. `send`, `add` and `tree-add` have their own specs for what they send.
require("tests.busted_setup")

describe("commands", function()
  local commands
  local loaded_names = {
    "claudinho",
    "claudinho.commands",
    "claudinho.sessions",
    "claudinho.ui.window",
    "claudinho.notify",
    "claudinho.terminal",
    "claudinho.diff",
    "claudinho.logger",
    "claudinho.visual_commands",
  }
  local saved_loaded, restore_list
  local log, state, created

  ---Replace tbl[key] until after_each.
  local function stub(tbl, key, value)
    table.insert(restore_list, { tbl, key, tbl[key] })
    tbl[key] = value
  end

  ---Run `:Claudinho <args>` the way Neovim hands it over.
  ---@param args string
  ---@param extra table|nil Other options of the command (`bang`, `range`...)
  local function run(args, extra)
    local fargs = {}
    for word in args:gmatch("%S+") do
      fargs[#fargs + 1] = word
    end
    local opts = { args = args, fargs = fargs, bang = false }
    for key, value in pairs(extra or {}) do
      opts[key] = value
    end
    commands.run(opts)
  end

  ---@param kind string
  ---@return string[] The notices of that kind, in order
  local function notices(kind)
    local found = {}
    for _, notice in ipairs(state.notices) do
      if notice[1] == kind then
        found[#found + 1] = notice[2]
      end
    end
    return found
  end

  ---Make tabs `numbers` exist; the first one is the active one.
  local function with_tabs(...)
    state.tabs = {}
    for _, n in ipairs({ ... }) do
      state.tabs[n] = { number = n, state = "running" }
    end
    state.active = (...)
  end

  before_each(function()
    saved_loaded, restore_list = {}, {}
    for _, name in ipairs(loaded_names) do
      saved_loaded[name] = package.loaded[name]
      package.loaded[name] = nil
    end
    log = {}
    state = { tabs = {}, active = nil, notices = {}, mode = "n", feedkeys = 0, selects = {} }
    created = {}

    package.loaded["claudinho.notify"] = {
      info = function(msg)
        table.insert(state.notices, { "info", msg })
      end,
      reply = function(msg)
        table.insert(state.notices, { "reply", msg })
      end,
      error = function(msg)
        table.insert(state.notices, { "error", msg })
      end,
    }
    package.loaded["claudinho.logger"] = {
      debug = function() end,
      info = function() end,
      warn = function() end,
      error = function(_, msg)
        table.insert(state.notices, { "logged", msg })
      end,
    }
    package.loaded["claudinho.sessions"] = {
      NO_TABS = "No Claude tabs open",
      state = setmetatable({}, {
        __index = function(_, key)
          if key == "tabs" then
            return state.tabs
          elseif key == "active" then
            return state.active
          end
        end,
      }),
      active = function()
        return state.active and state.tabs[state.active] or nil
      end,
      numbers = function()
        local list = {}
        for n in pairs(state.tabs) do
          list[#list + 1] = n
        end
        table.sort(list)
        return list
      end,
      new = function(extra)
        table.insert(log, "sessions.new" .. (extra or ""))
      end,
      activate = function(n)
        table.insert(log, "sessions.activate " .. n)
        state.active = n
        return true
      end,
      next = function()
        table.insert(log, "sessions.next")
      end,
      prev = function()
        table.insert(log, "sessions.prev")
      end,
      close = function(n)
        table.insert(log, "sessions.close " .. n)
      end,
      restart = function(n)
        table.insert(log, "sessions.restart " .. n)
      end,
      kill_all = function()
        table.insert(log, "sessions.kill_all")
      end,
      reject_all_pending = function(reason)
        table.insert(log, "sessions.reject_all_pending " .. reason)
        return state.waiting or 0
      end,
    }
    package.loaded["claudinho.ui.window"] = {
      toggle = function()
        table.insert(log, "window.toggle")
      end,
      show = function(opts)
        table.insert(log, "window.show focus=" .. tostring(opts and opts.focus))
      end,
      hide = function()
        table.insert(log, "window.hide")
      end,
      focus = function()
        table.insert(log, "window.focus")
      end,
    }
    package.loaded["claudinho.terminal"] = {
      send_to_terminal = function(text, opts)
        table.insert(log, ("terminal.send_to_terminal %s submit=%s"):format(text, tostring(opts.submit)))
        return true
      end,
    }
    package.loaded["claudinho.diff"] = {
      accept_current_diff = function()
        table.insert(log, "diff.accept_current_diff")
      end,
      deny_current_diff = function()
        table.insert(log, "diff.deny_current_diff")
      end,
      close_pending_diffs = function(reason)
        table.insert(log, "diff.close_pending_diffs " .. reason)
        return state.pending or 0
      end,
      close_rejected_diffs = function()
        return state.rejected or 0
      end,
      close_saved_diffs = function()
        return state.saved or 0, state.unsaved or {}, state.kept or {}
      end,
    }
    package.loaded["claudinho"] = {
      send_at_mention = function(file_path, start_line, end_line, context)
        table.insert(log, ("send_at_mention %s %s %s %s"):format(file_path, start_line, end_line, context))
        return true
      end,
      open_with_model = function()
        table.insert(log, "open_with_model")
      end,
    }
    package.loaded["claudinho.visual_commands"] = {
      create_visual_command_wrapper = function(normal, visual)
        state.tree_handlers = { normal = normal, visual = visual }
        return function(opts)
          state.wrapped_opts = opts
          table.insert(log, "visual_commands.wrapper")
        end
      end,
    }

    stub(vim.fn, "mode", function()
      return state.mode
    end)
    stub(vim.api, "nvim_feedkeys", function()
      state.feedkeys = state.feedkeys + 1
    end)
    stub(vim.api, "nvim_replace_termcodes", function(text)
      return text
    end)
    stub(vim.api, "nvim_create_user_command", function(name, callback, opts)
      table.insert(created, { name = name, callback = callback, opts = opts })
    end)
    stub(vim.fn, "fnamemodify", function(path)
      return path
    end)

    commands = require("claudinho.commands")
  end)

  after_each(function()
    for i = #restore_list, 1, -1 do
      local entry = restore_list[i]
      entry[1][entry[2]] = entry[3]
    end
    for _, name in ipairs(loaded_names) do
      package.loaded[name] = saved_loaded[name]
    end
  end)

  describe("setup", function()
    it("creates :Claudinho with subcommands, a range, a bang and completion", function()
      commands.setup({})

      assert.are.equal(1, #created)
      assert.are.equal("Claudinho", created[1].name)
      assert.are.equal("*", created[1].opts.nargs)
      assert.is_true(created[1].opts.range)
      assert.is_true(created[1].opts.bang)
      assert.are.equal(commands.complete, created[1].opts.complete)
      assert.are.equal(commands.run, created[1].callback)
    end)

    it("creates none of the :ClaudeCode* commands", function()
      commands.setup({})

      local old = {
        "ClaudeCode",
        "ClaudeCodeStart",
        "ClaudeCodeStop",
        "ClaudeCodeStatus",
        "ClaudeCodeSend",
        "ClaudeCodeTreeAdd",
        "ClaudeCodeAdd",
        "ClaudeCodeFocus",
        "ClaudeCodeOpen",
        "ClaudeCodeClose",
        "ClaudeCodeSendText",
        "ClaudeCodeDiffAccept",
        "ClaudeCodeDiffDeny",
        "ClaudeCodeCloseAllDiffs",
        "ClaudeCodeSelectModel",
      }
      for _, created_command in ipairs(created) do
        for _, name in ipairs(old) do
          assert.are_not.equal(name, created_command.name)
        end
      end
    end)

    it("lists the subcommands of the spec", function()
      assert.are.same({
        "toggle",
        "open",
        "hide",
        "focus",
        "new",
        "tab",
        "tab-next",
        "tab-prev",
        "tab-close",
        "tab-restart",
        "kill-all",
        "send",
        "add",
        "tree-add",
        "send-text",
        "diff-accept",
        "diff-deny",
        "close-all-diffs",
        "select-model",
      }, commands.SUBCOMMANDS)
    end)
  end)

  describe("toggle", function()
    it("hides or shows the window of the tabs there are", function()
      with_tabs(1)

      run("toggle")

      assert.are.same({ "window.toggle" }, log)
    end)

    it("starts the first tab without tabs", function()
      run("toggle")

      assert.are.same({ "sessions.new" }, log)
    end)

    it("is what :Claudinho does without a subcommand", function()
      with_tabs(1)

      commands.run({ args = "", fargs = {}, bang = false })

      assert.are.same({ "window.toggle" }, log)
    end)

    it("is what :Claudinho! does without a subcommand", function()
      commands.run({ args = "", fargs = {}, bang = true })

      assert.are.same({ "sessions.new" }, log)
    end)

    it("leaves Visual mode first", function()
      with_tabs(1)
      state.mode = "V"

      run("toggle")

      assert.are.equal(1, state.feedkeys)
    end)

    it("leaves Normal mode alone", function()
      with_tabs(1)

      run("toggle")

      assert.are.equal(0, state.feedkeys)
    end)
  end)

  describe("open", function()
    it("shows and focuses the window with tabs", function()
      with_tabs(1, 2)

      run("open")

      assert.are.same({ "window.show focus=true" }, log)
    end)

    it("starts the first tab without tabs", function()
      run("open")

      assert.are.same({ "sessions.new" }, log)
    end)
  end)

  describe("hide", function()
    it("hides the window", function()
      with_tabs(1)

      run("hide")

      assert.are.same({ "window.hide" }, log)
    end)

    it("replies without tabs", function()
      run("hide")

      assert.are.same({ "No Claude tabs open" }, notices("reply"))
      assert.are.same({}, log)
    end)
  end)

  describe("focus", function()
    it("focuses the window or hides it when it has the focus", function()
      with_tabs(1)
      state.mode = "v"

      run("focus")

      assert.are.same({ "window.focus" }, log)
      assert.are.equal(1, state.feedkeys)
    end)

    it("is open without tabs", function()
      run("focus")

      assert.are.same({ "sessions.new" }, log)
    end)
  end)

  describe("new", function()
    it("starts a tab", function()
      with_tabs(1)

      run("new")

      assert.are.same({ "sessions.new" }, log)
    end)
  end)

  describe("tab", function()
    it("activates the tab and shows the window, without taking the focus", function()
      with_tabs(1, 2, 3)

      run("tab 2")

      assert.are.same({ "sessions.activate 2", "window.show focus=false" }, log)
    end)

    it("replies without tabs", function()
      run("tab 1")

      assert.are.same({ "No Claude tabs open" }, notices("reply"))
      assert.are.same({}, log)
    end)

    it("lists the open tabs for a number that is no tab", function()
      with_tabs(1, 3)

      run("tab 2")

      assert.are.same({ "[Claudinho] No Claude tab 2. Open tabs: 1, 3" }, notices("error"))
      assert.are.same({}, log)
    end)

    it("lists the open tabs for what is not a number", function()
      with_tabs(1)

      run("tab x")

      assert.are.same({ "[Claudinho] No Claude tab x. Open tabs: 1" }, notices("error"))
    end)

    it("shows the usage without a number or with more than one", function()
      with_tabs(1)

      run("tab")
      run("tab 1 2")

      assert.are.same({
        "[Claudinho] Usage: :Claudinho tab <n>",
        "[Claudinho] Usage: :Claudinho tab <n>",
      }, notices("error"))
      assert.are.same({}, log)
    end)
  end)

  describe("tab-next and tab-prev", function()
    it("switch and show the window", function()
      with_tabs(1, 2)

      run("tab-next")
      run("tab-prev")

      assert.are.same({
        "sessions.next",
        "window.show focus=false",
        "sessions.prev",
        "window.show focus=false",
      }, log)
    end)

    it("reply without tabs", function()
      run("tab-next")
      run("tab-prev")

      assert.are.same({ "No Claude tabs open", "No Claude tabs open" }, notices("reply"))
      assert.are.same({}, log)
    end)
  end)

  describe("tab-close", function()
    it("closes the active tab without a number", function()
      with_tabs(2, 3)

      run("tab-close")

      assert.are.same({ "sessions.close 2" }, log)
    end)

    it("closes the tab of the number", function()
      with_tabs(1, 2, 3)

      run("tab-close 3")

      assert.are.same({ "sessions.close 3" }, log)
    end)

    it("lists the open tabs for a number that is no tab", function()
      with_tabs(1, 2)

      run("tab-close 5")

      assert.are.same({ "[Claudinho] No Claude tab 5. Open tabs: 1, 2" }, notices("error"))
      assert.are.same({}, log)
    end)

    it("replies without tabs, with or without a number", function()
      run("tab-close")
      run("tab-close 1")

      assert.are.same({ "No Claude tabs open", "No Claude tabs open" }, notices("reply"))
    end)

    it("shows the usage for more than one number", function()
      with_tabs(1, 2)

      run("tab-close 1 2")

      assert.are.same({ "[Claudinho] Usage: :Claudinho tab-close [n]" }, notices("error"))
      assert.are.same({}, log)
    end)
  end)

  describe("tab-restart", function()
    it("restarts the tab of the number", function()
      with_tabs(1, 2)

      run("tab-restart 2")

      assert.are.same({ "sessions.restart 2" }, log)
    end)

    it("needs the number", function()
      with_tabs(1)

      run("tab-restart")

      assert.are.same({ "[Claudinho] Usage: :Claudinho tab-restart <n>" }, notices("error"))
      assert.are.same({}, log)
    end)

    it("lists the open tabs for a number that is no tab", function()
      with_tabs(1, 2)

      run("tab-restart 9")

      assert.are.same({ "[Claudinho] No Claude tab 9. Open tabs: 1, 2" }, notices("error"))
      assert.are.same({}, log)
    end)

    it("replies without tabs", function()
      run("tab-restart 1")

      assert.are.same({ "No Claude tabs open" }, notices("reply"))
    end)
  end)

  describe("kill-all", function()
    it("ends every tab without asking", function()
      with_tabs(1, 2)

      run("kill-all")

      assert.are.same({ "sessions.kill_all" }, log)
    end)
  end)

  describe("send", function()
    it("goes through the visual wrapper with the options of the command", function()
      run("send", { range = 2, line1 = 4, line2 = 6 })

      assert.are.same({ "visual_commands.wrapper" }, log)
      assert.are.equal(4, state.wrapped_opts.line1)
      assert.are.equal(6, state.wrapped_opts.line2)
    end)
  end)

  describe("tree-add", function()
    it("goes through the visual wrapper", function()
      run("tree-add")

      assert.are.same({ "visual_commands.wrapper" }, log)
    end)
  end)

  describe("tree-add when the first tab cannot start", function()
    local files = { "/a.lua", "/b.lua", "/c.lua", "/d.lua", "/e.lua" }

    before_each(function()
      package.loaded["claudinho"].send_at_mention = function(file_path)
        table.insert(log, "send_at_mention " .. file_path)
        -- `sessions.new` showed why; the third value tells the loop to stop.
        return false, "[Claudinho] Could not start Claude 1: 'claude' is not executable", true
      end
      package.loaded["claudinho.integrations"] = {
        get_selected_files_from_tree = function()
          return files, nil
        end,
      }
      package.loaded["claudinho.visual_commands"].get_files_from_visual_selection = function()
        return files, nil
      end
    end)

    it("tries the first file only and logs nothing more", function()
      run("tree-add")
      state.tree_handlers.normal()

      assert.same({ "visual_commands.wrapper", "send_at_mention /a.lua" }, log)
      assert.same({}, notices("logged"))
    end)

    it("does the same for a visual selection", function()
      run("tree-add")
      state.tree_handlers.visual({})

      assert.same({ "visual_commands.wrapper", "send_at_mention /a.lua" }, log)
      assert.same({}, notices("logged"))
    end)
  end)

  describe("add", function()
    it("logs the missing path as an error", function()
      run("add")

      assert.are.same({ "Claudinho add: No file path provided" }, notices("logged"))
      assert.are.same({}, log)
    end)
  end)

  describe("send-text", function()
    it("sends the text and submits it", function()
      with_tabs(1)

      run("send-text run the tests")

      assert.are.same({ "terminal.send_to_terminal run the tests submit=true" }, log)
    end)

    it("inserts without submitting after :Claudinho!", function()
      with_tabs(1)

      run("send-text draft", { bang = true })

      assert.are.same({ "terminal.send_to_terminal draft submit=false" }, log)
    end)

    it("inserts without submitting for send-text!", function()
      with_tabs(1)

      run("send-text! draft")

      assert.are.same({ "terminal.send_to_terminal draft submit=false" }, log)
    end)

    it("shows the usage without text", function()
      run("send-text")

      assert.are.same({ "[Claudinho] Usage: :Claudinho send-text <text>" }, notices("error"))
      assert.are.same({}, log)
    end)
  end)

  describe("diff-accept and diff-deny", function()
    it("act on the diff of the current buffer", function()
      run("diff-accept")
      run("diff-deny")

      assert.are.same({ "diff.accept_current_diff", "diff.deny_current_diff" }, log)
    end)
  end)

  describe("close-all-diffs", function()
    it("closes the diffs, rejects the ones waiting for their tab and tells what it did", function()
      state.pending, state.waiting, state.rejected, state.saved = 1, 2, 3, 4

      run("close-all-diffs")

      assert.are.same({ "diff.close_pending_diffs user command", "sessions.reject_all_pending user command" }, log)
      assert.are.same({
        "Closed 3 pending Claude diff(s)",
        "Closed 3 rejected Claude diff(s)",
        "Closed 4 accepted Claude diff(s). Their files hold the accepted text.",
      }, notices("info"))
      assert.are.same({}, notices("reply"))
    end)

    it("counts a diff that only waited for its tab", function()
      state.waiting = 1

      run("close-all-diffs")

      assert.are.same({ "Closed 1 pending Claude diff(s)" }, notices("info"))
      assert.are.same({}, notices("reply"))
    end)

    it("replies when there is nothing to close", function()
      run("close-all-diffs")

      assert.are.same({ "No Claude diffs to close" }, notices("reply"))
      assert.are.same({}, notices("info"))
    end)

    it("warns about accepted edits that are not saved, and about diffs it kept", function()
      state.saved = 1
      state.unsaved = { { path = "/work/a.lua", write = ":w" } }
      state.kept = { { path = "/work/b.lua", why = "its buffer has other changes" } }

      run("close-all-diffs")

      assert.are.same({
        "The accepted Claude edits for /work/a.lua are in its buffer, not saved: :w writes them, :e! drops them",
        "Kept the accepted Claude diff for /work/b.lua: its buffer has other changes",
      }, notices("reply"))
    end)
  end)

  describe("select-model", function()
    it("asks the plugin to choose the model", function()
      run("select-model")

      assert.are.same({ "open_with_model" }, log)
    end)
  end)

  describe("unknown subcommands", function()
    local valid = "toggle, open, hide, focus, new, tab, tab-next, tab-prev, tab-close, tab-restart, kill-all, "
      .. "send, add, tree-add, send-text, diff-accept, diff-deny, close-all-diffs, select-model"

    it("name the word and list the valid ones", function()
      run("frobnicate")

      assert.are.same({ "[Claudinho] Unknown subcommand 'frobnicate'. Valid: " .. valid }, notices("error"))
      assert.are.same({}, log)
    end)

    it("do not know layout (rule 86)", function()
      run("layout float")

      assert.are.same({ "[Claudinho] Unknown subcommand 'layout'. Valid: " .. valid }, notices("error"))
      assert.are.same({}, log)
    end)

    it("do not know the old command names either", function()
      run("start")

      assert.are.equal(1, #notices("error"))
    end)
  end)

  describe("complete", function()
    it("lists every subcommand for an empty first word", function()
      assert.are.same(commands.SUBCOMMANDS, commands.complete("", "Claudinho ", 10))
    end)

    it("lists the subcommands that start with the word", function()
      assert.are.same(
        { "tab", "tab-next", "tab-prev", "tab-close", "tab-restart" },
        commands.complete("tab", "Claudinho tab", 13)
      )
      assert.are.same({ "send", "send-text", "select-model" }, commands.complete("se", "Claudinho se", 12))
    end)

    it("completes the first word after a range and a bang", function()
      assert.are.same({ "send", "send-text", "select-model" }, commands.complete("se", "'<,'>Claudinho! se", 18))
    end)

    it("lists the numbers of the tabs there are for tab, tab-close and tab-restart", function()
      with_tabs(1, 2, 10)

      assert.are.same({ "1", "2", "10" }, commands.complete("", "Claudinho tab ", 14))
      assert.are.same({ "1", "10" }, commands.complete("1", "Claudinho tab-close 1", 21))
      assert.are.same({ "2" }, commands.complete("2", "Claudinho tab-restart 2", 23))
    end)

    it("lists no numbers without tabs", function()
      assert.are.same({}, commands.complete("", "Claudinho tab ", 14))
    end)

    it("lists the files for the second word of add", function()
      local calls = {}
      stub(vim.fn, "getcompletion", function(lead, kind)
        table.insert(calls, { lead, kind })
        return { "src/a.lua", "src/b.lua" }
      end)

      assert.are.same({ "src/a.lua", "src/b.lua" }, commands.complete("src/", "Claudinho add src/", 18))
      assert.are.same({ { "src/", "file" } }, calls)
    end)

    it("completes nothing after the arguments of add that are not the file", function()
      stub(vim.fn, "getcompletion", function()
        error("getcompletion must not be called")
      end)

      assert.are.same({}, commands.complete("", "Claudinho add a.lua ", 20))
    end)

    it("completes nothing for subcommands without arguments, or for send-text", function()
      with_tabs(1)

      assert.are.same({}, commands.complete("", "Claudinho toggle ", 17))
      assert.are.same({}, commands.complete("", "Claudinho send-text ", 20))
    end)

    it("does not complete layout names", function()
      assert.are.same({}, commands.complete("", "Claudinho layout ", 17))
    end)
  end)
end)
