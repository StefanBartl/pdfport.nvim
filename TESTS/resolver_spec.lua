-- TESTS/resolver_spec.lua — pdfport.core.resolver fallback-chain resolution
--
-- Every backend here is a fake with a hard-coded `available`, so the chain
-- logic is exercised without depending on pdftotext/python/ollama actually
-- being installed on the machine running the suite.

return function(H)
  local registry = require("pdfport.core.registry")
  local resolver = require("pdfport.core.resolver")

  -- Distinct ids so this spec cannot collide with registry_spec's fakes or
  -- with the real built-ins.
  registry.register_backend(H.fake_backend("res_missing", false))
  registry.register_backend(H.fake_backend("res_present", true))
  registry.register_backend(H.fake_backend("res_other", true))

  -- ------------------------------------------------- explicit request first

  resolver._set_config({ fallback_chain = { "res_present" } })

  local b = resolver.resolve("res_other")
  H.eq(b and b.id, "res_other", "an explicitly requested available backend wins")

  -- An explicit request that is unavailable falls through to the chain rather
  -- than failing outright — the request is a preference, not a constraint.
  b = resolver.resolve("res_missing")
  H.eq(b and b.id, "res_present", "an unavailable explicit request falls back to the chain")

  -- ------------------------------------------------------- configured chain

  resolver._set_config({ fallback_chain = { "res_missing", "res_present", "res_other" } })
  b = resolver.resolve("auto")
  H.eq(b and b.id, "res_present", "auto walks the chain and skips unavailable entries")

  -- default_backend takes precedence over chain order.
  resolver._set_config({
    default_backend = "res_other",
    fallback_chain = { "res_present" },
  })
  b = resolver.resolve("auto")
  H.eq(b and b.id, "res_other", "default_backend is tried before the fallback chain")

  -- nil is treated as "auto", not as an unnamed backend.
  b = resolver.resolve(nil)
  H.eq(b and b.id, "res_other", "a nil request behaves like auto")

  -- ------------------------------------------------------ nothing available

  resolver._set_config({ fallback_chain = { "res_missing" } })
  local none, err = resolver.resolve("res_missing")
  H.eq(none, nil, "no available backend resolves to nil")
  H.ok(err, "an unresolvable request reports an error")
  H.match(err, "res_missing", "the error names the backends that were tried")

  -- An id that was never registered must not raise, just miss.
  local ghost, ghost_err = resolver.resolve("res_never_registered")
  H.eq(ghost, nil, "an unregistered id resolves to nil")
  H.ok(ghost_err, "an unregistered id reports an error rather than raising")

  -- ---------------------------------------------------- available_backends

  resolver._set_config({ fallback_chain = { "res_missing", "res_present", "res_other" } })
  local avail = resolver.available_backends()
  local seen = {}
  for _, backend in ipairs(avail) do
    seen[backend.id] = true
  end
  H.ok(seen["res_present"], "available_backends includes an available backend")
  H.ok(seen["res_other"], "available_backends includes the second available backend")
  H.falsy(seen["res_missing"], "available_backends excludes unavailable backends")

  -- A backend must not be listed twice just because it appears both in the
  -- configured chain and in the registry's own insertion order.
  local count = 0
  for _, backend in ipairs(avail) do
    if backend.id == "res_present" then count = count + 1 end
  end
  H.eq(count, 1, "a backend in both the chain and the registry is listed once")
end
