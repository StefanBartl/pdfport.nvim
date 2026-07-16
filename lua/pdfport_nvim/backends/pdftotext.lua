---@module 'pdfport_nvim.backends.pdftotext'
---@brief Extraction backend using the pdftotext CLI from poppler-utils.
---@description
--- Runs pdftotext asynchronously via lib.nvim.cross.uv.spawn_capture.
--- Install: apt install poppler-utils | brew install poppler | winget install poppler

local platform = require("pdfport_nvim.platform")
local spawn_capture = require("lib.nvim.cross.uv.spawn_capture")

---@type PdfPort.StatefulBackend
local M = {
  id   = "pdftotext",
  name = "pdftotext (poppler-utils)",
  capabilities = {
    markdown     = false,
    tables       = false,
    ocr          = false,
    remote       = false,
    gpu_optional = false,
  },
}

---@return boolean
function M.available()
  return platform.has("pdftotext")
end

---@param path string
---@param opts PdfPort.InternalExtractOpts
---@return PdfPort.Result|nil
function M.extract(path, opts)
  local args = { "-layout", "-enc", "UTF-8" }

  if opts.pages and #opts.pages > 0 then
    args[#args + 1] = "-f"; args[#args + 1] = tostring(opts.pages[1])
    args[#args + 1] = "-l"; args[#args + 1] = tostring(opts.pages[#opts.pages])
  elseif opts.max_pages then
    args[#args + 1] = "-l"; args[#args + 1] = tostring(opts.max_pages)
  end

  args[#args + 1] = path
  args[#args + 1] = "-"

  local timeout_ms = opts.timeout_ms or 30000
  local argv = { "pdftotext" }
  for _, a in ipairs(args) do argv[#argv + 1] = a end

  spawn_capture(argv, { timeout_ms = timeout_ms }, function(spawn_result)
    local result
    if spawn_result.timed_out then
      result = {
        status = "error", text = nil, format = "plain", backend = "pdftotext",
        pages_processed = nil,
        error = string.format("pdftotext: timed out after %d ms", timeout_ms),
      }
    elseif spawn_result.ok then
      result = {
        status = "ok", text = spawn_result.stdout, format = "plain", backend = "pdftotext",
        pages_processed = opts.max_pages, error = nil,
      }
    else
      result = {
        status = "error", text = nil, format = "plain", backend = "pdftotext",
        pages_processed = nil,
        error = string.format("pdftotext exited %d: %s", spawn_result.code, spawn_result.stderr),
      }
    end
    M._last_result = result
    if type(opts.__callback) == "function" then opts.__callback(result) end
  end)

  return nil
end

return M
