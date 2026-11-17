-- Tests for the :Claudinho send-text subcommand (#197).
require("tests.busted_setup")
require("tests.mocks.vim")

describe("Claudinho send-text command", function()
  local mock_terminal
  local handler
  local config
  local saved_require = _G.require

  local function setup_mocks()
    mock_terminal = {
      setup = function() end,
      send_to_terminal = spy.new(function()
        return true
      end),
    }

    vim.api.nvim_create_user_command = spy.new(function(name, callback, opts)
      if name == "Claudinho" then
        handler, config = callback, opts
      end
    end)
    vim.notify = spy.new(function() end)

    _G.require = function(mod)
      if mod == "claudinho.terminal" then
        return mock_terminal
      else
        return saved_require(mod)
      end
    end
  end

  before_each(function()
    handler, config = nil, nil
    setup_mocks()

    package.loaded["claudinho.commands"] = nil
    package.loaded["claudinho.terminal"] = nil

    require("claudinho.commands").setup({})
  end)

  after_each(function()
    _G.require = saved_require
    package.loaded["claudinho.commands"] = nil
  end)

  ---Run `:Claudinho <args>` the way Neovim hands it over.
  ---@param args string
  ---@param bang boolean|nil
  local function run(args, bang)
    local fargs = {}
    for word in args:gmatch("%S+") do
      fargs[#fargs + 1] = word
    end
    handler({ args = args, fargs = fargs, bang = bang or false })
  end

  it("is a subcommand of :Claudinho, which takes arguments and a bang", function()
    assert.is_function(handler)
    assert.is_equal("*", config.nargs)
    assert.is_true(config.bang)
    assert.is_string(config.desc)
  end)

  it("sends text and submits by default", function()
    run("send-text run the tests")

    assert.spy(mock_terminal.send_to_terminal).was_called()
    local call = mock_terminal.send_to_terminal.calls[1]
    assert.is_equal("run the tests", call.vals[1])
    assert.is_true(call.vals[2].submit)
  end)

  it("inserts without submitting when bang is used", function()
    run("send-text draft text", true)

    local call = mock_terminal.send_to_terminal.calls[1]
    assert.is_equal("draft text", call.vals[1])
    assert.is_false(call.vals[2].submit)
  end)

  it("inserts without submitting for send-text!", function()
    run("send-text! draft text")

    local call = mock_terminal.send_to_terminal.calls[1]
    assert.is_equal("draft text", call.vals[1])
    assert.is_false(call.vals[2].submit)
  end)

  it("keeps the spaces inside the text", function()
    run("send-text  two   spaces")

    assert.is_equal("two   spaces", mock_terminal.send_to_terminal.calls[1].vals[1])
  end)

  it("shows the usage and does not send when no text is provided", function()
    run("send-text")

    assert.spy(mock_terminal.send_to_terminal).was_not_called()
    assert.spy(vim.notify).was_called()
    assert.is_equal("[Claudinho] Usage: :Claudinho send-text <text>", vim.notify.calls[1].vals[1])
    assert.is_equal(vim.log.levels.ERROR, vim.notify.calls[1].vals[2])
  end)
end)
