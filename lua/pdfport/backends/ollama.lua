---@module 'pdfport.backends.ollama'
---@brief Extraction backend using a local ollama multimodal model.
---@description
--- Rasterizes each PDF page via pdftoppm and sends images to the ollama API.
--- Runs curl asynchronously via lib.nvim.cross.uv.spawn_capture.
--- Requires: ollama daemon running, pdftoppm, curl.

local platform = require("pdfport.platform")
local spawn_capture = require("lib.nvim.cross.uv.spawn_capture")
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

---@return boolean
function M.available()
  return platform.has("ollama") and platform.has("pdftoppm") and platform.has("curl")
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
--- CDX: hand-rolled base64 encoder; backends/claude.lua now uses
--- vim.base64.encode (Neovim 0.10+) for the same job and this whole function
--- could go the same way.
---@param path string
---@return string|nil b64
---@return string|nil error_msg
local function b64_encode(path)
  local f = io.open(path, "rb")
  if not f then return nil, "b64_encode: cannot open: " .. path end
  local data = f:read("*a")
  f:close()
  if not data then return nil, "b64_encode: failed to read: " .. path end

  local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  local result = {}
  local len = #data
  local i = 1

  while i <= len do
    local b1 = data:byte(i) or 0
    local b2 = data:byte(i + 1) or 0
    local b3 = data:byte(i + 2) or 0
    local n = b1 * 65536 + b2 * 256 + b3
    result[#result + 1] =
      chars:sub(math.floor(n / 262144) % 64 + 1, math.floor(n / 262144) % 64 + 1)
    result[#result + 1] = chars:sub(math.floor(n / 4096) % 64 + 1, math.floor(n / 4096) % 64 + 1)
    result[#result + 1] = i + 1 <= len
        and chars:sub(math.floor(n / 64) % 64 + 1, math.floor(n / 64) % 64 + 1)
      or "="
    result[#result + 1] = i + 2 <= len and chars:sub(n % 64 + 1, n % 64 + 1) or "="
    i = i + 3
  end
  return table.concat(result), nil
end

---@internal
---@param b64 string|nil
---@param prompt string
---@param model string
---@param host string
---@param timeout_ms integer
---@param callback fun(text: string|nil, err: string|nil): nil
---@return nil
local function query_ollama(b64, prompt, model, host, timeout_ms, callback)
  -- vim.json.encode handles quoting/escaping correctly - the previous
  -- gsub('"', '\\"') only escaped quotes and newlines, not backslashes, so
  -- a Windows path or regex in the prompt (e.g. "C:\repos\foo") produced
  -- invalid JSON that the receiving end would reject.
  local body_tbl = { model = model, prompt = prompt, stream = false }
  if b64 then body_tbl.images = { b64 } end
  local body = vim.json.encode(body_tbl)

  local body_file = vim.fn.tempname() .. ".json"
  local f = io.open(body_file, "w")
  if not f then
    callback(nil, "ollama: failed to write temp request file")
    return
  end
  f:write(body)
  f:close()

  local argv = {
    "curl",
    "-s",
    "-X",
    "POST",
    host .. "/api/generate",
    "-H",
    "Content-Type: application/json",
    "-d",
    "@" .. body_file,
  }

  spawn_capture(argv, { timeout_ms = timeout_ms, env = spawn_env.array() }, function(spawn_result)
    vim.fn.delete(body_file)

    if spawn_result.timed_out then
      callback(nil, string.format("ollama: request timed out after %d ms", timeout_ms))
      return
    end
    if not spawn_result.ok then
      callback(nil, string.format("curl exited %d: %s", spawn_result.code, spawn_result.stderr))
      return
    end

    local raw = spawn_result.stdout
    -- check for ollama-level error
    local first = vim.trim(vim.split(raw, "\n", { plain = true })[1] or "")
    if first ~= "" then
      local ok_e, e_obj = pcall(vim.json.decode, first)
      if ok_e and type(e_obj) == "table" and type(e_obj.error) == "string" then
        callback(nil, "ollama error: " .. e_obj.error)
        return
      end
    end
    local lines = vim.split(raw, "\n", { plain = true })
    local text = nil
    for i = #lines, 1, -1 do
      local line = vim.trim(lines[i])
      if line ~= "" then
        local ok_j, decoded = pcall(vim.json.decode, line)
        if ok_j and type(decoded) == "table" and type(decoded.response) == "string" then
          text = decoded.response
          break
        end
      end
    end
    if not text then
      callback(nil, "ollama: response field missing. Raw: " .. raw:sub(1, 300))
      return
    end
    callback(text, nil)
  end)
end

---@param path string
---@param opts PdfPort.InternalExtractOpts
---@return PdfPort.Result|nil
function M.extract(path, opts)
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

    if is_vision then
      rasterize(path, page, function(png)
        if not png then
          local result = {
            status = "error",
            text = nil,
            format = "markdown",
            backend = "ollama",
            pages_processed = page_idx - 2,
            error = string.format("ollama: failed to rasterize page %d", page),
          }
          if type(opts.__callback) == "function" then opts.__callback(result) end
          return
        end
        local b64, b64_err = b64_encode(png)
        vim.fn.delete(png)
        if not b64 then
          local result = {
            status = "error",
            text = nil,
            format = "markdown",
            backend = "ollama",
            pages_processed = page_idx - 2,
            error = string.format("ollama: %s", b64_err or "base64 encoding failed"),
          }
          if type(opts.__callback) == "function" then opts.__callback(result) end
          return
        end
        query_ollama(b64, prompt, model, host, timeout_ms, function(text, err)
          if err then
            local result = {
              status = "error",
              text = nil,
              format = "markdown",
              backend = "ollama",
              pages_processed = page_idx - 2,
              error = err,
            }
            if type(opts.__callback) == "function" then opts.__callback(result) end
            return
          end
          page_texts[#page_texts + 1] = string.format("<!-- page %d -->\n%s", page, text or "")
          process_next()
        end)
      end)
    else
      local pdftotext_argv = { "pdftotext", "-f", tostring(page), "-l", tostring(page), path, "-" }

      -- pdftotext used to run through vim.system():wait() / vim.fn.system(),
      -- once per page. Same problem as the vision branch above: a freeze per
      -- page. It hands its stdout over through a callback now.
      local function with_text(raw_text)
        local page_prompt = string.format("%s\n\nPage %d content:\n%s", prompt, page, raw_text)
        query_ollama(nil, page_prompt, model, host, timeout_ms, function(text, err)
          if err then
            local result = {
              status = "error",
              text = nil,
              format = "markdown",
              backend = "ollama",
              pages_processed = page_idx - 2,
              error = err,
            }
            if type(opts.__callback) == "function" then opts.__callback(result) end
            return
          end
          page_texts[#page_texts + 1] = string.format("<!-- page %d -->\n%s", page, text or "")
          process_next()
        end)
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
