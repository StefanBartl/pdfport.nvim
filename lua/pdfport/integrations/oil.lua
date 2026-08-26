---@module 'pdfport.integrations.oil'
---@brief oil.nvim integration for pdfport.nvim.
---@description
--- Registers buffer-local keymaps whenever an oil buffer opens.
---
--- Usage:
---
---   require("pdfport.integrations.oil").setup()
---
--- Pass `false` for any action to disable that default keymap, e.g.:
---
---   require("pdfport.integrations.oil").setup({ open_system = false })
---
--- What each key does lives in `pdfport.bindings.keymaps`, shared with the
--- other file trees: the only thing that differs here is how the path under
--- the cursor is found.

local M = {}

local notify = require("pdfport.util.notify").create("[pdfport.oil]")
local autocmds = require("pdfport.bindings.autocmds")
local keymaps = require("pdfport.bindings.keymaps")

---@internal
---@see pdfport.integrations.netrw, pdfport.integrations.nvim_tree  Same-shaped helper, filetype-specific
---@return string|nil
local function current_node_path()
  local ok, oil = pcall(require, "oil")
  if not ok then return nil end
  local dir = oil.get_current_dir()
  local entry = oil.get_cursor_entry()
  if not dir or not entry or not entry.name then return nil end
  return dir .. entry.name
end

---@param opts? PdfPort.KeymapOpts
---@return nil
function M.setup(opts)
  autocmds.on_filetype("oil", "pdfport_oil", function(buf)
    keymaps.bind(buf, "oil", current_node_path, notify, opts)
  end)
end

return M
