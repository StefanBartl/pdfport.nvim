---@module 'pdfport.bindings.autocmds'
---@brief Shared FileType-autocmd helper for buffer-local keymap registration.
---@description
--- Centralizes the FileType-autocmd + augroup boilerplate used by the netrw,
--- oil.nvim and nvim-tree integrations, so each registration is idempotent
--- (re-running setup() clears and re-creates its own augroup instead of
--- accumulating duplicate autocmds/keymaps).

local autocmd = require("lib.nvim.autocmd")

local M = {}

---@param pattern string                        vim FileType pattern, e.g. "netrw", "oil", "NvimTree"
---@param augroup_name string                    unique augroup name (cleared on each call)
---@param callback fun(buf: integer): nil        invoked with the entered buffer number
---@return nil
function M.on_filetype(pattern, augroup_name, callback)
  autocmd.create("FileType", function(ev) callback(ev.buf) end, {
    pattern = pattern,
    group   = augroup_name,
  })
end

return M
