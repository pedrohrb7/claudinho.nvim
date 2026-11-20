require("tests.busted_setup")

local FIXTURES = "tests/fixtures/claude/"

local SESSION_ID = "123e4567-e89b-12d3-a456-426614174000"

local function fixture(name)
  local file = assert(io.open(FIXTURES .. name .. ".json", "r"))
  local body = file:read("*a")
  file:close()
  return body
end

describe("sources.session_data", function()
  local session_data
  local original_decode

  before_each(function()
    original_decode = vim.json.decode
    -- The busted mock has no real decoder; the lenient one of the test setup stands in, and a nil is an error as in Neovim.
    vim.json.decode = function(body)
      local value = _G.json_decode(body)
      if value == nil then
        error("invalid JSON")
      end
      return value
    end
    package.loaded["claudinho.sources.session_data"] = nil
    session_data = require("claudinho.sources.session_data")
  end)

  after_each(function()
    vim.json.decode = original_decode
  end)

  local function statusline(name)
    return session_data.from_statusline(session_data.decode(fixture(name)))
  end

  describe("decode()", function()
    it("decodes an object", function()
      assert.equals(SESSION_ID, session_data.decode(fixture("hook_stop")).session_id)
    end)

    it("returns nil, without an error, for invalid JSON", function()
      assert.is_nil(session_data.decode(""))
      assert.is_nil(session_data.decode(nil))
      assert.is_nil(session_data.decode(42))
    end)

    it("returns nil when the decoder fails", function()
      vim.json.decode = function()
        error("boom")
      end
      assert.is_nil(session_data.decode("{"))
    end)

    it("returns nil for JSON that is not an object", function()
      vim.json.decode = function()
        return { 1, 2 }
      end
      assert.is_nil(session_data.decode("[1,2]"))
      vim.json.decode = function()
        return "text"
      end
      assert.is_nil(session_data.decode('"text"'))
    end)
  end)

  describe("model_label()", function()
    it("keeps a display name that has a digit", function()
      assert.equals("Opus 5.5", statusline("statusline_opus_display_version").model)
    end)

    it("takes the version from the id when the display name has none", function()
      assert.equals("Opus 5.5", statusline("statusline_opus_display_only").model)
      assert.equals("Opus 5.5", statusline("statusline_no_effort").model)
    end)

    it("drops the date suffix of a new-format id", function()
      assert.equals("Haiku 4.5", statusline("statusline_id_haiku_dated").model)
    end)

    it("reads the legacy format", function()
      assert.equals("Haiku 3.5", statusline("statusline_id_legacy").model)
    end)

    it("drops the provider prefix and the -v1:0 suffix", function()
      assert.equals("Opus 5.5", statusline("statusline_id_bedrock").model)
    end)

    it("drops the [1m] suffix and accepts a single-number version", function()
      assert.equals("Opus 5", statusline("statusline_id_context").model)
    end)

    it("handles the other id decorations", function()
      assert.equals("Sonnet 4.5", session_data.model_label({ id = "claude-sonnet-4-5@20250929" }))
      assert.equals("Opus 5", session_data.model_label({ id = "claude-opus-5" }))
    end)

    it("falls back to the display name for an unknown id", function()
      assert.equals("Banana", statusline("statusline_id_unknown").model)
    end)

    it("returns nil without a display name or a usable id", function()
      assert.is_nil(session_data.model_label({ id = "gpt-banana" }))
      assert.is_nil(session_data.model_label({}))
      assert.is_nil(session_data.model_label("opus"))
      assert.is_nil(session_data.model_label(nil))
    end)
  end)

  describe("from_statusline()", function()
    it("reads session id, model and effort", function()
      assert.same(
        { session_id = SESSION_ID, model = "Opus 5.5", effort = "high" },
        statusline("statusline_opus_display_version")
      )
    end)

    it("leaves the effort out when the field is missing", function()
      assert.is_nil(statusline("statusline_no_effort").effort)
    end)

    it("treats fields of the wrong type as missing", function()
      assert.same({}, statusline("statusline_wrong_types"))
    end)

    it("accepts nil", function()
      assert.same({}, session_data.from_statusline(nil))
    end)

    it("drops a session id that is no UUID, as it reaches the command line of --resume", function()
      for _, hostile in ipairs({
        "--dangerously-skip-permissions",
        "--settings=/tmp/x.json",
        "123e4567-e89b-12d3-a456-42661417400",
        "123e4567-e89b-12d3-a456-4266141740000",
        "123e4567-e89b-12d3-a456-42661417400g",
        "123e4567-e89b-12d3-a456-426614174000 --x",
        "123e4567-e89b-12d3-a456-426614174000\n--x",
        "s1",
        "",
      }) do
        assert.is_nil(session_data.from_statusline({ session_id = hostile }).session_id, hostile)
        assert.is_nil(session_data.from_hook({ session_id = hostile }).session_id, hostile)
      end
    end)

    it("keeps a UUID in either case", function()
      local upper = "123E4567-E89B-12D3-A456-426614174000"
      assert.equals(upper, session_data.from_hook({ session_id = upper }).session_id)
    end)
  end)

  describe("rate_limits()", function()
    local EMPTY_MT = {}
    local original_empty_dict

    before_each(function()
      original_empty_dict = vim.empty_dict
      vim.empty_dict = function()
        return setmetatable({}, EMPTY_MT)
      end
    end)

    after_each(function()
      vim.empty_dict = original_empty_dict
    end)

    local function win(used, resets_at)
      return { used_percentage = used, resets_at = resets_at }
    end

    it("reads both windows from the fixture", function()
      assert.same({
        five_hour = { used = 23.5, resets_at = 1790000000 },
        seven_day = { used = 41.2, resets_at = 1790400000 },
      }, statusline("statusline_rate_limits_both").rate_limits)
    end)

    it("reads one window from the fixture", function()
      assert.same(
        { five_hour = { used = 80, resets_at = 1790000000 } },
        statusline("statusline_rate_limits_one").rate_limits
      )
    end)

    it("keeps an empty object as {}, as the decoder marks it", function()
      assert.same({}, session_data.rate_limits(vim.empty_dict()))
      assert.same({}, session_data.rate_limits({ spend_limit = { used_percentage = 5 }, new_field = 1 }))
    end)

    it("reads the empty-object fixture as nil when the decoder leaves no mark, and as {} when it does", function()
      -- The lenient decoder of the test setup returns a plain table.
      assert.is_nil(statusline("statusline_rate_limits_empty").rate_limits)
      assert.same({}, session_data.from_statusline({ rate_limits = vim.empty_dict() }).rate_limits)
    end)

    it("gives nil for what is not an object", function()
      for _, value in ipairs({ {}, { 1, 2 }, "x", 5, true }) do
        assert.is_nil(session_data.rate_limits(value))
      end
      assert.is_nil(session_data.rate_limits(nil))
      assert.is_nil(session_data.rate_limits(vim.NIL))
    end)

    it("accepts decimal, 0, 100 and above 100 as they came", function()
      local r = session_data.rate_limits({
        five_hour = win(79.5, 10),
        seven_day = win(103, 10),
      })
      assert.equals(79.5, r.five_hour.used)
      assert.equals(103, r.seven_day.used)
      assert.equals(0, session_data.rate_limits({ five_hour = win(0) }).five_hour.used)
      assert.equals(100, session_data.rate_limits({ five_hour = win(100) }).five_hour.used)
    end)

    it("drops a window whose used_percentage is negative, wrong type, null, NaN or infinite", function()
      for _, bad in ipairs({ -1, "23", true, {}, vim.NIL, 0 / 0, math.huge, -math.huge }) do
        assert.same({}, session_data.rate_limits({ five_hour = win(bad, 10), seven_day = { resets_at = 10 } }))
      end
    end)

    it("drops a window that is not a table", function()
      assert.same({}, session_data.rate_limits({ five_hour = "x", seven_day = 3 }))
    end)

    it("leaves resets_at out when missing, wrong type, zero, negative or not finite", function()
      for _, bad in ipairs({ "soon", 0, -5, 0 / 0, math.huge }) do
        assert.same({ five_hour = { used = 10 } }, session_data.rate_limits({ five_hour = win(10, bad) }))
      end
      assert.same({ five_hour = { used = 10 } }, session_data.rate_limits({ five_hour = win(10) }))
    end)

    it("ignores spend_limit and new fields", function()
      local r = session_data.rate_limits({
        five_hour = { used_percentage = 1, resets_at = 5, extra = true },
        spend_limit = { used_percentage = 9 },
        month = win(3, 4),
      })
      assert.same({ five_hour = { used = 1, resets_at = 5 } }, r)
    end)

    it("handles the wrong-types fixture", function()
      assert.same({ seven_day = { used = 10 } }, statusline("statusline_rate_limits_wrong_types").rate_limits)
    end)
  end)

  describe("vim_mode", function()
    it("reads NORMAL from the fixture", function()
      assert.equals("NORMAL", statusline("statusline_vim_normal").vim_mode)
    end)

    it("reads INSERT", function()
      assert.equals("INSERT", session_data.from_statusline({ vim = { mode = "INSERT" } }).vim_mode)
    end)

    it("is nil without vim, with a vim of the wrong type or a mode of the wrong type", function()
      assert.is_nil(session_data.from_statusline({}).vim_mode)
      assert.is_nil(session_data.from_statusline({ vim = "NORMAL" }).vim_mode)
      assert.is_nil(session_data.from_statusline({ vim = { mode = 1 } }).vim_mode)
      assert.is_nil(session_data.from_statusline({ vim = { mode = "" } }).vim_mode)
    end)

    it("does not change model, effort or session id", function()
      local d = statusline("statusline_rate_limits_both")
      assert.equals("Opus 5.5", d.model)
      assert.equals("high", d.effort)
      assert.equals(SESSION_ID, d.session_id)
    end)
  end)

  describe("from_hook()", function()
    local function hook(name)
      return session_data.from_hook(session_data.decode(fixture(name)))
    end

    it("reads the mode of a SessionStart", function()
      assert.same({ session_id = SESSION_ID, mode = "plan" }, hook("hook_session_start_clear"))
    end)

    it("reads the mode of a UserPromptSubmit", function()
      assert.equals("acceptEdits", hook("hook_user_prompt_submit").mode)
    end)

    it("has no mode when the event does not carry one", function()
      assert.same({ session_id = SESSION_ID }, hook("hook_stop"))
    end)

    it("reads an unknown event without error", function()
      assert.same({ session_id = SESSION_ID, mode = "auto" }, hook("hook_unknown_event"))
    end)

    it("ignores a mode of the wrong type", function()
      assert.same({}, session_data.from_hook({ permission_mode = 3, session_id = {} }))
      assert.same({}, session_data.from_hook(nil))
    end)
  end)
end)
