---@module 'pdfport.backends.pdfplumber'
---@brief Extraction backend using the Python pdfplumber library.
---@description
--- Runs the pdfplumber script asynchronously via lib.nvim.cross.uv.spawn_capture.
--- Install: pip install pdfplumber

local platform = require("pdfport.platform")
local spawn_capture = require("lib.nvim.cross.uv.spawn_capture")

--- See the note on `Backend` in `@types/init.lua`: declared as a class so
--- the methods defined below the literal count as implementing it.
---@class PdfPort.Backend.Pdfplumber : PdfPort.Backend
local M = {
  id = "pdfplumber",
  name = "pdfplumber (Python)",
  capabilities = {
    markdown = false,
    tables = true,
    ocr = false,
    remote = false,
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
  local has_pages = opts.pages ~= nil and #opts.pages > 0

  -- `opts.pages` takes priority over `opts.max_pages`, same precedence as
  -- backends/pdftotext.lua. Page numbers are formatted with `%d` (not
  -- interpolated as text), so this stays a plain Python integer list literal
  -- regardless of what the caller passed in.
  local explicit_pages = "None"
  if has_pages then
    local nums = {}
    for i, p in ipairs(opts.pages) do
      nums[i] = string.format("%d", p)
    end
    explicit_pages = "[" .. table.concat(nums, ",") .. "]"
  end

  local script = string.format(
    [[
import sys, pdfplumber
path           = %q
max_pages      = %d
explicit_pages = %s
with pdfplumber.open(path) as pdf:
    if explicit_pages is not None:
        pages = [pdf.pages[i - 1] for i in explicit_pages if 1 <= i <= len(pdf.pages)]
    elif max_pages > 0:
        pages = pdf.pages[:max_pages]
    else:
        pages = pdf.pages
    parts = []
    for page in pages:
        text = page.extract_text()
        if text:
            parts.append(text)
    print("\n\n".join(parts))
]],
    path,
    max_pages,
    explicit_pages
  )

  local script_file = vim.fn.tempname() .. ".py"
  local f = io.open(script_file, "w")
  if not f then
    return {
      status = "error",
      text = nil,
      format = "plain",
      backend = "pdfplumber",
      pages_processed = nil,
      error = "pdfplumber: failed to write temp script",
    }
  end
  f:write(script)
  f:close()

  local python = platform.python()
  if not python then
    vim.fn.delete(script_file)
    return {
      status = "error",
      text = nil,
      format = "plain",
      backend = "pdfplumber",
      pages_processed = nil,
      error = "pdfplumber: no python interpreter found on PATH",
    }
  end

  local timeout_ms = opts.timeout_ms or 30000

  spawn_capture({ python, script_file }, { timeout_ms = timeout_ms }, function(spawn_result)
    vim.fn.delete(script_file)
    local result
    if spawn_result.timed_out then
      result = {
        status = "error",
        text = nil,
        format = "plain",
        backend = "pdfplumber",
        pages_processed = nil,
        error = string.format("pdfplumber: timed out after %d ms", timeout_ms),
      }
    elseif spawn_result.ok then
      result = {
        status = "ok",
        text = spawn_result.stdout,
        format = "plain",
        backend = "pdfplumber",
        -- Only reports a max_pages count when that is what actually bounded
        -- the run; an explicit `opts.pages` selection (honored above, in the
        -- script itself) is not a page *count*, so it stays unreported here
        -- rather than borrowing max_pages's meaning for something else.
        pages_processed = (not has_pages and max_pages > 0) and max_pages or nil,
        error = nil,
      }
    else
      result = {
        status = "error",
        text = nil,
        format = "plain",
        backend = "pdfplumber",
        pages_processed = nil,
        error = string.format("pdfplumber exited %d: %s", spawn_result.code, spawn_result.stderr),
      }
    end
    if type(opts.__callback) == "function" then opts.__callback(result) end
  end)

  return nil
end

return M
