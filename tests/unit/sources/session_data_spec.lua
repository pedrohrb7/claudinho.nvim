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
