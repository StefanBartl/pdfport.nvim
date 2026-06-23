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

function M._register_commands()
  ---@param arg_lead string
  ---@return string[]
  local function complete_pdf_path(arg_lead)
    if arg_lead == "" then
      local cfile = vim.fn.expand("<cfile>")
      if cfile and cfile ~= "" and vim.fn.filereadable(cfile) == 1 then
        return { cfile }
      end
      return {}
    end
    local completions = vim.fn.glob(arg_lead .. "*", false, true)
    local pdfs, rest  = {}, {}
    for _, p in ipairs(completions) do
      if p:lower():match("%.pdf$") then pdfs[#pdfs + 1] = p
      else                              rest[#rest + 1] = p end
    end
    vim.list_extend(pdfs, rest)
    return pdfs
  end

  ---@param args table
  ---@return string|nil
  local function resolve_path(args)
    if args.args and args.args ~= "" then
      return vim.fn.expand(args.args)
    end
    local cfile = vim.fn.expand("<cfile>")
    if cfile and cfile ~= "" then
      local abs = vim.fn.fnamemodify(cfile, ":p")
      if vim.fn.filereadable(abs) == 1 then return abs end
      if vim.fn.filereadable(cfile) == 1 then return cfile end
    end
    local buf_name = vim.api.nvim_buf_get_name(0)
    if buf_name and buf_name ~= "" then return buf_name end
    return nil
  end

  local base = { nargs = "?", complete = complete_pdf_path }

  vim.api.nvim_create_user_command("PdfPort", function(args)
    local path = resolve_path(args)
    if not path or path == "" then
      vim.notify("PdfPort: no file path (argument, cfile, or current buffer)", vim.log.levels.ERROR)
      return
    end

    local choices = {
      { label = "buffer  – auto",                  mode = "buffer",   backend = nil          },
      { label = "buffer  – pdftotext",             mode = "buffer",   backend = "pdftotext"  },
      { label = "buffer  – marker (Markdown AI)",  mode = "buffer",   backend = "marker"     },
      { label = "buffer  – docling",               mode = "buffer",   backend = "docling"    },
      { label = "buffer  – Claude API",            mode = "buffer",   backend = "claude"     },
      { label = "buffer  – Ollama",                mode = "buffer",   backend = "ollama"     },
      { label = "float   – auto",                  mode = "float",    backend = nil          },
      { label = "terminal image preview",          mode = "terminal", backend = nil          },
      { label = "system application",              mode = "system",   backend = nil          },
    }

    local items = { [#choices] = nil }
    for i, c in ipairs(choices) do items[i] = c.label end

    local function on_select(_, idx)
      local c = choices[idx]
      if not c then return end
      M.open({ path = path, mode = c.mode, backend_id = c.backend, focus = true })
    end

    local hover_ok, hover = pcall(require, "lib.nvim.ui.hover_select")
    if hover_ok then
      hover.open({ title = "pdfport – open as", items = items, auto_width = true, on_select = on_select })
    else
      vim.ui.select(items, { prompt = "pdfport – open as:" }, function(_, idx)
        if idx then on_select(nil, idx) end
      end)
    end
  end, vim.tbl_extend("force", base, { desc = "pdfport: open PDF (mode picker)" }))

  vim.api.nvim_create_user_command("PdfPortText", function(args)
    local path = resolve_path(args)
    if not path or path == "" then
      vim.notify("PdfPortText: no file path", vim.log.levels.ERROR); return
    end
    M.open({ path = path, mode = "buffer", focus = true })
  end, vim.tbl_extend("force", base, { desc = "pdfport: extract PDF text to buffer" }))

  vim.api.nvim_create_user_command("PdfPortFloat", function(args)
    local path = resolve_path(args)
    if not path or path == "" then
      vim.notify("PdfPortFloat: no file path", vim.log.levels.ERROR); return
    end
    M.open({ path = path, mode = "float", focus = true })
  end, vim.tbl_extend("force", base, { desc = "pdfport: show PDF text in float window" }))

  vim.api.nvim_create_user_command("PdfPortSystem", function(args)
    local path = resolve_path(args)
    if not path or path == "" then
      vim.notify("PdfPortSystem: no file path", vim.log.levels.ERROR); return
    end
    M.open({ path = path, mode = "system" })
  end, vim.tbl_extend("force", base, { desc = "pdfport: open PDF with system application" }))

  vim.api.nvim_create_user_command("PdfPortTerminal", function(args)
    local path = resolve_path(args)
    if not path or path == "" then
      vim.notify("PdfPortTerminal: no file path", vim.log.levels.ERROR); return
    end
    M.open({ path = path, mode = "terminal" })
  end, vim.tbl_extend("force", base, { desc = "pdfport: render PDF as terminal image" }))

  vim.api.nvim_create_user_command("PdfPortHealth", function(_)
    vim.cmd("checkhealth pdfport_nvim")
  end, { desc = "pdfport: run health check" })
end

return M
