---@module 'pdfport.backends.ollama'
---@brief Extraction backend using a local ollama model.
---@description
--- Two routes through the same daemon, picked by whether the configured
--- model is a vision model:
---   * vision  -- rasterize each page with `pdftoppm` and send the PNG as an
---                image attachment,
---   * text    -- run `pdftotext` on the page and send its output as prompt
---                text, for a model that cannot see.
--- Either way the HTTP call goes through
--- [ai.nvim](https://github.com/StefanBartl/ai.nvim)'s `ask()`, which owns
--- the request shape, the JSON encoding and the base64.
---
--- This file used to carry its own curl path and, below it, a hand-rolled
--- base64 encoder -- the `CDX` note on that function asked for exactly this
--- removal. What is left is the part that is about PDFs: rasterizing pages,
--- choosing the route, and stitching per-page answers back together.
---
--- ai.nvim is an OPTIONAL dependency: `available()` returns false when it is
--- not installed, so pdfport keeps working with lib.nvim alone for everyone
--- who does not use this backend.
---
--- Requires: ai.nvim, ollama daemon running, pdftoppm, curl.

local platform = require("pdfport.platform")
local spawn_env = require("pdfport.util.spawn_env")

--- See the note on `Backend` in `@types/init.lua`: declared as a class so
--- the methods defined below the literal count as implementing it.
---@class PdfPort.Backend.Ollama : PdfPort.ConfigurableBackend
local M = {
  id = "ollama",
  name = "Ollama (local multimodal)",
  capabilities = {
    markdown = true,
    tables = true,
    ocr = true,
    remote = false,
    gpu_optional = true,
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
---`require("ai")`, or nil when ai.nvim is not installed.
---@return table|nil
local function ai()
  local ok, mod = pcall(require, "ai")
  return ok and mod or nil
end

---@return boolean
function M.available()
  return platform.has("ollama")
    and platform.has("pdftoppm")
    and platform.has("curl")
    and ai() ~= nil
end

---@internal
---Rasterise one page to PNG. Asynchronous: the path (or nil) arrives via `cb`.
---
---This used to be `rasterize_sync`, blocking on `vim.system():wait()` (or
---`vim.fn.system`). pdftoppm at 150 DPI takes hundreds of milliseconds per
---page and this runs once per page of the document, so a 20-page PDF froze
---Neovim twenty times over. The surrounding page loop was already a callback
---chain (`process_next`), so nothing else had to change shape.
---@param pdf_path string
---@param page integer
---@param cb fun(png_path: string|nil)
local function rasterize(pdf_path, page, cb)
  local tmp = vim.fn.tempname()
  local args = {
    "-png",
    "-r",
    "150",
    "-f",
    tostring(page),
    "-l",
    tostring(page),
    "-singlefile",
    pdf_path,
    tmp,
  }
  local cmd = vim.list_extend({ "pdftoppm" }, args)

  local function done()
    local png = tmp .. ".png"
    cb(vim.fn.filereadable(png) == 1 and png or nil)
  end

  if not vim.system then
    vim.fn.system(cmd)
    done()
    return
  end

  vim.system(cmd, spawn_env.opts(), function()
    -- vim.system callbacks run off the main loop; filereadable and everything
    -- the caller does next need the main loop.
    vim.schedule(done)
  end)
end

---@internal
---One request to the daemon, through ai.nvim's `ollama` provider.
---
---`host` is passed per-request rather than via ai.nvim's own
---`AI_OLLAMA_HOST` env var, so pdfport's `opts.ollama_host` config option
---keeps working without touching the user's environment.
---@param ai_mod table
---@param attachment Ai.Attachment|nil page image, or nil for the text route
---@param prompt string
---@param model string
---@param host string
---@param timeout_ms integer
---@param callback fun(text: string|nil, err: string|nil): nil
---@return nil
local function query_ollama(ai_mod, attachment, prompt, model, host, timeout_ms, callback)
  ai_mod.ask({
    prompt = prompt,
    provider = "ollama",
    model = model,
    host = host,
    attachments = attachment and { attachment } or nil,
    timeout_ms = timeout_ms,
  }, function(ok, res_or_err)
    if ok then
      ---@diagnostic disable-next-line: undefined-field
      callback(res_or_err.text, nil)
    else
      ---@diagnostic disable-next-line: undefined-field
      callback(nil, tostring(res_or_err.message or res_or_err))
    end
  end)
end

---@param path string
---@param opts PdfPort.InternalExtractOpts
---@return PdfPort.Result|nil
function M.extract(path, opts)
  local ai_mod = ai()
  if not ai_mod then
    -- Synchronous return only -- see backends/claude.lua's own note: the
    -- dispatcher fires a non-nil result itself, so calling opts.__callback
    -- here as well would double-fire it.
    return {
      status = "error",
      text = nil,
      format = "markdown",
      backend = "ollama",
      pages_processed = nil,
      error = "ollama: ai.nvim is not installed -- required by this backend",
    }
  end

  local host = (_config and _config.ollama_host) or "http://localhost:11434"
  local model = opts.model or (_config and _config.ollama_model) or "llava"
  local prompt = opts.prompt
    or "Extract all visible text from this image. Format the output as Markdown."
  local timeout_ms = opts.timeout_ms or 60000

  -- Two things at once. The default is the initialiser rather than a trailing
  -- `else`, because declared bare `pages` reads as maybe-nil inside
  -- `process_next` below -- a closure does not carry the narrowing the
  -- branches established. And `opts.pages` goes through a local, because
  -- narrowing a *field* does not carry into the assignment that follows it.
  ---@type integer[]
  local pages = { 1 }
  local requested = opts.pages
  if requested and #requested > 0 then
    pages = requested
  elseif opts.max_pages then
    pages = {}
    for i = 1, opts.max_pages do
      pages[i] = i
    end
  end

  local is_vision = model:lower():match("llava")
    or model:lower():match("bakllava")
    or model:lower():match("moondream")
    or model:lower():match("vision")

  local page_texts = {}
  local page_idx = 1

  ---@param message string
  ---@return nil
  local function fail(message)
    local result = {
      status = "error",
      text = nil,
      format = "markdown",
      backend = "ollama",
      pages_processed = page_idx - 2,
      error = message,
    }
    if type(opts.__callback) == "function" then opts.__callback(result) end
  end

  local function process_next()
    if page_idx > #pages then
      local result = {
        status = "ok",
        text = table.concat(page_texts, "\n\n---\n\n"),
        format = "markdown",
        backend = "ollama",
        pages_processed = #pages,
        error = nil,
      }
      local cb = opts.__callback
      if type(cb) == "function" then cb(result) end
      return
    end

    local page = pages[page_idx]
    page_idx = page_idx + 1

    ---@param text string|nil
    ---@param err string|nil
    local function collect(text, err)
      if err then
        fail(err)
        return
      end
      page_texts[#page_texts + 1] = string.format("<!-- page %d -->\n%s", page, text or "")
      process_next()
    end

    if is_vision then
      rasterize(path, page, function(png)
        if not png then
          fail(string.format("ollama: failed to rasterize page %d", page))
          return
        end
        local attachment, attachment_err = require("ai.attachments").from_file(png)
        vim.fn.delete(png)
        if not attachment then
          fail("ollama: " .. (attachment_err or "could not read the rasterized page"))
          return
        end
        query_ollama(ai_mod, attachment, prompt, model, host, timeout_ms, collect)
      end)
    else
      local pdftotext_argv = { "pdftotext", "-f", tostring(page), "-l", tostring(page), path, "-" }

      -- pdftotext used to run through vim.system():wait() / vim.fn.system(),
      -- once per page. Same problem as the vision branch above: a freeze per
      -- page. It hands its stdout over through a callback now.
      local function with_text(raw_text)
        local page_prompt = string.format("%s\n\nPage %d content:\n%s", prompt, page, raw_text)
        query_ollama(ai_mod, nil, page_prompt, model, host, timeout_ms, collect)
      end

      if not vim.system then
        with_text(vim.fn.system(pdftotext_argv))
      else
        vim.system(pdftotext_argv, spawn_env.opts({ text = true }), function(res)
          -- Off the main loop here; query_ollama and the result handling below
          -- both touch Neovim state.
          vim.schedule(function()
            with_text(res.stdout or "")
          end)
        end)
      end
    end
  end

  vim.schedule(process_next)
  return nil
end

return M
