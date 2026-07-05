---@module 'pdfport_nvim.backends.docling'
---@brief Extraction backend using IBM docling.
---@description
--- Produces high-quality Markdown preserving tables and document structure.
--- Install: pip install docling

local platform = require("pdfport_nvim.platform")
local uv       = vim.uv or vim.loop

---@type PdfPort.Backend
local M = {
  id   = "docling",
  name = "docling (IBM, Python)",
  capabilities = {
    markdown     = true,
    tables       = true,
    ocr          = true,
    remote       = false,
    gpu_optional = true,
  },
}

---@return boolean
function M.available()
  return platform.python() ~= nil and platform.has_python_module("docling")
end

---@param path string
---@param opts PdfPort.InternalExtractOpts
---@return PdfPort.Result|nil
function M.extract(path, opts)
  local max_pages = opts.max_pages or 0

  local script = string.format([[
import sys
from docling.document_converter import DocumentConverter
path      = %q
max_pages = %d
try:
    converter = DocumentConverter()
    result    = converter.convert(path)
    md        = result.document.export_to_markdown()
    print(md)
except Exception as e:
    print(f"docling error: {e}", file=sys.stderr)
    sys.exit(1)
]], path, max_pages)

  local script_file = vim.fn.tempname() .. ".py"
  local f = io.open(script_file, "w")
  if not f then
    return {
      status = "error", text = nil, format = "markdown", backend = "docling",
      pages_processed = nil, error = "docling: failed to write temp script",
    }
  end
  f:write(script)
  f:close()

  local stdout_chunks = {}
  local stderr_chunks = {}
  local stdout        = uv.new_pipe(false)
  local stderr        = uv.new_pipe(false)
  if not stdout or not stderr then
    vim.fn.delete(script_file)
    return {
      status = "error", text = nil, format = "markdown", backend = "docling",
      pages_processed = nil, error = "docling: failed to create process pipes",
    }
  end

  local timeout_ms = opts.timeout_ms or 120000
  local timer      = uv.new_timer()
  if not timer then
    vim.fn.delete(script_file)
    return {
      status = "error", text = nil, format = "markdown", backend = "docling",
      pages_processed = nil, error = "docling: failed to create timeout timer",
    }
  end

  local function cleanup()
    if timer  and not timer:is_closing()  then timer:stop(); timer:close() end
    if stdout and not stdout:is_closing() then stdout:close() end
    if stderr and not stderr:is_closing() then stderr:close() end
    vim.fn.delete(script_file)
  end

  local python = platform.python()
  if not python then
    vim.fn.delete(script_file)
    return {
      status = "error", text = nil, format = "markdown", backend = "docling",
      pages_processed = nil, error = "docling: no python interpreter found on PATH",
    }
  end

  local handle = uv.spawn(python, {
    args  = { script_file },
    stdio = { nil, stdout, stderr },
  }, function(code, _)
    cleanup()
    local text     = table.concat(stdout_chunks)
    local err_text = table.concat(stderr_chunks)
    vim.schedule(function()
      local result = code == 0 and {
        status = "ok",    text = text, format = "markdown", backend = "docling",
        pages_processed = max_pages > 0 and max_pages or nil, error = nil,
      } or {
        status = "error", text = nil, format = "markdown", backend = "docling",
        pages_processed = nil,
        error = string.format("docling exited %d: %s", code, err_text),
      }
      if type(opts.__callback) == "function" then opts.__callback(result) end
    end)
  end)

  if not handle then
    vim.fn.delete(script_file)
    return {
      status = "error", text = nil, format = "markdown", backend = "docling",
      pages_processed = nil, error = "docling: failed to spawn " .. python,
    }
  end

  stdout:read_start(function(_, data) if data then stdout_chunks[#stdout_chunks + 1] = data end end)
  stderr:read_start(function(_, data) if data then stderr_chunks[#stderr_chunks + 1] = data end end)

  timer:start(timeout_ms, 0, function()
    if handle and not handle:is_closing() then handle:kill(15) end
    cleanup()
    vim.schedule(function()
      local result = {
        status = "error", text = nil, format = "markdown", backend = "docling",
        pages_processed = nil,
        error = string.format("docling: timed out after %d ms", timeout_ms),
      }
      if type(opts.__callback) == "function" then opts.__callback(result) end
    end)
  end)

  return nil
end

return M
