--- The key mapping preset (`keymaps.preset`, rule 69): off by default, and when on it maps its keys with the commands of
--- the spec, leaves alone a key that already has a mapping (with an informative notice), and does not warn about its own
--- keys when `setup` runs again.
require("tests.busted_setup")

describe("keymaps preset", function()
  local commands
  local loaded_names = { "claudinho.commands", "claudinho.notify" }
  local saved_loaded, restore_list
  local mapped, existing, notices

  ---Replace tbl[key] until after_each.
  local function stub(tbl, key, value)
    table.insert(restore_list, { tbl, key, tbl[key] })
    tbl[key] = value
  end

  ---@param lhs string
  ---@return table|nil The map call of the key
  local function mapping(lhs)
    for _, call in ipairs(mapped) do
      if call.lhs == lhs then
        return call
      end
    end
    return nil
  end

  before_each(function()
    saved_loaded, restore_list = {}, {}
    for _, name in ipairs(loaded_names) do
      saved_loaded[name] = package.loaded[name]
      package.loaded[name] = nil
    end
    mapped, existing, notices = {}, {}, {}

    package.loaded["claudinho.notify"] = {
      info = function(msg, opts)
        table.insert(notices, { msg = msg, opts = opts })
      end,
      reply = function() end,
      error = function() end,
    }
    stub(vim.keymap, "set", function(mode, lhs, rhs, opts)
      table.insert(mapped, { mode = mode, lhs = lhs, rhs = rhs, opts = opts })
    end)
    stub(vim.fn, "maparg", function(lhs, mode, abbr, dict)
      assert.are.equal(false, abbr)
      assert.are.equal(true, dict)
      return existing[mode .. " " .. lhs] or {}
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

  it("maps nothing when the preset is off", function()
    commands.apply_preset({ keymaps = { preset = false } })

    assert.are.same({}, mapped)
    assert.are.same({}, notices)
  end)

  it("maps nothing without a keymaps table", function()
    commands.apply_preset({})
    commands.apply_preset(nil)

    assert.are.same({}, mapped)
  end)

  it("maps nothing from commands.setup with the default configuration", function()
    stub(vim.api, "nvim_create_user_command", function() end)

    commands.setup({ keymaps = { preset = false } })

    assert.are.same({}, mapped)
  end)

  describe("with the preset on", function()
    before_each(function()
      commands.apply_preset({ keymaps = { preset = true } })
    end)

    it("maps the twenty keys of the table", function()
      assert.are.equal(20, #mapped)
      assert.are.equal(20, #commands.PRESET)
    end)

    it("maps the commands of the spec", function()
      local expected = {
        { "n", "<leader>ac", "<cmd>Claudinho toggle<cr>" },
        { "n", "<leader>af", "<cmd>Claudinho focus<cr>" },
        { "n", "<leader>an", "<cmd>Claudinho new<cr>" },
        { "n", "<leader>al", "<cmd>Claudinho tab-next<cr>" },
        { "n", "<leader>ah", "<cmd>Claudinho tab-prev<cr>" },
        { "n", "<leader>a1", "<cmd>Claudinho tab 1<cr>" },
        { "n", "<leader>a2", "<cmd>Claudinho tab 2<cr>" },
        { "n", "<leader>a3", "<cmd>Claudinho tab 3<cr>" },
        { "n", "<leader>a4", "<cmd>Claudinho tab 4<cr>" },
        { "n", "<leader>a5", "<cmd>Claudinho tab 5<cr>" },
        { "n", "<leader>a6", "<cmd>Claudinho tab 6<cr>" },
        { "n", "<leader>a7", "<cmd>Claudinho tab 7<cr>" },
        { "n", "<leader>a8", "<cmd>Claudinho tab 8<cr>" },
        { "n", "<leader>a9", "<cmd>Claudinho tab 9<cr>" },
        { "n", "<leader>ax", "<cmd>Claudinho tab-close<cr>" },
        { "n", "<leader>am", "<cmd>Claudinho select-model<cr>" },
        { "n", "<leader>ab", "<cmd>Claudinho add %<cr>" },
        { "x", "<leader>as", ":Claudinho send<cr>" },
        { "n", "<leader>aa", "<cmd>Claudinho diff-accept<cr>" },
        { "n", "<leader>ad", "<cmd>Claudinho diff-deny<cr>" },
      }
      for _, key in ipairs(expected) do
        local call = mapping(key[2])
        assert.is_not_nil(call, key[2])
        assert.are.equal(key[1], call.mode, key[2])
        assert.are.equal(key[3], call.rhs, key[2])
      end
    end)

    it("gives each key a description in English", function()
      for _, call in ipairs(mapped) do
        assert.is_string(call.opts.desc, call.lhs)
        assert.is_truthy(call.opts.desc:match("^Claudinho: "), call.lhs)
      end
    end)

    it("says nothing when no key was taken", function()
      assert.are.same({}, notices)
    end)
  end)

  it("leaves a key that is already mapped alone and says so, once", function()
    existing["n <leader>ac"] = { lhs = " ac", rhs = ":echo mine<cr>" }

    commands.apply_preset({ keymaps = { preset = true } })

    assert.is_nil(mapping("<leader>ac"))
    assert.are.equal(19, #mapped)
    assert.are.equal(1, #notices)
    assert.are.equal("[Claudinho] keymaps.preset left <leader>ac alone: it is already mapped.", notices[1].msg)
    assert.is_true(notices[1].opts.once)
  end)

  it("checks the mapping in the mode of the key", function()
    -- <leader>as is a mapping of Visual mode (x): one in Normal mode is another key.
    existing["n <leader>as"] = { rhs = ":echo mine<cr>" }

    commands.apply_preset({ keymaps = { preset = true } })

    assert.is_not_nil(mapping("<leader>as"))
    assert.are.same({}, notices)

    existing["x <leader>as"] = { rhs = ":echo mine<cr>" }
    mapped, notices = {}, {}
    commands.apply_preset({ keymaps = { preset = true } })

    assert.is_nil(mapping("<leader>as"))
    assert.are.equal(1, #notices)
  end)

  it("keeps every other key when one is taken", function()
    existing["n <leader>ac"] = { rhs = "x" }
    existing["n <leader>a1"] = { rhs = "y" }

    commands.apply_preset({ keymaps = { preset = true } })

    assert.are.equal(18, #mapped)
    assert.are.equal(2, #notices)
  end)

  it("maps its own keys again, without a notice, when setup runs twice", function()
    local own = {}
    for _, key in ipairs(commands.PRESET) do
      own[key[2] .. " " .. key[1]] = { rhs = key[3], desc = key[4] }
    end
    existing = own

    commands.apply_preset({ keymaps = { preset = true } })

    assert.are.equal(20, #mapped)
    assert.are.same({}, notices)
  end)
end)
