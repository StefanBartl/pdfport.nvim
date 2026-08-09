---@module 'pdfport.producers.weasyprint'
---@brief HTML → PDF producer using the weasyprint CLI (Python).
---@description
--- First choice for HTML: clean CSS Paged Media support. Install:
--- pip install weasyprint

local platform = require("pdfport.platform")
local spawn_capture = require("lib.nvim.cross.uv.spawn_capture")

---@type PdfPort.Producer
local M = {
  id = "weasyprint",
  name = "weasyprint",
  accepts = { "html" },
  capabilities = {
    batch = false,
    lossless = false,
    styling = true,
    toc = false,
    remote = false,
  },
}

---@return boolean
function M.available()
  return platform.has("weasyprint")
end

---@param req PdfPort.InternalCreateOpts
---@return PdfPort.CreateResult|nil
function M.create(req)
  local argv = { "weasyprint", req.inputs[1], req.output }

  local timeout_ms = req.timeout_ms or 60000

  spawn_capture(argv, { timeout_ms = timeout_ms }, function(spawn_result)
    local result
    if spawn_result.timed_out then
      result = {
        status = "error",
        path = nil,
        producer = "weasyprint",
        pages = nil,
        error = string.format("weasyprint: timed out after %d ms", timeout_ms),
      }
    elseif spawn_result.ok then
      result = {
        status = "ok",
        path = req.output,
        producer = "weasyprint",
        pages = nil,
        error = nil,
      }
    else
      result = {
        status = "error",
        path = nil,
        producer = "weasyprint",
        pages = nil,
        error = string.format("weasyprint exited %d: %s", spawn_result.code, spawn_result.stderr),
      }
    end
    if type(req.__callback) == "function" then req.__callback(result) end
  end)

  return nil
end

return M
