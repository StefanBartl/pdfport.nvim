---@module 'pdfport.integrations.netrw'
---@brief netrw integration for pdfport.nvim.
---@description
--- Registers buffer-local keymaps whenever netrw opens.
--- netrw does not provide a Lua API -- paths are derived from vim.b.netrw_curdir
--- and the word under cursor.
---
--- Usage:
---
---   require("pdfport.integrations.netrw").setup()
---
--- Pass `false` for any action to disable that default keymap, e.g.:
---
---   require("pdfport.integrations.netrw").setup({ open_system = false })
---
--- What each key does lives in `pdfport.bindings.keymaps`, shared with the
--- other file trees: the only thing that differs here is how the path under
--- the cursor is found.

local M = {}

local notify = require("pdfport.util.notify").create("[pdfport.netrw]")
local autocmds = require("pdfport.bindings.autocmds")
local keymaps = require("pdfport.bindings.keymaps")

---@internal
---@see pdfport.integrations.nvim_tree, pdfport.integrations.oil  Same-shaped helper, filetype-specific
---@return string|nil
local function current_node_path()
  local dir = vim.b.netrw_curdir
  local file = vim.fn.expand("<cfile>")
  if not dir or dir == "" then return nil end
  if not file or file == "" then return nil end
  local sep = (dir:sub(-1) == "/" or dir:sub(-1) == "\\") and "" or "/"
  return dir .. sep .. file
end

---@param opts? PdfPort.KeymapOpts
---@return nil
function M.setup(opts)
  autocmds.on_filetype("netrw", "pdfport_netrw", function(buf)
    keymaps.bind(buf, "netrw", current_node_path, notify, opts)
  end)
end

return M
