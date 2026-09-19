---@module 'pdfport.util.cache'
---@brief Cross-session cache for extracted PDF text.
---@description
--- Wraps lib.nvim.cache.disk under a single namespace, keyed by
--- path + backend id + page-range variant. Invalidated by the source file's
--- mtime rather than a blanket TTL — a PDF that hasn't changed on disk stays
--- cached indefinitely; one that has is re-extracted transparently.
---
--- `path` is expected to be canonical (`util.path.canonical`): the key is a
--- string, so two spellings of one file would be two entries. `core.dispatcher`
--- canonicalizes before it calls in here, and is the only caller.
---
--- Capped at MAX_ENTRIES, oldest-cached-first, since mtime invalidation alone
--- never shrinks the store. A loaded entry's fields are re-validated by type
--- before being trusted (it is a JSON file on disk, not something only this
--- module ever writes) and dropped on the first mismatch.

local disk = require("lib.nvim.cache.disk")

local uv = vim.uv or vim.loop

local M = {}

local NAMESPACE = "pdfport_extract"

-- mtime invalidation makes a *stale* entry unreadable but never removes it,
-- so without a cap the store grows forever: one entry per (path, backend,
-- variant) combination ever opened, including files since deleted, renamed,
-- or re-extracted under a different backend/variant, each holding a PDF's
-- full extracted text. Evicted oldest-cached-first once the count is
-- exceeded, so the store -- one JSON file, fully parsed on every read and
-- write -- cannot grow without bound for the life of the install.
local MAX_ENTRIES = 500

---@internal
---@param path string
---@param backend_id string|nil
---@param variant string
---@return string
local function cache_key(path, backend_id, variant)
  return string.format("%s::%s::%s", path, backend_id or "auto", variant)
end

---@internal
---@param path string
---@return integer|nil
local function mtime(path)
  local stat = uv.fs_stat(path)
  return stat and stat.mtime and stat.mtime.sec or nil
end

---@internal
---Removes the oldest-cached entries in place until `store` is at most
---`MAX_ENTRIES` long, called right before every save.
---@param store table<string, table>
---@return nil
local function evict_oldest(store)
  local keys = {}
  for k in pairs(store) do
    keys[#keys + 1] = k
  end
  if #keys <= MAX_ENTRIES then return end

  table.sort(keys, function(a, b)
    return (store[a].cached_at or 0) < (store[b].cached_at or 0)
  end)
  for i = 1, #keys - MAX_ENTRIES do
    store[keys[i]] = nil
  end
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

  local key = cache_key(path, backend_id, variant)
  local entry = store[key]
  if not entry or entry.mtime ~= file_mtime then return nil end

  -- A persisted entry is untrusted input: a hand-edited store, a JSON null
  -- decoding to vim.NIL, or any writer other than this module can leave a
  -- field with the wrong type -- and `text` flows straight into
  -- renderers/buffer.lua's vim.split() the moment it is trusted. Reject the
  -- whole entry on the first bad field rather than passing it through and
  -- crashing somewhere else, and drop it from the store so the corrupt
  -- entry does not leave this PDF permanently unopenable via the cache.
  if
    type(entry.text) ~= "string"
    or type(entry.format) ~= "string"
    or type(entry.backend) ~= "string"
    or (entry.pages_processed ~= nil and type(entry.pages_processed) ~= "number")
  then
    store[key] = nil
    disk.save(NAMESPACE, store)
    return nil
  end

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
    cached_at = os.time(),
  }

  evict_oldest(store)
  disk.save(NAMESPACE, store)
end

---@return boolean ok
function M.clear()
  return disk.clear(NAMESPACE)
end

return M
