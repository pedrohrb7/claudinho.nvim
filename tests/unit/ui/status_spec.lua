require("tests.busted_setup")

describe("ui.status", function()
  local status

  before_each(function()
    package.loaded["claudinho.ui.status"] = nil
    status = require("claudinho.ui.status")
  end)

  it("joins model, effort and mode in this order", function()
    assert.equals(
      "Opus 5.5 \xC2\xB7 high \xC2\xB7 plan",
      status.text({ mode = "plan", effort = "high", model = "Opus 5.5" })
    )
  end)

  it("skips a missing item without a stray separator", function()
    assert.equals("Opus 5.5 \xC2\xB7 plan", status.text({ model = "Opus 5.5", mode = "plan" }))
    assert.equals("high \xC2\xB7 plan", status.text({ effort = "high", mode = "plan" }))
    assert.equals("Opus 5.5", status.text({ model = "Opus 5.5" }))
    assert.equals("high", status.text({ effort = "high" }))
  end)

  it("is empty without data", function()
    assert.equals("", status.text({}))
    assert.equals("", status.text(nil))
  end)

  describe("modes", function()
    local cases = {
      { "default", "manual" },
      { "manual", "manual" },
      { "plan", "plan" },
      { "auto", "auto" },
      { "acceptEdits", "accept edits" },
      { "dontAsk", "don't ask" },
      { "bypassPermissions", "bypass permissions" },
    }
    for _, case in ipairs(cases) do
      local mode, shown = case[1], case[2]
      it(mode .. " shows " .. shown, function()
        assert.equals(shown, status.text({ mode = mode }))
      end)
    end

    it("shows an unknown mode as it came", function()
      assert.equals("futureMode", status.text({ mode = "futureMode" }))
    end)
  end)

  it("doubles % for the statusline", function()
    assert.equals("100%% model", status.text({ model = "100% model" }))
  end)
end)
