require("tests.busted_setup")

describe("ui.window geometry", function()
  local window

  ---@type ClaudinhoWindowConfig
  local defaults = {
    layout = "right",
    right = { width = 0.30 },
    bottom = { height = 0.30 },
    float = { width = 0.80, height = 0.80 },
    tab_title_max = 24,
  }

  ---@param overrides table|nil
  ---@return ClaudinhoWindowConfig
  local function window_config(overrides)
    return vim.tbl_deep_extend("force", defaults, overrides or {})
  end

  before_each(function()
    package.loaded["claudinho.ui.window"] = nil
    window = require("claudinho.ui.window")
  end)

  describe("right", function()
    local cases = {
      { 200, 0.30, 60 },
      { 120, 0.30, 36 },
      { 101, 0.30, 30 },
      { 80, 0.50, 40 },
      { 10, 0.05, 1 },
    }
    for _, case in ipairs(cases) do
      it(("takes floor(%d * %s) = %d columns"):format(case[1], case[2], case[3]), function()
        local geometry =
          window.geometry("right", { columns = case[1], lines = 50 }, window_config({ right = { width = case[2] } }))
        assert.same({ width = case[3] }, geometry)
      end)
    end
  end)

  describe("bottom", function()
    local cases = {
      { 50, 0.30, 15 },
      { 24, 0.30, 7 },
      { 40, 0.50, 20 },
      { 5, 0.10, 1 },
    }
    for _, case in ipairs(cases) do
      it(("takes floor(%d * %s) = %d rows"):format(case[1], case[2], case[3]), function()
        local geometry = window.geometry(
          "bottom",
          { columns = 100, lines = case[1] },
          window_config({ bottom = { height = case[2] } })
        )
        assert.same({ height = case[3] }, geometry)
      end)
    end
  end)

  describe("float", function()
    it("is centered in the editor area", function()
      local geometry = window.geometry("float", { columns = 200, lines = 50, cmdheight = 1 }, window_config())
      -- 49 rows of editor area: 80% is 39, centered at row 5; 80% of 200 is 160 columns, centered at column 20.
      assert.same({ width = 160, height = 39, col = 20, row = 5 }, geometry)
    end)

    it("leaves the tabline and the statusline out of the area", function()
      local env = { columns = 100, lines = 40, cmdheight = 1, top = 1, status = 1 }
      local geometry = window.geometry("float", env, window_config({ float = { width = 0.5, height = 0.5 } }))
      -- 37 rows of area: 50% is 18, row = 1 + floor((37 - 18) / 2) = 10.
      assert.same({ width = 50, height = 18, col = 25, row = 10 }, geometry)
    end)

    it("follows the screen size", function()
      local small = window.geometry("float", { columns = 80, lines = 24, cmdheight = 1 }, window_config())
      local large = window.geometry("float", { columns = 240, lines = 60, cmdheight = 1 }, window_config())
      assert.same({ width = 64, height = 18, col = 8, row = 2 }, small)
      assert.same({ width = 192, height = 47, col = 24, row = 6 }, large)
    end)

    it("takes the whole area at 1 and stays inside it", function()
      local geometry = window.geometry(
        "float",
        { columns = 90, lines = 30, cmdheight = 2 },
        window_config({ float = { width = 1, height = 1 } })
      )
      assert.same({ width = 90, height = 28, col = 0, row = 0 }, geometry)
    end)

    it("never goes below one cell on a tiny screen", function()
      local geometry = window.geometry("float", { columns = 1, lines = 2, cmdheight = 1 }, window_config())
      assert.equals(1, geometry.width)
      assert.equals(1, geometry.height)
    end)
  end)

  it("tab needs no size", function()
    assert.same({}, window.geometry("tab", { columns = 100, lines = 40 }, window_config()))
  end)

  it("an unknown layout is sized as right", function()
    assert.same({ width = 30 }, window.geometry("nowhere", { columns = 100, lines = 40 }, window_config()))
  end)
end)
