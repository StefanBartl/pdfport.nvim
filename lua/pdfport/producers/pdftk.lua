---@module 'pdfport.producers.pdftk'
---@brief PDF + PDF → one PDF producer using the pdftk CLI (merge fallback).
---@description
--- Second choice behind qpdf. Registered as a "pdf" producer, same as
--- qpdf/ghostscript — see producers/qpdf.lua for why. Install: pdftk
--- (pdftk-java on most package managers today).

local platform = require("pdfport.platform")
local spawn_capture = require("lib.nvim.cross.uv.spawn_capture")

--- See the note on `Producer` in `@types/init.lua`: declared as a class so
--- the methods defined below the literal count as implementing it.
---@class PdfPort.Producer.Pdftk : PdfPort.Producer
local M = {
  id = "pdftk",
  name = "pdftk",
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
  return platform.has("pdftk")
end

---@param req PdfPort.InternalCreateOpts
---@return PdfPort.CreateResult|nil
function M.create(req)
  local argv = { "pdftk" }
  for _, input in ipairs(req.inputs) do
    argv[#argv + 1] = input
  end
  argv[#argv + 1] = "cat"
  argv[#argv + 1] = "output"
  argv[#argv + 1] = req.output

  local timeout_ms = req.timeout_ms or 60000

  spawn_capture(argv, { timeout_ms = timeout_ms }, function(spawn_result)
    local result
    if spawn_result.timed_out then
      result = {
        status = "error",
        path = nil,
        producer = "pdftk",
        pages = nil,
        error = string.format("pdftk: timed out after %d ms", timeout_ms),
      }
    elseif spawn_result.ok then
      result = {
        status = "ok",
        path = req.output,
        producer = "pdftk",
        pages = nil,
        error = nil,
      }
    else
      result = {
        status = "error",
        path = nil,
        producer = "pdftk",
        pages = nil,
        error = string.format("pdftk exited %d: %s", spawn_result.code, spawn_result.stderr),
      }
    end
    if type(req.__callback) == "function" then req.__callback(result) end
  end)

  return nil
end

return M
