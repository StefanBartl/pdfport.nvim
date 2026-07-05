---@module 'pdfport_nvim'
---@brief Public API entry point for pdfport.nvim.
---@description
--- Quick start:
---
---   require("pdfport_nvim").setup({
---     default_backend = "auto",
---     fallback_chain  = { "pdftotext", "marker", "docling", "claude" },
---   })
---
--- Open a PDF from Lua:
---
---   require("pdfport_nvim").open({
---     path       = "/path/to/file.pdf",
---     mode       = "buffer",   -- "buffer"|"float"|"terminal"|"system"
---     backend_id = "marker",   -- optional; nil = auto
---   })
---
--- Extract text only (without rendering):
---
---   require("pdfport_nvim").extract({
---     path       = "/path/to/file.pdf",
---     max_pages  = 5,
---     __callback = function(result) ... end,
---   })

local M = {}

local config = require("pdfport_nvim.config")

---@type boolean
local _initialized = false

-- #############################################################################
-- Setup
-- #############################################################################

---@param user_config? PdfPort.Config
---@return nil
function M.setup(user_config)
  config.setup(user_config)
  local cfg = config.get()

  require("pdfport_nvim.core.resolver")._set_config(cfg)
  require("pdfport_nvim.core.dispatcher")._set_config(cfg)

  local ok_claude, claude = pcall(require, "pdfport_nvim.backends.claude")
  if ok_claude and type(claude._set_config) == "function" then
    claude._set_config(cfg)
  end

  local ok_ollama, ollama = pcall(require, "pdfport_nvim.backends.ollama")
  if ok_ollama and type(ollama._set_config) == "function" then
    ollama._set_config(cfg)
  end

  require("pdfport_nvim.backends").load_all()

  local reg = require("pdfport_nvim.core.registry")

  local renderers = {
    { id = "buffer",   mod = "pdfport_nvim.renderers.buffer"   },
    { id = "float",    mod = "pdfport_nvim.renderers.float"    },
    { id = "system",   mod = "pdfport_nvim.renderers.system"   },
    { id = "terminal", mod = "pdfport_nvim.renderers.terminal" },
  }
  for _, r in ipairs(renderers) do
    local ok_r, rm = pcall(require, r.mod)
    if ok_r then reg.register_renderer(r.id, rm.render) end
  end

  M._register_commands()

  _initialized = true

  if cfg.debug then
    vim.notify("pdfport_nvim: initialized", vim.log.levels.DEBUG)
  end
end

-- #############################################################################
-- Public API
-- #############################################################################

---@param opts PdfPort.OpenOpts
---@return nil
function M.open(opts)
  if not _initialized then M.setup() end

  assert(type(opts) == "table", "pdfport_nvim.open: opts must be a table")
  assert(type(opts.path) == "string" and opts.path ~= "", "pdfport_nvim.open: opts.path must be a non-empty string")

  require("pdfport_nvim.core.dispatcher").open(opts)
end

---@param opts PdfPort.InternalExtractOpts
---@return nil
function M.extract(opts)
  if not _initialized then M.setup() end

  assert(type(opts) == "table", "pdfport_nvim.extract: opts must be a table")
  assert(type(opts.path) == "string", "pdfport_nvim.extract: opts.path must be a string")
  assert(type(opts.__callback) == "function", "pdfport_nvim.extract: opts.__callback must be a function")

  require("pdfport_nvim.core.dispatcher").dispatch(opts, opts.__callback)
end

---@return PdfPort.Config
function M.config()
  return vim.deepcopy(config.get())
end

---@return table  Module with commands() and keymaps()
function M.neotree()
  return require("pdfport_nvim.integrations.neotree")
end

---@return table  Module with setup_nvim_tree()
function M.nvim_tree()
  return require("pdfport_nvim.integrations.nvim_tree")
end

---@return table  Module with setup()
function M.netrw()
  return require("pdfport_nvim.integrations.netrw")
end

---@return table  Module with setup()
function M.oil()
  return require("pdfport_nvim.integrations.oil")
end

---@return table  Unified integration (open_current, current_pdf_path)
function M.integrations()
  return require("pdfport_nvim.integrations")
end

---@return table  Module with previewer() and filetype_hook
function M.telescope()
  return require("pdfport_nvim.integrations.telescope")
end

---@return table  Module with preview_fn()
function M.fzf()
  return require("pdfport_nvim.integrations.fzf")
end

---@param backend PdfPort.Backend
---@return nil
function M.register_backend(backend)
  require("pdfport_nvim.core.registry").register_backend(backend)
end

-- #############################################################################
-- User commands
-- #############################################################################

---@return nil
function M._register_commands()
  require("pdfport_nvim.bindings.usrcmds").register(M)
end

return M
