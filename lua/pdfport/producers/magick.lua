---@module 'pdfport.producers.magick'
---@brief Image → PDF producer using ImageMagick's `magick` CLI.
---@description
--- Pragmatic default: already assumed present in this setup (images.nvim's
--- own `convert.lua` builds on `magick`), handles multi-image → multi-page
--- PDF natively. Recompresses (larger, minimally lossier PDFs than img2pdf).
---
--- Always `magick`, never `convert` — `convert.exe` collides with Windows'
--- own `convert` on PATH. See platform.has("magick") below.

local platform = require("pdfport.platform")
local spawn_capture = require("lib.nvim.cross.uv.spawn_capture")

---@type PdfPort.Producer
local M = {
  id = "magick",
  name = "magick (ImageMagick)",
  accepts = { "image" },
  capabilities = {
    batch = true,
    lossless = false,
    styling = false,
    toc = false,
    remote = false,
  },
}

---@return boolean
function M.available()
  return platform.has("magick")
end

---@param req PdfPort.InternalCreateOpts
---@return PdfPort.CreateResult|nil
function M.create(req)
  local argv = { "magick" }
  for _, input in ipairs(req.inputs) do
    argv[#argv + 1] = input
  end
  argv[#argv + 1] = req.output

  local timeout_ms = req.timeout_ms or 60000

  spawn_capture(argv, { timeout_ms = timeout_ms }, function(spawn_result)
    local result
    if spawn_result.timed_out then
      result = {
        status = "error",
        path = nil,
        producer = "magick",
        pages = nil,
        error = string.format("magick: timed out after %d ms", timeout_ms),
      }
    elseif spawn_result.ok then
      result = {
        status = "ok",
        path = req.output,
        producer = "magick",
        pages = #req.inputs,
        error = nil,
      }
    else
      result = {
        status = "error",
        path = nil,
        producer = "magick",
        pages = nil,
        error = string.format("magick exited %d: %s", spawn_result.code, spawn_result.stderr),
      }
    end
    if type(req.__callback) == "function" then req.__callback(result) end
  end)

  return nil
end

return M
