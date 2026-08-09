---@module 'pdfport.producers.qpdf'
---@brief PDF + PDF → one PDF producer using the qpdf CLI (merge).
---@description
--- First choice for merging: small, exact, no re-encoding of page content.
--- Registered as a "pdf" producer so it reuses pdfport's normal
--- create()/composer machinery — pdfport.merge() is a thin wrapper that
--- calls composer.create() with `from = "pdf"`. Install: qpdf.

local platform = require("pdfport.platform")
local spawn_capture = require("lib.nvim.cross.uv.spawn_capture")

---@type PdfPort.Producer
local M = {
  id = "qpdf",
  name = "qpdf",
  accepts = { "pdf" },
  capabilities = {
    batch = true,
    lossless = true,
    styling = false,
    toc = false,
    remote = false,
  },
}

---@return boolean
function M.available()
  return platform.has("qpdf")
end

---@param req PdfPort.InternalCreateOpts
---@return PdfPort.CreateResult|nil
function M.create(req)
  local argv = { "qpdf", "--empty", "--pages" }
  for _, input in ipairs(req.inputs) do
    argv[#argv + 1] = input
  end
  argv[#argv + 1] = "--"
  argv[#argv + 1] = req.output

  local timeout_ms = req.timeout_ms or 60000

  spawn_capture(argv, { timeout_ms = timeout_ms }, function(spawn_result)
    local result
    if spawn_result.timed_out then
      result = {
        status = "error",
        path = nil,
        producer = "qpdf",
        pages = nil,
        error = string.format("qpdf: timed out after %d ms", timeout_ms),
      }
    elseif spawn_result.ok then
      result = {
        status = "ok",
        path = req.output,
        producer = "qpdf",
        pages = nil,
        error = nil,
      }
    else
      result = {
        status = "error",
        path = nil,
        producer = "qpdf",
        pages = nil,
        error = string.format("qpdf exited %d: %s", spawn_result.code, spawn_result.stderr),
      }
    end
    if type(req.__callback) == "function" then req.__callback(result) end
  end)

  return nil
end

return M
