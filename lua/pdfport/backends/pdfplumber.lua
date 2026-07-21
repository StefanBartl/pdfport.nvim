---@module 'pdfport.backends.pdfplumber'
---@brief Extraction backend using the Python pdfplumber library.
---@description
--- Runs the pdfplumber script asynchronously via lib.nvim.cross.uv.spawn_capture.
--- Install: pip install pdfplumber

local platform = require("pdfport.platform")
local spawn_capture = require("lib.nvim.cross.uv.spawn_capture")

---@type PdfPort.Backend
local M = {
  id   = "pdfplumber",
  name = "pdfplumber (Python)",
  capabilities = {
    markdown     = false,
    tables       = true,
    ocr          = false,
    remote       = false,
    gpu_optional = false,
  },
}

---@return boolean
function M.available()
  return platform.python() ~= nil and platform.has_python_module("pdfplumber")
end

---@param path string
---@param opts PdfPort.InternalExtractOpts
---@return PdfPort.Result|nil
function M.extract(path, opts)
  local max_pages = opts.max_pages or 0

  local script = string.format([[
import sys, pdfplumber
path      = %q
max_pages = %d
with pdfplumber.open(path) as pdf:
    pages = pdf.pages if max_pages == 0 else pdf.pages[:max_pages]
    parts = []
    for page in pages:
        text = page.extract_text()
        if text:
            parts.append(text)
    print("\n\n".join(parts))
]], path, max_pages)

  local script_file = vim.fn.tempname() .. ".py"
  local f = io.open(script_file, "w")
  if not f then
    return {
      status = "error", text = nil, format = "plain", backend = "pdfplumber",
      pages_processed = nil, error = "pdfplumber: failed to write temp script",
    }
  end
  f:write(script)
  f:close()

  local python = platform.python()
  if not python then
    vim.fn.delete(script_file)
    return {
      status = "error", text = nil, format = "plain", backend = "pdfplumber",
      pages_processed = nil, error = "pdfplumber: no python interpreter found on PATH",
    }
  end

  local timeout_ms = opts.timeout_ms or 30000

  spawn_capture({ python, script_file }, { timeout_ms = timeout_ms }, function(spawn_result)
    vim.fn.delete(script_file)
    local result
    if spawn_result.timed_out then
      result = {
        status = "error", text = nil, format = "plain", backend = "pdfplumber",
        pages_processed = nil,
        error = string.format("pdfplumber: timed out after %d ms", timeout_ms),
      }
    elseif spawn_result.ok then
      result = {
        status = "ok", text = spawn_result.stdout, format = "plain", backend = "pdfplumber",
        pages_processed = max_pages > 0 and max_pages or nil, error = nil,
      }
    else
      result = {
        status = "error", text = nil, format = "plain", backend = "pdfplumber",
        pages_processed = nil,
        error = string.format("pdfplumber exited %d: %s", spawn_result.code, spawn_result.stderr),
      }
    end
    if type(opts.__callback) == "function" then opts.__callback(result) end
  end)

  return nil
end

return M
