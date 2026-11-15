require("tests.busted_setup")
require("tests.mocks.vim")

describe("claudinho namespace", function()
  it("finds the claudinho module on the package path", function()
    assert.is_truthy(package.searchpath("claudinho", package.path))
  end)

  it("no longer finds a claudecode module on the package path", function()
    assert.is_nil(package.searchpath("claudecode", package.path))
  end)

  it("exposes setup as a function", function()
    assert.is_function(require("claudinho").setup)
  end)

  it("reports the version from the VERSION file", function()
    local file = assert(io.open("VERSION", "r"))
    local text = file:read("*l")
    file:close()
    assert.equals(text, require("claudinho").version:string())
  end)
end)
