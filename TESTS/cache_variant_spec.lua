-- TESTS/cache_variant_spec.lua — the extraction cache's key discriminator.
--
-- `pdfport.util.cache` keys an entry by `path::backend::variant`, and this is
-- the variant. It decides what counts as "the same extraction of this file",
-- so getting it wrong does not raise anything: it silently hands back an
-- answer to a different question, looking freshly computed.
--
-- The dispatcher's own helper is exercised directly rather than through
-- `pdfport.extract()`: it is a pure function of the merged extract options,
-- and going through the dispatcher would mean calling `setup()`, which
-- `open_done_spec.lua` also does and which is not re-entrant.

return function(H)
  local dispatcher = require("pdfport.core.dispatcher")
  local variant = dispatcher._cache_variant

  -- ----------------------------------------------- backends with no prompt

  -- pdftotext, pdfplumber, marker, docling and tesseract take neither a
  -- prompt nor a model. Their keys must stay byte-for-byte what they were
  -- before prompt/model entered the picture, or every cache entry on every
  -- existing installation is silently orphaned by an upgrade.
  H.eq(variant({}), "all", 'no pages and no prompt is still plain "all"')
  H.eq(variant({ max_pages = 5 }), "5", "max_pages alone is still just the number")
  H.eq(variant({ pages = { 1, 2, 3 } }), "1,2,3", "a page list alone is still the list")
  H.eq(variant({ pages = {} }), "all", 'an empty page list falls back to "all", as before')

  -- ------------------------------------------------- prompt discriminates

  local list_tables = variant({ prompt = "List every table." })
  local summarise = variant({ prompt = "Summarise in one sentence." })
  H.ok(list_tables ~= summarise, "two different prompts must not share a cache entry")
  H.ok(
    list_tables ~= "all",
    "a prompted extraction must not share the unprompted backends' key either"
  )

  H.eq(
    variant({ prompt = "List every table." }),
    list_tables,
    "the same prompt is stable across calls -- otherwise nothing ever hits the cache"
  )

  -- ------------------------------------------------- model discriminates

  local flash = variant({ model = "gemini-2.5-flash" })
  local pro = variant({ model = "gemini-2.5-pro" })
  H.ok(flash ~= pro, "two different models must not share a cache entry")

  -- And the two are independent: same prompt, different model, still distinct.
  H.ok(
    variant({ prompt = "p", model = "a" }) ~= variant({ prompt = "p", model = "b" }),
    "model still discriminates when the prompt is held fixed"
  )
  H.ok(
    variant({ prompt = "a", model = "m" }) ~= variant({ prompt = "b", model = "m" }),
    "prompt still discriminates when the model is held fixed"
  )

  -- ------------------------------------------------- page range still counts

  H.ok(
    variant({ pages = { 1 }, prompt = "p" }) ~= variant({ pages = { 2 }, prompt = "p" }),
    "the page range keeps discriminating once a prompt is in play"
  )

  -- ------------------------------------------------- the key stays a key

  -- The prompt is hashed, not embedded: it is arbitrary user text, and a
  -- multi-kilobyte prompt must not become a multi-kilobyte cache key.
  local long = variant({ prompt = string.rep("x", 20000) })
  H.ok(#long < 100, "a 20 KB prompt must not produce a 20 KB key, got " .. #long)

  -- A prompt containing the separator must not be able to collide with a
  -- different prompt/model pair by forging one.
  local forged = variant({ prompt = "p::deadbeef00000000::gemini-2.5-pro" })
  local real = variant({ prompt = "p", model = "gemini-2.5-pro" })
  H.ok(forged ~= real, "a prompt containing the separator must not forge another key")
end
