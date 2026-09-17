---@module 'pdfport.backends.claude'
---@brief Extraction backend using the Anthropic Claude API.
---@description
--- Sends the PDF as a base64-encoded document attachment through
--- [ai.nvim](https://github.com/StefanBartl/ai.nvim)'s provider-agnostic
--- `ask()`, which owns the HTTP call, the JSON encoding and keeping the API
--- key out of curl's argv.
---
--- This file used to carry its own curl/provider path: build the Messages
--- API body by hand, write it to a temp file, write the key to a second
--- `chmod`-protected temp file for `-K`, spawn curl, decode the response,
--- clean up. All of that was correct by the end -- and it was the second
--- copy of it in this collection. `ai.nvim` exists to be the first, so what
--- is left here is the part that is actually about PDFs: which model, which
--- prompt, and turning an `Ai.Response` into a `PdfPort.Result`.
---
--- ai.nvim is an OPTIONAL dependency: `available()` returns false when it is
--- not installed, exactly as it does for a missing API key, so pdfport keeps
--- working with lib.nvim alone for everyone who does not use this backend.
---
--- Requires: ai.nvim, ANTHROPIC_API_KEY (or `opts.claude_api_key`), curl,
--- internet connection.

local platform = require("pdfport.platform")

--- See the note on `Backend` in `@types/init.lua`: declared as a class so
--- the methods defined below the literal count as implementing it.
---@class PdfPort.Backend.Claude : PdfPort.ConfigurableBackend
local M = {
  id = "claude",
  name = "Anthropic Claude API",
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
  local key = (_config and _config.claude_api_key) or vim.env.ANTHROPIC_API_KEY
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
    backend = "claude",
    pages_processed = nil,
    error = message,
  }
end

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
    return failure("claude: ai.nvim is not installed -- required by this backend")
  end

  local key = api_key()
  if not key then return failure("claude: ANTHROPIC_API_KEY not set") end

  -- `ai.attachments.from_file` does what this file's own `read_base64` did:
  -- one blocking `vim.uv` read plus `vim.base64.encode` (Neovim 0.10+),
  -- never a `base64 -w 0` subprocess -- that flag is GNU-only, so the old
  -- shell-out failed on macOS and had no binary to call at all on Windows.
  local attachment, attachment_err = require("ai.attachments").from_file(path)
  if not attachment then
    return failure("claude: " .. (attachment_err or "could not read the PDF"))
  end

  local timeout_ms = opts.timeout_ms or 60000

  ai_mod.ask({
    prompt = opts.prompt or DEFAULT_PROMPT,
    provider = "claude",
    -- pdfport's own default, passed explicitly rather than left to ai.nvim's
    -- `config.model.claude`: which model reads a PDF well is this plugin's
    -- business, and a user's global ai.nvim model choice (picked for chat,
    -- say) must not silently become the extraction model.
    model = opts.model or "claude-opus-4-5",
    -- Lets `opts.claude_api_key` keep working without writing it into the
    -- user's environment for ai.nvim's own env-var lookup to find.
    api_key = key,
    attachments = { attachment },
    timeout_ms = timeout_ms,
  }, function(ok, res_or_err)
    local result
    if ok then
      result = {
        status = "ok",
        ---@diagnostic disable-next-line: undefined-field
        text = res_or_err.text,
        format = "markdown",
        backend = "claude",
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
