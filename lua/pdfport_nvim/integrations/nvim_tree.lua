---@module 'pdfport_nvim.integrations.nvim_tree'
---@brief nvim-tree integration for pdfport.nvim.
---@description
--- Usage:
---
---   require("pdfport_nvim.integrations.nvim_tree").setup()
---
--- Or with custom keymaps:
---
---   require("pdfport_nvim.integrations.nvim_tree").setup({
---     open        = "<leader>po",
---     open_text   = "<leader>pt",
---     open_system = "<leader>ps",
---   })

local M = {}

---@return string|nil
local function current_node_path()
  local ok, api = pcall(require, "nvim-tree.api")
  if not ok then return nil end
  local node = api.tree.get_node_under_cursor()
  if not node or not node.absolute_path then return nil end
  return node.absolute_path
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
  local api_ok, tree_api = pcall(require, "nvim-tree.api")
  if not api_ok then return end

  local mappings = {
    { key = opts.open        or "<leader>po", fn = M.cmd_open        },
    { key = opts.open_text   or "<leader>pt", fn = M.cmd_open_text   },
    { key = opts.open_system or "<leader>ps", fn = M.cmd_open_system },
    { key = opts.open_terminal or "<leader>pi", fn = M.cmd_open_terminal },
  }

  for _, m in ipairs(mappings) do
    tree_api.config.mappings.default_on_attach = tree_api.config.mappings.default_on_attach
    -- attach inside nvim-tree's on_attach, so register via nvim-tree events if possible
    -- Fallback: use a BufEnter autocmd on NvimTree buffers
    vim.api.nvim_create_autocmd("FileType", {
      pattern  = "NvimTree",
      callback = function(ev)
        vim.keymap.set("n", m.key, m.fn, {
          buffer  = ev.buf,
          silent  = true,
          noremap = true,
          desc    = "pdfport: " .. m.key,
        })
      end,
    })
  end
end

function M.cmd_open()
  local path = current_node_path()
  if not path or not is_pdf(path) then
    vim.notify("pdfport_nvim: not a PDF file", vim.log.levels.WARN)
    return
  end
  pick_mode_and_open(path)
end

function M.cmd_open_text()
  local path = current_node_path()
  if not path or not is_pdf(path) then return end
  require("pdfport_nvim").open({ path = path, mode = "buffer", split = "vsplit", focus = true })
end

function M.cmd_open_system()
  local path = current_node_path()
  if not path or not is_pdf(path) then return end
  require("pdfport_nvim").open({ path = path, mode = "system" })
end

function M.cmd_open_terminal()
  local path = current_node_path()
  if not path or not is_pdf(path) then return end
  require("pdfport_nvim").open({ path = path, mode = "terminal" })
end

return M
