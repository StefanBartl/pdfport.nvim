---@module 'pdfport_nvim.util.picker'
---@brief Shared "open PDF as…" mode picker used by all file-tree integrations.
---@description
--- Falls back to vim.ui.select when lib.nvim's hover_select is not installed.

local M = {}

---@type { label: string, mode: PdfPort.RendererMode, backend: PdfPort.BackendId|nil }[]
local CHOICES = {
  { label = "Plain text  (pdftotext)",  mode = "buffer",   backend = "pdftotext" },
  { label = "Markdown    (marker)",      mode = "buffer",   backend = "marker"    },
  { label = "Markdown    (docling)",     mode = "buffer",   backend = "docling"   },
  { label = "Markdown    (Claude AI)",   mode = "buffer",   backend = "claude"    },
  { label = "Markdown    (Ollama AI)",   mode = "buffer",   backend = "ollama"    },
  { label = "Float window (auto)",       mode = "float",    backend = nil         },
  { label = "Terminal preview",          mode = "terminal", backend = nil         },
  { label = "System application",        mode = "system",   backend = nil         },
}

---@param path string
---@return nil
function M.pick_and_open(path)
  local pdfport = require("pdfport_nvim")

  local items = {}
  for i, c in ipairs(CHOICES) do items[i] = c.label end

  local function on_select(_, idx)
    if not idx then return end
    local choice = CHOICES[idx]
    if not choice then return end
    pdfport.open({ path = path, mode = choice.mode, backend_id = choice.backend, focus = true })
  end

  local hover_ok, hover = pcall(require, "lib.nvim.ui.hover_select")
  if hover_ok then
    hover.open({ title = "Open PDF as…", items = items, auto_width = true, on_select = on_select })
  else
    vim.ui.select(items, { prompt = "Open PDF as:" }, function(_, idx)
      if idx then on_select(nil, idx) end
    end)
  end
end

return M
