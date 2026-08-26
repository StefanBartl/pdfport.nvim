---@module 'pdfport.bindings.autocmds'
---@brief Shared FileType-autocmd helper for buffer-local keymap registration.
---@description
--- Centralizes the FileType-autocmd + augroup boilerplate used by the netrw,
--- oil.nvim and nvim-tree integrations, so each registration is idempotent
--- (re-running setup() clears and re-creates its own augroup instead of
--- accumulating duplicate autocmds/keymaps).

local autocmd = require("lib.nvim.bindings.autocmd")

local M = {}

---@param pattern string                        vim FileType pattern, e.g. "netrw", "oil", "NvimTree"
---@param augroup_name string                    unique augroup name (cleared on each call)
---@param callback fun(buf: integer): nil        invoked with the entered buffer number
---@return nil
function M.on_filetype(pattern, augroup_name, callback)
  autocmd.create("FileType", function(ev)
    callback(ev.buf)
  end, {
    pattern = pattern,
    group = augroup_name,
  })
end

---@brief Optional, opt-in via config.auto_open_on_read: intercepts a direct
---`:e file.pdf` and invokes the mode picker instead of loading the raw PDF
---bytes into a buffer. Idempotent like M.on_filetype (own augroup, cleared
---on each call).
---@return nil
function M.register_bufreadcmd()
  autocmd.create("BufReadCmd", function(ev)
    local path = vim.api.nvim_buf_get_name(ev.buf)
    vim.bo[ev.buf].buftype = "nofile"
    vim.bo[ev.buf].modifiable = false
    vim.bo[ev.buf].bufhidden = "wipe"
    vim.bo[ev.buf].swapfile = false
    vim.schedule(function()
      require("pdfport.util.picker").pick_and_open(path)
    end)
  end, {
    pattern = "*.pdf",
    group = "pdfport_bufreadcmd",
    desc = "pdfport: auto-invoke the mode picker when a PDF is opened directly",
  })
end

return M
