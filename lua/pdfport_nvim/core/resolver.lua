---@module 'pdfport_nvim.core.resolver'
---@brief Backend selection and fallback chain resolution for pdfport.nvim.
---@description
--- Resolves the first available backend for a given request.
--- The fallback chain is walked in priority order; availability checks are
--- cached in platform.lua so repeated calls are fast.

local registry = require("pdfport_nvim.core.registry")

local M = {}

---@type PdfPort.Config|nil
local _config = nil

---@param config PdfPort.Config
---@return nil
function M._set_config(config)
  _config = config
end

---@param requested PdfPort.BackendId|"auto"|nil
---@return PdfPort.BackendId[]
local function build_chain(requested)
  local cfg          = _config or {}
  local global_chain = cfg.fallback_chain or {}

  if requested and requested ~= "auto" then
    local chain = { [#global_chain + 1] = nil }
    chain[1] = requested
    for i = 1, #global_chain do chain[i + 1] = global_chain[i] end
    return chain
  end

  if cfg.default_backend and cfg.default_backend ~= "auto" then
    local chain = { cfg.default_backend }
    for i = 1, #global_chain do
      if global_chain[i] ~= cfg.default_backend then
        chain[#chain + 1] = global_chain[i]
      end
    end
    return chain
  end

  local chain = {}
  for i = 1, #global_chain do
    chain[#chain + 1] = global_chain[i]
  end
  for _, id in ipairs(registry.backend_ids()) do
    chain[#chain + 1] = id
  end
  return require("lib.lua.tables").dedup_list(chain)
end

---@param requested PdfPort.BackendId|"auto"|nil
---@return PdfPort.Backend|nil backend
---@return string|nil error_msg
function M.resolve(requested)
  local chain = build_chain(requested)
  for i = 1, #chain do
    local backend = registry.get_backend(chain[i])
    if backend then
      local ok, avail = pcall(backend.available)
      if ok and avail then return backend, nil end
    end
  end
  return nil, string.format("pdfport_nvim: no available backend. Tried: [%s]", table.concat(chain, ", "))
end

---@return PdfPort.Backend[]
function M.available_backends()
  local chain  = build_chain("auto")
  local result = {}
  for i = 1, #chain do
    local backend = registry.get_backend(chain[i])
    if backend then
      local ok, avail = pcall(backend.available)
      if ok and avail then result[#result + 1] = backend end
    end
  end
  return result
end

return M
