---@module 'pdfport_nvim.integrations.nvim_tree'
---@brief nvim-tree integration for pdfport.nvim.
---@description
--- Usage:
---
---   require("pdfport_nvim.integrations.nvim_tree").setup()
---
--- Or with custom keymaps (pass `false` to disable a default):
---
---   require("pdfport_nvim.integrations.nvim_tree").setup({
---     open        = "<leader>po",
---     open_text   = "<leader>pt",
---     open_system = false,
---   })

local M = {}

local map      = require("lib.nvim.map")
local notify   = require("pdfport_nvim.util.notify").create("[pdfport_nvim.nvim_tree]")
local picker   = require("pdfport_nvim.util.picker")
local autocmds = require("pdfport_nvim.bindings.autocmds")
local keymaps  = require("pdfport_nvim.bindings.keymaps")

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

function M.cmd_open()
  local path = current_node_path()
  if not path or not is_pdf(path) then
    notify.warn("not a PDF file")
    return
  end
  picker.pick_and_open(path)
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

---@param opts? PdfPort.KeymapOpts
---@return nil
function M.setup(opts)
  local api_ok = pcall(require, "nvim-tree.api")
  if not api_ok then return end

  local resolved = keymaps.resolve(opts)

  local mappings = {
    { key = resolved.open,          fn = M.cmd_open,          desc = keymaps.DESCRIPTIONS.open          },
    { key = resolved.open_text,     fn = M.cmd_open_text,     desc = keymaps.DESCRIPTIONS.open_text     },
    { key = resolved.open_system,   fn = M.cmd_open_system,   desc = keymaps.DESCRIPTIONS.open_system   },
    { key = resolved.open_terminal, fn = M.cmd_open_terminal, desc = keymaps.DESCRIPTIONS.open_terminal },
  }

  autocmds.on_filetype("NvimTree", "pdfport_nvim_tree", function(buf)
    for _, m in ipairs(mappings) do
      if m.key then
        map("n", m.key, m.fn, { buffer = buf }, m.desc)
      end
    end
  end)

  keymaps.register_which_key(resolved)
end

return M
