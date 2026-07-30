-- TESTS/registry_spec.lua — pdfport.core.registry + the lazy backend proxies
--
-- The lazy-proxy behaviour is the interesting part: backends must NOT be
-- required at setup() time, only when the resolver walks far enough to
-- consider one. A regression there would drag every backend's top-level
-- requires into startup.

return function(H)
  local registry = require("pdfport.core.registry")

  -- ------------------------------------------------------ backend registry

  registry.register_backend(H.fake_backend("spec_alpha", true))
  H.ok(registry.has_backend("spec_alpha"), "a registered backend is found")
  H.eq(registry.get_backend("spec_alpha").id, "spec_alpha", "get_backend returns it")
  H.eq(registry.get_backend("spec_nonexistent"), nil, "an unknown id returns nil")

  -- Registration is documented as idempotent: re-registering the same id
  -- replaces the entry without adding a second slot to the order list.
  local before = #registry.backend_ids()
  registry.register_backend(H.fake_backend("spec_alpha", false))
  H.eq(#registry.backend_ids(), before, "re-registering an id does not duplicate it")
  H.eq(registry.get_backend("spec_alpha").available(), false, "re-registering replaces the entry")

  -- Order is insertion order, and that ordering is what the resolver's
  -- fallback chain falls back on.
  registry.register_backend(H.fake_backend("spec_beta", true))
  local ids = registry.backend_ids()
  H.eq(ids[#ids], "spec_beta", "the newest backend is last in insertion order")

  -- backend_ids/all_backends must hand out copies — a caller mutating the
  -- returned list must not corrupt the registry's own order.
  local snapshot = registry.backend_ids()
  snapshot[#snapshot + 1] = "spec_injected"
  H.eq(#registry.backend_ids(), #snapshot - 1, "backend_ids returns a copy, not the internal list")

  -- --------------------------------------------------------- input guards

  H.falsy(pcall(registry.register_backend, nil), "a nil backend is rejected")
  H.falsy(pcall(registry.register_backend, { id = "" }), "an empty id is rejected")
  H.falsy(
    pcall(registry.register_backend, { id = "x", available = true, extract = function() end }),
    "a non-function available is rejected"
  )

  -- ----------------------------------------------------- renderer registry

  registry.register_renderer("spec_mode", function() end)
  H.eq(type(registry.get_renderer("spec_mode")), "function", "a renderer is retrievable by mode")
  H.eq(registry.get_renderer("spec_missing"), nil, "an unknown mode returns nil")
  H.falsy(
    pcall(registry.register_renderer, "x", "not a function"),
    "a non-function renderer is rejected"
  )

  -- ------------------------------------------------------ lazy backend load
  do
    -- load_all registers proxies for every built-in. Touching none of them
    -- must leave every real backend module unloaded.
    require("pdfport.backends").load_all({})

    for _, id in ipairs({
      "pdftotext",
      "pdfplumber",
      "marker",
      "docling",
      "ollama",
      "tesseract",
      "claude",
    }) do
      H.ok(registry.has_backend(id), ("built-in backend %q is registered"):format(id))
      H.eq(
        package.loaded["pdfport.backends." .. id],
        nil,
        ("registering %q did not require its module"):format(id)
      )
    end

    -- Touching one proxy loads exactly that one, and no others.
    local _ = registry.get_backend("pdftotext").available()
    H.ok(package.loaded["pdfport.backends.pdftotext"], "touching a proxy loads its real module")
    H.eq(
      package.loaded["pdfport.backends.marker"],
      nil,
      "touching one proxy does not load its siblings"
    )
  end

  -- ------------------------------------------------------------ diagnostics

  local lines = registry.diagnostics()
  H.ok(#lines > 0, "diagnostics produces output")
  H.eq(type(lines[1]), "string", "diagnostics returns a list of strings")
end
