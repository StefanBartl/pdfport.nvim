---@module 'pdfport.backends.pdftotext'
---@brief Extraction backend using the pdftotext CLI from poppler-utils.
---@description
--- Runs pdftotext asynchronously via lib.nvim.cross.uv.spawn_capture.
--- Install: apt install poppler-utils | brew install poppler | winget install poppler

local platform = require("pdfport.platform")
local spawn_capture = require("lib.nvim.cross.uv.spawn_capture")
local spawn_env = require("pdfport.util.spawn_env")

--- See the note on `Backend` in `@types/init.lua`: declared as a class so
--- the methods defined below the literal count as implementing it.
---@class PdfPort.Backend.Pdftotext : PdfPort.StatefulBackend
local M = {
  id = "pdftotext",
  name = "pdftotext (poppler-utils)",
  capabilities = {
    markdown = false,
    tables = false,
    ocr = false,
    remote = false,
    gpu_optional = false,
  },
}

---@return boolean
function M.available()
  return platform.has("pdftotext")
end

--- pdftotext has no "these pages" flag, only the span `-f first -l last`.
--- Work out that span and whether it is exactly the requested set.
---@param pages integer[]  non-empty; need not be sorted or free of duplicates
---@return integer first
---@return integer last
---@return table<integer, true> wanted
---@return boolean exact  true when every page of the span was requested
local function plan_span(pages)
  local first, last, distinct = math.huge, -math.huge, 0
  local wanted = {}
  for _, p in ipairs(pages) do
    if not wanted[p] then
      wanted[p] = true
      distinct = distinct + 1
    end
    if p < first then first = p end
    if p > last then last = p end
  end
  return first, last, wanted, distinct == last - first + 1
end

--- Cut the text of a `first..last` run down to the pages in `wanted`.
---
--- pdftotext ends every page with a form feed, also the last one, so the n-th
--- segment is page `first + n - 1`. Each kept page keeps its own terminator,
--- which leaves the output in the same shape pdftotext itself prints. A text
--- without any form feed cannot be split, so it is returned whole.
---@param text string
---@param first integer
---@param wanted table<integer, true>
---@return string
local function keep_pages(text, first, wanted)
  local kept, pos, page = {}, 1, first
  while true do
    local ff = text:find("\f", pos, true)
    if not ff then break end
    if wanted[page] then kept[#kept + 1] = text:sub(pos, ff) end
    pos, page = ff + 1, page + 1
  end
  if page == first then return text end
  if pos <= #text and wanted[page] then kept[#kept + 1] = text:sub(pos) end
  return table.concat(kept)
end

---@param path string
---@param opts PdfPort.InternalExtractOpts
---@return PdfPort.Result|nil
function M.extract(path, opts)
  local args = { "-layout", "-enc", "UTF-8" }

  local has_pages = opts.pages ~= nil and #opts.pages > 0
  local first, wanted, exact
  if has_pages then
    local last
    first, last, wanted, exact = plan_span(opts.pages)
    args[#args + 1] = "-f"
    args[#args + 1] = tostring(first)
    args[#args + 1] = "-l"
    args[#args + 1] = tostring(last)
  elseif opts.max_pages then
    args[#args + 1] = "-l"
    args[#args + 1] = tostring(opts.max_pages)
  end

  args[#args + 1] = path
  args[#args + 1] = "-"

  local timeout_ms = opts.timeout_ms or 30000
  local argv = { "pdftotext" }
  for _, a in ipairs(args) do
    argv[#argv + 1] = a
  end

  spawn_capture(argv, { timeout_ms = timeout_ms, env = spawn_env.array() }, function(spawn_result)
    local result
    if spawn_result.timed_out then
      result = {
        status = "error",
        text = nil,
        format = "plain",
        backend = "pdftotext",
        pages_processed = nil,
        error = string.format("pdftotext: timed out after %d ms", timeout_ms),
      }
    elseif spawn_result.ok then
      local text = spawn_result.stdout
      -- A disjoint request ("1-3,5") has to come out as exactly those pages:
      -- the span would otherwise drag in page 4 as well.
      if has_pages and not exact and type(text) == "string" then
        text = keep_pages(text, first, wanted)
      end
      result = {
        status = "ok",
        text = text,
        format = "plain",
        backend = "pdftotext",
        -- An explicit selection is not a page count (same as pdfplumber).
        pages_processed = (not has_pages) and opts.max_pages or nil,
        error = nil,
      }
    else
      result = {
        status = "error",
        text = nil,
        format = "plain",
        backend = "pdftotext",
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
