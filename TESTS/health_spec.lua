-- TESTS/health_spec.lua — `:checkhealth pdfport`.
--
-- A health report is the first thing a user reads when a backend "does
-- nothing", so the failure mode that matters is a report that is quietly
-- wrong: a tool reported missing because the check looked only at PATH, a
-- section that contradicts another one, a probe that shells out to a daemon
-- on a machine that has none.
--
-- `vim.health` is replaced with a recorder and `pdfport.platform` with a
-- stand-in whose installed-tool set the spec chooses, so every branch is
-- reachable and the report is the same on a bare CI runner as on a fully
-- equipped machine. Nothing here spawns a process: the one probe that would
-- (`curl` against the ollama daemon) is behind an `ollama` gate this spec
-- never opens.

return function(H)
  ---Run `pdfport.health.check()` against a chosen environment.
  ---@param present table<string, boolean>  what platform.has reports installed
  ---@param extra table  further package.loaded replacements
  ---@param python string|nil
  ---@return table report  { ok = string[], warn = …, error = …, info = …, start = … }
  local function check(present, extra, python)
    local report = { ok = {}, warn = {}, error = {}, info = {}, start = {} }
    -- `vim.health.warn(msg, advice)` -- the advice list is where the install
    -- command lives, and "how do I fix it" is half of what a report is for,
    -- so both halves are recorded as one line.
    local function record(kind)
      return function(msg, advice)
        local line = tostring(msg)
        if type(advice) == "table" then line = line .. " || " .. table.concat(advice, " | ") end
        report[kind][#report[kind] + 1] = line
      end
    end

    local saved_health = vim.health
    vim.health = {
      ok = record("ok"),
      warn = record("warn"),
      error = record("error"),
      info = record("info"),
      start = record("start"),
    }

    local replacements = {
      ["pdfport.platform"] = H.fake_platform(present, python),
      ["lib.nvim.deps.spec"] = {
        find = function()
          return "/fake/install.json"
        end,
        load = function()
          return { tools = { { bin = "soffice" }, { bin = "chrome" } } }
        end,
      },
      ["lib.nvim.deps.detect"] = {
        found_as = function(tool)
          return present[tool.bin] and tool.bin or nil
        end,
      },
      ["lib.nvim.deps.health"] = {
        pointer_for = function(name)
          report.info[#report.info + 1] = "deps pointer for " .. name
        end,
      },
      ["pdfport.producers.chromium"] = {
        resolved_browser = function()
          return present.chromium and "chromium" or nil
        end,
      },
      ["pdfport.health"] = H.UNLOAD,
    }
    for k, v in pairs(extra) do
      replacements[k] = v
    end

    local ok, err = pcall(H.with_modules, replacements, function()
      require("pdfport.health").check()
    end)
    vim.health = saved_health
    if not ok then error(err, 0) end
    return report
  end

  ---Is there a line of `kind` matching `pat`?
  ---@param report table
  ---@param kind string
  ---@param pat string
  ---@return boolean
  local function has(report, kind, pat)
    for _, line in ipairs(report[kind]) do
      if line:match(pat) then return true end
    end
    return false
  end

  local saved_anthropic, saved_gemini = vim.env.ANTHROPIC_API_KEY, vim.env.GEMINI_API_KEY

  -- ------------------------------------------------- a fully equipped machine

  vim.env.ANTHROPIC_API_KEY = "sk-ant-spec"
  vim.env.GEMINI_API_KEY = "gem-spec"

  local full = check({
    pdftotext = true,
    marker_single = true,
    ollama = false,
    tesseract = true,
    curl = true,
    img2pdf = true,
    magick = true,
    pandoc = true,
    xelatex = true,
    weasyprint = true,
    chromium = true,
    soffice = true,
    qpdf = true,
    pdftk = true,
    gs = true,
    pdftoppm = true,
    chafa = true,
    python3 = true,
    ["pymod:pdfplumber"] = true,
    ["pymod:docling"] = true,
  }, {}, "python3")

  -- Every section the report promises has to actually be started, or its
  -- lines end up filed under the previous heading.
  for _, section in ipairs({
    "pdfport: core",
    "pdfport: extraction backends",
    "pdfport: creation producers",
    "pdfport: merge producers",
    "pdfport: renderers",
    "pdfport: terminal image renderer",
    "pdfport: integrations",
    "pdfport: registered backends",
    "pdfport: registered producers",
  }) do
    H.ok(has(full, "start", vim.pesc(section)), ("the %q section is reported"):format(section))
  end

  H.eq(#full.error, 0, "a fully equipped machine reports no errors at all")
  H.ok(has(full, "ok", "pdfport%.platform loads"), "the core modules are reported as loading")
  H.ok(has(full, "ok", "pdfport%.core%.registry loads"), "including the registry")
  H.ok(has(full, "ok", "pdfport%.core%.dispatcher loads"), "and the dispatcher")

  H.ok(has(full, "ok", "pdftotext backend: ready"), "pdftotext is reported ready")
  H.ok(has(full, "ok", "pdfplumber: available"), "pdfplumber is reported available")
  H.ok(has(full, "ok", "docling: available"), "as is docling")
  H.ok(has(full, "ok", "marker backend: ready"), "and marker")
  H.ok(has(full, "ok", "tesseract backend: ready"), "and tesseract")
  H.ok(has(full, "ok", "ANTHROPIC_API_KEY set"), "a present Anthropic key is reported")
  H.falsy(has(full, "ok", "sk%-ant%-spec"), "without printing the key itself, only its length")
  H.ok(has(full, "ok", "GEMINI_API_KEY set"), "and a present Gemini key likewise")

  H.ok(has(full, "ok", "img2pdf producer: ready"), "img2pdf is reported ready")
  H.ok(has(full, "ok", "magick producer: ready"), "magick too")
  -- The pandoc line names the engine it found, because "pandoc is installed"
  -- is only half the answer -- pandoc alone cannot make a PDF.
  H.ok(has(full, "ok", "pandoc producer: ready.*engine: xelatex"), "pandoc reports its PDF engine")
  H.ok(has(full, "ok", "weasyprint producer: ready"), "weasyprint is reported ready")
  H.ok(
    has(full, "ok", "chromium producer: ready.*browser: chromium"),
    "and chromium names its browser"
  )
  H.ok(has(full, "ok", "soffice producer: ready"), "soffice is reported ready")
  H.ok(has(full, "ok", "qpdf producer: ready"), "qpdf is reported ready")
  H.ok(has(full, "ok", "pdftk producer: ready"), "pdftk too")
  H.ok(has(full, "ok", "ghostscript producer: ready.*exe: gs"), "and ghostscript names its binary")

  H.ok(has(full, "ok", "buffer renderer"), "the built-in renderers are reported")
  H.ok(has(full, "ok", "system renderer: xdg%-open"), "with the system opener named")
  H.ok(has(full, "ok", "best renderer: chafa"), "and the terminal image tool that was picked")
  H.ok(has(full, "ok", "netrw: built%-in"), "netrw is always available")
  H.ok(has(full, "info", "deps pointer for pdfport%.nvim"), "the declared-tools pointer is emitted")

  -- The live registry: setup() has run by now, so every built-in must be
  -- listed with its availability.
  H.ok(
    has(full, "ok", "pdftotext%s+available") or has(full, "warn", "pdftotext%s+unavailable"),
    "each registered backend is listed with its live availability"
  )
  H.ok(
    has(full, "ok", "img2pdf%s+available") or has(full, "warn", "img2pdf%s+unavailable"),
    "and so is each registered producer"
  )

  -- ---------------------------------------------------------- a bare machine

  vim.env.ANTHROPIC_API_KEY = nil
  vim.env.GEMINI_API_KEY = nil

  local bare = check({}, {}, nil)

  H.eq(#bare.error, 0, "a machine with no tools at all is a pile of warnings, not errors")
  H.ok(has(bare, "warn", "pdftotext backend: not on PATH"), "pdftotext is reported missing")
  H.ok(has(bare, "warn", "no python interpreter"), "and the missing interpreter is called out once")
  H.falsy(
    has(bare, "warn", "pdfplumber: not installed"),
    "rather than reporting each python module missing on top of it"
  )
  H.ok(has(bare, "warn", "marker backend"), "marker is reported missing")
  H.ok(
    has(bare, "info", "ollama: not installed"),
    "ollama is info, not a warning -- it is optional"
  )
  H.ok(has(bare, "warn", "pandoc producer: not on PATH"), "pandoc is reported missing")
  H.ok(
    has(bare, "info", "chromium producer: no Chromium%-family browser"),
    "and the browser fallback is info, since weasyprint is the first choice"
  )
  H.ok(has(bare, "warn", "soffice producer: not found"), "soffice is reported missing")
  H.ok(has(bare, "warn", "ghostscript producer: no gs"), "as is every Ghostscript spelling")
  H.ok(has(bare, "warn", "no terminal image renderer"), "and the terminal image tool")

  -- Missing keys are only reported when curl is there to use them: the two
  -- remote backends have no other external tool, so a machine without curl
  -- has nothing to say about their keys.
  H.falsy(has(bare, "warn", "ANTHROPIC_API_KEY"), "with no curl, the API keys are not mentioned")

  local with_curl = check({ curl = true }, {}, nil)
  H.ok(has(with_curl, "warn", "ANTHROPIC_API_KEY not set"), "with curl, a missing key is a warning")
  H.ok(has(with_curl, "warn", "GEMINI_API_KEY not set"), "for both remote backends")
  -- curl itself is optional, not required: backends/claude.lua's own
  -- available() returns false without it rather than failing, and
  -- docs/install.json declares it optional. A `required` here made one run
  -- contradict itself.
  H.falsy(has(bare, "error", "curl"), "curl is never reported as a required tool")
  H.ok(has(bare, "info", "curl NOT found on PATH %(optional%)"), "only as an optional one")

  -- -------------------------------------------------- the in-between cases

  -- pandoc present but no engine: the one case where "the tool is installed"
  -- and "the producer works" genuinely differ.
  local no_engine = check({ pandoc = true }, {}, nil)
  H.ok(has(no_engine, "ok", "pandoc found on PATH"), "pandoc itself is found")
  H.ok(
    has(no_engine, "warn", "pandoc found but no PDF engine"),
    "but the producer is reported unusable without an engine"
  )
  H.ok(has(no_engine, "warn", "tectonic"), "with the engines to choose from named")

  -- ai.nvim is optional and reported once, up front, rather than three times
  -- over in the claude/gemini/ollama lines.
  H.ok(has(bare, "info", "ai%.nvim not installed"), "a missing ai.nvim is info, not a warning")
  H.ok(
    has(bare, "info", "every other extraction backend still works"),
    "and the report says what still works without it"
  )

  local with_ai = check({}, {
    ["ai"] = { ask = function() end },
  }, nil)
  H.ok(has(with_ai, "ok", "ai%.nvim found"), "an installed ai.nvim is reported as found")

  -- lib.nvim is the one hard dependency, and the report says so. Its
  -- *absence* is deliberately not simulated here: `M.check()`'s last line
  -- calls the composer unguarded, so a run without lib.nvim raises before the
  -- report can be read back -- and pdfport does not load at all without it
  -- anyway, since bindings/usrcmds.lua requires the composer at module level.
  H.ok(has(bare, "ok", "lib%.nvim found"), "lib.nvim is reported as the dependency it is")

  -- ui.nvim, by contrast, is a soft enhancement: without it the picker falls
  -- back to vim.ui.select, so its absence is info.
  H.ok(has(bare, "info", "ui%.kit not found"), "a missing ui.kit is info, not a warning")

  vim.env.ANTHROPIC_API_KEY = saved_anthropic
  vim.env.GEMINI_API_KEY = saved_gemini
end
