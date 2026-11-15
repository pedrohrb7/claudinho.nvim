require("tests.busted_setup")

local temp_dir = require("tests.helpers.temp_dir")
local q = temp_dir.quote

local function have(tool)
  return os.execute("command -v " .. tool .. " >/dev/null 2>&1") == 0
end

local function run(cmd)
  local pipe = assert(io.popen(cmd .. ' 2>&1; echo "__EXIT:$?"'))
  local out = pipe:read("*a")
  pipe:close()
  local code = tonumber(out:match("__EXIT:(%d+)%s*$"))
  return out:gsub("__EXIT:%d+%s*$", ""), code
end

local function read(path)
  local file = assert(io.open(path, "r"))
  local text = file:read("*a")
  file:close()
  return text
end

local function write(path, text)
  local file = assert(io.open(path, "w"))
  file:write(text)
  file:close()
end

local CHANGELOG = [[
# Changelog

## [Unreleased]

### Added

- A new thing.

## [0.1.0] - 2026-01-01

### Changed

- First release.

[Unreleased]: https://github.com/pedrohrb7/claudinho.nvim/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/pedrohrb7/claudinho.nvim/releases/tag/v0.1.0
]]

if not (have("git") and have("bash")) then
  describe("scripts/release.sh", function()
    pending("needs git and bash on PATH")
  end)
  return
end

describe("scripts/release.sh", function()
  local dir
  local script

  ---Run git inside the fixture repo.
  local function git(args)
    return run("git -C " .. q(dir) .. " " .. args)
  end

  ---Run the copied script inside the fixture repo.
  local function release(args)
    return run("cd " .. q(dir) .. " && RELEASE_SKIP_FORMAT=1 bash scripts/release.sh " .. args)
  end

  before_each(function()
    dir = temp_dir.new()
    script = read("scripts/release.sh")
    os.execute("mkdir -p " .. q(dir .. "/scripts"))
    write(dir .. "/scripts/release.sh", script)
    write(dir .. "/VERSION", "0.1.0\n")
    write(dir .. "/CHANGELOG.md", CHANGELOG)
    assert(select(2, git("init -q -b main")) == 0)
    git("config user.name Tester")
    git("config user.email tester@example.com")
    git("config commit.gpgsign false")
    git("config tag.gpgsign false")
    git("add -A")
    assert(select(2, git("commit -q -m initial")) == 0)
  end)

  after_each(function()
    temp_dir.remove(dir)
    dir = nil
  end)

  it("bumps minor, rewrites the changelog, commits and tags", function()
    local out, code = release("minor")
    assert.are.equal(0, code, out)
    assert.are.equal("0.2.0\n", read(dir .. "/VERSION"))

    local changelog = read(dir .. "/CHANGELOG.md")
    local today = os.date("%Y-%m-%d")
    assert.is_truthy(
      changelog:find("## [Unreleased]\n\n## [0.2.0] - " .. today .. "\n\n### Added\n\n- A new thing.", 1, true)
    )
    assert.is_truthy(
      changelog:find(
        "[Unreleased]: https://github.com/pedrohrb7/claudinho.nvim/compare/v0.2.0...HEAD\n[0.2.0]: https://github.com/pedrohrb7/claudinho.nvim/releases/tag/v0.2.0\n[0.1.0]: ",
        1,
        true
      )
    )
    assert.is_nil(changelog:find("compare/v0.1.0", 1, true))

    assert.are.equal("chore(release): 0.2.0\n", (git("log -1 --format=%s")))
    assert.are.equal("", (git("status --porcelain")))
    local tag_commit = git("rev-list -n 1 v0.2.0")
    local head = git("rev-parse HEAD")
    assert.are.equal(head, tag_commit)
    assert.are.equal("tag\n", (git("cat-file -t v0.2.0")))
    assert.are.equal("claudinho.nvim 0.2.0\n", (git("tag -l --format='%(contents:subject)' v0.2.0")))
    assert.is_truthy(out:find("git push origin main v0.2.0", 1, true))
  end)

  it("bumps patch", function()
    local out, code = release("patch")
    assert.are.equal(0, code, out)
    assert.are.equal("0.1.1\n", read(dir .. "/VERSION"))
    assert.are.equal("v0.1.1\n", (git("tag -l v0.1.1")))
  end)

  it("bumps major and resets minor and patch", function()
    write(dir .. "/VERSION", "1.4.7\n")
    git("commit -q -am bump")
    local out, code = release("major")
    assert.are.equal(0, code, out)
    assert.are.equal("2.0.0\n", read(dir .. "/VERSION"))
    assert.are.equal("v2.0.0\n", (git("tag -l v2.0.0")))
  end)

  it("refuses a dirty working tree", function()
    write(dir .. "/dirty.txt", "x")
    local out, code = release("minor")
    assert.are_not.equal(0, code)
    assert.is_truthy(out:find("not clean", 1, true))
    assert.are.equal("0.1.0\n", read(dir .. "/VERSION"))
  end)

  it("refuses an empty Unreleased section", function()
    write(dir .. "/CHANGELOG.md", (CHANGELOG:gsub("%- A new thing%.\n", "")))
    git("commit -q -am empty")
    local out, code = release("minor")
    assert.are_not.equal(0, code)
    assert.is_truthy(out:find("no entries", 1, true))
    assert.are.equal("", (git("tag -l v0.2.0")))
  end)

  it("refuses when the tag already exists", function()
    git("tag v0.2.0")
    local out, code = release("minor")
    assert.are_not.equal(0, code)
    assert.is_truthy(out:find("already exists", 1, true))
    assert.are.equal("0.1.0\n", read(dir .. "/VERSION"))
  end)

  it("refuses on a branch other than main", function()
    git("checkout -q -b feature")
    local out, code = release("minor")
    assert.are_not.equal(0, code)
    assert.is_truthy(out:find("main", 1, true))
    assert.are.equal("0.1.0\n", read(dir .. "/VERSION"))
  end)

  it("refuses a missing or invalid bump kind", function()
    local out, code = release("")
    assert.are_not.equal(0, code)
    assert.is_truthy(out:find("missing bump kind", 1, true))
    out, code = release("huge")
    assert.are_not.equal(0, code)
    assert.is_truthy(out:find("unknown argument", 1, true))
  end)

  it("changes nothing with --dry-run", function()
    local head_before = git("rev-parse HEAD")
    local out, code = release("minor --dry-run")
    assert.are.equal(0, code, out)
    assert.is_truthy(out:find("0.2.0", 1, true))
    assert.is_truthy(out:find("+## [0.2.0] - " .. os.date("%Y-%m-%d"), 1, true))
    assert.are.equal(head_before, git("rev-parse HEAD"))
    assert.are.equal("", (git("tag -l v0.2.0")))
    assert.are.equal("", (git("status --porcelain")))
    assert.are.equal("0.1.0\n", read(dir .. "/VERSION"))
    assert.are.equal(CHANGELOG, read(dir .. "/CHANGELOG.md"))
  end)
end)
