---@module 'pdfport_nvim.backends.pdftotext'
---@brief Extraction backend using the pdftotext CLI from poppler-utils.
---@description
--- Runs pdftotext asynchronously via vim.uv.spawn.
--- Install: apt install poppler-utils | brew install poppler | winget install poppler

local platform = require("pdfport_nvim.platform")
local uv       = vim.uv or vim.loop

---@type PdfPort.StatefulBackend
local M = {
  id   = "pdftotext",
  name = "pdftotext (poppler-utils)",
  capabilities = {
    markdown     = false,
    tables       = false,
    ocr          = false,
    remote       = false,
    gpu_optional = false,
  },
}

---@return boolean
function M.available()
  return platform.has("pdftotext")
end

---@param path string
---@param opts PdfPort.InternalExtractOpts
---@return PdfPort.Result|nil
function M.extract(path, opts)
  local args = { "-layout", "-enc", "UTF-8" }

  if opts.pages and #opts.pages > 0 then
    args[#args + 1] = "-f"; args[#args + 1] = tostring(opts.pages[1])
    args[#args + 1] = "-l"; args[#args + 1] = tostring(opts.pages[#opts.pages])
  elseif opts.max_pages then
    args[#args + 1] = "-l"; args[#args + 1] = tostring(opts.max_pages)
  end

  args[#args + 1] = path
  args[#args + 1] = "-"

  local chunks        = {}
  local stderr_chunks = {}
  local stdout        = uv.new_pipe(false)
  local stderr        = uv.new_pipe(false)

  if not stdout or not stderr then
    return {
      status = "error", text = nil, format = "plain", backend = "pdftotext",
      pages_processed = nil, error = "pdftotext: failed to create process pipes",
    }
  end

  local timeout_ms = opts.timeout_ms or 30000
  local timer      = uv.new_timer()
  if not timer then
    return {
      status = "error", text = nil, format = "plain", backend = "pdftotext",
      pages_processed = nil, error = "pdftotext: failed to create timeout timer",
    }
  end

  local handle

  local function cleanup()
    if timer and not timer:is_closing()  then timer:stop(); timer:close() end
    if stdout and not stdout:is_closing() then stdout:close() end
    if stderr and not stderr:is_closing() then stderr:close() end
  end

  handle = uv.spawn("pdftotext", {
    args  = args,
    stdio = { nil, stdout, stderr },
  }, function(code, _)
    cleanup()
    local text     = table.concat(chunks)
    local err_text = table.concat(stderr_chunks)

    vim.schedule(function()
      local result = code == 0 and {
        status = "ok",    text = text,  format = "plain", backend = "pdftotext",
        pages_processed = opts.max_pages, error = nil,
      } or {
        status = "error", text = nil,   format = "plain", backend = "pdftotext",
        pages_processed = nil,
        error = string.format("pdftotext exited %d: %s", code, err_text),
      }
      M._last_result = result
      if type(opts.__callback) == "function" then opts.__callback(result) end
    end)
  end)

  if not handle then
    return {
      status = "error", text = nil, format = "plain", backend = "pdftotext",
      pages_processed = nil, error = "pdftotext: failed to spawn process",
    }
  end

  stdout:read_start(function(_, data)
    if data then chunks[#chunks + 1] = data end
  end)

  stderr:read_start(function(_, data)
    if data then stderr_chunks[#stderr_chunks + 1] = data end
  end)

  timer:start(timeout_ms, 0, function()
    if handle and not handle:is_closing() then handle:kill(15) end
    cleanup()
    vim.schedule(function()
      local result = {
        status = "error", text = nil, format = "plain", backend = "pdftotext",
        pages_processed = nil,
        error = string.format("pdftotext: timed out after %d ms", timeout_ms),
      }
      if type(opts.__callback) == "function" then opts.__callback(result) end
    end)
  end)

  return nil
end

return M
