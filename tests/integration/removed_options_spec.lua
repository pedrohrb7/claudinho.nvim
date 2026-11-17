-- Real-Neovim check that the removed-option warnings come out once per key and per session, even if setup() runs
-- again. Mock vim has no real vim.notify_once, so under busted this is pending.
if vim == nil or vim.fn.has("nvim") ~= 1 then
  describe("removed options", function()
    pending("needs a real Neovim")
  end)
  return
end

describe("removed options", function()
  local saved_notify = vim.notify
  local notifications

  before_each(function()
    notifications = {}
    vim.notify = function(msg, level)
      table.insert(notifications, { msg = msg, level = level })
    end
  end)

  after_each(function()
    vim.notify = saved_notify
  end)

  local function removed_config()
    return {
      notify = true,
      auto_start = false,
      queue_timeout = 5000,
      diff_opts = {
        vertical_split = true,
        open_in_current_tab = true,
        auto_close_on_accept = true,
        show_diff_stats = true,
      },
      terminal = { provider = "snacks", snacks_win_opts = {}, split_side = "left" },
      cwd = "/tmp",
    }
  end

  local function warns_removed()
    local warns = {}
    for _, n in ipairs(notifications) do
      if n.level == vim.log.levels.WARN and n.msg:find("was removed", 1, true) then
        table.insert(warns, n.msg)
      end
    end
    return warns
  end

  it("shows one warning per key on the first setup and none on the second", function()
    local claudinho = require("claudinho")
    claudinho.setup(removed_config())

    assert.are.equal(10, #warns_removed())

    notifications = {}
    claudinho.setup(removed_config())
    assert.are.same({}, warns_removed())
  end)

  it("shows no warning without notify = true, and the health check keeps the keys", function()
    local claudinho = require("claudinho")
    local config = removed_config()
    config.notify = nil
    config.cwd_provider = function() end
    claudinho.setup(config)

    assert.are.same({}, warns_removed())
    local paths = {}
    for _, row in ipairs(claudinho.state.removed_found) do
      paths[#paths + 1] = table.concat(row.path, ".")
    end
    assert.is_true(vim.tbl_contains(paths, "terminal.split_side"))
    assert.is_true(vim.tbl_contains(paths, "cwd_provider"))
  end)
end)
