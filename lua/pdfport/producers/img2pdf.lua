---@module 'pdfport.producers.img2pdf'
---@brief Image → PDF producer using the img2pdf CLI (Python).
---@description
--- First choice for images: lossless — embeds JPEG/PNG data unchanged
--- instead of recompressing it. Install: pip install img2pdf

local platform = require("pdfport.platform")
local spawn_capture = require("lib.nvim.cross.uv.spawn_capture")

--- See the note on `Producer` in `@types/init.lua`: declared as a class so
--- the methods defined below the literal count as implementing it.
---@class PdfPort.Producer.Img2pdf : PdfPort.Producer
local M = {
  id = "img2pdf",
  name = "img2pdf",
  accepts = { "image" },
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
  return platform.has("img2pdf")
end

---@param req PdfPort.InternalCreateOpts
---@return PdfPort.CreateResult|nil
function M.create(req)
  local argv = { "img2pdf", "--output", req.output }
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
        producer = "img2pdf",
        pages = nil,
        error = string.format("img2pdf: timed out after %d ms", timeout_ms),
      }
    elseif spawn_result.ok then
      result = {
        status = "ok",
        path = req.output,
        producer = "img2pdf",
        pages = #req.inputs,
        error = nil,
      }
    else
      result = {
        status = "error",
        path = nil,
        producer = "img2pdf",
        pages = nil,
        error = string.format("img2pdf exited %d: %s", spawn_result.code, spawn_result.stderr),
      }
    end
    if type(req.__callback) == "function" then req.__callback(result) end
  end)

  return nil
end

return M
