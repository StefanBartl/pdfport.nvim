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
---
--- What each key does lives in `pdfport.bindings.keymaps`, shared with the
--- other file trees: the only thing that differs here is how the path under
--- the cursor is found. The `cmd_*` functions stay exported so nvim-tree's own
--- `on_attach` can map them directly.

local M = {}

local notify = require("pdfport.util.notify").create("[pdfport.nvim_tree]")
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

--- The shared actions, over this tree's path getter.
---@type table<string, Lib.Keymap.Action>
local actions = keymaps.actions(current_node_path, notify)

---Opens the PDF under the cursor via the mode picker (buffer/float/system/terminal).
---@return nil
M.cmd_open = actions.open.rhs

---Extracts the PDF under the cursor straight to a scratch buffer, skipping the picker.
---@return nil
M.cmd_open_text = actions.open_text.rhs

---Opens the PDF under the cursor in the OS default application.
---@return nil
M.cmd_open_system = actions.open_system.rhs

---Opens the PDF under the cursor as a terminal image preview.
---@return nil
M.cmd_open_terminal = actions.open_terminal.rhs

---@see pdfport.util.batch.open_selected
---@return nil
M.cmd_open_batch = actions.open_batch.rhs

---@param opts? PdfPort.KeymapOpts
---@return nil
function M.setup(opts)
  local api_ok = pcall(require, "nvim-tree.api")
  if not api_ok then return end

  autocmds.on_filetype("NvimTree", "pdfport_tree", function(buf)
    keymaps.bind(buf, "nvim_tree", current_node_path, notify, opts)
  end)
end

return M
