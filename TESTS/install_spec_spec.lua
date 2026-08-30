-- TESTS/install_spec_spec.lua — pdfport's own docs/install.json.
--
-- This file is data, and data is where a typo goes unnoticed: nothing in the
-- plugin requires it, no `luacheck` run reads it, and a broken entry surfaces
-- only as a tool quietly missing from `:checkhealth pdfport` and
-- `:Lib deps show`. A tool that is simply absent from a report looks exactly
-- like a tool nobody declared.
--
-- So: parse the real file with the real parser and insist it validates
-- completely, then pin the two entries whose shape is load-bearing rather
-- than incidental.

return function(H)
  local eq, ok = H.eq, H.ok

  local spec = require("lib.nvim.deps.spec")
  local detect = require("lib.nvim.deps.detect")

  local root = vim.fs.normalize(debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") .. "..")
  local path = root .. "/docs/install.json"

  local result, err = spec.load(path)
  ok(result ~= nil, "docs/install.json is readable: " .. tostring(err))
  ---@cast result -nil

  -- Zero, not "few": a rejected entry is silently dropped from `tools`, so a
  -- partial parse is indistinguishable from a shorter file.
  eq(#result.errors, 0, "docs/install.json validates with no errors")
  ok(#result.tools > 0, "docs/install.json declares at least one tool")

  ---@param bin string
  ---@return table|nil
  local function tool(bin)
    for _, t in ipairs(result.tools) do
      if t.bin == bin then return t end
    end
    return nil
  end

  -- Ghostscript is `gs` on Linux/macOS and `gswin64c`/`gswin32c` on Windows.
  -- Without the alternatives a Windows host reports "ghostscript producer:
  -- ready (exe: gswin64c)" in one section and "gs NOT found" in the next --
  -- one run, two answers.
  do
    local gs = tool("gs")
    ok(gs ~= nil, "gs is declared")
    ---@cast gs -nil
    eq(
      table.concat(gs.bin_alternatives or {}, ","),
      "gswin64c,gswin32c",
      "gs declares its Windows spellings"
    )
    eq(
      table.concat(detect.names(gs), ","),
      "gs,gswin64c,gswin32c",
      "detection probes all three, canonical first"
    )
  end

  -- curl is optional: only the claude backend and the ollama daemon check use
  -- it, and `backends/claude.lua`'s own `available()` returns false without
  -- it. `health.lua` used to report it as required, which made the same
  -- `:checkhealth` run contradict this file.
  do
    local curl = tool("curl")
    ok(curl ~= nil, "curl is declared")
    ---@cast curl -nil
    eq(curl.required, false, "curl is declared optional")
  end

  -- Every declared tool is optional, and that is the plugin's actual
  -- contract: pdfport degrades to whatever is installed, and the pdftotext
  -- path needs nothing this file lists to be present.
  for _, t in ipairs(result.tools) do
    eq(t.required, false, ("%s is declared optional"):format(t.bin))
  end

  -- Two things the parser already enforces, pinned here because they are the
  -- fields a hand-edited entry gets wrong: a non-empty `why` and at least one
  -- real package-manager key.
  for _, t in ipairs(result.tools) do
    ok(t.why and #t.why > 0, ("%s says why it matters"):format(t.bin))
    ok(next(t.pkg) ~= nil, ("%s names at least one package"):format(t.bin))
  end
end
