-- TESTS/dispatcher_spec.lua — core/dispatcher's dispatch paths, and
-- core/rasterize's process handling.
--
-- `open_done_spec.lua` already pins the one property `on_done` exists for
-- (settling exactly once). This covers the branching in front of it: which
-- requests never reach a backend at all (the two renderer-only modes, an
-- invalid path), what the cache is consulted with and when it is written, what
-- happens when a backend raises, and how the progress indicator is opened and
-- closed around all of it.
--
-- Every backend here is a fake, and `pdfport.util.cache` and
-- `lib.nvim.progress` are replaced in `package.loaded`, so nothing is spawned
-- and nothing is written to the user's cache.

return function(H)
  local registry = require("pdfport.core.registry")
  local resolver = require("pdfport.core.resolver")
  local dispatcher = require("pdfport.core.dispatcher")

  -- A real file on disk: validate_path stats it, so a fictional path would
  -- only ever exercise the not-found branch.
  local pdf = vim.fn.tempname() .. "-dispatch-spec.pdf"
  vim.fn.writefile({ "%PDF-1.4 fake" }, pdf)

  ---Run dispatch and wait for the single result it schedules.
  ---@param opts table
  ---@return table|nil result
  ---@return integer calls
  local function dispatch(opts)
    local got, calls = nil, 0
    dispatcher.dispatch(opts, function(result)
      calls = calls + 1
      got = result
    end)
    vim.wait(2000, function()
      return calls > 0
    end, 5)
    return got, calls
  end

  -- ------------------------------------------------------ argument guards

  H.falsy(pcall(dispatcher.dispatch, nil, function() end), "dispatch rejects a nil opts table")
  H.falsy(pcall(dispatcher.dispatch, { path = 42 }, function() end), "and a non-string path")
  H.falsy(pcall(dispatcher.dispatch, { path = pdf }, nil), "and a missing callback")

  -- ------------------------------------------------------ path validation

  do
    local missing = vim.fn.tempname() .. "-not-there.pdf"
    local got = dispatch({ path = missing })
    H.eq(got.status, "error", "a path that does not exist is an error")
    H.match(got.error, "file not found", "saying so")
    H.eq(got.backend, "none", "with no backend to blame")

    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    local on_dir = dispatch({ path = dir })
    H.eq(on_dir.status, "error", "a directory is not a PDF")
    H.match(on_dir.error, "not a regular file", "and says which kind of wrong it is")
    pcall(vim.fn.delete, dir, "rf")

    local empty = dispatch({ path = "" })
    H.eq(empty.status, "error", "an empty path is rejected before it is ever stat'ed")
    H.match(empty.error, "non%-empty string", "with the reason")
  end

  -- ------------------------------------------- renderer-only modes short-circuit

  -- `system` and `terminal` never extract anything: handing a PDF to the OS
  -- viewer or rasterizing it does not need its text, and running a backend
  -- first would cost minutes on an OCR chain for nothing.
  do
    local saved_system = registry.get_renderer("system")
    local saved_terminal = registry.get_renderer("terminal")

    local extracted = false
    registry.register_backend(H.fake_backend("disp_watch", true, function()
      extracted = true
    end))
    resolver._set_config({ fallback_chain = { "disp_watch" } })

    local seen
    registry.register_renderer("system", function(result, opts)
      seen = { result = result, opts = opts }
    end)
    dispatch({ path = pdf, mode = "system" })
    H.ok(seen, "mode=system reaches the system renderer")
    H.eq(seen.result.backend, "system", "with a synthetic result attributed to `system`")
    H.eq(seen.result.status, "ok", "reported as ok")
    H.eq(seen.result.text, nil, "and carrying no text, because none was extracted")
    H.eq(seen.opts.path, pdf, "the renderer gets the original opts, including the path")
    H.falsy(extracted, "and no backend ran")

    seen = nil
    registry.register_renderer("terminal", function(result, opts)
      seen = { result = result, opts = opts }
    end)
    dispatch({ path = pdf, mode = "terminal" })
    H.ok(seen, "mode=terminal reaches the terminal renderer")
    -- The terminal renderer rasterizes the file itself, so the path travels
    -- in `text` -- that is the field its render(result, opts) contract reads.
    H.eq(seen.result.text, pdf, "with the PDF path handed over in the result's text field")
    H.eq(seen.result.backend, "terminal", "attributed to `terminal`")
    H.falsy(extracted, "still without running a backend")

    -- Unregistering is not part of the registry's API, so the missing-renderer
    -- branch is reached by pointing the mode at a registry that never had it.
    registry.register_renderer("system", saved_system or function() end)
    registry.register_renderer("terminal", saved_terminal or function() end)
  end

  -- ------------------------------------------------------ backend resolution

  do
    -- An explicit backend_id, not "auto": under auto the resolver appends
    -- every registered id after the configured chain, and this spec shares a
    -- registry with several deliberately-available fakes.
    resolver._set_config({ fallback_chain = { "disp_nothing_available" } })
    registry.register_backend(H.fake_backend("disp_nothing_available", false))
    local got = dispatch({ path = pdf, backend_id = "disp_nothing_available" })
    H.eq(got.status, "error", "no available backend is an error result")
    H.match(got.error, "no available backend", "saying so")
    H.match(got.error, "disp_nothing_available", "and naming what was tried")
  end

  -- ----------------------------------------------------- extract options

  do
    local seen_opts
    registry.register_backend({
      id = "disp_opts",
      available = function()
        return true
      end,
      extract = function(path, opts)
        seen_opts = opts
        return { status = "ok", text = "t", format = "plain", backend = "disp_opts" }
      end,
    })
    resolver._set_config({ fallback_chain = { "disp_opts" } })
    dispatcher._set_config({
      extract_opts = { timeout_ms = 4321, cache = false, max_pages = 2 },
    })

    dispatch({ path = pdf })
    H.eq(seen_opts.timeout_ms, 4321, "config.extract_opts reaches the backend")
    H.eq(seen_opts.max_pages, 2, "including a configured page cap")

    -- Per-call values win over the configured ones, and a per-call nil does
    -- not blank out a configured value.
    dispatch({ path = pdf, timeout_ms = 99, pages = { 4, 5 }, prompt = "p", model = "m" })
    H.eq(seen_opts.timeout_ms, 99, "a per-call timeout overrides the configured one")
    H.eq_list(seen_opts.pages, { 4, 5 }, "a per-call page list is passed through")
    H.eq(seen_opts.prompt, "p", "as is a prompt")
    H.eq(seen_opts.model, "m", "and a model")
    H.eq(seen_opts.max_pages, 2, "while the configured cap survives a call that omits it")
    H.eq(type(seen_opts.__callback), "function", "and the backend is given its callback")
  end

  -- --------------------------------------------------------------- caching

  do
    local reads, writes = {}, {}
    local stored = nil
    H.with_modules({
      ["pdfport.util.cache"] = {
        get = function(path, backend_id, variant)
          reads[#reads + 1] = { path = path, backend = backend_id, variant = variant }
          return stored
        end,
        set = function(path, backend_id, variant, result)
          writes[#writes + 1] =
            { path = path, backend = backend_id, variant = variant, result = result }
        end,
      },
    }, function()
      local ran = 0
      registry.register_backend({
        id = "disp_cached",
        available = function()
          return true
        end,
        extract = function()
          ran = ran + 1
          return { status = "ok", text = "fresh", format = "plain", backend = "disp_cached" }
        end,
      })
      resolver._set_config({ fallback_chain = { "disp_cached" } })
      dispatcher._set_config({ extract_opts = { cache = true } })

      local miss = dispatch({ path = pdf, max_pages = 3 })
      H.eq(#reads, 1, "an enabled cache is consulted exactly once per dispatch")
      H.eq(reads[1].path, pdf, "keyed on the file")
      H.eq(reads[1].backend, "disp_cached", "the backend that resolved")
      H.eq(reads[1].variant, "3", "and the page variant")
      H.eq(ran, 1, "a miss runs the backend")
      H.eq(miss.text, "fresh", "and returns its result")
      H.eq(#writes, 1, "which is written back to the cache")
      H.eq(writes[1].result.text, "fresh", "verbatim")

      stored = { status = "ok", text = "from cache", format = "plain", backend = "disp_cached" }
      local hit = dispatch({ path = pdf, max_pages = 3 })
      H.eq(hit.text, "from cache", "a hit is returned without running anything")
      H.eq(ran, 1, "the backend was not invoked a second time")
      H.eq(#writes, 1, "and a hit is not written back again")

      -- `cache = false` must not even look: consulting a cache the caller
      -- disabled is how a stale answer reaches a caller who asked for a fresh one.
      dispatcher._set_config({ extract_opts = { cache = false } })
      local uncached = dispatch({ path = pdf, max_pages = 3 })
      H.eq(#reads, 2, "a disabled cache is not consulted")
      H.eq(uncached.text, "fresh", "the backend runs instead")
      H.eq(ran, 2, "every time")
      H.eq(#writes, 1, "and nothing is written")

      -- Only successful extractions are cached.
      dispatcher._set_config({ extract_opts = { cache = true } })
      stored = nil
      registry.register_backend({
        id = "disp_cached",
        available = function()
          return true
        end,
        extract = function()
          return { status = "error", error = "boom", format = "plain", backend = "disp_cached" }
        end,
      })
      dispatch({ path = pdf })
      H.eq(#writes, 1, "a failed extraction is never cached")
    end)
  end

  -- ------------------------------------------------------- a backend raises

  do
    registry.register_backend({
      id = "disp_thrower",
      available = function()
        return true
      end,
      extract = function()
        error("backend exploded")
      end,
    })
    resolver._set_config({ fallback_chain = { "disp_thrower" } })
    dispatcher._set_config({ extract_opts = { cache = false } })

    local got, calls = dispatch({ path = pdf })
    H.eq(calls, 1, "a raising backend still settles exactly once")
    H.eq(got.status, "error", "as an error result rather than a propagated error")
    H.eq(got.backend, "disp_thrower", "attributed to the backend that raised")
    H.match(got.error, "threw", "saying it threw")
    H.match(got.error, "backend exploded", "and carrying the message")
  end

  -- An asynchronous backend answers through __callback and returns nil; the
  -- dispatcher must not then settle a second time on the nil return.
  do
    registry.register_backend({
      id = "disp_async",
      available = function()
        return true
      end,
      extract = function(_, opts)
        vim.schedule(function()
          opts.__callback({
            status = "ok",
            text = "async text",
            format = "plain",
            backend = "disp_async",
          })
        end)
        return nil
      end,
    })
    resolver._set_config({ fallback_chain = { "disp_async" } })

    local got, calls = dispatch({ path = pdf })
    vim.wait(200)
    H.eq(calls, 1, "an asynchronous backend settles exactly once")
    H.eq(got.text, "async text", "with the result it produced")
  end

  -- -------------------------------------------------------------- progress

  -- The indicator lives in the dispatcher rather than in each backend because
  -- the dispatcher is the one place every extraction passes through. What
  -- matters is that it is opened only past the cache check (a hit has nothing
  -- to report on) and closed exactly once, on success and failure alike.
  do
    local handles = {}
    local function fake_progress()
      return {
        create = function(opts)
          local handle = { opts = opts, updates = {}, finished = {} }
          function handle:update(u)
            self.updates[#self.updates + 1] = u
          end
          function handle:finish(msg)
            self.finished[#self.finished + 1] = msg
          end
          handles[#handles + 1] = handle
          return handle
        end,
      }
    end

    H.with_modules({
      ["lib.nvim.progress"] = fake_progress(),
      ["pdfport.core.dispatcher"] = H.UNLOAD,
      ["pdfport.util.cache"] = {
        get = function()
          return nil
        end,
        set = function() end,
      },
    }, function()
      local d = require("pdfport.core.dispatcher")
      d._set_config({ progress_style = "fidget", extract_opts = { cache = true } })

      registry.register_backend({
        id = "disp_progress",
        available = function()
          return true
        end,
        extract = function()
          return { status = "ok", text = "x", format = "plain", backend = "disp_progress" }
        end,
      })
      resolver._set_config({ fallback_chain = { "disp_progress" } })

      local calls = 0
      d.dispatch({ path = pdf }, function()
        calls = calls + 1
      end)
      vim.wait(1000, function()
        return calls > 0
      end, 5)

      H.eq(#handles, 1, "one indicator per extraction")
      H.eq(handles[1].opts.style, "fidget", "using the configured progress style")
      H.eq(handles[1].opts.title, "[pdfport]", "under the plugin's own title")
      H.eq(#handles[1].updates, 1, "updated once with what is running")
      H.match(handles[1].updates[1].text, "^disp_progress: ", "naming the backend")
      H.match(handles[1].updates[1].text, "dispatch%-spec%.pdf$", "and the file's basename only")
      H.eq_list(handles[1].finished, { "disp_progress done" }, "and finished exactly once, as done")

      registry.register_backend({
        id = "disp_progress",
        available = function()
          return true
        end,
        extract = function()
          return { status = "error", error = "nope", format = "plain", backend = "disp_progress" }
        end,
      })
      calls = 0
      d.dispatch({ path = pdf }, function()
        calls = calls + 1
      end)
      vim.wait(1000, function()
        return calls > 0
      end, 5)
      H.eq(#handles, 2, "a failing extraction also gets an indicator")
      H.eq_list(handles[2].finished, { "disp_progress failed" }, "which is finished as failed")

      -- A cache hit returns before the indicator is created: there is nothing
      -- to show progress on, and a flashed-and-closed indicator is noise.
      H.with_modules({
        ["pdfport.util.cache"] = {
          get = function()
            return { status = "ok", text = "cached", format = "plain", backend = "disp_progress" }
          end,
          set = function() end,
        },
      }, function()
        calls = 0
        d.dispatch({ path = pdf }, function()
          calls = calls + 1
        end)
        vim.wait(1000, function()
          return calls > 0
        end, 5)
        H.eq(#handles, 2, "a cache hit creates no indicator at all")
      end)
    end)
  end

  -- ---------------------------------------------------------- open() wiring

  do
    dispatcher._set_config({
      extract_opts = { cache = false },
      render_opts = { mode = "spec_default_mode", split = "vsplit", focus = false },
    })
    registry.register_backend(H.fake_backend("disp_open", true))
    resolver._set_config({ fallback_chain = { "disp_open" } })

    local rendered
    registry.register_renderer("spec_render_mode", function(result, opts)
      rendered = { result = result, opts = opts }
    end)

    -- The configured default mode is used when the caller names none. Here
    -- that is deliberately a mode with no renderer, to pin that the failure
    -- names the mode rather than falling back to something that does exist.
    local errs = {}
    dispatcher.open({ path = pdf }, function(msg)
      errs[#errs + 1] = msg
    end)
    vim.wait(1000, function()
      return #errs > 0
    end, 5)
    H.match(
      errs[1],
      "renderer 'spec_default_mode' not registered",
      "the configured render_opts.mode is used when the caller names none"
    )

    rendered = nil
    local ok_flag, err_flag
    dispatcher.open({ path = pdf, mode = "spec_render_mode", focus = true }, nil, function(o, e)
      ok_flag, err_flag = o, e
    end)
    vim.wait(1000, function()
      return rendered ~= nil
    end, 5)
    H.ok(rendered, "an explicit mode overrides the configured default")
    H.eq(ok_flag, true, "a successful render settles with ok = true")
    H.eq(err_flag, nil, "and no error")
    H.eq(rendered.opts.split, "vsplit", "render_opts from config reach the renderer")
    H.eq(rendered.opts.focus, true, "with per-call values winning over them")
    H.eq(rendered.opts.path, pdf, "and the path carried through")
    H.eq(rendered.result.backend, "disp_open", "the renderer gets the backend's own result")

    -- A renderer that raises is a failure of the open, not of Neovim.
    registry.register_renderer("spec_render_boom", function()
      error("renderer exploded")
    end)
    local boom_errs, settle_calls = {}, 0
    dispatcher.open({ path = pdf, mode = "spec_render_boom" }, function(msg)
      boom_errs[#boom_errs + 1] = msg
    end, function()
      settle_calls = settle_calls + 1
    end)
    vim.wait(1000, function()
      return #boom_errs > 0
    end, 5)
    vim.wait(100)
    H.eq(#boom_errs, 1, "a raising renderer reports once")
    H.eq(settle_calls, 1, "and settles once")
    H.match(boom_errs[1], "renderer 'spec_render_boom' failed", "naming the mode")
    H.match(boom_errs[1], "renderer exploded", "and carrying the error")

    -- on_error is optional: without one the dispatcher stays silent rather
    -- than notifying, which is what keeps it free of any particular UI.
    local ok_silent = pcall(function()
      dispatcher.open({ path = pdf, mode = "spec_render_boom" })
    end)
    H.ok(ok_silent, "open() without an on_error handler does not raise")
    vim.wait(100)
  end

  -- -------------------------------------------------------------- rasterize

  do
    H.with_modules({
      ["pdfport.platform"] = H.fake_platform({}),
      ["pdfport.core.rasterize"] = H.UNLOAD,
    }, function()
      local r = require("pdfport.core.rasterize")
      local png, err
      r.render_page(pdf, 1, {}, function(p, e)
        png, err = p, e
      end)
      H.eq(png, nil, "without pdftoppm no PNG comes back")
      H.match(err, "pdftoppm not found", "and the error says which tool to install")
      H.match(err, "poppler", "naming the package it lives in")
    end)

    -- The spawn itself: uv.spawn/uv.new_pipe are replaced on the table the
    -- module captured, so the argv and the base-path handling are assertable
    -- without poppler. `M.args` itself has its own spec.
    local uv = vim.uv or vim.loop
    local saved_spawn, saved_pipe = uv.spawn, uv.new_pipe
    local spawned
    uv.new_pipe = function()
      return {
        is_closing = function()
          return false
        end,
        close = function() end,
        read_start = function() end,
      }
    end

    local function run(page, opts, exit_code)
      uv.spawn = function(cmd, spawn_opts, on_exit)
        spawned = { cmd = cmd, args = spawn_opts.args }
        vim.schedule(function()
          on_exit(exit_code, 0)
        end)
        return { close = function() end }
      end
      local done, png, err = false, nil, nil
      H.with_modules({
        ["pdfport.platform"] = H.fake_platform({ pdftoppm = true }),
        ["pdfport.core.rasterize"] = H.UNLOAD,
      }, function()
        require("pdfport.core.rasterize").render_page(pdf, page, opts, function(p, e)
          done, png, err = true, p, e
        end)
        vim.wait(1000, function()
          return done
        end, 5)
      end)
      return png, err
    end

    local out_base = vim.fn.tempname() .. "-page"
    vim.fn.writefile({ "png bytes" }, out_base .. ".png")
    local png = run(3, { output_path = out_base .. ".png", dpi = 400 }, 0)
    H.eq(spawned.cmd, "pdftoppm", "rasterizing spawns pdftoppm")
    H.eq(spawned.args[H.index_of(spawned.args, "-r") + 1], "400", "at the requested dpi")
    H.eq(spawned.args[H.index_of(spawned.args, "-f") + 1], "3", "for the requested page")
    -- -singlefile makes pdftoppm append ".png" itself, so the base handed to
    -- it must not already carry the extension or the file lands as ".png.png".
    H.eq(spawned.args[#spawned.args], out_base, "with the .png stripped off the output base")
    H.eq(png, out_base .. ".png", "and the caller gets the path including the extension back")

    local _, exit_err = run(1, { output_path = out_base .. ".png" }, 4)
    H.match(exit_err, "pdftoppm exited 4", "a non-zero exit is reported with its code")

    pcall(vim.fn.delete, out_base .. ".png")
    local _, missing_err = run(1, { output_path = out_base .. ".png" }, 0)
    H.match(
      missing_err,
      "pdftoppm exited 0",
      "a clean exit that produced no PNG is reported too, not silently handed back"
    )

    uv.spawn, uv.new_pipe = saved_spawn, saved_pipe
  end

  pcall(vim.fn.delete, pdf)

  -- Put the plugin back the way the remaining specs expect to find it.
  require("pdfport").setup({})
end
