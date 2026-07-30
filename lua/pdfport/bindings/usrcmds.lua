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

          local choices = {
            {
              label = "buffer  – auto",
              mode = "buffer",
              backend = nil,
            },
            {
              label = "buffer  – pdftotext",
              mode = "buffer",
              backend = "pdftotext",
            },
            {
              label = "buffer  – marker (Markdown AI)",
              mode = "buffer",
              backend = "marker",
            },
            {
              label = "buffer  – docling",
              mode = "buffer",
              backend = "docling",
            },
            {
              label = "buffer  – Claude API",
              mode = "buffer",
              backend = "claude",
            },
            {
              label = "buffer  – Ollama",
              mode = "buffer",
              backend = "ollama",
            },
            {
              label = "float   – auto",
              mode = "float",
              backend = nil,
            },
            {
              label = "terminal image preview",
              mode = "terminal",
              backend = nil,
            },
            {
              label = "system application",
              mode = "system",
              backend = nil,
            },
          }

          local items = { [#choices] = nil }
          for i, c in ipairs(choices) do
            items[i] = c.label
          end

          local function on_select(_, idx)
            local c = choices[idx]
            if not c then return end

            -- Built once and reused by both branches. Also keeps the call out
            -- of a deeply nested inline table: stylua does not reach a stable
            -- fixpoint on that shape here (it alternates between two layouts
            -- on successive runs), which would make `stylua --check` in CI
            -- fail no matter which of the two is committed.
            local open_opts = {
              path = path,
              mode = c.mode,
              backend_id = c.backend,
              focus = true,
            }

            if c.mode == "float" or c.mode == "terminal" then
              page_range.prompt(function(pages)
                open_opts.pages = pages
                pdfport.open(open_opts, notify.error)
              end)
              return
            end

            pdfport.open(open_opts, notify.error)
          end

          local kit_ok, kit = pcall(require, "lib.nvim.ui.kit")
          if kit_ok and type(kit.select) == "function" then
            kit.select({ title = "pdfport – open as", items = items, on_select = on_select })
          else
            vim.ui.select(items, { prompt = "pdfport – open as:" }, function(_, idx)
              if idx then on_select(nil, idx) end
            end)
          end
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
          local registry = require("pdfport.core.registry")
          local ok_scratch, make_scratch = pcall(require, "lib.nvim.window.make_scratch")
          local lines = registry.diagnostics()
          if ok_scratch then
            make_scratch({
              lines = lines,
              filetype = "text",
              title = " pdfport: backends ",
              title_pos = "center",
              width = math.floor(vim.o.columns * 0.6),
              height = math.floor(vim.o.lines * 0.5),
              wo = { wrap = false },
              nice_quit = true,
            })
          else
            notify.info(table.concat(lines, "\n"))
          end
        end,
      },
    },
  })
end

return M
