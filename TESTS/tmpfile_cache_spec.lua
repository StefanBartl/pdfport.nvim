-- TESTS/tmpfile_cache_spec.lua — the two pieces of state pdfport keeps on
-- disk: the scratch files creation inputs are materialized to, and the
-- cross-session extraction cache.
--
-- `util.tmpfile` exists because every producer spawns a CLI and a CLI needs a
-- real path, which `opts.text`/`opts.bufnr` do not have. Its whole contract is
-- "the file is there while the producer runs and gone afterwards", so the
-- lifecycle is what is asserted, against real files.
--
-- `util.cache` is keyed by path + backend + variant and invalidated by the
-- source PDF's mtime rather than a TTL. `lib.nvim.cache.disk` is replaced with
-- an in-memory store, so the spec can read the keys back and nothing is
-- written to the user's real cache directory.

return function(H)
  -- -------------------------------------------------------------- tmpfile

  do
    local tmpfile = require("pdfport.util.tmpfile")
    local tmp_root = vim.fn.stdpath("cache") .. "/pdfport.nvim/tmp"

    local md = tmpfile.write_text("# Title\n\nbody", "markdown")
    H.match(md, "%.md$", "markdown content is materialized with a .md extension")
    H.match(md:gsub("\\", "/"), "pdfport%.nvim/tmp/", "inside pdfport's own scratch directory")
    H.eq(vim.fn.filereadable(md), 1, "and the file really exists")
    H.eq_list(vim.fn.readfile(md), { "# Title", "", "body" }, "with the content split into lines")

    -- The extension is not cosmetic: pandoc picks its reader from it, so a
    -- Markdown document handed over as .txt renders as literal asterisks.
    H.match(tmpfile.write_text("plain", "text"), "%.txt$", "text becomes .txt")
    H.match(tmpfile.write_text("<p>x</p>", "html"), "%.html$", "html becomes .html")
    H.match(
      tmpfile.write_text("x", "image"),
      "%.txt$",
      "a kind with no text extension falls back to .txt rather than an extensionless file"
    )

    -- Two writes in the same millisecond must not collide: the name mixes
    -- uv.hrtime() with a random component for exactly that reason.
    local one = tmpfile.write_text("a", "markdown")
    local two = tmpfile.write_text("b", "markdown")
    H.falsy(one == two, "two scratch files in a row get distinct names")

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "line one", "line two" })
    local from_buf = tmpfile.write_buffer(bufnr, "markdown")
    H.eq_list(
      vim.fn.readfile(from_buf),
      { "line one", "line two" },
      "write_buffer writes the buffer's lines verbatim"
    )
    H.match(from_buf, "%.md$", "honouring the kind's extension too")
    vim.api.nvim_buf_delete(bufnr, { force = true })

    -- cleanup() is deferred through vim.schedule: the producer's callback has
    -- to have run before the input it read is removed.
    tmpfile.cleanup(md)
    H.eq(vim.fn.filereadable(md), 1, "cleanup() does not delete synchronously")
    vim.wait(500, function()
      return vim.fn.filereadable(md) == 0
    end)
    H.eq(vim.fn.filereadable(md), 0, "but the file is gone once the scheduler has run")

    -- A path that is already gone must not raise: composer.lua cleans up on
    -- every exit path, including ones where nothing was written.
    local ok_missing = pcall(tmpfile.cleanup, tmp_root .. "/definitely-not-there.md")
    H.ok(ok_missing, "cleaning up a path that does not exist is a no-op, not an error")
    vim.wait(200)

    for _, leftover in ipairs({ one, two, from_buf }) do
      pcall(vim.fn.delete, leftover)
    end
    for _, pattern in ipairs({ "/*.txt", "/*.html" }) do
      for _, leftover in ipairs(vim.fn.glob(tmp_root .. pattern, false, true)) do
        pcall(vim.fn.delete, leftover)
      end
    end
  end

  -- ---------------------------------------------------------------- cache

  do
    local uv = vim.uv or vim.loop

    -- Canonical, the way `core.dispatcher` canonicalizes before it keys
    -- anything: this module takes the path it is handed at face value.
    local pdf = H.tempfile("-cache-spec.pdf", { "%PDF-1.4 fake" })

    local store = {}
    local cleared = {}
    local disk = {
      load = function(namespace)
        return store[namespace]
      end,
      save = function(namespace, data)
        store[namespace] = data
      end,
      clear = function(namespace)
        cleared[#cleared + 1] = namespace
        store[namespace] = nil
        return true
      end,
    }

    H.with_modules({
      ["lib.nvim.cache.disk"] = disk,
      ["pdfport.util.cache"] = H.UNLOAD,
    }, function()
      local cache = require("pdfport.util.cache")

      H.eq(cache.get(pdf, "pdftotext", "all"), nil, "an empty cache is a miss, not an error")

      cache.set(pdf, "pdftotext", "all", {
        status = "ok",
        text = "extracted text",
        format = "plain",
        backend = "pdftotext",
        pages_processed = 3,
      })

      -- One namespace, whatever the file: a per-PDF namespace would mean one
      -- cache file per document in the user's cache directory.
      local namespaces = {}
      for ns in pairs(store) do
        namespaces[#namespaces + 1] = ns
      end
      H.eq_list(namespaces, { "pdfport_extract" }, "everything lives under one namespace")

      local keys = {}
      for key in pairs(store.pdfport_extract) do
        keys[#keys + 1] = key
      end
      H.eq(#keys, 1, "one entry was written")
      H.match(keys[1], "::pdftotext::all$", "the key is path::backend::variant")
      H.match(keys[1], "cache%-spec%.pdf", "with the source path in front")

      local hit = cache.get(pdf, "pdftotext", "all")
      H.ok(hit, "the entry is found again")
      H.eq(hit.status, "ok", "and comes back as an ok result")
      H.eq(hit.text, "extracted text", "with the text")
      H.eq(hit.format, "plain", "the format")
      H.eq(hit.backend, "pdftotext", "the backend")
      H.eq(hit.pages_processed, 3, "and the page count")
      H.eq(hit.error, nil, "and no error field")

      -- Each of the three key components has to discriminate on its own, or
      -- one extraction silently answers a different question.
      H.eq(cache.get(pdf, "marker", "all"), nil, "a different backend is a different entry")
      H.eq(cache.get(pdf, "pdftotext", "1,2"), nil, "as is a different page variant")
      H.eq(cache.get(pdf .. "x", "pdftotext", "all"), nil, "and a different file misses entirely")

      -- mtime, not a TTL: a PDF that has not changed stays cached forever,
      -- one that has is re-extracted transparently.
      local later = os.time() + 120
      uv.fs_utime(pdf, later, later)
      H.eq(cache.get(pdf, "pdftotext", "all"), nil, "touching the source file invalidates it")

      cache.set(pdf, "pdftotext", "all", {
        status = "ok",
        text = "re-extracted",
        format = "plain",
        backend = "pdftotext",
      })
      H.eq(cache.get(pdf, "pdftotext", "all").text, "re-extracted", "and the new run replaces it")

      -- Only successful extractions are worth keeping: caching an error would
      -- pin a transient failure (a daemon that was down) until the file changes.
      local before = vim.tbl_count(store.pdfport_extract)
      cache.set(pdf, "pdftotext", "err", { status = "error", error = "boom" })
      cache.set(pdf, "pdftotext", "empty", { status = "ok", text = nil, format = "plain" })
      H.eq(
        vim.tbl_count(store.pdfport_extract),
        before,
        "neither an error nor an empty result is stored"
      )

      -- A file that is not there has no mtime to key on, so both directions
      -- have to miss rather than guess.
      local gone = pdf .. "-gone"
      cache.set(gone, "pdftotext", "all", { status = "ok", text = "x", format = "plain" })
      H.eq(cache.get(gone, "pdftotext", "all"), nil, "a vanished source file is never cached")

      H.ok(cache.clear(), "clear() reports success")
      H.eq_list(cleared, { "pdfport_extract" }, "clearing exactly pdfport's own namespace")
      H.eq(cache.get(pdf, "pdftotext", "all"), nil, "after which every entry is gone")

      -- A corrupted or foreign cache file must degrade to a miss, not raise.
      store.pdfport_extract = "not a table"
      H.eq(cache.get(pdf, "pdftotext", "all"), nil, "a non-table store reads as empty")
      cache.set(pdf, "pdftotext", "all", { status = "ok", text = "fresh", format = "plain" })
      H.eq(type(store.pdfport_extract), "table", "and is replaced wholesale on the next write")
      H.eq(cache.get(pdf, "pdftotext", "all").text, "fresh", "with the new entry readable")
    end)

    pcall(vim.fn.delete, pdf)
  end
end
