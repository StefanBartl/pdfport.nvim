---@module 'pdfport.util.page_count'
---@brief Page count of a PDF via `pdfinfo`, and the "only page 1" notice.
---@description
--- `ollama` and `tesseract` process page 1 only when the caller names neither
--- `pages` nor `max_pages` (an unbounded run would mean one slow, uncancellable
--- model/OCR request per page). That is a deliberate default, but it used to
--- come back as a plain "ok" for a multi-page document -- and was cached as
--- the whole thing. `annotate` turns it into a "partial" result that says so.
--- `pdfinfo` ships with poppler next to `pdftoppm`; when it is missing or
--- fails, the result stays "ok" (nothing to compare against).

local spawn_env = require("pdfport.util.spawn_env")

local M = {}

---Page count of `path`, or nil when `pdfinfo` is unavailable or fails.
---@param path string
---@param callback fun(count: integer|nil)  Always called, on the main loop
---@return nil
function M.count(path, callback)
  local started = pcall(function()
    vim.system({ "pdfinfo", path }, spawn_env.opts({ text = true }), function(res)
      local pages = res.code == 0 and tonumber((res.stdout or ""):match("Pages:%s*(%d+)")) or nil
      vim.schedule(function()
        callback(pages)
      end)
    end)
  end)
  if not started then vim.schedule(function()
    callback(nil)
  end) end
end

---Marks `result` "partial" when the document has more pages than were processed,
---then hands it to `callback`. Only meant for the implicit first-page default.
---@param result PdfPort.Result
---@param path string
---@param backend string  Backend id, used in the message
---@param callback fun(result: PdfPort.Result)
---@return nil
function M.annotate(result, path, backend, callback)
  M.count(path, function(total)
    if total and total > (result.pages_processed or 1) then
      result.status = "partial"
      result.error = string.format(
        "%s: only page %d of %d processed -- pass pages= or max_pages= for more",
        backend,
        result.pages_processed or 1,
        total
      )
    end
    callback(result)
  end)
end

return M
