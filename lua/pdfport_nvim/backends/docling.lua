---@module 'pdfport_nvim.backends.docling'
---@brief Extraction backend using IBM docling.
---@description
--- Produces high-quality Markdown preserving tables and document structure.
--- Runs the docling script asynchronously via lib.nvim.cross.uv.spawn_capture.
--- Install: pip install docling

local platform = require("pdfport_nvim.platform")
local spawn_capture = require("lib.nvim.cross.uv.spawn_capture")

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

  local python = platform.python()
  if not python then
    vim.fn.delete(script_file)
    return {
      status = "error", text = nil, format = "markdown", backend = "docling",
      pages_processed = nil, error = "docling: no python interpreter found on PATH",
    }
  end

  local timeout_ms = opts.timeout_ms or 120000

  spawn_capture({ python, script_file }, { timeout_ms = timeout_ms }, function(spawn_result)
    vim.fn.delete(script_file)
    local result
    if spawn_result.timed_out then
      result = {
        status = "error", text = nil, format = "markdown", backend = "docling",
        pages_processed = nil,
        error = string.format("docling: timed out after %d ms", timeout_ms),
      }
    elseif spawn_result.ok then
      result = {
        status = "ok", text = spawn_result.stdout, format = "markdown", backend = "docling",
        pages_processed = max_pages > 0 and max_pages or nil, error = nil,
      }
    else
      result = {
        status = "error", text = nil, format = "markdown", backend = "docling",
        pages_processed = nil,
        error = string.format("docling exited %d: %s", spawn_result.code, spawn_result.stderr),
      }
    end
    if type(opts.__callback) == "function" then opts.__callback(result) end
  end)

  return nil
end

return M
