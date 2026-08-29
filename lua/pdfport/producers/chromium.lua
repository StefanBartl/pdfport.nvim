---@module 'pdfport.producers.chromium'
---@brief HTML → PDF producer using a Chromium-family browser's headless
---@brief print-to-pdf.
---@description
--- Fallback behind weasyprint: no Python dependency, but a heavier process
--- and a gruesome CLI (fixed default margins, no CSS Paged Media). Tries
--- chromium → google-chrome → chrome → msedge, in that order — whichever
--- Chromium-family binary is actually on PATH.

local platform = require("pdfport.platform")
local spawn_capture = require("lib.nvim.cross.uv.spawn_capture")

--- See the note on `Producer` in `@types/init.lua`: declared as a class so
--- the methods defined below the literal count as implementing it.
---@class PdfPort.Producer.Chromium : PdfPort.Producer
local M = {
  id = "chromium",
  name = "chromium (headless print-to-pdf)",
  accepts = { "html" },
  capabilities = {
    batch = false,
    lossless = false,
    styling = false,
    toc = false,
    remote = false,
  },
}

---@internal Order matters: dedicated Chromium/Chrome builds before the
---platform-bundled Edge, which not everyone wants pdfport reaching for.
local BROWSER_CHAIN = { "chromium", "chromium-browser", "google-chrome", "chrome", "msedge" }

---@internal
---@return string|nil
local function resolve_browser()
  return platform.first_available(BROWSER_CHAIN)
end

---@return boolean
function M.available()
  return resolve_browser() ~= nil
end

---@param req PdfPort.InternalCreateOpts
---@return PdfPort.CreateResult|nil
function M.create(req)
  local browser = resolve_browser()
  if not browser then
    local result = {
      status = "error",
      path = nil,
      producer = "chromium",
      pages = nil,
      error = "chromium: no Chromium-family browser found (chromium/google-chrome/chrome/msedge)",
    }
    if type(req.__callback) == "function" then req.__callback(result) end
    return nil
  end

  -- file:// URL, not a bare path — headless Chrome only reliably resolves a
  -- bare filesystem path to a page on some platforms; the URL form works
  -- everywhere the same way.
  local input_path = vim.fn.fnamemodify(req.inputs[1], ":p"):gsub("\\", "/")
  local input_url = "file:///" .. input_path:gsub("^/+", "")

  local argv = {
    browser,
    "--headless",
    "--disable-gpu",
    "--no-pdf-header-footer",
    "--print-to-pdf=" .. req.output,
    input_url,
  }

  local timeout_ms = req.timeout_ms or 60000

  spawn_capture(argv, { timeout_ms = timeout_ms }, function(spawn_result)
    local result
    if spawn_result.timed_out then
      result = {
        status = "error",
        path = nil,
        producer = "chromium",
        pages = nil,
        error = string.format("chromium: timed out after %d ms", timeout_ms),
      }
    elseif spawn_result.ok then
      result = {
        status = "ok",
        path = req.output,
        producer = "chromium",
        pages = nil,
        error = nil,
      }
    else
      result = {
        status = "error",
        path = nil,
        producer = "chromium",
        pages = nil,
        error = string.format("chromium exited %d: %s", spawn_result.code, spawn_result.stderr),
      }
    end
    if type(req.__callback) == "function" then req.__callback(result) end
  end)

  return nil
end

return M
