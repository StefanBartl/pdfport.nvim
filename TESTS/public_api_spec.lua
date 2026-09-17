-- TESTS/public_api_spec.lua — `require("pdfport")` itself: the surface other
-- plugins call into.
--
-- This module is almost entirely argument checks and delegation, which is
-- exactly why it is worth pinning: the delegation is a contract several
-- sibling plugins depend on and cannot see change. `github_stats.nvim` calls
-- `pdfport.can_create("markdown")` and compares it to `true` with `==`, then
-- `pdfport.create{ text=…, from="markdown", output=…, on_conflict="overwrite",
-- __callback=… }` and reads `result.status`/`result.error`; hover.nvim and
-- images.nvim call `render_page`/`can_render_page_crop`. Each of those is
-- asserted here in the shape its caller actually uses.

return function(H)
  local pdfport = require("pdfport")
  local registry = require("pdfport.core.registry")

  -- ---------------------------------------------------------- the surface

  for _, name in ipairs({
    "setup",
    "open",
    "pick_open",
    "extract",
    "config",
    "render_page",
    "can_render_page_crop",
    "create",
    "can_create",
    "merge",
    "register_producer",
    "register_backend",
    "neotree",
    "nvim_tree",
    "netrw",
    "oil",
    "integrations",
    "telescope",
    "fzf",
  }) do
    H.eq(type(pdfport[name]), "function", ("pdfport exposes %s()"):format(name))
  end

  -- --------------------------------------------------------- argument guards

  -- Every entry point asserts rather than failing later inside the dispatcher,
  -- where the message would name an internal module instead of the call the
  -- user actually got wrong.
  H.falsy(pcall(pdfport.open, nil), "open() rejects a nil opts table")
  H.falsy(pcall(pdfport.open, { path = "" }), "open() rejects an empty path")
  H.falsy(pcall(pdfport.open, { path = 7 }), "open() rejects a non-string path")

  H.falsy(pcall(pdfport.pick_open, nil), "pick_open() rejects a nil path")
  H.falsy(pcall(pdfport.pick_open, ""), "pick_open() rejects an empty path")

  H.falsy(pcall(pdfport.extract, { path = "/a.pdf" }), "extract() requires a callback")
  H.falsy(
    pcall(pdfport.extract, { __callback = function() end }),
    "extract() requires a path as well"
  )

  H.falsy(pcall(pdfport.create, {}), "create() rejects a request with no input at all")
  H.falsy(pcall(pdfport.create, { inputs = {} }), "create() rejects an empty input list")
  H.falsy(pcall(pdfport.merge, { inputs = { "a.pdf" }, output = "o.pdf" }), "merge() needs two")
  H.falsy(pcall(pdfport.merge, { inputs = { "a.pdf", "b.pdf" } }), "merge() needs an output")

  H.falsy(pcall(pdfport.render_page, "", 1, {}, function() end), "render_page() needs a path")
  H.falsy(
    pcall(pdfport.render_page, "/a.pdf", "one", {}, function() end),
    "render_page() needs a numeric page"
  )
  H.falsy(pcall(pdfport.render_page, "/a.pdf", 1, {}, nil), "render_page() needs a callback")

  -- --------------------------------------------------------------- config()

  do
    local cfg = pdfport.config()
    H.eq(type(cfg), "table", "config() hands back the live configuration")
    H.eq(cfg.default_backend, "auto", "with the resolved values in it")

    -- A deep copy, not the module's own table: a consumer inspecting the
    -- config must not be able to reconfigure the plugin by mutating it.
    cfg.default_backend = "mutated"
    cfg.extract_opts.timeout_ms = 1
    local fresh = pdfport.config()
    H.eq(fresh.default_backend, "auto", "mutating the returned table changes nothing")
    H.eq(
      fresh.extract_opts.timeout_ms,
      30000,
      "including its nested tables, which a shallow copy would have shared"
    )
  end

  -- ----------------------------------------------- the render_page contract

  -- A capability question rather than a version number, because what a
  -- consumer needs to know is whether `opts.crop` is understood -- and a build
  -- that predates it ignores an unknown field in silence, which is the worst
  -- possible answer for the feature it exists for.
  H.eq(pdfport.can_render_page_crop(), true, "can_render_page_crop() answers a plain boolean true")

  do
    local calls = {}
    H.with_modules({
      ["pdfport.core.rasterize"] = {
        render_page = function(path, page, opts, cb)
          calls[#calls + 1] = { path = path, page = page, opts = opts }
          cb("/tmp/page.png", nil)
        end,
      },
    }, function()
      local got
      pdfport.render_page(
        "/docs/a.pdf",
        4,
        { dpi = 400, crop = { x = 1, y = 2, w = 3, h = 4 } },
        function(png)
          got = png
        end
      )
      H.eq(#calls, 1, "render_page delegates to core.rasterize")
      H.eq(calls[1].path, "/docs/a.pdf", "with the path")
      H.eq(calls[1].page, 4, "the page")
      H.eq(calls[1].opts.dpi, 400, "the dpi")
      H.eq(calls[1].opts.crop.w, 3, "and the crop window, passed through untouched")
      H.eq(got, "/tmp/page.png", "handing the caller back a real, caller-owned PNG path")

      -- `opts` is optional: hover.nvim's first call has no options at all.
      pdfport.render_page("/docs/a.pdf", 1, nil, function() end)
      H.eq(#calls, 2, "render_page works without an options table")
    end)
  end

  -- ------------------------------------------- the github_stats.nvim contract

  do
    registry.register_producer(H.fake_producer("api_md", true, { "markdown" }))
    require("pdfport.core.composer")._set_config({ create_chain = { markdown = { "api_md" } } })

    -- `== true`, not `if ... then`: github_stats.nvim compares the result to
    -- `true` literally, so a truthy non-boolean would read as "no producer".
    H.eq(pdfport.can_create("markdown"), true, "can_create() answers a plain boolean true")
    H.eq(pdfport.can_create("office"), false, "and a plain boolean false when nothing resolves")

    local out = vim.fn.stdpath("cache") .. "/pdfport_spec_api.pdf"
    pcall(vim.fn.delete, out)

    local got
    pdfport.create({
      text = "# Report\n\nbody\n",
      from = "markdown",
      output = out,
      on_conflict = "overwrite",
      __callback = function(result)
        got = result
      end,
    })
    vim.wait(2000, function()
      return got ~= nil
    end, 5)

    H.ok(got, "create() with text/from/output reaches the caller's __callback")
    H.eq(got.status, "ok", "reporting status = 'ok' on success")
    H.eq(got.path, out, "at exactly the output path that was requested")
    H.eq(got.error, nil, "with no error field")
    H.eq(got.producer, "api_md", "naming the producer that ran")

    -- The failure half of the same contract: a status other than "ok" and a
    -- human-readable `error`, which is what the caller shows the user.
    local failed
    pdfport.create({
      text = "# Report\n",
      from = "office",
      output = out,
      __callback = function(result)
        failed = result
      end,
    })
    vim.wait(2000, function()
      return failed ~= nil
    end, 5)
    H.eq(failed.status, "error", "an unresolvable kind reports status = 'error'")
    H.ok(type(failed.error) == "string" and failed.error ~= "", "with a non-empty error message")
    H.match(failed.error, "no available producer", "saying what could not be done")
  end

  -- -------------------------------------------------------------- merge()

  do
    local requests = {}
    H.with_modules({
      ["pdfport.core.composer"] = {
        create = function(opts, callback)
          requests[#requests + 1] = { opts = opts, callback = callback }
        end,
        can_create = function()
          return true
        end,
        _set_config = function() end,
      },
    }, function()
      pdfport.merge({ inputs = { "/a.pdf", "/b.pdf" }, output = "/out/m.pdf" })
      H.eq(#requests, 1, "merge() goes through the composer, like every other creation")
      -- The input kind is fixed to "pdf" rather than guessed, so the merge
      -- producers (qpdf/pdftk/ghostscript) are the chain that gets walked.
      H.eq(requests[1].opts.from, "pdf", "with the input kind pinned to pdf")
      H.eq_list(requests[1].opts.inputs, { "/a.pdf", "/b.pdf" }, "carrying every input")
      H.eq(requests[1].opts.output, "/out/m.pdf", "and the output")
      H.eq(type(requests[1].callback), "function", "and a default callback when none was given")
    end)
  end

  -- ----------------------------------------------- the default notifications

  -- create()/merge() without an `__callback` are the interactive form (that
  -- is what `:PdfPort create` uses), so they have to say what happened.
  do
    local notes = {}
    H.with_modules({
      ["lib.nvim.notify"] = {
        create = function()
          return {
            info = function(msg)
              notes[#notes + 1] = { level = "info", msg = msg }
            end,
            warn = function() end,
            error = function(msg)
              notes[#notes + 1] = { level = "error", msg = msg }
            end,
            debug = function() end,
          }
        end,
      },
      ["pdfport.util.notify"] = H.UNLOAD,
      ["pdfport"] = H.UNLOAD,
      ["pdfport.core.composer"] = {
        create = function(opts, callback)
          callback(opts.__spec_result)
        end,
        can_create = function()
          return true
        end,
        _set_config = function() end,
      },
    }, function()
      local api = require("pdfport")

      api.create({
        inputs = { "/a.png" },
        __spec_result = { status = "ok", path = "/out/a.pdf", producer = "img2pdf" },
      })
      H.eq(notes[1].level, "info", "a successful create() reports at info level")
      H.match(notes[1].msg, "/out/a%.pdf", "naming the file it made")
      H.match(notes[1].msg, "img2pdf", "and the producer that made it")

      api.create({
        inputs = { "/a.png" },
        __spec_result = { status = "error", error = "img2pdf exited 1" },
      })
      H.eq(notes[2].level, "error", "a failed create() reports at error level")
      H.match(notes[2].msg, "img2pdf exited 1", "with the producer's own message")

      api.create({ inputs = { "/a.png" }, __spec_result = { status = "error" } })
      H.match(notes[3].msg, "pdfport.create failed", "and a failure with no message still says so")

      api.merge({
        inputs = { "/a.pdf", "/b.pdf" },
        output = "/out/m.pdf",
        __spec_result = { status = "ok", path = "/out/m.pdf", producer = "qpdf" },
      })
      H.eq(notes[4].level, "info", "a successful merge() reports at info level")
      H.match(notes[4].msg, "merged 2 PDFs", "naming how many files went in")
      H.match(notes[4].msg, "qpdf", "and which producer merged them")

      api.merge({
        inputs = { "/a.pdf", "/b.pdf" },
        output = "/out/m.pdf",
        __spec_result = { status = "error" },
      })
      H.match(notes[5].msg, "pdfport.merge failed", "and a failed merge says so too")
    end)
  end

  -- ------------------------------------------------- registration delegation

  do
    pdfport.register_backend(H.fake_backend("api_registered_backend", true))
    H.ok(
      registry.has_backend("api_registered_backend"),
      "register_backend() puts a third-party backend in the registry"
    )
    pdfport.register_producer(H.fake_producer("api_registered_producer", true))
    H.ok(
      registry.has_producer("api_registered_producer"),
      "register_producer() does the same for a producer"
    )
    -- The guards belong to the registry, but a caller only ever sees them
    -- through these two functions.
    H.falsy(pcall(pdfport.register_backend, { id = "no_functions" }), "with the same input guards")
  end

  -- ------------------------------------------------- integration accessors

  do
    H.eq(
      pdfport.integrations(),
      require("pdfport.integrations"),
      "integrations() is the unified module"
    )
    H.eq(pdfport.neotree(), require("pdfport.integrations.neotree"), "neotree() is its integration")
    H.eq(pdfport.nvim_tree(), require("pdfport.integrations.nvim_tree"), "nvim_tree() likewise")
    H.eq(pdfport.netrw(), require("pdfport.integrations.netrw"), "netrw() likewise")
    H.eq(pdfport.oil(), require("pdfport.integrations.oil"), "oil() likewise")
    H.eq(pdfport.fzf(), require("pdfport.integrations.fzf"), "fzf() likewise")
    -- telescope() is the one accessor whose module requires telescope.nvim
    -- itself, and only inside previewer(); loading it must still work.
    H.eq(type(pdfport.telescope().filetype_hook), "function", "telescope() exposes its hook")
  end

  -- --------------------------------------------------------------- setup()

  do
    local shown = {}
    local function deps_stub()
      return {
        ["lib.nvim.deps"] = {
          show_once = function(name)
            shown[#shown + 1] = name
          end,
        },
      }
    end

    H.with_modules(deps_stub(), function()
      require("pdfport").setup({})
    end)
    H.eq_list(shown, { "pdfport.nvim" }, "setup() offers the one-time dependency popup by default")

    shown = {}
    H.with_modules(deps_stub(), function()
      require("pdfport").setup({ deps_popup = false })
    end)
    -- Checked here rather than left to lib.nvim's global vim.g toggle, so the
    -- plugin's own spec is a real place to turn this off.
    H.eq(#shown, 0, "and deps_popup = false turns it off from pdfport's own spec")

    -- setup() pushes the resolved config into all three coordinators.
    require("pdfport").setup({ default_backend = "marker", extract_opts = { timeout_ms = 111 } })
    H.eq(pdfport.config().default_backend, "marker", "setup() applies a user value")
    H.eq(pdfport.config().extract_opts.timeout_ms, 111, "deep-merged over the defaults")
    H.eq(pdfport.config().render_opts.mode, "buffer", "leaving the rest at their defaults")

    for _, mode in ipairs({ "buffer", "float", "system", "terminal" }) do
      H.ok(registry.get_renderer(mode), ("setup() registers the %q renderer"):format(mode))
    end

    -- auto_open_on_read is opt-in: off, no BufReadCmd exists at all.
    pcall(vim.api.nvim_del_augroup_by_name, "pdfport_bufreadcmd")
    require("pdfport").setup({})
    local ok_group = pcall(vim.api.nvim_get_autocmds, { group = "pdfport_bufreadcmd" })
    H.falsy(ok_group, "auto_open_on_read defaults to off, so no BufReadCmd is registered")

    require("pdfport").setup({ auto_open_on_read = true })
    local read_cmds = vim.api.nvim_get_autocmds({ group = "pdfport_bufreadcmd" })
    H.eq(#read_cmds, 1, "auto_open_on_read = true registers the BufReadCmd")
    H.eq(read_cmds[1].pattern, "*.pdf", "on *.pdf")
    pcall(vim.api.nvim_del_augroup_by_name, "pdfport_bufreadcmd")
  end

  -- Back to the defaults for whatever runs after this spec.
  require("pdfport").setup({})
end
