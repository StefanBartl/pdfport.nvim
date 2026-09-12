---@module 'pdfport.producers.chromium'
---@brief HTML → PDF producer using a Chromium-family browser's headless
---@brief print-to-pdf.
---@description
--- Fallback behind weasyprint: no Python dependency, but a heavier process
--- and a gruesome CLI (fixed default margins, no CSS Paged Media). Tries
--- every name `docs/install.json`'s `chrome` entry declares (chromium,
--- chromium-browser, google-chrome, chrome, msedge, ...) on PATH, then that
--- entry's declared `paths` fallback -- a headless browser is not something
--- users typically add to PATH themselves, and PATH alone reports "missing"
--- on a machine that has one plainly installed (measured for the identical
--- tool in hover.nvim/casedesk.nvim; same fix here via `lib.nvim.deps`,
--- rather than a hand-rolled search this module used to keep in sync with
--- `docs/install.json` by hand).

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

---@internal
--- This plugin's own `chrome` tool declaration from `docs/install.json` --
--- the single source of truth `M.available()`/`M.create()` and
--- `pdfport.health`'s browser check all resolve through, rather than each
--- keeping its own copy of the name/location list. Resolved once; a spec
--- that cannot be found or parsed still gets a PATH-only search (via a bare
--- `{ bin = "chrome" }`) rather than none at all.
---@type Lib.Deps.Tool|nil
local _chrome_tool = nil

---@internal
---@return Lib.Deps.Tool
local function chrome_tool()
  if _chrome_tool ~= nil then return _chrome_tool end

  local spec = require("lib.nvim.deps.spec")
  local path = spec.find("pdfport.nvim")
  local result = path and spec.load(path)
  if result then
    for _, tool in ipairs(result.tools) do
      if tool.bin == "chrome" then
        _chrome_tool = tool
        return tool
      end
    end
  end

  _chrome_tool = { bin = "chrome" }
  return _chrome_tool
end

---@internal
---@return string|nil
local function resolve_browser()
  return require("lib.nvim.deps.detect").found_as(chrome_tool())
end

--- The browser `M.create()` would run, or nil -- same probe, not a second
--- copy of it. Public so `pdfport.health`'s `:checkhealth pdfport` line can
--- report on and name the exact binary this producer would actually use.
---@return string|nil
function M.resolved_browser()
  return resolve_browser()
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
