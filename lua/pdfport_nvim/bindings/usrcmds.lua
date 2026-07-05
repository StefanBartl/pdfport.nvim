---@module 'pdfport_nvim.bindings.usrcmds'
---@brief User-command registration for pdfport.nvim.
---@description
--- Registers :PdfPort, :PdfPortText, :PdfPortFloat, :PdfPortSystem,
--- :PdfPortTerminal and :PdfPortHealth. All commands accept an optional path
--- argument; if omitted they fall back to <cfile> and then the current
--- buffer name. See docs/BINDINGS.md for the full cheatsheet.

local M = {}

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

---@param pdfport table  the pdfport_nvim public API module (for M.open())
---@return nil
function M.register(pdfport)
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
      pdfport.open({ path = path, mode = c.mode, backend_id = c.backend, focus = true })
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
    pdfport.open({ path = path, mode = "buffer", focus = true })
  end, vim.tbl_extend("force", base, { desc = "pdfport: extract PDF text to buffer" }))

  vim.api.nvim_create_user_command("PdfPortFloat", function(args)
    local path = resolve_path(args)
    if not path or path == "" then
      vim.notify("PdfPortFloat: no file path", vim.log.levels.ERROR); return
    end
    pdfport.open({ path = path, mode = "float", focus = true })
  end, vim.tbl_extend("force", base, { desc = "pdfport: show PDF text in float window" }))

  vim.api.nvim_create_user_command("PdfPortSystem", function(args)
    local path = resolve_path(args)
    if not path or path == "" then
      vim.notify("PdfPortSystem: no file path", vim.log.levels.ERROR); return
    end
    pdfport.open({ path = path, mode = "system" })
  end, vim.tbl_extend("force", base, { desc = "pdfport: open PDF with system application" }))

  vim.api.nvim_create_user_command("PdfPortTerminal", function(args)
    local path = resolve_path(args)
    if not path or path == "" then
      vim.notify("PdfPortTerminal: no file path", vim.log.levels.ERROR); return
    end
    pdfport.open({ path = path, mode = "terminal" })
  end, vim.tbl_extend("force", base, { desc = "pdfport: render PDF as terminal image" }))

  vim.api.nvim_create_user_command("PdfPortHealth", function(_)
    vim.cmd("checkhealth pdfport_nvim")
  end, { desc = "pdfport: run health check" })
end

return M
