-- TESTS/ai_backends_spec.lua — the claude/gemini/ollama backends' contract
-- with ai.nvim.
--
-- Those three are the only backends that talk to an HTTP API, and they do it
-- through ai.nvim's `ask()` rather than their own curl path. Two things about
-- that arrangement are worth pinning down, and neither needs a network or an
-- API key:
--
--   1. ai.nvim is OPTIONAL. Without it installed, both backends must report
--      themselves unavailable and — if called anyway — fail with a message
--      naming the missing dependency, not raise. pdfport advertises lib.nvim
--      as its one real plugin dependency, and that has to stay true for
--      everyone who does not use these two backends.
--   2. The request pdfport builds is the one the API needs: the PDF as a
--      `document` attachment for claude and gemini, the page image as an
--      `image` one for ollama, with pdfport's own model/host/key overrides
--      carried per request rather than through the user's environment.
--
-- `ai` and `ai.attachments` are faked through `package.preload`, so this
-- runs identically on a machine with ai.nvim installed and one without.

return function(H)
  local BACKENDS = {
    "pdfport.backends.claude",
    "pdfport.backends.gemini",
    "pdfport.backends.ollama",
  }

  ---Drop both backends so the next `require` re-runs their module body.
  local function unload_backends()
    for _, mod in ipairs(BACKENDS) do
      package.loaded[mod] = nil
    end
  end

  ---Run `fn` with `ai`/`ai.attachments` faked, restoring both afterwards.
  ---@param fake_ai table|nil nil means "ai.nvim is not installed"
  ---@param fake_attachments table|nil
  ---@param fn fun()
  local function with_ai(fake_ai, fake_attachments, fn)
    local saved_loaded = { ["ai"] = package.loaded["ai"] }
    local saved_preload = { ["ai"] = package.preload["ai"] }
    saved_loaded["ai.attachments"] = package.loaded["ai.attachments"]
    saved_preload["ai.attachments"] = package.preload["ai.attachments"]

    package.loaded["ai"] = fake_ai
    package.loaded["ai.attachments"] = fake_attachments
    if fake_ai == nil then
      -- A real ai.nvim on the runtimepath would still be found by `require`
      -- even with `package.loaded` cleared; a preload that errors is what
      -- actually simulates "not installed" on either kind of machine.
      package.preload["ai"] = function()
        error("module 'ai' not found")
      end
      package.preload["ai.attachments"] = function()
        error("module 'ai.attachments' not found")
      end
    end

    unload_backends()
    local ok, err = pcall(fn)

    package.loaded["ai"] = saved_loaded["ai"]
    package.loaded["ai.attachments"] = saved_loaded["ai.attachments"]
    package.preload["ai"] = saved_preload["ai"]
    package.preload["ai.attachments"] = saved_preload["ai.attachments"]
    unload_backends()

    if not ok then error(err, 0) end
  end

  ---An `ai` stand-in that records the request it was handed and answers it.
  ---@param answer string
  ---@return table fake, table captured
  local function fake_ai(answer)
    local captured = {}
    return {
      ask = function(req, cb)
        captured[#captured + 1] = req
        cb(true, { text = answer, provider = req.provider })
      end,
    },
      captured
  end

  ---An `ai.attachments` stand-in: no filesystem, no base64.
  ---@param kind "image"|"document"
  ---@param media_type string
  ---@return table
  local function fake_attachments(kind, media_type)
    return {
      from_file = function(path)
        return { kind = kind, media_type = media_type, data = "BASE64", name = path }, nil
      end,
    }
  end

  -- ------------------------------------------- 1. ai.nvim is optional

  with_ai(nil, nil, function()
    for _, mod in ipairs(BACKENDS) do
      local backend = require(mod)
      H.falsy(backend.available(), mod .. " is unavailable without ai.nvim")
    end
  end)

  with_ai(nil, nil, function()
    -- Called anyway (a caller naming the backend explicitly): a message, not
    -- a raised error, and delivered the way the dispatcher expects.
    local claude = require("pdfport.backends.claude")
    local result = claude.extract("/tmp/x.pdf", {})
    H.ok(result, "claude.extract returns a result synchronously without ai.nvim")
    H.eq(result.status, "error", "that result is an error")
    H.match(result.error, "ai%.nvim", "and it names the missing dependency")

    local gemini = require("pdfport.backends.gemini")
    local gemini_result = gemini.extract("/tmp/x.pdf", {})
    H.ok(gemini_result, "gemini.extract returns a result synchronously without ai.nvim")
    H.eq(gemini_result.status, "error", "that result is an error too")
    H.match(gemini_result.error, "ai%.nvim", "and names the missing dependency")

    local ollama = require("pdfport.backends.ollama")
    local ollama_result = ollama.extract("/tmp/x.pdf", {})
    H.ok(ollama_result, "ollama.extract returns a result synchronously without ai.nvim")
    H.eq(ollama_result.status, "error", "that result is an error too")
    H.match(ollama_result.error, "ai%.nvim", "and names the missing dependency")
  end)

  -- ------------------------------------------- 2. the request pdfport builds

  local ai_stub, claude_requests = fake_ai("# Extracted")
  with_ai(ai_stub, fake_attachments("document", "application/pdf"), function()
    local claude = require("pdfport.backends.claude")
    claude._set_config({ claude_api_key = "from-config" })

    local got
    local returned = claude.extract("/tmp/report.pdf", {
      model = "claude-opus-4-5",
      timeout_ms = 12345,
      __callback = function(result)
        got = result
      end,
    })

    H.eq(returned, nil, "claude.extract answers through __callback, not a return value")
    H.eq(#claude_requests, 1, "exactly one request was sent")

    local req = claude_requests[1]
    H.eq(req.provider, "claude", "the request names the claude provider")
    H.eq(req.model, "claude-opus-4-5", "and pdfport's model, not ai.nvim's default")
    H.eq(req.api_key, "from-config", "opts.claude_api_key is carried per request")
    H.eq(req.timeout_ms, 12345, "as is the timeout")
    H.eq(#req.attachments, 1, "the PDF travels as one attachment")
    H.eq(req.attachments[1].kind, "document", "sent whole, as a document")
    H.eq(req.attachments[1].media_type, "application/pdf", "with the right media type")

    H.eq(got.status, "ok", "a successful answer becomes an ok result")
    H.eq(got.text, "# Extracted", "carrying the model's text")
    H.eq(got.format, "markdown", "declared as markdown")
    H.eq(got.backend, "claude", "and attributed to this backend")
  end)

  -- An error from ai.nvim arrives as a `LibErrorValue`, not a string, and has
  -- to be unwrapped -- a bare tostring() would put "table: 0x..." in front of
  -- the user.
  with_ai(
    {
      ask = function(_, cb)
        cb(false, { kind = "timeout", message = "claude: request timed out after 60000 ms" })
      end,
    },
    fake_attachments("document", "application/pdf"),
    function()
      local claude = require("pdfport.backends.claude")
      claude._set_config({ claude_api_key = "k" })
      local got
      claude.extract("/tmp/report.pdf", {
        __callback = function(result)
          got = result
        end,
      })
      H.eq(got.status, "error", "a failed request becomes an error result")
      H.match(got.error, "timed out", "with the error's own message, not its table address")
    end
  )

  local gemini_stub, gemini_requests = fake_ai("# From Gemini")
  with_ai(gemini_stub, fake_attachments("document", "application/pdf"), function()
    local gemini = require("pdfport.backends.gemini")
    gemini._set_config({ gemini_api_key = "from-config" })

    local got
    gemini.extract("/tmp/report.pdf", {
      __callback = function(result)
        got = result
      end,
    })

    H.eq(#gemini_requests, 1, "exactly one request was sent")
    local req = gemini_requests[1]
    H.eq(req.provider, "gemini", "the request names the gemini provider")
    H.eq(req.model, "gemini-2.5-flash", "with pdfport's own default model")
    H.eq(req.api_key, "from-config", "opts.gemini_api_key is carried per request")
    -- The whole point of this backend existing rather than a rasterizing
    -- one: gemini is the only provider besides claude that ai.nvim can send
    -- a document to, so the PDF goes whole and no page is ever rendered.
    H.eq(#req.attachments, 1, "the PDF travels as one attachment")
    H.eq(req.attachments[1].kind, "document", "sent whole, as a document")

    H.eq(got.status, "ok", "a successful answer becomes an ok result")
    H.eq(got.text, "# From Gemini", "carrying the model's text")
    H.eq(got.backend, "gemini", "attributed to this backend")
  end)

  local ollama_stub, ollama_requests = fake_ai("page text")
  with_ai(ollama_stub, fake_attachments("image", "image/png"), function()
    local ollama = require("pdfport.backends.ollama")
    ollama._set_config({ ollama_host = "http://192.168.1.4:11434", ollama_model = "llava" })

    -- The text route: no rasterization, so this needs neither pdftoppm nor a
    -- real PDF -- `pdftotext` is spawned, fails on a missing file, and its
    -- empty stdout still produces a well-formed request.
    local got
    ollama.extract("/tmp/missing.pdf", {
      model = "llama3.2",
      pages = { 1 },
      __callback = function(result)
        got = result
      end,
    })
    -- extract() defers its first step through vim.schedule, and vim.system's
    -- callback lands off the main loop -- so the request is not in flight yet
    -- when extract() returns.
    vim.wait(3000, function()
      return got ~= nil
    end, 20)

    H.ok(got, "the text route completed")
    H.eq(#ollama_requests, 1, "one request per page")
    local req = ollama_requests[1]
    H.eq(req.provider, "ollama", "the request names the ollama provider")
    H.eq(req.model, "llama3.2", "with the model the caller asked for")
    H.eq(req.host, "http://192.168.1.4:11434", "opts.ollama_host is carried per request")
    H.eq(req.attachments, nil, "a non-vision model gets no image, only text")
    H.match(req.prompt, "Page 1 content:", "the page's text is folded into the prompt")
    H.eq(got.status, "ok", "and the answer becomes an ok result")
    H.eq(got.pages_processed, 1, "with the page count filled in")
  end)
end
