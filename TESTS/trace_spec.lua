-- TESTS/trace_spec.lua -- the debug trace of dispatch and create (util/trace.lua).
--
-- With `config.debug` on, every dispatch and every create leaves one line: the path, the chain that
-- was asked for, the backend or producer that answered, cache hit or miss, the status and the time.
-- Without `debug` nothing is reported and nothing is built (the trace takes a builder function that
-- is not called). The notifier is a double, so the lines can be read back.

return function(H)
  local registry = require("pdfport.core.registry")
  local resolver = require("pdfport.core.resolver")
  local dispatcher = require("pdfport.core.dispatcher")
  local composer = require("pdfport.core.composer")

  local pdf = H.tempfile("-trace-spec.pdf", { "%PDF-1.4 fake" })

  ---@type string[]
  local lines = {}
  local fake_notify = {
    create = function()
      return {
        info = function() end,
        warn = function() end,
        error = function() end,
        debug = function(msg, cfg)
          if cfg and cfg.debug then lines[#lines + 1] = msg end
        end,
      }
    end,
  }

  ---Run `fn` with the notifier replaced and util.trace re-required, so no earlier notifier is cached.
  ---@param fn fun()
  local function with_fake_notifier(fn)
    H.with_modules({ ["pdfport.util.notify"] = fake_notify, ["pdfport.util.trace"] = H.UNLOAD }, fn)
  end

  ---@param opts table
  ---@return table|nil
  local function dispatch(opts)
    local got
    dispatcher.dispatch(opts, function(result)
      got = result
    end)
    vim.wait(2000, function()
      return got ~= nil
    end, 5)
    return got
  end

  registry.register_backend(H.fake_backend("trace_backend", true))
  resolver._set_config({ fallback_chain = { "trace_backend" } })

  -- ── dispatch, cache miss ─────────────────────────────────────────────────────────
  with_fake_notifier(function()
    dispatcher._set_config({ debug = true, extract_opts = { cache = false } })
    lines = {}
    local got = dispatch({ path = pdf, backend_id = "trace_backend" })
    H.eq(got.status, "ok", "the dispatch itself is unchanged")
    H.eq(#lines, 1, "one trace line per dispatch")
    H.match(lines[1], "dispatch ", "it says what it is")
    H.match(lines[1], "trace%-spec%.pdf", "it names the file")
    H.match(lines[1], "trace_backend", "the answering backend and the chain are in it")
    H.match(lines[1], "cache miss", "a miss is reported as a miss")
    H.match(lines[1], ", ok,", "with the status of the result")
    H.match(lines[1], "%d+%.%d ms", "and the time")
  end)

  -- ── dispatch, cache hit ──────────────────────────────────────────────────────────
  with_fake_notifier(function()
    H.with_modules({
      ["pdfport.util.cache"] = {
        get = function()
          return { status = "ok", text = "cached", format = "plain", backend = "trace_backend" }
        end,
        set = function() end,
      },
    }, function()
      dispatcher._set_config({ debug = true, extract_opts = { cache = true } })
      lines = {}
      dispatch({ path = pdf, backend_id = "trace_backend" })
      H.eq(#lines, 1, "a cache hit leaves one line too")
      H.match(lines[1], "cache hit", "reported as a hit")
    end)
  end)

  -- ── dispatch, debug off ──────────────────────────────────────────────────────────
  with_fake_notifier(function()
    dispatcher._set_config({ debug = false, extract_opts = { cache = false } })
    lines = {}
    local built = false
    local trace = require("pdfport.util.trace")
    trace.emit({ debug = false }, function()
      built = true
      return "x"
    end)
    H.falsy(built, "without debug the line is not even built")
    dispatch({ path = pdf, backend_id = "trace_backend" })
    H.eq(#lines, 0, "and a dispatch reports nothing")
  end)

  -- ── create ───────────────────────────────────────────────────────────────────────
  registry.register_producer(H.fake_producer("trace_producer", true))
  composer._set_config({ create_chain = { image = { "trace_producer" } } })
  local img = H.tempfile("-trace-spec.png", { "png" })

  ---@param opts table
  ---@return table|nil
  local function create(opts)
    local got
    composer.create(opts, function(result)
      got = result
    end)
    vim.wait(2000, function()
      return got ~= nil
    end, 5)
    return got
  end

  with_fake_notifier(function()
    composer._set_config({ debug = true, create_chain = { image = { "trace_producer" } } })
    lines = {}
    local out = vim.fn.tempname() .. ".pdf"
    local got = create({ inputs = { img }, from = "image", output = out })
    H.eq(got.status, "ok", "the create itself is unchanged")
    H.eq(#lines, 1, "one trace line per create")
    H.match(lines[1], "create ", "it says what it is")
    H.match(lines[1], "kind image", "with the input kind")
    H.match(lines[1], "trace_producer", "and the producer chain and the answering producer")
    H.match(lines[1], "%d+%.%d ms", "and the time")
    pcall(vim.fn.delete, out)

    composer._set_config({ debug = false, create_chain = { image = { "trace_producer" } } })
    lines = {}
    out = vim.fn.tempname() .. ".pdf"
    create({ inputs = { img }, from = "image", output = out })
    H.eq(#lines, 0, "without debug a create reports nothing")
    pcall(vim.fn.delete, out)
  end)

  dispatcher._set_config({})
  composer._set_config({})
end
