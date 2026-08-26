---@module 'pdfport.integrations.nvim_tree'
---@brief nvim-tree integration for pdfport.nvim.
---@description
--- Usage:
---
---   require("pdfport.integrations.nvim_tree").setup()
---
--- Or with custom keymaps (pass `false` to disable a default):
---
---   require("pdfport.integrations.nvim_tree").setup({
---     open        = "<leader>po",
---     open_text   = "<leader>pt",
---     open_system = false,
---   })

local M = {}

local map = require("lib.nvim.bindings.keymap")
local notify = require("pdfport.util.notify").create("[pdfport.nvim_tree]")
local picker = require("pdfport.util.picker")
local autocmds = require("pdfport.bindings.autocmds")
local keymaps = require("pdfport.bindings.keymaps")

---@internal
---@see pdfport.integrations.netrw, pdfport.integrations.oil  Same-shaped helper, filetype-specific
---@return string|nil
local function current_node_path()
  local ok, api = pcall(require, "nvim-tree.api")
  if not ok then return nil end
  local node = api.tree.get_node_under_cursor()
  if not node or not node.absolute_path then return nil end
  return node.absolute_path
end

---@internal
---@see pdfport.integrations.netrw, pdfport.integrations.oil, pdfport.integrations.neotree  Same check, duplicated per-tree
---@param path string
---@return boolean
local function is_pdf(path)
  return path:lower():match("%.pdf$") ~= nil
end

---Opens the PDF under the cursor via the mode picker (buffer/float/system/terminal).
---@return nil
function M.cmd_open()
  local path = current_node_path()
  if not path or not is_pdf(path) then
    notify.warn("not a PDF file")
    return
  end
  picker.pick_and_open(path)
end

---Extracts the PDF under the cursor straight to a scratch buffer, skipping the picker.
---@return nil
function M.cmd_open_text()
  local path = current_node_path()
  if not path or not is_pdf(path) then return end
  require("pdfport").open({ path = path, mode = "buffer", split = "vsplit", focus = true })
end

---Opens the PDF under the cursor in the OS default application.
---@return nil
function M.cmd_open_system()
  local path = current_node_path()
  if not path or not is_pdf(path) then return end
  require("pdfport").open({ path = path, mode = "system" })
end

---Opens the PDF under the cursor as a terminal image preview.
---@return nil
function M.cmd_open_terminal()
  local path = current_node_path()
  if not path or not is_pdf(path) then return end
  require("pdfport").open({ path = path, mode = "terminal" })
end

---@see pdfport.util.batch.open_selected
---@return nil
function M.cmd_open_batch()
  require("pdfport.util.batch").open_selected(current_node_path)
end

---@param opts? PdfPort.KeymapOpts
---@return nil
function M.setup(opts)
  local api_ok = pcall(require, "nvim-tree.api")
  if not api_ok then return end

  local resolved = keymaps.resolve(opts)

  local mappings = {
    {
      mode = "n",
      key = resolved.open,
      fn = M.cmd_open,
      desc = keymaps.DESCRIPTIONS.open,
    },
    {
      mode = "n",
      key = resolved.open_text,
      fn = M.cmd_open_text,
      desc = keymaps.DESCRIPTIONS.open_text,
    },
    {
      mode = "n",
      key = resolved.open_system,
      fn = M.cmd_open_system,
      desc = keymaps.DESCRIPTIONS.open_system,
    },
    {
      mode = "n",
      key = resolved.open_terminal,
      fn = M.cmd_open_terminal,
      desc = keymaps.DESCRIPTIONS.open_terminal,
    },
    {
      mode = "v",
      key = resolved.open_batch,
      fn = M.cmd_open_batch,
      desc = keymaps.DESCRIPTIONS.open_batch,
    },
  }

  autocmds.on_filetype("NvimTree", "pdfport_tree", function(buf)
    for _, m in ipairs(mappings) do
      if m.key then map(m.mode, m.key, m.fn, { buffer = buf }, m.desc) end
    end
  end)

  keymaps.register_which_key(resolved)
end

return M
