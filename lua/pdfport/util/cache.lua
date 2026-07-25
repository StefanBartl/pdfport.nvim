---@module 'pdfport.util.cache'
---@brief Cross-session cache for extracted PDF text.
---@description
--- Wraps lib.nvim.cache.disk under a single namespace, keyed by
--- path + backend id + page-range variant. Invalidated by the source file's
--- mtime rather than a blanket TTL — a PDF that hasn't changed on disk stays
--- cached indefinitely; one that has is re-extracted transparently.

local disk = require("lib.nvim.cache.disk")

local uv = vim.uv or vim.loop

local M = {}

local NAMESPACE = "pdfport_extract"

---@param path string
---@param backend_id string|nil
---@param variant string
---@return string
local function cache_key(path, backend_id, variant)
  return string.format("%s::%s::%s", path, backend_id or "auto", variant)
end

---@param path string
---@return integer|nil
local function mtime(path)
  local stat = uv.fs_stat(path)
  return stat and stat.mtime and stat.mtime.sec or nil
end

---@param path string
---@param backend_id string|nil
---@param variant string  page-range discriminator, e.g. "all" or "1,2,3"
---@return PdfPort.Result|nil
function M.get(path, backend_id, variant)
  local file_mtime = mtime(path)
  if not file_mtime then return nil end

  local store = disk.load(NAMESPACE)
  if type(store) ~= "table" then return nil end

  local entry = store[cache_key(path, backend_id, variant)]
  if not entry or entry.mtime ~= file_mtime then return nil end

  return {
    status = "ok",
    text = entry.text,
    format = entry.format,
    backend = entry.backend,
    pages_processed = entry.pages_processed,
    error = nil,
  }
end

---@param path string
---@param backend_id string|nil
---@param variant string
---@param result PdfPort.Result
---@return nil
function M.set(path, backend_id, variant, result)
  if not result or result.status ~= "ok" or not result.text then return end
  local file_mtime = mtime(path)
  if not file_mtime then return end

  local store = disk.load(NAMESPACE)
  if type(store) ~= "table" then store = {} end

  store[cache_key(path, backend_id, variant)] = {
    text = result.text,
    format = result.format,
    backend = result.backend,
    pages_processed = result.pages_processed,
    mtime = file_mtime,
  }
  disk.save(NAMESPACE, store)
end

---@return boolean ok
function M.clear()
  return disk.clear(NAMESPACE)
end

return M
