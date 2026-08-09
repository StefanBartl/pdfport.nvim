---@module 'pdfport.producers'
---@brief Loads and registers all built-in creation producers.
---@description
--- Mirrors backends/init.lua: producers are registered as lazy proxies, the
--- real module is only `require`d the first time the composer's resolver
--- walks the fallback chain far enough to consider it, not unconditionally
--- at setup() time.

local registry = require("pdfport.core.registry")

local M = {}

---@type { id: PdfPort.ProducerId, module: string }[]
local BUILTIN_PRODUCERS = {
  { id = "img2pdf", module = "pdfport.producers.img2pdf" },
  { id = "magick", module = "pdfport.producers.magick" },
  { id = "pandoc", module = "pdfport.producers.pandoc" },
}

---@internal
---@param entry { id: PdfPort.ProducerId, module: string }
---@param cfg PdfPort.Config|nil
---@return PdfPort.Producer
local function make_lazy_producer(entry, cfg)
  ---@type PdfPort.Producer|nil
  local loaded = nil
  local load_failed = false

  local function load()
    if loaded or load_failed then return loaded end
    local ok, producer = pcall(require, entry.module)
    if ok and type(producer) == "table" then
      loaded = producer
      if cfg and type(producer._set_config) == "function" then producer._set_config(cfg) end
    else
      load_failed = true
    end
    return loaded
  end

  return setmetatable({
    id = entry.id,

    available = function()
      local p = load()
      if not p then return false end
      local ok, avail = pcall(p.available)
      return ok and avail == true
    end,

    create = function(req)
      local p = load()
      if not p then
        return {
          status = "error",
          path = nil,
          producer = entry.id,
          pages = nil,
          error = string.format("pdfport: producer '%s' failed to load", entry.id),
        }
      end
      return p.create(req)
    end,
  }, {
    __index = function(_, key)
      local p = load()
      return p and p[key] or nil
    end,
  })
end

---@param cfg? PdfPort.Config
---@return nil
function M.load_all(cfg)
  for i = 1, #BUILTIN_PRODUCERS do
    registry.register_producer(make_lazy_producer(BUILTIN_PRODUCERS[i], cfg))
  end
end

---@param module_path string
---@return boolean ok
---@return string|nil error_msg
function M.load_custom(module_path)
  local ok, producer = pcall(require, module_path)
  if not ok then
    return false, string.format("pdfport: failed to load producer '%s': %s", module_path, producer)
  end
  if type(producer) ~= "table" or type(producer.id) ~= "string" then
    return false,
      string.format("pdfport: '%s' did not return a valid PdfPort.Producer", module_path)
  end
  registry.register_producer(producer)
  return true, nil
end

return M
