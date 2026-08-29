---@module 'pdfport.producers.ghostscript'
---@brief PDF + PDF → one PDF producer using Ghostscript (merge, last resort).
---@description
--- Last choice behind qpdf/pdftk: rewrites/recompresses every page through
--- its own PDF interpreter instead of copying page content unchanged, so
--- output can be larger or subtly different. Kept as a fallback because it's
--- the most commonly pre-installed of the three. Executable name varies by
--- platform: `gs` (Unix), `gswin64c`/`gswin32c` (Windows).

local platform = require("pdfport.platform")
local spawn_capture = require("lib.nvim.cross.uv.spawn_capture")

--- See the note on `Producer` in `@types/init.lua`: declared as a class so
--- the methods defined below the literal count as implementing it.
---@class PdfPort.Producer.Ghostscript : PdfPort.Producer
local M = {
  id = "ghostscript",
  name = "Ghostscript",
  accepts = { "pdf" },
  capabilities = {
    batch = true,
    lossless = false,
    styling = false,
    toc = false,
    remote = false,
  },
}

---@internal
local EXE_CHAIN = { "gs", "gswin64c", "gswin32c" }

---@return string|nil
local function resolve_exe()
  return platform.first_available(EXE_CHAIN)
end

---@return boolean
function M.available()
  return resolve_exe() ~= nil
end

---@param req PdfPort.InternalCreateOpts
---@return PdfPort.CreateResult|nil
function M.create(req)
  local exe = resolve_exe()
  if not exe then
    local result = {
      status = "error",
      path = nil,
      producer = "ghostscript",
      pages = nil,
      error = "ghostscript: no gs/gswin64c/gswin32c found on PATH",
    }
    if type(req.__callback) == "function" then req.__callback(result) end
    return nil
  end

  local argv = {
    exe,
    "-dBATCH",
    "-dNOPAUSE",
    "-q",
    "-sDEVICE=pdfwrite",
    "-sOutputFile=" .. req.output,
  }
  for _, input in ipairs(req.inputs) do
    argv[#argv + 1] = input
  end

  local timeout_ms = req.timeout_ms or 60000

  spawn_capture(argv, { timeout_ms = timeout_ms }, function(spawn_result)
    local result
    if spawn_result.timed_out then
      result = {
        status = "error",
        path = nil,
        producer = "ghostscript",
        pages = nil,
        error = string.format("ghostscript: timed out after %d ms", timeout_ms),
      }
    elseif spawn_result.ok then
      result = {
        status = "ok",
        path = req.output,
        producer = "ghostscript",
        pages = nil,
        error = nil,
      }
    else
      result = {
        status = "error",
        path = nil,
        producer = "ghostscript",
        pages = nil,
        error = string.format("ghostscript exited %d: %s", spawn_result.code, spawn_result.stderr),
      }
    end
    if type(req.__callback) == "function" then req.__callback(result) end
  end)

  return nil
end

return M
