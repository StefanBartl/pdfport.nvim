-- TESTS/smoke_spec.lua — every module loads, and setup() wires the plugin up.
--
-- This is the "clearest gap" the docs/ROADMAP audit named: nothing previously
-- caught a syntax error or a bad require in a module that only runs when an
-- external tool happens to be installed.

return function(H)
  -- ------------------------------------------------------ every module loads

  -- Backends are deliberately included: they are lazy at runtime, so without
  -- an explicit require here a typo inside one would only surface on a
  -- machine that has that particular tool installed.
  local modules = {
    "pdfport",
    "pdfport.config",
    "pdfport.config.DEFAULTS",
    "pdfport.core.registry",
    "pdfport.core.resolver",
    "pdfport.core.dispatcher",
    "pdfport.core.composer",
    "pdfport.backends",
    "pdfport.backends.pdftotext",
    "pdfport.backends.pdfplumber",
    "pdfport.backends.marker",
    "pdfport.backends.docling",
    "pdfport.backends.ollama",
    "pdfport.backends.tesseract",
    "pdfport.backends.claude",
    "pdfport.producers",
    "pdfport.producers.img2pdf",
    "pdfport.producers.magick",
    "pdfport.renderers.buffer",
    "pdfport.renderers.float",
    "pdfport.renderers.system",
    "pdfport.renderers.terminal",
    "pdfport.platform",
    "pdfport.util.batch",
    "pdfport.util.cache",
    "pdfport.util.notify",
    "pdfport.util.page_range",
    "pdfport.util.picker",
    "pdfport.health",
  }

  for _, mod in ipairs(modules) do
    local ok, err = pcall(require, mod)
    H.ok(ok, ("module %s loads: %s"):format(mod, tostring(err)))
  end

  -- ------------------------------------------------------------------ setup

  local pdfport = require("pdfport")
  H.eq(type(pdfport.setup), "function", "pdfport exposes setup()")

  local ok, err = pcall(pdfport.setup, {})
  H.ok(ok, ("setup({}) succeeds: %s"):format(tostring(err)))

  -- setup() is documented as idempotent — a second call must not error or
  -- double-register commands.
  local ok2, err2 = pcall(pdfport.setup, {})
  H.ok(ok2, ("setup() is idempotent: %s"):format(tostring(err2)))

  -- After setup the built-ins and the four renderers must be present.
  local registry = require("pdfport.core.registry")
  H.ok(registry.has_backend("pdftotext"), "setup registers the built-in backends")
  for _, mode in ipairs({ "buffer", "float", "system", "terminal" }) do
    H.ok(registry.get_renderer(mode), ("setup registers the %q renderer"):format(mode))
  end

  -- ------------------------------------------------------------- user command

  local cmds = vim.api.nvim_get_commands({})
  H.ok(cmds.PdfPort or cmds.Pdfport, "setup registers the :PdfPort user command")

  -- ------------------------------------------------------------ checkhealth

  -- Every plugin in this collection is expected to support :checkhealth.
  H.eq(type(require("pdfport.health").check), "function", "health.check is callable")
end
