---@diagnostic disable: missing-fields
-- The backend/producer doubles below implement only what the registry test
-- exercises; a full interface per case would be noise, not coverage.
-- TESTS/producer_spec.lua — pdfport.core.registry producer half +
-- pdfport.core.composer (the create() mirror of dispatcher/resolver).
--
-- Every producer here is a fake with a hard-coded `available`, so the chain
-- logic is exercised without depending on img2pdf/magick actually being
-- installed on the machine running the suite.

return function(H)
  local registry = require("pdfport.core.registry")
  local composer = require("pdfport.core.composer")

  -- ------------------------------------------------------ producer registry

  registry.register_producer(H.fake_producer("spec_p_alpha", true))
  H.ok(registry.has_producer("spec_p_alpha"), "a registered producer is found")
  H.eq(registry.get_producer("spec_p_alpha").id, "spec_p_alpha", "get_producer returns it")
  H.eq(registry.get_producer("spec_p_nonexistent"), nil, "an unknown id returns nil")

  local before = #registry.producer_ids()
  registry.register_producer(H.fake_producer("spec_p_alpha", false))
  H.eq(#registry.producer_ids(), before, "re-registering an id does not duplicate it")
  H.eq(
    registry.get_producer("spec_p_alpha").available(),
    false,
    "re-registering replaces the entry"
  )

  H.falsy(pcall(registry.register_producer, nil), "a nil producer is rejected")
  H.falsy(pcall(registry.register_producer, { id = "" }), "an empty id is rejected")
  H.falsy(
    pcall(registry.register_producer, { id = "x", available = true, create = function() end }),
    "a non-function available is rejected"
  )

  -- ------------------------------------------------------------- composer

  registry.register_producer(H.fake_producer("spec_p_missing", false))
  registry.register_producer(H.fake_producer("spec_p_present", true))
  registry.register_producer(H.fake_producer("spec_p_other", true))

  composer._set_config({
    create_chain = { image = { "spec_p_missing", "spec_p_present", "spec_p_other" } },
  })

  local resolved = composer.resolve("image")
  H.eq(
    resolved and resolved.id,
    "spec_p_present",
    "resolve walks the chain and skips unavailable entries"
  )
  H.ok(composer.can_create("image"), "can_create is true once a producer resolves")

  composer._set_config({ create_chain = { image = { "spec_p_missing" } } })
  H.falsy(
    composer.can_create("image"),
    "can_create is false when nothing in the chain is available"
  )

  -- An explicit producer_id request is tried first, ahead of the chain.
  composer._set_config({
    create_chain = { image = { "spec_p_present" } },
  })
  local explicit = composer.resolve("image", "spec_p_other")
  H.eq(explicit and explicit.id, "spec_p_other", "an explicit producer_id wins over the chain")

  -- A kind with no chain entries and no accepting producer must not resolve.
  local none, err = composer.resolve("markdown")
  H.eq(none, nil, "an input kind with no configured chain resolves to nil")
  H.ok(err, "an unresolvable kind reports an error")

  -- ------------------------------------------------------ lazy producer load
  do
    require("pdfport.producers").load_all({})

    for _, id in ipairs({
      "img2pdf",
      "magick",
      "pandoc",
      "weasyprint",
      "chromium",
      "soffice",
      "qpdf",
      "pdftk",
      "ghostscript",
    }) do
      H.ok(registry.has_producer(id), ("built-in producer %q is registered"):format(id))
      H.eq(
        package.loaded["pdfport.producers." .. id],
        nil,
        ("registering %q did not require its module"):format(id)
      )
    end

    local _ = registry.get_producer("img2pdf").available()
    H.ok(package.loaded["pdfport.producers.img2pdf"], "touching a proxy loads its real module")
    H.eq(
      package.loaded["pdfport.producers.magick"],
      nil,
      "touching one proxy does not load its siblings"
    )
  end

  -- --------------------------------------------------------------- create()

  composer._set_config({
    create_chain = { image = { "spec_p_present" } },
  })

  do
    local tmp_dir = vim.fn.stdpath("cache") .. "/pdfport_spec"
    vim.fn.mkdir(tmp_dir, "p")
    local input = tmp_dir .. "/a.png"
    vim.fn.writefile({ "x" }, input)
    local output = tmp_dir .. "/a.pdf"
    pcall(vim.fn.delete, output)

    local got
    composer.create({ inputs = { input }, from = "image" }, function(result)
      got = result
    end)
    vim.wait(200, function()
      return got ~= nil
    end)

    H.ok(got, "create() invokes the callback")
    H.eq(got.status, "ok", "a resolvable kind creates successfully")
    H.eq(got.path, output, "default output path is the input's stem + .pdf")
    H.eq(got.producer, "spec_p_present", "result reports the producer that ran")
  end

  do
    local got
    composer.create({ inputs = {} }, function(result)
      got = result
    end)
    vim.wait(200, function()
      return got ~= nil
    end)
    H.eq(got and got.status, "error", "empty inputs is a validation error")
  end

  do
    local got
    composer.create({ inputs = { "unresolvable_kind.zzz" } }, function(result)
      got = result
    end)
    vim.wait(200, function()
      return got ~= nil
    end)
    H.eq(got and got.status, "error", "an unguessable extension without opts.from is an error")
  end

  -- ------------------------------------------------------- text/bufnr inputs

  registry.register_producer(H.fake_producer("spec_p_markdown", true, { "markdown" }))
  composer._set_config({ create_chain = { markdown = { "spec_p_markdown" } } })

  do
    -- Passing more than one of inputs/text/bufnr is rejected up front.
    local got
    composer.create({ inputs = { "a.md" }, text = "# x" }, function(result)
      got = result
    end)
    vim.wait(200, function()
      return got ~= nil
    end)
    H.eq(got and got.status, "error", "inputs + text together is a validation error")
  end

  do
    -- text/bufnr without opts.from cannot guess a kind (no extension).
    local got
    composer.create({ text = "# hello" }, function(result)
      got = result
    end)
    vim.wait(200, function()
      return got ~= nil
    end)
    H.eq(got and got.status, "error", "opts.text without opts.from is a validation error")
  end

  do
    -- text/bufnr without opts.output has no default output path.
    local got
    composer.create({ text = "# hello", from = "markdown" }, function(result)
      got = result
    end)
    vim.wait(200, function()
      return got ~= nil
    end)
    H.eq(got and got.status, "error", "opts.text without opts.output is a validation error")
  end

  do
    local tmp_dir = vim.fn.stdpath("cache") .. "/pdfport_spec"
    vim.fn.mkdir(tmp_dir, "p")
    local output = tmp_dir .. "/from_text.pdf"
    pcall(vim.fn.delete, output)

    local got
    composer.create({ text = "# hello", from = "markdown", output = output }, function(result)
      got = result
    end)
    vim.wait(200, function()
      return got ~= nil
    end)

    H.ok(got, "create() with opts.text invokes the callback")
    H.eq(got.status, "ok", "opts.text materializes to a tmpfile and creates successfully")
    H.eq(got.path, output, "the explicit output path is honored")

    -- The materialized tmpfile must be cleaned up again after the callback.
    local cache_tmp_dir = vim.fn.stdpath("cache") .. "/pdfport.nvim/tmp"
    local leftover = vim.fn.glob(cache_tmp_dir .. "/*.md", false, true)
    H.eq(#leftover, 0, "the materialized tmpfile is deleted after create() completes")
  end

  -- ------------------------------------------------------------- merge (pdf)
  -- pdfport.merge() is a thin wrapper that calls composer.create() with
  -- `from = "pdf"` — exercised here at the composer level (like the rest of
  -- this file) with a fake "pdf"-accepting producer, no real qpdf/pdftk/
  -- ghostscript required.

  registry.register_producer(H.fake_producer("spec_p_pdf", true, { "pdf" }))
  composer._set_config({ create_chain = { pdf = { "spec_p_pdf" } } })

  H.ok(composer.can_create("pdf"), "can_create('pdf') is true once a merge producer resolves")

  do
    local tmp_dir = vim.fn.stdpath("cache") .. "/pdfport_spec"
    vim.fn.mkdir(tmp_dir, "p")
    local a, b = tmp_dir .. "/m1.pdf", tmp_dir .. "/m2.pdf"
    vim.fn.writefile({ "x" }, a)
    vim.fn.writefile({ "x" }, b)
    local output = tmp_dir .. "/merged.pdf"
    pcall(vim.fn.delete, output)

    local got
    composer.create({ inputs = { a, b }, from = "pdf", output = output }, function(result)
      got = result
    end)
    vim.wait(200, function()
      return got ~= nil
    end)

    H.ok(got, "merge (create with from='pdf') invokes the callback")
    H.eq(got.status, "ok", "merging two pdfs resolves and succeeds")
    H.eq(got.path, output, "the explicit merge output path is honored")
    H.eq(got.producer, "spec_p_pdf", "result reports the merge producer that ran")
  end

  -- The real init.lua public API surface: pdfport.merge() rejects bad input
  -- shapes before ever touching the composer.
  do
    local pdfport = require("pdfport")
    H.falsy(
      pcall(pdfport.merge, { inputs = { "only_one.pdf" }, output = "out.pdf" }),
      "pdfport.merge: fewer than 2 inputs is rejected"
    )
    H.falsy(
      pcall(pdfport.merge, { inputs = { "a.pdf", "b.pdf" } }),
      "pdfport.merge: missing opts.output is rejected"
    )
  end
end
