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

    for _, id in ipairs({ "img2pdf", "magick" }) do
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
end
