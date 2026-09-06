---@module 'pdfport.core.registry'
---@brief Backend, producer, and renderer registry for pdfport.nvim.
---@description
--- Three independent registries: extraction backends, creation producers, and
--- output renderers. Registration is idempotent. All lookups are O(1).

local M = {}

---@type table<PdfPort.BackendId, PdfPort.Backend>
local _backends = {}

---@type PdfPort.BackendId[]
local _backend_order = {}

---@param backend PdfPort.Backend
---@return nil
function M.register_backend(backend)
  assert(type(backend) == "table", "backend must be a table")
  assert(type(backend.id) == "string" and backend.id ~= "", "backend.id must be a non-empty string")
  assert(type(backend.available) == "function", "backend.available must be a function")
  assert(type(backend.extract) == "function", "backend.extract must be a function")

  if not _backends[backend.id] then _backend_order[#_backend_order + 1] = backend.id end
  _backends[backend.id] = backend
end

---@param id PdfPort.BackendId
---@return PdfPort.Backend|nil
function M.get_backend(id)
  return _backends[id]
end

---@return PdfPort.Backend[]
function M.all_backends()
  local result = { [#_backend_order] = nil }
  for i = 1, #_backend_order do
    result[i] = _backends[_backend_order[i]]
  end
  return result
end

---@return PdfPort.BackendId[]
function M.backend_ids()
  local ids = { [#_backend_order] = nil }
  for i = 1, #_backend_order do
    ids[i] = _backend_order[i]
  end
  return ids
end

---@param id PdfPort.BackendId
---@return boolean
function M.has_backend(id)
  return _backends[id] ~= nil
end

-- #############################################################################
-- Producer registry (PDF creation — the reverse of extraction)
-- #############################################################################

---@type table<PdfPort.ProducerId, PdfPort.Producer>
local _producers = {}

---@type PdfPort.ProducerId[]
local _producer_order = {}

---@param producer PdfPort.Producer
---@return nil
function M.register_producer(producer)
  assert(type(producer) == "table", "producer must be a table")
  assert(
    type(producer.id) == "string" and producer.id ~= "",
    "producer.id must be a non-empty string"
  )
  assert(type(producer.available) == "function", "producer.available must be a function")
  assert(type(producer.create) == "function", "producer.create must be a function")

  if not _producers[producer.id] then _producer_order[#_producer_order + 1] = producer.id end
  _producers[producer.id] = producer
end

---@param id PdfPort.ProducerId
---@return PdfPort.Producer|nil
function M.get_producer(id)
  return _producers[id]
end

---@return PdfPort.Producer[]
function M.all_producers()
  local result = { [#_producer_order] = nil }
  for i = 1, #_producer_order do
    result[i] = _producers[_producer_order[i]]
  end
  return result
end

---@return PdfPort.ProducerId[]
function M.producer_ids()
  local ids = { [#_producer_order] = nil }
  for i = 1, #_producer_order do
    ids[i] = _producer_order[i]
  end
  return ids
end

---@param id PdfPort.ProducerId
---@return boolean
function M.has_producer(id)
  return _producers[id] ~= nil
end

-- #############################################################################
-- Renderer registry
-- #############################################################################

---@type table<PdfPort.RendererMode, fun(result: PdfPort.Result, opts: PdfPort.RenderOpts): nil>
local _renderers = {}

---@param mode PdfPort.RendererMode
---@param fn fun(result: PdfPort.Result, opts: PdfPort.RenderOpts): nil
---@return nil
function M.register_renderer(mode, fn)
  assert(type(mode) == "string" and mode ~= "", "mode must be a non-empty string")
  assert(type(fn) == "function", "renderer fn must be a function")
  _renderers[mode] = fn
end

---@param mode PdfPort.RendererMode
---@return (fun(result: PdfPort.Result, opts: PdfPort.RenderOpts): nil)|nil
function M.get_renderer(mode)
  return _renderers[mode]
end

---@return PdfPort.RendererMode[]
function M.renderer_modes()
  local modes = {}
  for mode in pairs(_renderers) do
    modes[#modes + 1] = mode
  end
  return modes
end

---@return string[]
function M.diagnostics()
  local lines = { "pdfport registry diagnostics", "" }
  lines[#lines + 1] = "Backends:"
  if #_backend_order == 0 then
    lines[#lines + 1] = "  (none registered)"
  else
    for i = 1, #_backend_order do
      local id = _backend_order[i]
      local b = _backends[id]
      local ok, avail = pcall(b.available)
      local status = (ok and avail) and "available" or "unavailable"
      lines[#lines + 1] = string.format("  [%d] %-16s  %s", i, id, status)
    end
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "Producers:"
  if #_producer_order == 0 then
    lines[#lines + 1] = "  (none registered)"
  else
    for i = 1, #_producer_order do
      local id = _producer_order[i]
      local p = _producers[id]
      local ok, avail = pcall(p.available)
      local status = (ok and avail) and "available" or "unavailable"
      lines[#lines + 1] = string.format("  [%d] %-16s  %s", i, id, status)
    end
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "Renderers:"
  local modes = M.renderer_modes()
  if #modes == 0 then
    lines[#lines + 1] = "  (none registered)"
  else
    for _, mode in ipairs(modes) do
      lines[#lines + 1] = string.format("  %-12s", mode)
    end
  end
  return lines
end

return M
