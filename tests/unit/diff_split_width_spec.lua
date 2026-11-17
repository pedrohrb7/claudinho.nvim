require("tests.busted_setup")

describe("Diff/idle terminal split width resolution", function()
  local diff = require("claudinho.diff")

  local function resolve(when)
    return diff._resolve_split_width_percentage(when)
  end

  it("uses window.right.width for both states when diff width is unset", function()
    diff.setup({ window = { right = { width = 0.5 } } })
    assert.are.equal(0.5, resolve("idle"))
    assert.are.equal(0.5, resolve("diff"))
  end)

  it("shrinks to window.right.diff_width while a diff is active, idle unchanged", function()
    diff.setup({ window = { right = { width = 0.5, diff_width = 0.3 } } })
    assert.are.equal(0.5, resolve("idle"))
    assert.are.equal(0.3, resolve("diff"))
  end)

  it("falls back to the 0.30 default when no widths are configured", function()
    diff.setup({ window = { right = {} } })
    assert.are.equal(0.30, resolve("idle"))
    assert.are.equal(0.30, resolve("diff"))
  end)

  it("ignores an out-of-range diff width and falls back to the idle width", function()
    diff.setup({ window = { right = { width = 0.5, diff_width = 2.0 } } })
    assert.are.equal(0.5, resolve("diff"))
  end)

  it("ignores a non-number diff width and falls back to the idle width", function()
    diff.setup({ window = { right = { width = 0.4, diff_width = "wide" } } })
    assert.are.equal(0.4, resolve("diff"))
  end)

  it("allows a diff width wider than the idle width", function()
    diff.setup({ window = { right = { width = 0.3, diff_width = 0.6 } } })
    assert.are.equal(0.3, resolve("idle"))
    assert.are.equal(0.6, resolve("diff"))
  end)
end)
