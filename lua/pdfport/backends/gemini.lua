---@module 'pdfport.backends.gemini'
---@brief Extraction backend using Google's Gemini API.
---@description
--- Sends the PDF whole, as a base64 document attachment, through
--- [ai.nvim](https://github.com/StefanBartl/ai.nvim)'s provider-agnostic
--- `ask()` — the model reads the PDF itself, so nothing is rasterized here.
---
--- The sibling of `backends/claude.lua`, and deliberately its near-copy:
--- both are "hand the whole file to a model that can read it". Gemini and
--- Anthropic are the only two providers ai.nvim can send a document to at
--- all (`capabilities.documents`), which is exactly what makes this backend
--- about a hundred lines rather than a second copy of `ollama.lua`'s
--- page-by-page rasterizing loop.
---
--- ai.nvim is an OPTIONAL dependency: `available()` returns false when it is
--- not installed, exactly as it does for a missing API key, so pdfport keeps
--- working with lib.nvim alone for everyone who does not use this backend.
---
--- Requires: ai.nvim, GEMINI_API_KEY (or `opts.gemini_api_key`), curl,
--- internet connection.

local platform = require("pdfport.platform")

--- See the note on `Backend` in `@types/init.lua`: declared as a class so
--- the methods defined below the literal count as implementing it.
---@class PdfPort.Backend.Gemini : PdfPort.ConfigurableBackend
local M = {
  id = "gemini",
  name = "Google Gemini API",
  capabilities = {
    markdown = true,
    tables = true,
    ocr = true,
    remote = true,
    gpu_optional = false,
  },
}

---@type PdfPort.Config|nil
local _config = nil

---@param config PdfPort.Config
---@return nil
function M._set_config(config)
  _config = config
end

---@internal
---@return string|nil
local function api_key()
  local key = (_config and _config.gemini_api_key) or vim.env.GEMINI_API_KEY
  return (type(key) == "string" and key ~= "") and key or nil
end

---@internal
---`require("ai")`, or nil when ai.nvim is not installed.
---@return table|nil
local function ai()
  local ok, mod = pcall(require, "ai")
  return ok and mod or nil
end

---@return boolean
function M.available()
  return platform.has("curl") and ai() ~= nil and api_key() ~= nil
end

---@internal
---@param message string
---@return PdfPort.Result
local function failure(message)
  return {
    status = "error",
    text = nil,
    format = "markdown",
    backend = "gemini",
    pages_processed = nil,
    error = message,
  }
end

--- `gemini-2.5-flash`, not `-pro`: extraction is a bulk, per-document job
--- where the whole file is the input, and flash reads PDFs well enough for
--- it at a fraction of the cost and latency. Override with `opts.model` per
--- call for a document that needs the stronger model.
local DEFAULT_MODEL = "gemini-2.5-flash"

local DEFAULT_PROMPT = table.concat({
  "Extract all text content from this PDF document.",
  "Format the output as clean Markdown.",
  "Preserve headings, lists, tables and code blocks.",
  "Do not add commentary or preamble.",
}, " ")

---@param path string
---@param opts PdfPort.InternalExtractOpts
---@return PdfPort.Result|nil
function M.extract(path, opts)
  -- Every early return below is synchronous (not via opts.__callback) so the
  -- dispatcher's own "if result ~= nil then callback(result) end" fires it
  -- exactly once -- calling opts.__callback here too would double-fire.
  local ai_mod = ai()
  if not ai_mod then
    return failure("gemini: ai.nvim is not installed -- required by this backend")
  end

  local key = api_key()
  if not key then return failure("gemini: GEMINI_API_KEY not set") end

  -- Google caps an *inline* request (this one) at 20 MB total; past that its
  -- Files API is the documented route, and ai.nvim does not speak it. A PDF
  -- over that comes back as a plain API error naming the limit rather than
  -- being silently truncated, so there is nothing to pre-empt here -- but it
  -- is the reason a very large scan belongs on the ollama backend instead,
  -- which sends one rasterized page at a time.
  local attachment, attachment_err = require("ai.attachments").from_file(path)
  if not attachment then
    return failure("gemini: " .. (attachment_err or "could not read the PDF"))
  end

  ai_mod.ask({
    prompt = opts.prompt or DEFAULT_PROMPT,
    provider = "gemini",
    -- pdfport's own default, passed explicitly rather than left to ai.nvim's
    -- `config.model.gemini`: which model reads a PDF well is this plugin's
    -- business, and a user's global ai.nvim model choice (picked for chat,
    -- say) must not silently become the extraction model.
    model = opts.model or DEFAULT_MODEL,
    -- Lets `opts.gemini_api_key` keep working without writing it into the
    -- user's environment for ai.nvim's own env-var lookup to find.
    api_key = key,
    attachments = { attachment },
    timeout_ms = opts.timeout_ms or 60000,
  }, function(ok, res_or_err)
    local result
    if ok then
      result = {
        status = "ok",
        ---@diagnostic disable-next-line: undefined-field
        text = res_or_err.text,
        format = "markdown",
        backend = "gemini",
        pages_processed = nil,
        error = nil,
      }
    else
      ---@diagnostic disable-next-line: undefined-field
      result = failure(tostring(res_or_err.message or res_or_err))
    end
    if type(opts.__callback) == "function" then opts.__callback(result) end
  end)

  return nil
end

return M
