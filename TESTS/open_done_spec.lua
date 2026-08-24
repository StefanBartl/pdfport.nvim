-- TESTS/open_done_spec.lua — pdfport.open's `on_done` completion signal.
--
-- Opening is asynchronous end to end (every dispatcher path goes through
-- vim.schedule) and success is otherwise silent, so `on_done` is the only way
-- a caller can know an open finished. `util.batch` counts it to report an
-- accurate summary, which means the one property that really matters is that
-- it settles EXACTLY once on every path — a double-settle would inflate the
-- count, a missing one would hang the summary forever.
--
-- Runs LAST in run.lua: it calls setup() and performs real opens, which pulls
-- producer/backend modules into package.loaded. registry_spec and
-- producer_spec assert those are not loaded yet, so this has to come after
-- both -- placed earlier, it breaks producer_spec.

return function(H)
  local pdfport = require("pdfport")
  pdfport.setup({})

  ---Run one open and wait for it to settle.
  ---@param opts table
  ---@return integer calls, boolean|nil ok, string|nil err
  local function open_and_wait(opts)
    local calls, ok, err = 0, nil, nil
    pdfport.open(opts, function() end, function(o, e)
      calls = calls + 1
      ok, err = o, e
    end)
    vim.wait(3000, function()
      return calls > 0
    end)
    -- Keep waiting a little after the first call: a second one would arrive
    -- on a later tick, and "settled once" is exactly what is being asserted.
    vim.wait(200)
    return calls, ok, err
  end

  -- ------------------------------------------------------- failure settles

  local missing = vim.fn.tempname() .. "-pdfport-missing.pdf"
  local calls, ok, err = open_and_wait({ path = missing, mode = "buffer" })

  H.eq(calls, 1, "a failed open settles exactly once")
  H.eq(ok, false, "a failed open settles with ok = false")
  H.ok(type(err) == "string" and err ~= "", "a failed open reports an error string")

  -- ------------------------------------------------ an unknown mode settles
  --
  -- A different failure branch (no renderer registered) rather than the same
  -- one again, since each branch has its own `settle` call to get wrong.

  local unknown_calls, unknown_ok = open_and_wait({
    path = missing,
    mode = "definitely-not-a-registered-renderer",
  })
  H.eq(unknown_calls, 1, "an unknown mode settles exactly once")
  H.eq(unknown_ok, false, "an unknown mode settles with ok = false")

  -- ------------------------------------------------------- optional callback
  --
  -- Every existing caller passes two arguments; omitting `on_done` must stay
  -- a no-op rather than raising inside the dispatcher's settle helper.

  local ok_without = pcall(function()
    pdfport.open({ path = missing, mode = "buffer" }, function() end)
  end)
  H.ok(ok_without, "on_done is optional")
end
