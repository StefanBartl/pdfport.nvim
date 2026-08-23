---@module 'pdfport.bindings.usrcmds'
---@brief Registers :PdfPort <subcommand>, one verb built via lib.nvim's
---@brief composer (:Verb sub … + <Tab> completion + Markdown docgen).
---@description
--- Bare `:PdfPort [path]` opens the interactive mode picker; `text`/`float`/
--- `system`/`terminal` open directly in that mode; `health` runs
--- :checkhealth. All path-taking routes accept an optional path argument; if
--- omitted they fall back to <cfile> and then the current buffer name. See
--- docs/BINDINGS.md for the full cheatsheet.

local composer = require("lib.nvim.usercmd.composer")
local notify = require("pdfport.util.notify").create("[pdfport.usrcmds]")
local page_range = require("pdfport.util.page_range")

local M = {}

---@internal
---@param arg_lead string
---@return string[]
local function complete_pdf_path(arg_lead)
  if arg_lead == "" then
    local cfile = vim.fn.expand("<cfile>")
    if cfile and cfile ~= "" and vim.fn.filereadable(cfile) == 1 then return { cfile } end
    return {}
  end
  local completions = vim.fn.glob(arg_lead .. "*", false, true)
  local pdfs, rest = {}, {}
  for _, p in ipairs(completions) do
    if p:lower():match("%.pdf$") then
      pdfs[#pdfs + 1] = p
    else
      rest[#rest + 1] = p
    end
  end
  vim.list_extend(pdfs, rest)
  return pdfs
end

-- <cfile>-aware, .pdf-prioritized completion — meaningfully different from
-- composer's built-in PATH type (plain vim.fn.getcompletion), so it's its
-- own registered type rather than a fallback to the built-in.
composer.register_type("PDF_PATH", {
  validate = function(raw)
    return true, raw, nil
  end,
  complete = function(arg_lead)
    return complete_pdf_path(arg_lead)
  end,
})

---@internal
---@param explicit string|nil  Already-extracted positional arg, if any
---@return string|nil
local function resolve_path(explicit)
  if explicit and explicit ~= "" then return vim.fn.expand(explicit) end
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

---@internal Shared by the "backends" and "producers" routes: both just show
---registry.diagnostics() (backends+producers together) in a titled scratch
---window, or notify with the plain text if lib.nvim's scratch helper is
---unavailable.
---@param title string
---@return nil
local function show_diagnostics(title)
  local registry = require("pdfport.core.registry")
  local ok_scratch, make_scratch = pcall(require, "lib.nvim.window.make_scratch")
  local lines = registry.diagnostics()
  if ok_scratch then
    make_scratch({
      lines = lines,
      filetype = "text",
      title = title,
      title_pos = "center",
      width = math.floor(vim.o.columns * 0.6),
      height = math.floor(vim.o.lines * 0.5),
      wo = { wrap = false },
      nice_quit = true,
    })
  else
    notify.info(table.concat(lines, "\n"))
  end
end

---@param pdfport table  the pdfport public API module (for M.open())
---@return nil
function M.register(pdfport)
  local path_arg = { { name = "path", type = "PDF_PATH", optional = true } }

  --- Shared "no path found" guard, mirroring the original per-command error text.
  ---@param ctx Lib.UserCmd.Composer.Ctx
  ---@param label string
  ---@return string|nil
  local function require_path(ctx, label)
    local path = resolve_path(ctx.args.path)
    if not path or path == "" then
      notify.error(label .. ": no file path (argument, cfile, or current buffer)")
      return nil
    end
    return path
  end

  composer.verb("PdfPort", {
    desc = "Open/preview a PDF (pluggable extraction backends)",
    routes = {
      -- Bare `:PdfPort [path]` — the interactive mode picker. `path = {}` is
      -- the verb's root route: it matches even with no literal subcommand.
      {
        path = {},
        args = path_arg,
        desc = "Open PDF (interactive mode picker)",
        run = function(ctx)
          local path = require_path(ctx, "PdfPort")
          if not path then return end

          -- Delegates to pdfport.util.picker (also `pdfport.pick_open()`) so
          -- there is exactly one choice list — and exactly one place that
          -- guarantees "system application" is always an option — instead of
          -- this command keeping its own hand-maintained copy that can drift
          -- from lua/pdfport/util/picker.lua's.
          pdfport.pick_open(path, { title = "pdfport – open as" })
        end,
      },

      {
        path = { "text" },
        args = path_arg,
        desc = "Extract PDF text to buffer",
        run = function(ctx)
          local path = require_path(ctx, "PdfPort text")
          if path then
            pdfport.open({ path = path, mode = "buffer", focus = true }, notify.error)
          end
        end,
      },

      {
        path = { "float" },
        args = path_arg,
        desc = "Show PDF text in float window",
        run = function(ctx)
          local path = require_path(ctx, "PdfPort float")
          if not path then return end
          page_range.prompt(function(pages)
            pdfport.open({ path = path, mode = "float", focus = true, pages = pages }, notify.error)
          end)
        end,
      },

      {
        path = { "system" },
        args = path_arg,
        desc = "Open PDF with system application",
        run = function(ctx)
          local path = require_path(ctx, "PdfPort system")
          if path then pdfport.open({ path = path, mode = "system" }, notify.error) end
        end,
      },

      {
        path = { "terminal" },
        args = path_arg,
        desc = "Render PDF as terminal image",
        run = function(ctx)
          local path = require_path(ctx, "PdfPort terminal")
          if not path then return end
          page_range.prompt(function(pages)
            pdfport.open({ path = path, mode = "terminal", pages = pages }, notify.error)
          end)
        end,
      },

      {
        path = { "health" },
        desc = "Run health check",
        run = function()
          vim.cmd("checkhealth pdfport")
        end,
      },

      {
        path = { "backends" },
        desc = "List all registered backends with live availability",
        run = function()
          show_diagnostics(" pdfport: backends ")
        end,
      },

      {
        path = { "create" },
        args = path_arg,
        desc = "Create a PDF from an image (path arg, cfile, or current buffer)",
        run = function(ctx)
          local path = require_path(ctx, "PdfPort create")
          if not path then return end
          pdfport.create({ inputs = { path } })
        end,
      },

      {
        path = { "producers" },
        desc = "List all registered creation producers with live availability",
        run = function()
          show_diagnostics(" pdfport: producers ")
        end,
      },

      {
        path = { "merge" },
        args = { { name = "output", type = "PDF_PATH" } },
        desc = "Merge two or more PDFs: :PdfPort merge <output.pdf> <a.pdf> <b.pdf> ...",
        run = function(ctx)
          local output = ctx.args.output
          local inputs = ctx.rest or {}
          if not output or output == "" then
            notify.error("PdfPort merge: no output path given")
            return
          end
          if #inputs < 2 then
            notify.error("PdfPort merge: need at least 2 input PDFs, got " .. #inputs)
            return
          end
          pdfport.merge({ inputs = inputs, output = vim.fn.expand(output) })
        end,
      },
    },
  })
end

return M
