---@module 'pdfport_nvim.backends'
---@brief Loads and registers all built-in extraction backends.

local registry = require("pdfport_nvim.core.registry")

local M = {}

---@type { id: PdfPort.BackendId, module: string }[]
local BUILTIN_BACKENDS = {
  { id = "pdftotext",  module = "pdfport_nvim.backends.pdftotext"  },
  { id = "pdfplumber", module = "pdfport_nvim.backends.pdfplumber" },
  { id = "marker",     module = "pdfport_nvim.backends.marker"     },
  { id = "docling",    module = "pdfport_nvim.backends.docling"    },
  { id = "ollama",     module = "pdfport_nvim.backends.ollama"     },
  { id = "claude",     module = "pdfport_nvim.backends.claude"     },
}

---@return nil
function M.load_all()
  for i = 1, #BUILTIN_BACKENDS do
    local entry = BUILTIN_BACKENDS[i]
    local ok, backend = pcall(require, entry.module)
    if ok and type(backend) == "table" then
      ---@cast backend PdfPort.Backend
      registry.register_backend(backend)
    end
  end
end

---@param module_path string
---@return boolean ok
---@return string|nil error_msg
function M.load_custom(module_path)
  local ok, backend = pcall(require, module_path)
  if not ok then
    return false, string.format("pdfport_nvim: failed to load backend '%s': %s", module_path, backend)
  end
  if type(backend) ~= "table" or type(backend.id) ~= "string" then
    return false, string.format("pdfport_nvim: '%s' did not return a valid PdfPort.Backend", module_path)
  end
  registry.register_backend(backend)
  return true, nil
end

return M
