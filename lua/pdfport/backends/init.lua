---@module 'pdfport.backends'
---@brief Loads and registers all built-in extraction backends.
---@description
--- Backends are registered as lazy proxies: the real module (and whatever
--- work its top-level `require`s do) is only loaded the first time the
--- proxy's `available`/`extract`/any other field is actually touched — i.e.
--- when the resolver walks the fallback chain far enough to consider that
--- backend, not unconditionally at setup() time.

local registry = require("pdfport.core.registry")

local M = {}

---@type { id: PdfPort.BackendId, module: string }[]
local BUILTIN_BACKENDS = {
  { id = "pdftotext", module = "pdfport.backends.pdftotext" },
  { id = "pdfplumber", module = "pdfport.backends.pdfplumber" },
  { id = "marker", module = "pdfport.backends.marker" },
  { id = "docling", module = "pdfport.backends.docling" },
  { id = "ollama", module = "pdfport.backends.ollama" },
  { id = "tesseract", module = "pdfport.backends.tesseract" },
  { id = "claude", module = "pdfport.backends.claude" },
}

---@internal
---@param entry { id: PdfPort.BackendId, module: string }
---@param cfg PdfPort.Config|nil
---@return PdfPort.Backend
local function make_lazy_backend(entry, cfg)
  ---@type PdfPort.Backend|nil
  local loaded = nil
  local load_failed = false

  local function load()
    if loaded or load_failed then return loaded end
    local ok, backend = pcall(require, entry.module)
    if ok and type(backend) == "table" then
      loaded = backend
      if cfg and type(backend._set_config) == "function" then backend._set_config(cfg) end
    else
      load_failed = true
    end
    return loaded
  end

  return setmetatable({
    id = entry.id,

    available = function()
      local b = load()
      if not b then return false end
      local ok, avail = pcall(b.available)
      return ok and avail == true
    end,

    extract = function(path, opts)
      local b = load()
      if not b then
        return {
          status = "error",
          text = nil,
          format = "plain",
          backend = entry.id,
          pages_processed = nil,
          error = string.format("pdfport: backend '%s' failed to load", entry.id),
        }
      end
      return b.extract(path, opts)
    end,
  }, {
    -- Any other field access (name, capabilities, _set_config, ...) also
    -- triggers the load — those are only ever read once availability was
    -- already established, so this never loads a backend earlier than
    -- available()/extract() already would.
    __index = function(_, key)
      local b = load()
      return b and b[key] or nil
    end,
  })
end

---@param cfg? PdfPort.Config
---@return nil
function M.load_all(cfg)
  for i = 1, #BUILTIN_BACKENDS do
    registry.register_backend(make_lazy_backend(BUILTIN_BACKENDS[i], cfg))
  end
end

---@param module_path string
---@return boolean ok
---@return string|nil error_msg
function M.load_custom(module_path)
  local ok, backend = pcall(require, module_path)
  if not ok then
    return false, string.format("pdfport: failed to load backend '%s': %s", module_path, backend)
  end
  if type(backend) ~= "table" or type(backend.id) ~= "string" then
    return false, string.format("pdfport: '%s' did not return a valid PdfPort.Backend", module_path)
  end
  registry.register_backend(backend)
  return true, nil
end

return M
