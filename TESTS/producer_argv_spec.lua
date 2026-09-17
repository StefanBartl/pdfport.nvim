-- TESTS/producer_argv_spec.lua — the command line every producer would run.
--
-- This plugin's whole write side is nine wrappers around an external tool,
-- and the part of each one that can actually be wrong is the argv: the order
-- of input and output, a flag that has to be a complete set, a separator that
-- has to be there (`qpdf ... --`), a path that has to be turned into a URL
-- (chromium), an output filename the tool refuses to take at all (soffice).
-- None of that needs the tool installed, and running the tool would not check
-- it any better than reading the list back does.
--
-- So: `lib.nvim.cross.uv.spawn_capture` is replaced in `package.loaded` before
-- the producer module is required (see H.with_modules on why it has to happen
-- in that order), and the spec asserts on the recorded argv plus the four
-- callback branches every producer has — clean exit, non-zero exit with
-- stderr, timeout, and the tool not being installed at all.
--
-- Nothing here spawns a process.

return function(H)
  local SPAWN = "lib.nvim.cross.uv.spawn_capture"

  ---Require `module` with `spawn_capture` and `pdfport.platform` replaced.
  ---@param module string
  ---@param present table<string, boolean>  what `platform.has` reports installed
  ---@param fn fun(producer: table, rec: table)
  ---@param extra table|nil  further `package.loaded` replacements
  ---@return nil
  local function with_producer(module, present, fn, extra)
    local rec = H.spawn_recorder()
    local replacements = {
      [SPAWN] = rec.fn,
      ["pdfport.platform"] = H.fake_platform(present),
      [module] = H.UNLOAD,
    }
    for k, v in pairs(extra or {}) do
      replacements[k] = v
    end
    H.with_modules(replacements, function()
      fn(require(module), rec)
    end)
  end

  ---Run `create` and hand back the single result its callback received.
  ---@param producer table
  ---@param req table
  ---@return table|nil result_via_callback
  ---@return integer calls
  local function create(producer, req)
    local got, calls = nil, 0
    req.__callback = function(result)
      calls = calls + 1
      got = result
    end
    local returned = producer.create(req)
    H.eq(returned, nil, "create() answers through __callback, never a return value")
    return got, calls
  end

  ---The three failure branches every producer shares, asserted in one place
  ---rather than nine times over: a non-zero exit names the code and carries
  ---the tool's own stderr, and a timeout says so with the budget it was given.
  ---@param module string
  ---@param present table<string, boolean>
  ---@param id string
  ---@param req_fn fun(): table  a fresh request per branch
  ---@param extra table|nil
  ---@return nil
  local function assert_failure_branches(module, present, id, req_fn, extra)
    with_producer(module, present, function(producer, rec)
      rec.result = H.spawn_result({ ok = false, code = 3, stderr = "boom from " .. id })
      local got = create(producer, req_fn())
      H.eq(got.status, "error", id .. ": a non-zero exit is an error result")
      H.eq(got.path, nil, id .. ": a failed run reports no output path")
      H.eq(got.producer, id, id .. ": the error names the producer")
      H.match(got.error, "3", id .. ": the exit code is in the message")
      H.match(got.error, "boom from " .. id, id .. ": so is the tool's stderr")
    end, extra)

    with_producer(module, present, function(producer, rec)
      rec.result = H.spawn_result({ ok = false, code = -1, timed_out = true })
      local req = req_fn()
      req.timeout_ms = 1234
      local got = create(producer, req)
      H.eq(got.status, "error", id .. ": a timeout is an error result")
      H.match(got.error, "timed out", id .. ": and says it timed out")
      H.match(got.error, "1234", id .. ": naming the budget it was given")
    end, extra)
  end

  -- ------------------------------------------------------------- img2pdf

  with_producer("pdfport.producers.img2pdf", { img2pdf = true }, function(producer, rec)
    H.ok(producer.available(), "img2pdf is available when the binary is on PATH")
    H.eq_list(producer.accepts, { "image" }, "img2pdf accepts images")
    H.ok(producer.capabilities.lossless, "img2pdf declares itself lossless")

    local got, calls = create(producer, {
      inputs = { "/pics/a.png", "/pics/b.png" },
      output = "/out/album.pdf",
    })
    H.eq(calls, 1, "img2pdf settles exactly once")

    local argv = H.last_argv(rec)
    H.eq_list(
      argv,
      { "img2pdf", "--output", "/out/album.pdf", "/pics/a.png", "/pics/b.png" },
      "img2pdf: the output is named by --output, inputs follow in order"
    )
    H.eq(got.status, "ok", "a clean exit is an ok result")
    H.eq(got.path, "/out/album.pdf", "reporting the output path it was asked for")
    H.eq(got.pages, 2, "and one page per input image")
    H.eq(rec.calls[1].opts.timeout_ms, 60000, "the default timeout is 60 s")
  end)

  with_producer("pdfport.producers.img2pdf", {}, function(producer)
    H.falsy(producer.available(), "img2pdf is unavailable when the binary is missing")
  end)

  assert_failure_branches("pdfport.producers.img2pdf", { img2pdf = true }, "img2pdf", function()
    return { inputs = { "/pics/a.png" }, output = "/out/a.pdf" }
  end)

  -- -------------------------------------------------------------- magick

  with_producer("pdfport.producers.magick", { magick = true }, function(producer, rec)
    H.ok(producer.available(), "magick is available when the binary is on PATH")

    local got = create(producer, {
      inputs = { "/pics/a.png", "/pics/b.png" },
      output = "/out/album.pdf",
      timeout_ms = 9000,
    })

    H.eq_list(
      H.last_argv(rec),
      { "magick", "/pics/a.png", "/pics/b.png", "/out/album.pdf" },
      "magick: inputs first, the output is the LAST argument (its CLI has no -o)"
    )
    -- `magick`, never `convert`: convert.exe collides with Windows' own
    -- convert on PATH, which is why the module documents the choice.
    H.eq(H.last_argv(rec)[1], "magick", "magick never shells out to `convert`")
    H.eq(got.pages, 2, "magick reports one page per input image")
    H.eq(rec.calls[1].opts.timeout_ms, 9000, "an explicit timeout is passed through")
  end)

  assert_failure_branches("pdfport.producers.magick", { magick = true }, "magick", function()
    return { inputs = { "/pics/a.png" }, output = "/out/a.pdf" }
  end)

  -- -------------------------------------------------------------- pandoc

  -- pandoc is a converter, not a PDF engine: without one behind it the
  -- producer must report itself unavailable rather than spawn and fail.
  with_producer("pdfport.producers.pandoc", { pandoc = true }, function(producer, rec)
    H.falsy(producer.available(), "pandoc alone is not available -- it needs a PDF engine")

    local got = create(producer, { inputs = { "/docs/a.md" }, output = "/out/a.pdf" })
    H.eq(#rec.calls, 0, "with no engine, pandoc never spawns")
    H.eq(got.status, "error", "it reports the missing engine instead")
    H.match(got.error, "no PDF engine", "naming what is missing")
    H.match(got.error, "tectonic", "and listing the engines it looked for")
  end)

  with_producer(
    "pdfport.producers.pandoc",
    { pandoc = true, xelatex = true, pdflatex = true },
    function(producer, rec)
      H.ok(producer.available(), "pandoc plus an engine is available")

      local got = create(producer, {
        inputs = { "/docs/notes/a.md" },
        output = "/out/a.pdf",
        toc = true,
        title = "My Report",
        template = "/templates/eisvogel.latex",
      })

      local argv = H.last_argv(rec)
      H.eq(argv[1], "pandoc", "pandoc: the tool comes first")
      H.eq(argv[2], "/docs/notes/a.md", "then the input")
      H.eq(argv[3], "-o", "then -o")
      H.eq(argv[4], "/out/a.pdf", "then the output")
      -- xelatex over pdflatex: ENGINE_CHAIN order is what decides, not
      -- whichever `platform.has` happens to answer first.
      H.ok(
        H.index_of(argv, "--pdf-engine=xelatex"),
        "the earliest engine in the chain wins, not just any installed one"
      )
      -- Relative image paths in the source break once pandoc compiles from a
      -- temp dir, which is what --resource-path exists to prevent.
      local resource_path
      for _, a in ipairs(argv) do
        resource_path = a:match("^%-%-resource%-path=(.+)$") or resource_path
      end
      H.ok(resource_path, "pandoc is given a --resource-path")
      H.match(
        resource_path,
        "notes$",
        "anchored to the source file's own directory, not the compile dir"
      )
      H.ok(H.index_of(argv, "--toc"), "req.toc adds --toc")

      local meta = H.index_of(argv, "--metadata")
      H.ok(meta, "req.title adds --metadata")
      H.eq(argv[meta + 1], "title=My Report", "as a single title=<value> argument, unsplit")

      local tpl = H.index_of(argv, "--template")
      H.ok(tpl, "req.template adds --template")
      H.eq(argv[tpl + 1], "/templates/eisvogel.latex", "with the template path after it")

      H.eq(got.status, "ok", "a clean exit is an ok result")
      H.eq(got.path, "/out/a.pdf", "naming the output")
      -- pandoc does not report a page count, and guessing one would be worse
      -- than saying nothing.
      H.eq(got.pages, nil, "pandoc reports no page count")
    end
  )

  with_producer(
    "pdfport.producers.pandoc",
    { pandoc = true, tectonic = true, typst = true },
    function(producer, rec)
      local got = create(producer, { inputs = { "/docs/a.md" }, output = "/out/a.pdf" })
      H.ok(
        H.index_of(H.last_argv(rec), "--pdf-engine=tectonic"),
        "tectonic is preferred over typst (no 4 GB TeXLive to install)"
      )
      H.eq(got.status, "ok", "and the run succeeds")

      local argv = H.last_argv(rec)
      H.falsy(H.index_of(argv, "--toc"), "no req.toc means no --toc")
      H.falsy(H.index_of(argv, "--metadata"), "no req.title means no --metadata")
      H.falsy(H.index_of(argv, "--template"), "no req.template means no --template")
      -- An empty string is not a title: passing `--metadata title=` would
      -- blank out a title the document declares in its own front matter.
      local blank = create(producer, {
        inputs = { "/docs/a.md" },
        output = "/out/a.pdf",
        title = "",
        template = "",
      })
      H.eq(blank.status, "ok", "an empty title/template still runs")
      H.falsy(H.index_of(H.last_argv(rec), "--metadata"), "an empty title adds no --metadata")
      H.falsy(H.index_of(H.last_argv(rec), "--template"), "an empty template adds no --template")
    end
  )

  -- `pdf_engine` other than "auto" pins the engine -- and, when that one is
  -- not installed, does NOT silently fall back to another.
  with_producer(
    "pdfport.producers.pandoc",
    { pandoc = true, lualatex = true, xelatex = true },
    function(producer, rec)
      producer._set_config({ pdf_engine = "lualatex" })
      create(producer, { inputs = { "/docs/a.md" }, output = "/out/a.pdf" })
      H.ok(
        H.index_of(H.last_argv(rec), "--pdf-engine=lualatex"),
        "a configured pdf_engine overrides the chain order"
      )

      producer._set_config({ pdf_engine = "typst" })
      H.falsy(producer.available(), "a configured engine that is not installed is not available")
      local got = create(producer, { inputs = { "/docs/a.md" }, output = "/out/a.pdf" })
      H.eq(got.status, "error", "and it does not silently substitute another engine")
      H.eq(#rec.calls, 1, "still exactly the one spawn from the first case")
    end
  )

  assert_failure_branches(
    "pdfport.producers.pandoc",
    { pandoc = true, tectonic = true },
    "pandoc",
    function()
      return { inputs = { "/docs/a.md" }, output = "/out/a.pdf" }
    end
  )

  -- ---------------------------------------------------------- weasyprint

  with_producer("pdfport.producers.weasyprint", { weasyprint = true }, function(producer, rec)
    H.ok(producer.available(), "weasyprint is available when installed")
    H.eq_list(producer.accepts, { "html" }, "weasyprint accepts html")

    local got = create(producer, { inputs = { "/site/index.html" }, output = "/out/site.pdf" })
    H.eq_list(
      H.last_argv(rec),
      { "weasyprint", "/site/index.html", "/out/site.pdf" },
      "weasyprint: positional input then output, no flags"
    )
    H.eq(got.status, "ok", "a clean exit is an ok result")
  end)

  assert_failure_branches(
    "pdfport.producers.weasyprint",
    { weasyprint = true },
    "weasyprint",
    function()
      return { inputs = { "/site/index.html" }, output = "/out/site.pdf" }
    end
  )

  -- ------------------------------------------------------------ chromium

  -- chromium resolves its browser through lib.nvim.deps rather than a
  -- hand-rolled PATH walk, so the seam here is `deps.detect.found_as`.
  local function chromium_deps(browser)
    return {
      ["lib.nvim.deps.detect"] = {
        found_as = function()
          return browser
        end,
      },
      ["lib.nvim.deps.spec"] = {
        find = function()
          return "/fake/docs/install.json"
        end,
        load = function()
          return { tools = { { bin = "chrome", paths = { "/opt/chrome" } } } }
        end,
      },
    }
  end

  with_producer("pdfport.producers.chromium", {}, function(producer, rec)
    H.ok(producer.available(), "chromium is available once deps resolves a browser")
    H.eq(producer.resolved_browser(), "msedge", "and names the exact binary create() would run")

    local got = create(producer, { inputs = { "/site/index.html" }, output = "/out/site.pdf" })
    local argv = H.last_argv(rec)

    H.eq(argv[1], "msedge", "chromium runs the resolved browser, not a hard-coded name")
    H.ok(H.index_of(argv, "--headless"), "headless")
    H.ok(H.index_of(argv, "--disable-gpu"), "with the GPU off")
    H.ok(H.index_of(argv, "--no-pdf-header-footer"), "and no browser-added header/footer")
    H.ok(
      H.index_of(argv, "--print-to-pdf=/out/site.pdf"),
      "the output path rides on --print-to-pdf=, not a separate argument"
    )
    -- A bare filesystem path only resolves to a page on some platforms; the
    -- URL form behaves the same everywhere, which is why it is built here.
    H.match(argv[#argv], "^file:///", "the input is the LAST argument, and a file:// URL")
    H.match(argv[#argv], "index%.html$", "pointing at the HTML that was passed in")
    H.falsy(argv[#argv]:match("\\"), "with backslashes normalized away for the URL")
    H.falsy(argv[#argv]:match("^file:////"), "and exactly three slashes, not four")
    H.eq(got.status, "ok", "a clean exit is an ok result")
  end, chromium_deps("msedge"))

  with_producer("pdfport.producers.chromium", {}, function(producer, rec)
    H.falsy(producer.available(), "chromium is unavailable when no browser is found")
    H.eq(producer.resolved_browser(), nil, "and resolved_browser() says so")

    local got, calls = create(producer, { inputs = { "/site/a.html" }, output = "/out/a.pdf" })
    H.eq(#rec.calls, 0, "with no browser, nothing is spawned")
    H.eq(calls, 1, "the caller is still told exactly once")
    H.eq(got.status, "error", "as an error result")
    H.match(got.error, "no Chromium%-family browser", "naming what is missing")
  end, chromium_deps(nil))

  assert_failure_branches("pdfport.producers.chromium", {}, "chromium", function()
    return { inputs = { "/site/a.html" }, output = "/out/a.pdf" }
  end, chromium_deps("chromium"))

  -- ------------------------------------------------------------- soffice

  -- soffice does not accept an output filename at all: it writes
  -- `<stem>.pdf` into `--outdir` and the producer renames it afterwards.
  -- That rename is the interesting part, so this one uses real files.
  local soffice_dir = vim.fn.stdpath("cache") .. "/pdfport_spec_soffice"
  vim.fn.mkdir(soffice_dir, "p")

  with_producer("pdfport.producers.soffice", { soffice = true }, function(producer, rec)
    H.ok(producer.available(), "soffice is available when installed")
    H.eq_list(producer.accepts, { "office" }, "soffice accepts office documents")

    local output = soffice_dir .. "/renamed.pdf"
    pcall(vim.fn.delete, output)

    rec.on_call = function(argv)
      local at = H.index_of(argv, "--outdir")
      vim.fn.writefile({ "%PDF-1.4 fake" }, argv[at + 1] .. "/report.pdf")
    end

    local got = create(producer, { inputs = { "/office/report.docx" }, output = output })

    local argv = H.last_argv(rec)
    H.eq(argv[1], "soffice", "soffice: the tool comes first")
    H.ok(H.index_of(argv, "--headless"), "headless")
    local conv = H.index_of(argv, "--convert-to")
    H.eq(argv[conv + 1], "pdf", "converting to pdf")
    local outdir = H.index_of(argv, "--outdir")
    H.ok(outdir, "into an --outdir")
    H.eq(argv[#argv], "/office/report.docx", "with the input last")
    H.falsy(
      H.index_of(argv, output),
      "the requested output path is NOT passed to soffice -- its CLI cannot take one"
    )
    -- The scratch dir is a sibling of the tmpfile dir, not the output's
    -- directory: converting must not litter next to the user's file.
    H.match(argv[outdir + 1], "pdfport%.nvim/tmp/soffice%-", "the scratch dir is pdfport's own")

    H.eq(got.status, "ok", "a clean exit plus a produced file is an ok result")
    H.eq(got.path, output, "and the file has been renamed to the requested output")
    H.eq(vim.fn.filereadable(output), 1, "which now exists on disk")
    H.eq(vim.fn.isdirectory(argv[outdir + 1]), 0, "while the scratch dir is cleaned up again")
  end)

  with_producer("pdfport.producers.soffice", { soffice = true }, function(producer, rec)
    -- Exit 0 but nothing written: soffice reports success for inputs it
    -- silently declines, so the producer has to check rather than trust it.
    local got = create(producer, {
      inputs = { "/office/report.docx" },
      output = soffice_dir .. "/never.pdf",
    })
    H.eq(got.status, "error", "a success exit with no output file is still an error")
    H.match(got.error, "no output file", "and says exactly that")
    local argv = H.last_argv(rec)
    H.eq(vim.fn.isdirectory(argv[H.index_of(argv, "--outdir") + 1]), 0, "scratch dir cleaned up")
  end)

  assert_failure_branches("pdfport.producers.soffice", { soffice = true }, "soffice", function()
    return { inputs = { "/office/a.docx" }, output = soffice_dir .. "/a.pdf" }
  end)

  pcall(vim.fn.delete, soffice_dir, "rf")

  -- ---------------------------------------------------------------- qpdf

  with_producer("pdfport.producers.qpdf", { qpdf = true }, function(producer, rec)
    H.ok(producer.available(), "qpdf is available when installed")
    H.eq_list(producer.accepts, { "pdf" }, "qpdf accepts PDFs (it is the merge producer)")
    H.ok(producer.capabilities.lossless, "qpdf merges without re-encoding")

    local got = create(producer, {
      inputs = { "/a.pdf", "/b.pdf", "/c.pdf" },
      output = "/out/merged.pdf",
    })

    -- `qpdf --empty --pages a b c -- out.pdf`: the bare `--` is what ends the
    -- page list. Without it qpdf reads the output path as another input.
    H.eq_list(
      H.last_argv(rec),
      { "qpdf", "--empty", "--pages", "/a.pdf", "/b.pdf", "/c.pdf", "--", "/out/merged.pdf" },
      "qpdf: --empty --pages <inputs> -- <output>, with the -- terminator present"
    )
    H.eq(got.status, "ok", "a clean exit is an ok result")
    H.eq(got.path, "/out/merged.pdf", "naming the merged file")
  end)

  assert_failure_branches("pdfport.producers.qpdf", { qpdf = true }, "qpdf", function()
    return { inputs = { "/a.pdf", "/b.pdf" }, output = "/out/m.pdf" }
  end)

  -- --------------------------------------------------------------- pdftk

  with_producer("pdfport.producers.pdftk", { pdftk = true }, function(producer, rec)
    H.ok(producer.available(), "pdftk is available when installed")

    local got = create(producer, { inputs = { "/a.pdf", "/b.pdf" }, output = "/out/merged.pdf" })
    H.eq_list(
      H.last_argv(rec),
      { "pdftk", "/a.pdf", "/b.pdf", "cat", "output", "/out/merged.pdf" },
      "pdftk: <inputs> cat output <output>"
    )
    H.eq(got.status, "ok", "a clean exit is an ok result")
  end)

  assert_failure_branches("pdfport.producers.pdftk", { pdftk = true }, "pdftk", function()
    return { inputs = { "/a.pdf", "/b.pdf" }, output = "/out/m.pdf" }
  end)

  -- --------------------------------------------------------- ghostscript

  -- The executable name is platform-dependent (gs / gswin64c / gswin32c),
  -- which is the one thing this producer resolves before building an argv.
  with_producer("pdfport.producers.ghostscript", { gs = true }, function(producer, rec)
    H.ok(producer.available(), "ghostscript is available as `gs`")

    local got = create(producer, { inputs = { "/a.pdf", "/b.pdf" }, output = "/out/merged.pdf" })
    H.eq_list(H.last_argv(rec), {
      "gs",
      "-dBATCH",
      "-dNOPAUSE",
      "-q",
      "-sDEVICE=pdfwrite",
      "-sOutputFile=/out/merged.pdf",
      "/a.pdf",
      "/b.pdf",
    }, "ghostscript: batch/quiet flags, -sOutputFile= carries the output, inputs last")
    H.eq(got.status, "ok", "a clean exit is an ok result")
  end)

  with_producer("pdfport.producers.ghostscript", { gswin64c = true }, function(producer, rec)
    H.ok(producer.available(), "ghostscript is available as `gswin64c` on Windows")
    create(producer, { inputs = { "/a.pdf" }, output = "/out/m.pdf" })
    H.eq(H.last_argv(rec)[1], "gswin64c", "and runs under that name")
  end)

  with_producer("pdfport.producers.ghostscript", {}, function(producer, rec)
    H.falsy(producer.available(), "ghostscript is unavailable with no gs variant on PATH")
    local got, calls = create(producer, { inputs = { "/a.pdf" }, output = "/out/m.pdf" })
    H.eq(#rec.calls, 0, "and spawns nothing")
    H.eq(calls, 1, "while still settling exactly once")
    H.eq(got.status, "error", "as an error")
    H.match(got.error, "gswin64c", "naming every variant it looked for")
  end)

  assert_failure_branches("pdfport.producers.ghostscript", { gs = true }, "ghostscript", function()
    return { inputs = { "/a.pdf", "/b.pdf" }, output = "/out/m.pdf" }
  end)

  -- -------------------------------------------------- the environment seam

  -- pandoc/pdftotext are the two tools most often installed by a version
  -- manager (Homebrew shellenv, pipx), whose PATH a libuv child does not
  -- inherit from an interactive shell -- so those two, and only those two,
  -- pass a completed env array through to spawn_capture.
  with_producer(
    "pdfport.producers.pandoc",
    { pandoc = true, tectonic = true },
    function(producer, rec)
      create(producer, { inputs = { "/docs/a.md" }, output = "/out/a.pdf" })
      H.eq(type(rec.calls[1].opts.env), "table", "pandoc is spawned with a completed env array")
      H.ok(#rec.calls[1].opts.env > 0, "which is not empty")
      H.match(rec.calls[1].opts.env[1], "=", "and is KEY=VALUE shaped, as libuv wants")
    end
  )

  -- --------------------------------------------------- custom registration

  do
    local producers = require("pdfport.producers")

    local ok_bad, err_bad = producers.load_custom("pdfport.producers.definitely_not_a_module")
    H.falsy(ok_bad, "load_custom reports a module that cannot be required")
    H.match(err_bad, "failed to load producer", "with a message naming the failure")

    -- A module that loads but is not a producer is rejected just as clearly:
    -- registering it would only move the error to first use.
    package.loaded["pdfport_spec_not_a_producer"] = { nope = true }
    local ok_shape, err_shape = producers.load_custom("pdfport_spec_not_a_producer")
    H.falsy(ok_shape, "load_custom rejects a module that is not a producer")
    H.match(err_shape, "did not return a valid", "saying what was wrong with it")
    package.loaded["pdfport_spec_not_a_producer"] = nil

    package.loaded["pdfport_spec_custom_producer"] = H.fake_producer("spec_custom", true)
    local ok_good = producers.load_custom("pdfport_spec_custom_producer")
    H.ok(ok_good, "load_custom accepts a well-formed producer module")
    H.ok(
      require("pdfport.core.registry").has_producer("spec_custom"),
      "and registers it under its own id"
    )
    package.loaded["pdfport_spec_custom_producer"] = nil
  end

  -- A lazy proxy whose module cannot be required must answer create() with an
  -- error result rather than raising through the composer.
  do
    local registry = require("pdfport.core.registry")
    local saved_preload = package.preload["pdfport.producers.img2pdf"]
    -- A preload that raises is what simulates "this module will not load" --
    -- the repo is on the runtimepath, so clearing package.path alone would
    -- not stop Neovim's own loader from finding the file anyway.
    package.preload["pdfport.producers.img2pdf"] = function()
      error("module 'pdfport.producers.img2pdf' is broken")
    end
    H.with_modules({ ["pdfport.producers.img2pdf"] = H.UNLOAD }, function()
      -- Proxies memoize their module on first touch, so a fresh set has to
      -- be registered for the broken one to be observed.
      require("pdfport.producers").load_all({})
      local proxy = registry.get_producer("img2pdf")
      H.falsy(proxy.available(), "a producer whose module will not load is not available")
      local result = proxy.create({ inputs = { "/a.png" }, output = "/a.pdf" })
      H.eq(result.status, "error", "and create() on it returns an error result")
      H.eq(result.producer, "img2pdf", "attributed to the producer that failed")
      H.match(result.error, "failed to load", "saying it could not be loaded")
    end)
    package.preload["pdfport.producers.img2pdf"] = saved_preload
    -- Restore proxies bound to the real, loadable modules for later specs.
    require("pdfport.producers").load_all({})
  end
end
