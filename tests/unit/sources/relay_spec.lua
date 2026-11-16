--- The relay script as a module: the request it builds and what main() does with its input, with the network and the
--- standard streams replaced. The real run (`nvim --clean -l`) is in tests/integration/relay_spec.lua.
require("tests.busted_setup")

describe("sources.relay", function()
  local relay

  before_each(function()
    package.loaded["claudinho.sources.relay"] = nil
    relay = require("claudinho.sources.relay")
  end)

  describe("build_request()", function()
    it("builds the request line, the headers and the body", function()
      local request = relay.build_request("hook", '{"a":1}', "tok-123")

      local head, body = request:match("^(.-)\r\n\r\n(.*)$")
      assert.equals('{"a":1}', body)
      assert.equals("POST /claudinho/hook HTTP/1.1", head:match("^[^\r]+"))
      assert.is_truthy(head:find("\r\nX-Claudinho-Token: tok-123", 1, true))
      assert.is_truthy(head:find("\r\nContent-Length: 7", 1, true))
      assert.is_truthy(head:find("\r\nConnection: close", 1, true))
    end)

    it("counts the Content-Length in bytes, not characters", function()
      local body = '{"model":"Opus \xc3\xa9\xe2\x82\xac"}'

      local request = relay.build_request("statusline", body, "t")

      assert.is_truthy(request:find("\r\nContent-Length: " .. #body .. "\r\n", 1, true))
      assert.equals(body, request:match("\r\n\r\n(.*)$"))
    end)

    it("leaves the token header out without a token", function()
      local request = relay.build_request("hook", "{}", nil)

      assert.is_nil(request:find("X-Claudinho-Token", 1, true))
    end)
  end)

  describe("parse_port()", function()
    it("accepts a port from 1 to 65535", function()
      assert.equals(1, relay.parse_port("1"))
      assert.equals(43210, relay.parse_port("43210"))
      assert.equals(65535, relay.parse_port("65535"))
    end)

    it("refuses a missing, empty, zero, huge, negative or non-integer value", function()
      for _, value in ipairs({ "", "0", "65536", "-4", "1.5", "abc" }) do
        assert.is_nil(relay.parse_port(value), value)
      end
      assert.is_nil(relay.parse_port(nil))
    end)
  end)

  describe("main()", function()
    local sent, out, stdin_reads, env

    ---@param kind string|nil
    ---@return integer
    local function run(kind)
      return relay.main(kind, {
        getenv = function(name)
          return env[name]
        end,
        read_stdin = function()
          stdin_reads = stdin_reads + 1
          return '{"session_id":"s1"}'
        end,
        write_stdout = function(text)
          table.insert(out, text)
        end,
        send = function(port, request)
          table.insert(sent, { port = port, request = request })
          return true
        end,
      })
    end

    before_each(function()
      sent, out, stdin_reads = {}, {}, 0
      env = { CLAUDINHO_PORT = "40123", CLAUDINHO_TOKEN = "tab-token" }
    end)

    it("exits 0 and does nothing for an unknown kind", function()
      assert.equals(0, run("other"))
      assert.equals(0, run(nil))

      assert.are.same({}, sent)
      assert.are.same({}, out)
      assert.equals(0, stdin_reads)
    end)

    it("posts the stdin of a hook with the tab token and prints nothing", function()
      assert.equals(0, run("hook"))

      assert.equals(1, #sent)
      assert.equals(40123, sent[1].port)
      assert.equals(relay.build_request("hook", '{"session_id":"s1"}', "tab-token"), sent[1].request)
      assert.are.same({}, out)
    end)

    it("prints an empty line for a statusline", function()
      assert.equals(0, run("statusline"))

      assert.are.same({ "\n" }, out)
      assert.equals("POST /claudinho/statusline HTTP/1.1", sent[1].request:match("^[^\r]+"))
    end)

    it("still prints the empty line when there is no port, and sends nothing", function()
      env.CLAUDINHO_PORT = nil

      assert.equals(0, run("statusline"))

      assert.are.same({ "\n" }, out)
      assert.are.same({}, sent)
    end)

    it("sends nothing for an invalid port", function()
      env.CLAUDINHO_PORT = "70000"

      assert.equals(0, run("hook"))

      assert.are.same({}, sent)
    end)

    it("exits 0 when the network step raises", function()
      local code = relay.main("hook", {
        getenv = function(name)
          return env[name]
        end,
        read_stdin = function()
          return "{}"
        end,
        send = function()
          error("boom")
        end,
      })

      assert.equals(0, code)
    end)
  end)
end)
