-- TESTS/backend_argv_spec.lua — the command line every non-AI extraction
-- backend would run, and what it does with the answer.
--
-- The mirror image of producer_argv_spec.lua for the read side. The three
-- remote/model backends already have ai_backends_spec.lua; these five shell
-- out, and each one gets the page selection into its tool's own flags
-- differently: pdftotext has -f/-l, marker has --max_pages, pdfplumber and
-- docling get it interpolated into a generated Python script, and tesseract
-- has no page concept at all so it drives pdftoppm once per page and
-- concatenates.
--
-- `lib.nvim.cross.uv.spawn_capture` is replaced in `package.loaded` before the
-- backend is required, so nothing here runs poppler, Python, OCR or a model.

return function(H)
  local SPAWN = "lib.nvim.cross.uv.spawn_capture"

  ---Require `module` with `spawn_capture` and `pdfport.platform` replaced.
  ---@param module string
  ---@param present table<string, boolean>
  ---@param python string|nil
  ---@param fn fun(backend: table, rec: table)
  ---@return nil
  local function with_backend(module, present, python, fn)
    local rec = H.spawn_recorder()
    H.with_modules({
      [SPAWN] = rec.fn,
      ["pdfport.platform"] = H.fake_platform(present, python),
      [module] = H.UNLOAD,
    }, function()
      fn(require(module), rec)
    end)
  end

  ---Run `extract` and hand back what the callback received.
  ---@param backend table
  ---@param path string
  ---@param opts table
  ---@return table|nil via_callback
  ---@return table|nil returned
  ---@return integer calls
  local function extract(backend, path, opts)
    local got, calls = nil, 0
    opts.__callback = function(result)
      calls = calls + 1
      got = result
    end
    local returned = backend.extract(path, opts)
    return got, returned, calls
  end

  -- ----------------------------------------------------------- pdftotext

  with_backend("pdfport.backends.pdftotext", { pdftotext = true }, nil, function(backend, rec)
    H.ok(backend.available(), "pdftotext is available when poppler is installed")
    H.falsy(backend.capabilities.markdown, "pdftotext yields plain text, not Markdown")

    local got, returned, calls = extract(backend, "/docs/a.pdf", {})
    H.eq(returned, nil, "pdftotext answers through __callback, not a return value")
    H.eq(calls, 1, "and settles exactly once")

    H.eq_list(
      H.last_argv(rec),
      { "pdftotext", "-layout", "-enc", "UTF-8", "/docs/a.pdf", "-" },
      "pdftotext: layout preserved, UTF-8 forced, input then `-` for stdout"
    )
    H.eq(got.status, "ok", "a clean exit is an ok result")
    H.eq(got.format, "plain", "declared as plain text")
    H.eq(got.backend, "pdftotext", "attributed to this backend")
    H.eq(rec.calls[1].opts.timeout_ms, 30000, "with the 30 s default timeout")
    -- pandoc and pdftotext are the two tools a version manager most often
    -- installs outside the PATH a libuv child inherits.
    H.eq(type(rec.calls[1].opts.env), "table", "and a completed env array")
  end)

  with_backend("pdfport.backends.pdftotext", { pdftotext = true }, nil, function(backend, rec)
    extract(backend, "/docs/a.pdf", { pages = { 3, 4, 7 } })
    local argv = H.last_argv(rec)
    -- pdftotext has no "these pages" flag, only a span -- so a disjoint
    -- request becomes first..last, which is the closest the tool can do.
    H.eq(
      argv[H.index_of(argv, "-f") + 1],
      "3",
      "an explicit page list starts the span at its first"
    )
    H.eq(argv[H.index_of(argv, "-l") + 1], "7", "and ends it at its last")

    extract(backend, "/docs/a.pdf", { max_pages = 5 })
    local capped = H.last_argv(rec)
    H.eq(capped[H.index_of(capped, "-l") + 1], "5", "max_pages alone becomes a -l upper bound")
    H.falsy(H.index_of(capped, "-f"), "with no -f, so it still starts at page one")

    extract(backend, "/docs/a.pdf", { pages = {} })
    H.falsy(H.index_of(H.last_argv(rec), "-f"), "an empty page list selects no span at all")
  end)

  with_backend("pdfport.backends.pdftotext", { pdftotext = true }, nil, function(backend, rec)
    rec.result = H.spawn_result({ stdout = "Hello from the PDF" })
    local got = extract(backend, "/docs/a.pdf", { max_pages = 2 })
    H.eq(got.text, "Hello from the PDF", "stdout becomes the extracted text verbatim")
    H.eq(got.pages_processed, 2, "and max_pages is reported back as the page count")

    rec.result = H.spawn_result({ ok = false, code = 1, stderr = "Syntax Error: Couldn't open" })
    local failed = extract(backend, "/docs/a.pdf", {})
    H.eq(failed.status, "error", "a non-zero exit is an error result")
    H.eq(failed.text, nil, "with no text")
    H.match(failed.error, "exited 1", "naming the exit code")
    H.match(failed.error, "Syntax Error", "and carrying poppler's own stderr")

    rec.result = H.spawn_result({ ok = false, timed_out = true })
    local timed = extract(backend, "/docs/a.pdf", { timeout_ms = 500 })
    H.eq(timed.status, "error", "a timeout is an error result")
    H.match(timed.error, "timed out after 500 ms", "naming the budget it was given")
  end)

  with_backend("pdfport.backends.pdftotext", {}, nil, function(backend)
    H.falsy(backend.available(), "pdftotext is unavailable when poppler is missing")
  end)

  -- ---------------------------------------------------------- pdfplumber

  -- pdfplumber and docling are Python libraries, not CLIs: each generates a
  -- script to a tempfile and runs the interpreter on it. What is assertable
  -- is the script's content (the path and the page cap are interpolated in)
  -- and that the tempfile is cleaned up again.
  with_backend(
    "pdfport.backends.pdfplumber",
    { ["pymod:pdfplumber"] = true },
    "python3",
    function(backend, rec)
      H.ok(backend.available(), "pdfplumber is available with an interpreter and the module")

      -- The script only exists while the interpreter would be running, so it
      -- is read inside the spawn seam and asserted on afterwards.
      local script_path, source, readable_while_running
      rec.on_call = function(argv)
        script_path = argv[2]
        readable_while_running = vim.fn.filereadable(script_path)
        source = table.concat(vim.fn.readfile(script_path), "\n")
      end
      rec.result = H.spawn_result({ stdout = "page one\n\npage two" })

      local got = extract(backend, "/docs/a.pdf", { max_pages = 3 })
      H.eq(H.last_argv(rec)[1], "python3", "pdfplumber runs the resolved interpreter")
      H.eq(#H.last_argv(rec), 2, "with the generated script as its only argument")
      H.eq(readable_while_running, 1, "the generated script exists while it runs")
      H.match(source, "import sys, pdfplumber", "the script imports pdfplumber")
      H.match(source, "/docs/a%.pdf", "with the PDF path interpolated in")
      H.match(source, "max_pages%s*= 3", "and the page cap as a literal")
      -- %q, not plain interpolation: a path with a quote or a backslash in it
      -- would otherwise be a syntax error in the generated Python.
      H.match(source, 'path%s*=%s*"', "the path is emitted quoted, not bare")

      H.eq(got.status, "ok", "a clean exit is an ok result")
      H.eq(got.text, "page one\n\npage two", "carrying the script's stdout")
      H.eq(got.format, "plain", "pdfplumber yields plain text")
      H.eq(got.pages_processed, 3, "reporting the page cap it honoured")
      H.eq(vim.fn.filereadable(script_path), 0, "and the generated script is deleted afterwards")

      local uncapped = extract(backend, "/docs/a.pdf", {})
      H.eq(uncapped.pages_processed, nil, "without max_pages no page count is claimed")
      H.match(
        source,
        "max_pages%s*= 0",
        "no cap is passed to the script as 0, its 'all pages' value"
      )

      -- LLS-31: opts.pages must actually reach the script, not just
      -- opts.max_pages, and it takes priority when both are given.
      local explicit = extract(backend, "/docs/a.pdf", { pages = { 2, 5 }, max_pages = 1 })
      H.match(source, "explicit_pages = %[2,5%]", "the explicit page list is interpolated in")
      H.eq(
        explicit.pages_processed,
        nil,
        "an explicit page selection is not reported as a page count"
      )
      H.eq(explicit.status, "ok", "and pdfplumber honours it, so the result is a plain ok")
    end
  )

  with_backend("pdfport.backends.pdfplumber", {}, nil, function(backend, rec)
    H.falsy(backend.available(), "pdfplumber is unavailable without an interpreter")
    -- The synchronous-return shape: the dispatcher fires a non-nil result
    -- itself, so this must NOT also go through __callback.
    local got, returned, calls = extract(backend, "/docs/a.pdf", {})
    H.eq(#rec.calls, 0, "with no interpreter, nothing is spawned")
    H.eq(got, nil, "and the callback is not invoked")
    H.eq(calls, 0, "not even once")
    H.eq(returned.status, "error", "the failure comes back as a synchronous result")
    H.match(returned.error, "no python interpreter", "naming what is missing")
  end)

  -- ------------------------------------------------------------- docling

  with_backend(
    "pdfport.backends.docling",
    { ["pymod:docling"] = true },
    "python",
    function(backend, rec)
      H.ok(backend.available(), "docling is available with an interpreter and the module")
      H.ok(backend.capabilities.markdown, "docling declares Markdown output")

      rec.on_call = function(argv)
        local source = table.concat(vim.fn.readfile(argv[2]), "\n")
        H.match(source, "DocumentConverter", "the script drives docling's DocumentConverter")
        H.match(source, "export_to_markdown", "and exports Markdown")
        H.match(source, "/docs/a%.pdf", "for the PDF it was given")
      end
      rec.result = H.spawn_result({ stdout = "# Title\n\nbody" })

      local got = extract(backend, "/docs/a.pdf", {})
      H.eq(H.last_argv(rec)[1], "python", "docling runs the resolved interpreter")
      H.eq(got.status, "ok", "a clean exit is an ok result")
      H.eq(got.text, "# Title\n\nbody", "carrying the converted Markdown")
      H.eq(got.format, "markdown", "declared as markdown")
      -- Four times pdftotext's: docling loads layout models before it reads
      -- a single page, so the shared 30 s default would time out every run.
      H.eq(rec.calls[1].opts.timeout_ms, 120000, "with a 120 s default timeout, not 30 s")

      -- LLS-31: the generated script never applies max_pages (converter.convert()
      -- always reads the whole document), so pages_processed must not report
      -- the planned cap as if it were the work actually performed.
      local capped = extract(backend, "/docs/a.pdf", { max_pages = 5 })
      H.eq(
        capped.pages_processed,
        nil,
        "max_pages is not silently claimed as applied -- docling has no page-limiting hook"
      )

      rec.on_call = nil
      rec.result = H.spawn_result({ ok = false, code = 1, stderr = "docling error: no such file" })
      local failed = extract(backend, "/docs/a.pdf", {})
      H.eq(failed.status, "error", "a non-zero exit is an error result")
      H.eq(failed.format, "markdown", "still declared markdown, so a caller can render it")
      H.match(failed.error, "docling error", "carrying the script's own stderr")

      -- LLS-31: docling's script honours neither pages nor max_pages, so an
      -- explicit page request must not come back as a plain "ok" -- that
      -- would claim the selection was applied when the whole document was
      -- converted instead.
      rec.result = H.spawn_result({ stdout = "# Title\n\nbody" })
      local partial = extract(backend, "/docs/a.pdf", { pages = { 2, 3 } })
      H.eq(partial.status, "partial", "an explicit page request is reported as partial")
      H.eq(partial.text, "# Title\n\nbody", "the whole-document text still comes back")
      H.match(partial.error, "not supported", "with the reason attached")
    end
  )

  with_backend("pdfport.backends.docling", {}, nil, function(backend)
    H.falsy(backend.available(), "docling is unavailable without an interpreter")
  end)

  -- -------------------------------------------------------------- marker

  -- marker_single writes into a directory rather than to stdout, so the
  -- backend has to find the file afterwards -- including via a recursive
  -- glob when marker does not use the layout it usually does.
  with_backend("pdfport.backends.marker", { marker_single = true }, nil, function(backend, rec)
    H.ok(backend.available(), "marker is available when marker_single is on PATH")

    local seen_dir
    rec.on_call = function(argv)
      seen_dir = argv[3]
      vim.fn.mkdir(seen_dir .. "/report", "p")
      vim.fn.writefile({ "# Report", "", "body" }, seen_dir .. "/report/report.md")
    end

    local got = extract(backend, "/docs/report.pdf", { max_pages = 4 })
    local argv = H.last_argv(rec)
    H.eq(argv[1], "marker_single", "marker: the tool comes first")
    H.eq(argv[2], "/docs/report.pdf", "then the PDF")
    H.eq(argv[3], seen_dir, "then the output directory it writes into")
    H.eq(argv[4], "--output_format", "then the format flag")
    H.eq(argv[5], "markdown", "asking for markdown")
    H.eq(argv[H.index_of(argv, "--max_pages") + 1], "4", "and max_pages becomes --max_pages")

    H.eq(got.status, "ok", "a clean exit with an output file is an ok result")
    H.eq(got.text, "# Report\n\nbody", "the produced Markdown is read back and joined")
    H.eq(got.format, "markdown", "declared as markdown")
    H.eq(got.pages_processed, 4, "reporting the page cap")
    H.eq(vim.fn.isdirectory(seen_dir), 0, "and the scratch directory is removed again")
  end)

  with_backend("pdfport.backends.marker", { marker_single = true }, nil, function(backend, rec)
    -- LLS-31: marker_single has no flag for an explicit page list -- only
    -- --max_pages reaches it -- so opts.pages must not come back as a plain
    -- "ok" once the whole document was extracted instead of the selection.
    rec.on_call = function(argv)
      vim.fn.mkdir(argv[3] .. "/report", "p")
      vim.fn.writefile({ "whole doc" }, argv[3] .. "/report/report.md")
    end
    local got = extract(backend, "/docs/report.pdf", { pages = { 2, 3 } })
    H.falsy(
      H.index_of(H.last_argv(rec), "--max_pages"),
      "opts.pages alone still does not produce a --max_pages flag"
    )
    H.eq(got.status, "partial", "an explicit page request is reported as partial")
    H.eq(got.text, "whole doc", "the whole-document text still comes back")
    H.match(got.error, "not supported", "with the reason attached")
  end)

  with_backend("pdfport.backends.marker", { marker_single = true }, nil, function(backend, rec)
    -- Not the <stem>/<stem>.md layout: the recursive glob is the recovery
    -- path, and it has to survive a tempdir under a Windows 8.3 %TEMP%
    -- (`C:/Users/STEFAN~1/...`), where `~1` is a pattern glob cannot resolve.
    rec.on_call = function(argv)
      vim.fn.mkdir(argv[3] .. "/nested/deeper", "p")
      vim.fn.writefile({ "recovered" }, argv[3] .. "/nested/deeper/out.md")
    end
    local got = extract(backend, "/docs/report.pdf", {})
    H.eq(got.status, "ok", "a .md found anywhere under the output dir still counts")
    H.eq(got.text, "recovered", "and its content is what comes back")
    H.falsy(H.index_of(H.last_argv(rec), "--max_pages"), "no max_pages means no --max_pages flag")
  end)

  with_backend("pdfport.backends.marker", { marker_single = true }, nil, function(backend, rec)
    rec.on_call = function(argv)
      vim.fn.mkdir(argv[3] .. "/sub", "p")
      vim.fn.writefile({ "not markdown" }, argv[3] .. "/sub/leftover.txt")
    end
    local got = extract(backend, "/docs/report.pdf", {})
    H.eq(got.status, "error", "a clean exit that produced no .md is an error")
    H.match(got.error, "no %.md file", "saying so")
    -- The "Present:" listing is the whole point of the 8.3 realpath dance
    -- above it: an empty one on a non-empty directory was the original bug.
    H.match(got.error, "leftover%.txt", "and listing what the directory did contain")
  end)

  with_backend("pdfport.backends.marker", { marker_single = true }, nil, function(backend, rec)
    rec.result = H.spawn_result({ ok = false, code = 2, stderr = "CUDA out of memory" })
    local got = extract(backend, "/docs/report.pdf", {})
    H.eq(got.status, "error", "a non-zero exit is an error result")
    H.match(got.error, "marker_single exited 2", "naming tool and exit code")
    H.match(got.error, "CUDA", "and carrying its stderr")

    rec.result = H.spawn_result({ ok = false, timed_out = true })
    local timed = extract(backend, "/docs/report.pdf", { timeout_ms = 777 })
    H.eq(timed.status, "error", "a timeout is an error result")
    H.match(timed.error, "777", "naming the budget")
  end)

  -- ----------------------------------------------------------- tesseract

  -- The only backend that drives two tools in sequence, once per page:
  -- pdftoppm rasterizes, tesseract OCRs the PNG, and the per-page texts are
  -- concatenated. Both spawns go through the same replaced seam.
  local function ocr_recorder(rec, text_for)
    rec.on_call = function(argv)
      if argv[1] == "pdftoppm" then vim.fn.writefile({ "fake png" }, argv[#argv] .. ".png") end
    end
    local original = rec.fn
    rec.fn = function(argv, opts, on_done)
      if argv[1] == "tesseract" then
        rec.calls[#rec.calls + 1] = { argv = argv, opts = opts }
        on_done(rec.result or H.spawn_result({ stdout = text_for(argv) }))
        return
      end
      original(argv, opts, on_done)
    end
  end

  do
    local rec = H.spawn_recorder()
    ocr_recorder(rec, function()
      return "OCR text"
    end)
    H.with_modules({
      [SPAWN] = function(...)
        return rec.fn(...)
      end,
      ["pdfport.platform"] = H.fake_platform({ tesseract = true, pdftoppm = true }),
      ["pdfport.backends.tesseract"] = H.UNLOAD,
    }, function()
      local backend = require("pdfport.backends.tesseract")
      H.ok(backend.available(), "tesseract needs both tesseract and pdftoppm")

      local got = extract(backend, "/docs/scan.pdf", { pages = { 2, 5 } })

      H.eq(#rec.calls, 4, "two pages means two rasterize+OCR pairs")
      local first = rec.calls[1].argv
      H.eq(first[1], "pdftoppm", "each page is rasterized first")
      H.eq(first[H.index_of(first, "-r") + 1], "300", "at 300 dpi, the OCR-friendly default")
      H.eq(first[H.index_of(first, "-f") + 1], "2", "with -f and -l pinned to the one page")
      H.eq(first[H.index_of(first, "-l") + 1], "2", "on both ends")
      H.ok(H.index_of(first, "-singlefile"), "and -singlefile, so the name is predictable")
      H.eq(first[#first - 1], "/docs/scan.pdf", "the PDF is the second-to-last argument")

      local second = rec.calls[2].argv
      H.eq(second[1], "tesseract", "then tesseract runs on the rendered page")
      H.eq(second[3], "stdout", "writing to stdout rather than a sidecar file")
      H.eq(second[2], first[#first] .. ".png", "reading the .png pdftoppm appended itself")
      H.eq(vim.fn.filereadable(second[2]), 0, "which is deleted once OCR has read it")

      H.eq(rec.calls[3].argv[H.index_of(rec.calls[3].argv, "-f") + 1], "5", "then the second page")

      H.eq(got.status, "ok", "the run succeeds")
      H.eq(got.text, "OCR text\n\nOCR text", "per-page text is joined with a blank line")
      H.eq(got.pages_processed, 2, "and both pages are reported")
      H.eq(got.format, "plain", "as plain text")
    end)
  end

  with_backend(
    "pdfport.backends.tesseract",
    { tesseract = true, pdftoppm = true },
    nil,
    function(backend, rec)
      -- No pages and no max_pages: page 1 only, rather than the whole
      -- document -- OCR is minutes per page, so "all" is not a safe default.
      rec.on_call = function(argv)
        -- Only pdftoppm names a PNG base; tesseract's last argument is the
        -- literal "stdout", which must not be turned into a file.
        if argv[1] == "pdftoppm" then vim.fn.writefile({ "png" }, argv[#argv] .. ".png") end
      end
      rec.result = H.spawn_result({ stdout = "one page" })
      local got = extract(backend, "/docs/scan.pdf", {})
      H.eq(got.pages_processed, 1, "with no selection tesseract does page 1 only")

      local counted = extract(backend, "/docs/scan.pdf", { max_pages = 3 })
      H.eq(counted.pages_processed, 3, "max_pages expands to pages 1..N")
    end
  )

  with_backend(
    "pdfport.backends.tesseract",
    { tesseract = true, pdftoppm = true },
    nil,
    function(backend, rec)
      rec.result = H.spawn_result({ ok = false, code = 1, stderr = "no such page" })
      local got = extract(backend, "/docs/scan.pdf", { pages = { 1, 2 } })
      H.eq(got.status, "error", "a failed rasterize aborts the whole extraction")
      H.match(got.error, "pdftoppm failed on page 1", "naming the tool and the page")
      H.match(got.error, "no such page", "and carrying its stderr")
      H.eq(#rec.calls, 1, "and no further page is attempted")

      -- BUG: `pages_processed` counts the page that just FAILED as processed.
      -- finish_error() reports `page_idx - 1`, but process_next() has already
      -- incremented page_idx past the current page by the time any of its
      -- callbacks can fail — so a failure on page 1 reports 1 page done when
      -- none completed. backends/ollama.lua's identically-shaped `fail()` gets
      -- this right with `page_idx - 2`; the two were written from the same
      -- template and only one of them was corrected. Pinned rather than
      -- fixed: it is a visible field of a public result type.
      H.eq(
        got.pages_processed,
        1,
        "BUG: a failure on page 1 still claims 1 page was processed (should be 0)"
      )
    end
  )

  with_backend(
    "pdfport.backends.tesseract",
    { tesseract = true, pdftoppm = true },
    nil,
    function(backend, rec)
      -- Exit 0 but no PNG: pdftoppm succeeds on a page it silently skipped,
      -- so the backend checks for the file rather than trusting the code.
      local got = extract(backend, "/docs/scan.pdf", { pages = { 1 } })
      H.eq(got.status, "error", "a missing PNG after a clean rasterize is an error")
      H.match(got.error, "rasterized PNG not found", "saying exactly that")
      H.eq(#rec.calls, 1, "and tesseract is never invoked on a file that is not there")
    end
  )

  with_backend("pdfport.backends.tesseract", { tesseract = true }, nil, function(backend)
    H.falsy(backend.available(), "tesseract without pdftoppm cannot rasterize, so is unavailable")
  end)

  -- ------------------------------------------------ custom backend loading

  do
    local backends = require("pdfport.backends")

    local ok_bad, err_bad = backends.load_custom("pdfport.backends.definitely_not_a_module")
    H.falsy(ok_bad, "load_custom reports a module that cannot be required")
    H.match(err_bad, "failed to load backend", "with a message naming the failure")

    package.loaded["pdfport_spec_not_a_backend"] = { nope = true }
    local ok_shape, err_shape = backends.load_custom("pdfport_spec_not_a_backend")
    H.falsy(ok_shape, "load_custom rejects a module that is not a backend")
    H.match(err_shape, "did not return a valid", "saying what was wrong with it")
    package.loaded["pdfport_spec_not_a_backend"] = nil

    package.loaded["pdfport_spec_custom_backend"] = H.fake_backend("spec_custom_backend", true)
    H.ok(
      backends.load_custom("pdfport_spec_custom_backend"),
      "load_custom accepts a well-formed backend module"
    )
    H.ok(
      require("pdfport.core.registry").has_backend("spec_custom_backend"),
      "and registers it under its own id"
    )
    package.loaded["pdfport_spec_custom_backend"] = nil
  end

  -- A lazy proxy whose module cannot be required answers extract() with an
  -- error result rather than raising through the dispatcher.
  do
    local registry = require("pdfport.core.registry")
    local saved = package.preload["pdfport.backends.marker"]
    package.preload["pdfport.backends.marker"] = function()
      error("module 'pdfport.backends.marker' is broken")
    end
    H.with_modules({ ["pdfport.backends.marker"] = H.UNLOAD }, function()
      require("pdfport.backends").load_all({})
      local proxy = registry.get_backend("marker")
      H.falsy(proxy.available(), "a backend whose module will not load is not available")
      local result = proxy.extract("/docs/a.pdf", {})
      H.eq(result.status, "error", "and extract() on it returns an error result")
      H.eq(result.backend, "marker", "attributed to the backend that failed")
      H.match(result.error, "failed to load", "saying it could not be loaded")
      -- Every other field of the result type is still filled in, so a caller
      -- that renders the result does not have to special-case this one.
      H.eq(result.format, "plain", "with the result shape intact")
    end)
    package.preload["pdfport.backends.marker"] = saved
    require("pdfport.backends").load_all({})
  end
end
