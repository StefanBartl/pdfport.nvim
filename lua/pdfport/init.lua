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
  require("pdfport.core.composer")._set_config(cfg)

  -- Backends are registered as lazy proxies (pdfport.backends.load_all) —
  -- the real claude/ollama modules (and their _set_config) only load the
  -- first time the resolver actually considers that backend, not here.
  require("pdfport.backends").load_all(cfg)

  -- Same lazy-proxy pattern for creation producers (img2pdf/magick).
  require("pdfport.producers").load_all(cfg)

  local reg = require("pdfport.core.registry")

  local renderers = {
    { id = "buffer", mod = "pdfport.renderers.buffer" },
    { id = "float", mod = "pdfport.renderers.float" },
    { id = "system", mod = "pdfport.renderers.system" },
    { id = "terminal", mod = "pdfport.renderers.terminal" },
  }
  for _, r in ipairs(renderers) do
    local ok_r, rm = pcall(require, r.mod)
    if ok_r then reg.register_renderer(r.id, rm.render) end
  end

  M._register_commands()

  if cfg.auto_open_on_read then require("pdfport.bindings.autocmds").register_bufreadcmd() end

  _initialized = true

  -- One-time (persisted across restarts, not just this session) "here's
  -- what CLI tools unlock which backend, and why" popup — the first time
  -- pdfport.nvim actually initializes after being installed. `cfg.deps_popup
  -- = false` (set right in the setup() spec, config/DEFAULTS.lua) disables
  -- it for this plugin specifically — checked here, not left to the global
  -- vim.g toggle alone, so the plugin's own spec is a real place to turn
  -- this off, not just a pointer to a separate lib.nvim setting. pcall'd
  -- despite lib.nvim being a hard dependency elsewhere in this file: an
  -- older lib.nvim without lib.nvim.deps shouldn't break setup() over an
  -- informational popup. `:Lib deps show pdfport.nvim` stays available for
  -- checking again at any time; see docs/install.json and
  -- :help lib.nvim-deps-first_run.
  if cfg.deps_popup ~= false then
    local ok_deps, deps = pcall(require, "lib.nvim.deps")
    if ok_deps then deps.show_once("pdfport.nvim") end
  end

  notify.debug("initialized", cfg)
end

-- #############################################################################
-- Public API
-- #############################################################################

---@param opts PdfPort.OpenOpts
---@param on_error? fun(msg: string): nil  Defaults to this plugin's own
---       notifier, so existing callers (integrations, the picker) keep seeing
---       errors without having to opt in explicitly. Pass your own to decide
---       presentation yourself (as bindings/usrcmds.lua does).
---@param on_done? fun(ok: boolean, err: string|nil)  optional completion
---       signal, settling exactly once. Opening is asynchronous end to end and
---       success is otherwise silent, so a caller opening several files (see
---       `pdfport.util.batch`) has no other way to report an accurate summary.
---@return nil
function M.open(opts, on_error, on_done)
  if not _initialized then M.setup() end

  assert(type(opts) == "table", "pdfport.open: opts must be a table")
  assert(
    type(opts.path) == "string" and opts.path ~= "",
    "pdfport.open: opts.path must be a non-empty string"
  )

  require("pdfport.core.dispatcher").open(opts, on_error or notify.error, on_done)
end

