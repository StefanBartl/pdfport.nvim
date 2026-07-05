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
--- Pass `false` for any action to disable that default keymap, e.g.:
---
---   require("pdfport_nvim.integrations.netrw").setup({ open_system = false })

local M = {}

local picker   = require("pdfport_nvim.util.picker")
local autocmds = require("pdfport_nvim.bindings.autocmds")
local keymaps  = require("pdfport_nvim.bindings.keymaps")

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

---@param opts? PdfPort.KeymapOpts
---@return nil
function M.setup(opts)
  local resolved = keymaps.resolve(opts)

  autocmds.on_filetype("netrw", "pdfport_netrw", function(buf)
    local function map(key, fn, desc)
      if not key then return end
      vim.keymap.set("n", key, fn, { buffer = buf, silent = true, noremap = true, desc = desc })
    end

    map(resolved.open, function()
      local path = current_node_path()
      if not path or not is_pdf(path) then
        vim.notify("pdfport_nvim: not a PDF file", vim.log.levels.WARN)
        return
      end
      picker.pick_and_open(path)
    end, keymaps.DESCRIPTIONS.open)

    map(resolved.open_text, function()
      local path = current_node_path()
      if not path or not is_pdf(path) then return end
      require("pdfport_nvim").open({ path = path, mode = "buffer", split = "vsplit", focus = true })
    end, keymaps.DESCRIPTIONS.open_text)

    map(resolved.open_system, function()
      local path = current_node_path()
      if not path or not is_pdf(path) then return end
      require("pdfport_nvim").open({ path = path, mode = "system" })
    end, keymaps.DESCRIPTIONS.open_system)

    map(resolved.open_terminal, function()
      local path = current_node_path()
      if not path or not is_pdf(path) then return end
      require("pdfport_nvim").open({ path = path, mode = "terminal" })
    end, keymaps.DESCRIPTIONS.open_terminal)
  end)

  keymaps.register_which_key(resolved)
end

return M
