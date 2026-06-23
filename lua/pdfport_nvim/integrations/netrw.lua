---@module 'pdfport_nvim.integrations.netrw'
---@brief netrw integration for pdfport.nvim.
---@description
--- Registers buffer-local keymaps whenever netrw opens.
--- netrw does not provide a Lua API — paths are derived from vim.b.netrw_curdir
--- and the word under cursor.
---
--- Usage:
---
---   require("pdfport_nvim.integrations.netrw").setup()
---
--- The setup call creates a FileType autocmd for "netrw".

local M = {}

---@return string|nil
local function current_node_path()
  local dir  = vim.b.netrw_curdir
  local file = vim.fn.expand("<cfile>")
  if not dir or dir == "" then return nil end
  if not file or file == "" then return nil end
  local sep  = (dir:sub(-1) == "/" or dir:sub(-1) == "\\") and "" or "/"
  return dir .. sep .. file
end

---@param path string
---@return boolean
local function is_pdf(path)
  return path:lower():match("%.pdf$") ~= nil
end

---@param path string
local function pick_mode_and_open(path)
  local pdfport = require("pdfport_nvim")
  local choices = {
    { label = "Plain text  (pdftotext)",  mode = "buffer",   backend = "pdftotext" },
    { label = "Markdown    (marker)",      mode = "buffer",   backend = "marker"    },
    { label = "Markdown    (docling)",     mode = "buffer",   backend = "docling"   },
    { label = "Markdown    (Claude AI)",   mode = "buffer",   backend = "claude"    },
    { label = "Markdown    (Ollama AI)",   mode = "buffer",   backend = "ollama"    },
    { label = "Float window (auto)",       mode = "float",    backend = nil         },
    { label = "Terminal preview",          mode = "terminal", backend = nil         },
    { label = "System application",        mode = "system",   backend = nil         },
  }
  local items = {}
  for i, c in ipairs(choices) do items[i] = c.label end

  local hover_ok, hover = pcall(require, "lib.nvim.ui.hover_select")
  local function on_select(_, idx)
    if not idx then return end
    local choice = choices[idx]
    if not choice then return end
    pdfport.open({ path = path, mode = choice.mode, backend_id = choice.backend, focus = true })
  end

  if hover_ok then
    hover.open({ title = "Open PDF as…", items = items, auto_width = true, on_select = on_select })
  else
    vim.ui.select(items, { prompt = "Open PDF as:" }, function(_, idx)
      if idx then on_select(nil, idx) end
    end)
  end
end

---@param opts? { open?: string, open_text?: string, open_system?: string, open_terminal?: string }
---@return nil
function M.setup(opts)
  opts = opts or {}
  local km_open     = opts.open         or "<leader>po"
  local km_text     = opts.open_text    or "<leader>pt"
  local km_system   = opts.open_system  or "<leader>ps"
  local km_terminal = opts.open_terminal or "<leader>pi"

  vim.api.nvim_create_autocmd("FileType", {
    pattern  = "netrw",
    group    = vim.api.nvim_create_augroup("pdfport_netrw", { clear = true }),
    callback = function(ev)
      local buf = ev.buf
      local function map(key, fn)
        vim.keymap.set("n", key, fn, { buffer = buf, silent = true, noremap = true })
      end

      map(km_open, function()
        local path = current_node_path()
        if not path or not is_pdf(path) then
          vim.notify("pdfport_nvim: not a PDF file", vim.log.levels.WARN)
          return
        end
        pick_mode_and_open(path)
      end)

      map(km_text, function()
        local path = current_node_path()
        if not path or not is_pdf(path) then return end
        require("pdfport_nvim").open({ path = path, mode = "buffer", split = "vsplit", focus = true })
      end)

      map(km_system, function()
        local path = current_node_path()
        if not path or not is_pdf(path) then return end
        require("pdfport_nvim").open({ path = path, mode = "system" })
      end)

      map(km_terminal, function()
        local path = current_node_path()
        if not path or not is_pdf(path) then return end
        require("pdfport_nvim").open({ path = path, mode = "terminal" })
      end)
    end,
  })
end

return M