---Ask the user how to open `path`, then open it that way. This is the same
---picker `:PdfPort` and every file-tree integration in this plugin use — the
---public entry point so OTHER plugins that embed pdfport.nvim (filetree.nvim,
---gopath.nvim, markdown.nvim, documentation.nvim, …) can offer one consistent
---picker instead of each hand-rolling its own two/three-item dialog.
---
---"System application" is always one of the choices (see
---pdfport.util.picker's module docs) — pass `opts.system_open` to route that
---one entry through your own OS-opener (e.g. for WSL path translation)
---instead of pdfport's `system` renderer, or `opts.system_first` to put it at
---the top of the list for callers whose pre-pdfport behaviour was "always the
---system viewer".
---@param path string
---@param opts? PdfPort.PickerOpts
---@return nil
function M.pick_open(path, opts)
  if not _initialized then M.setup() end

  assert(
    type(path) == "string" and path ~= "",
    "pdfport.pick_open: path must be a non-empty string"
  )

  require("pdfport.util.picker").pick_and_open(path, opts)
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

---Rasterize a single PDF page to a PNG file via pdftoppm. Same primitive the
---`terminal` renderer uses internally, but returns a real, caller-owned PNG
---path instead of display-and-delete — lets consumers like images.nvim show
---a PDF page as an image without depending on pdfport's terminal renderer or
---reimplementing rasterization themselves. Caller is responsible for
---deleting the returned file once done with it.
---@param path string
---@param page integer
---@param opts? PdfPort.RenderPageOpts
---@param callback fun(png_path: string|nil, err: string|nil): nil
---@return nil
function M.render_page(path, page, opts, callback)
  if not _initialized then M.setup() end

  assert(
    type(path) == "string" and path ~= "",
    "pdfport.render_page: path must be a non-empty string"
  )
  assert(type(page) == "number", "pdfport.render_page: page must be a number")
  assert(type(callback) == "function", "pdfport.render_page: callback must be a function")

  require("pdfport.core.rasterize").render_page(path, page, opts, callback)
end

-- #############################################################################
-- Creation ("write") API — the reverse of open/extract
-- #############################################################################

---@param opts PdfPort.CreateOpts|table  # exactly one of inputs/text/bufnr
---@return nil
function M.create(opts)
  if not _initialized then M.setup() end

  assert(type(opts) == "table", "pdfport.create: opts must be a table")
  assert(
    (type(opts.inputs) == "table" and #opts.inputs > 0)
      or type(opts.text) == "string"
      or type(opts.bufnr) == "number",
    "pdfport.create: pass exactly one of opts.inputs, opts.text, opts.bufnr"
  )

  local callback = opts.__callback
    or function(result)
      if result.status == "ok" then
        notify.info(string.format("created %s (%s)", result.path, result.producer))
      else
        notify.error(result.error or "pdfport.create failed")
      end
    end

  require("pdfport.core.composer").create(opts, callback)
end

---@param kind PdfPort.InputKind
---@return boolean
function M.can_create(kind)
  if not _initialized then M.setup() end
  return require("pdfport.core.composer").can_create(kind)
end

---Merge two or more PDFs into one. Thin wrapper over create()/composer with
---the input kind fixed to "pdf" — reuses the exact same resolve/on_conflict/
---progress machinery as every other producer chain (see
---producers/qpdf.lua, pdftk.lua, ghostscript.lua and create_chain.pdf).
---@param opts { inputs: string[], output: string, producer_id?: PdfPort.ProducerId, on_conflict?: "overwrite"|"suffix"|"error", opts?: table, __callback?: fun(result: PdfPort.CreateResult): nil }
---@return nil
function M.merge(opts)
  if not _initialized then M.setup() end

  assert(type(opts) == "table", "pdfport.merge: opts must be a table")
  assert(
    type(opts.inputs) == "table" and #opts.inputs >= 2,
    "pdfport.merge: opts.inputs must have at least 2 PDF paths"
  )
  assert(
    type(opts.output) == "string" and opts.output ~= "",
    "pdfport.merge: opts.output is required"
  )

  local callback = opts.__callback
    or function(result)
      if result.status == "ok" then
        notify.info(
          string.format("merged %d PDFs -> %s (%s)", #opts.inputs, result.path, result.producer)
        )
      else
        notify.error(result.error or "pdfport.merge failed")
      end
    end

  local create_opts = vim.tbl_extend("force", opts, { from = "pdf" })
  require("pdfport.core.composer").create(create_opts, callback)
end

---@param producer PdfPort.Producer
---@return nil
function M.register_producer(producer)
  require("pdfport.core.registry").register_producer(producer)
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
