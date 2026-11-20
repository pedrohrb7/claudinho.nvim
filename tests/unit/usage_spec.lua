--- The usage value keeps one promise: the account's limits are shown from the last value that arrived, and a window
--- disappears (with a redraw) once its reset time passed. The timer and the wall clock are replaced in the tests.
require("tests.busted_setup")

describe("The usage value", function()
  local usage, now, timers, refreshes, saved_window, saved_schedule

  local function fake_timer()
    local t = { closed = false, stopped = false }
    function t:start(_, _, cb)
      self.cb = cb
      self.interval = _
    end
    function t:stop()
      self.stopped = true
    end
    function t:is_closing()
      return self.closed
    end
    function t:close()
      self.closed = true
    end
    timers[#timers + 1] = t
    return t
  end

  before_each(function()
    saved_window = package.loaded["claudinho.ui.window"]
    saved_schedule = vim.schedule
    refreshes = 0
    timers = {}
    now = 1000
    package.loaded["claudinho.ui.window"] = {
      refresh = function()
        refreshes = refreshes + 1
      end,
    }
    vim.schedule = function(fn)
      fn()
    end
    package.loaded["claudinho.usage"] = nil
    usage = require("claudinho.usage")
    usage.now = function()
      return now
    end
    usage.new_timer = fake_timer
  end)

  after_each(function()
    usage.reset()
    package.loaded["claudinho.usage"] = nil
    package.loaded["claudinho.ui.window"] = saved_window
    vim.schedule = saved_schedule
  end)

  it("replaces the whole value and tells whether it changed", function()
    assert.is_true(usage.update({ five_hour = { used = 10 }, seven_day = { used = 20 } }))
    assert.is_false(usage.update({ five_hour = { used = 10 }, seven_day = { used = 20 } }))
    assert.is_true(usage.update({ five_hour = { used = 11 }, seven_day = { used = 20 } }))
  end)

  it("drops a window missing from the new value", function()
    usage.update({ five_hour = { used = 10 }, seven_day = { used = 20 } })
    assert.is_true(usage.update({ five_hour = { used = 10 } }))
    assert.is_nil(usage.windows(now).seven_day)
    assert.equals(10, usage.windows(now).five_hour.used)
  end)

  it("keeps the value when the update has none", function()
    usage.update({ five_hour = { used = 10 } })
    assert.is_false(usage.update(nil))
    assert.equals(10, usage.windows(now).five_hour.used)
  end)

  it("treats an empty value as a change that clears the windows", function()
    usage.update({ five_hour = { used = 10 } })
    assert.is_true(usage.update({}))
    assert.same({}, usage.windows(now))
  end)

  it("filters a window by its reset time: before, at and after", function()
    usage.update({ five_hour = { used = 10, resets_at = 1100 }, seven_day = { used = 20 } })
    assert.is_not_nil(usage.windows(1099.9).five_hour)
    assert.is_nil(usage.windows(1100).five_hour)
    assert.is_nil(usage.windows(1101).five_hour)
  end)

  it("keeps a window without resets_at", function()
    usage.update({ seven_day = { used = 20 } })
    assert.equals(20, usage.windows(1e12).seven_day.used)
  end)

  it("does not change the value without an update", function()
    usage.update({ five_hour = { used = 10, resets_at = 1100 } })
    now = 5000
    -- windows() filters but does not mutate
    assert.is_nil(usage.windows(now).five_hour)
    assert.equals(10, usage.state.value.five_hour.used)
  end)

  it("arms the clock when a reset is in the future", function()
    usage.update({ five_hour = { used = 10, resets_at = 1100 } })
    assert.equals(1, #timers)
    assert.equals(usage.TICK_MS, timers[1].interval)
    usage.update({ five_hour = { used = 11, resets_at = 1100 } })
    assert.equals(1, #timers)
  end)

  it("does not arm the clock without a future reset", function()
    usage.update({ five_hour = { used = 10 } })
    usage.update({ seven_day = { used = 10, resets_at = 999 } })
    assert.equals(0, #timers)
  end)

  it("stops the clock when an update leaves no future reset", function()
    usage.update({ five_hour = { used = 10, resets_at = 1100 } })
    usage.update({ five_hour = { used = 10 } })
    assert.is_true(timers[1].closed)
    assert.is_nil(usage.state.timer)
  end)

  it("redraws only when a window expires, and stops after the last one", function()
    usage.update({ five_hour = { used = 10, resets_at = 1100 }, seven_day = { used = 20, resets_at = 1200 } })
    timers[1].cb()
    assert.equals(0, refreshes)
    now = 1100
    timers[1].cb()
    assert.equals(1, refreshes)
    assert.is_nil(usage.state.value.five_hour)
    assert.is_false(timers[1].closed)
    now = 1200.5
    timers[1].cb()
    assert.equals(2, refreshes)
    assert.is_nil(usage.state.value.seven_day)
    assert.is_true(timers[1].closed)
    assert.is_nil(usage.state.timer)
  end)

  it("stop() stops the clock without erasing the value", function()
    usage.update({ five_hour = { used = 10, resets_at = 1100 } })
    usage.stop()
    assert.is_true(timers[1].closed)
    assert.equals(10, usage.state.value.five_hour.used)
  end)

  it("arms the clock again after stop() on the next update", function()
    usage.update({ five_hour = { used = 10, resets_at = 1100 } })
    usage.stop()
    usage.update({ five_hour = { used = 12, resets_at = 1100 } })
    assert.equals(2, #timers)
  end)
end)
