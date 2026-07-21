---@module 'pdfport'
---@brief Public API entry point for pdfport.nvim.
---@description
--- Quick start:
---
---   require("pdfport").setup({
---     default_backend = "auto",
---     fallback_chain  = { "pdftotext", "marker", "docling", "claude" },
---   })
---
--- Open a PDF from Lua:
---
---   require("pdfport").open({
---     path       = "/path/to/file.pdf",
---     mode       = "buffer",   -- "buffer"|"float"|"terminal"|"system"
---     backend_id = "marker",   -- optional; nil = auto
---   })
---
--- Extract text only (without rendering):
---
---   require("pdfport").extract({
---     path       = "/path/to/file.pdf",
---     max_pages  = 5,
---     __callback = function(result) ... end,
---   })

local M = {}

local config = require("pdfport.config")
local notify = require("pdfport.util.notify").create("[pdfport]")

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

  require("pdfport.core.resolver")._set_config(cfg)
  require("pdfport.core.dispatcher")._set_config(cfg)

  local ok_claude, claude = pcall(require, "pdfport.backends.claude")
  if ok_claude and type(claude._set_config) == "function" then
    claude._set_config(cfg)
  end

  local ok_ollama, ollama = pcall(require, "pdfport.backends.ollama")
  if ok_ollama and type(ollama._set_config) == "function" then
    ollama._set_config(cfg)
  end

  require("pdfport.backends").load_all()

  local reg = require("pdfport.core.registry")

  local renderers = {
    { id = "buffer",   mod = "pdfport.renderers.buffer"   },
    { id = "float",    mod = "pdfport.renderers.float"    },
    { id = "system",   mod = "pdfport.renderers.system"   },
    { id = "terminal", mod = "pdfport.renderers.terminal" },
  }
  for _, r in ipairs(renderers) do
    local ok_r, rm = pcall(require, r.mod)
    if ok_r then reg.register_renderer(r.id, rm.render) end
  end

  M._register_commands()

  _initialized = true

  notify.debug("initialized", cfg)
end

-- #############################################################################
-- Public API
-- #############################################################################

---@param opts PdfPort.OpenOpts
---@param on_error? fun(msg: string): nil  Defaults to this plugin's own
---notifier, so existing callers (integrations, the picker) keep seeing
---errors without having to opt in explicitly. Pass your own to decide
---presentation yourself (as bindings/usrcmds.lua does).
---@return nil
function M.open(opts, on_error)
  if not _initialized then M.setup() end

  assert(type(opts) == "table", "pdfport.open: opts must be a table")
  assert(type(opts.path) == "string" and opts.path ~= "", "pdfport.open: opts.path must be a non-empty string")

  require("pdfport.core.dispatcher").open(opts, on_error or notify.error)
end

---@param opts PdfPort.InternalExtractOpts
---@return nil
function M.extract(opts)
  if not _initialized then M.setup() end

  assert(type(opts) == "table", "pdfport.extract: opts must be a table")
  assert(type(opts.path) == "string", "pdfport.extract: opts.path must be a string")
  assert(type(opts.__callback) == "function", "pdfport.extract: opts.__callback must be a function")

  require("pdfport.core.dispatcher").dispatch(opts, opts.__callback)
end

---@return PdfPort.Config
function M.config()
  return vim.deepcopy(config.get())
end

---@return table  Module with commands() and keymaps()
function M.neotree()
  return require("pdfport.integrations.neotree")
end

---@return table  Module with setup_nvim_tree()
function M.nvim_tree()
  return require("pdfport.integrations.nvim_tree")
end

---@return table  Module with setup()
function M.netrw()
  return require("pdfport.integrations.netrw")
end

---@return table  Module with setup()
function M.oil()
  return require("pdfport.integrations.oil")
end

---@return table  Unified integration (open_current, current_pdf_path)
function M.integrations()
  return require("pdfport.integrations")
end

---@return table  Module with previewer() and filetype_hook
function M.telescope()
  return require("pdfport.integrations.telescope")
end

---@return table  Module with preview_fn()
function M.fzf()
  return require("pdfport.integrations.fzf")
end

---@param backend PdfPort.Backend
---@return nil
function M.register_backend(backend)
  require("pdfport.core.registry").register_backend(backend)
end

-- #############################################################################
-- User commands
-- #############################################################################

---@return nil
function M._register_commands()
  require("pdfport.bindings.usrcmds").register(M)
end

return M
