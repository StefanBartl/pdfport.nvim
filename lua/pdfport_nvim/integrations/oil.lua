---@module 'pdfport_nvim.integrations.oil'
---@brief oil.nvim integration for pdfport.nvim.
---@description
--- Usage:
---
---   require("pdfport_nvim.integrations.oil").setup()
---
--- Pass `false` for any action to disable that default keymap, e.g.:
---
---   require("pdfport_nvim.integrations.oil").setup({ open_system = false })

local M = {}

local map      = require("lib.nvim.map")
local notify   = require("pdfport_nvim.util.notify").create("[pdfport_nvim.oil]")
local picker   = require("pdfport_nvim.util.picker")
local autocmds = require("pdfport_nvim.bindings.autocmds")
local keymaps  = require("pdfport_nvim.bindings.keymaps")

---@return string|nil
local function current_node_path()
  local ok, oil = pcall(require, "oil")
  if not ok then return nil end
  local dir   = oil.get_current_dir()
  local entry = oil.get_cursor_entry()
  if not dir or not entry or not entry.name then return nil end
  return dir .. entry.name
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

  autocmds.on_filetype("oil", "pdfport_oil", function(buf)
    local function bind(key, fn, desc)
      if not key then return end
      map("n", key, fn, { buffer = buf }, desc)
    end

    bind(resolved.open, function()
      local path = current_node_path()
      if not path or not is_pdf(path) then
        notify.warn("not a PDF file")
        return
      end
      picker.pick_and_open(path)
    end, keymaps.DESCRIPTIONS.open)

    bind(resolved.open_text, function()
      local path = current_node_path()
      if not path or not is_pdf(path) then return end
      require("pdfport_nvim").open({ path = path, mode = "buffer", split = "vsplit", focus = true })
    end, keymaps.DESCRIPTIONS.open_text)

    bind(resolved.open_system, function()
      local path = current_node_path()
      if not path or not is_pdf(path) then return end
      require("pdfport_nvim").open({ path = path, mode = "system" })
    end, keymaps.DESCRIPTIONS.open_system)

    bind(resolved.open_terminal, function()
      local path = current_node_path()
      if not path or not is_pdf(path) then return end
      require("pdfport_nvim").open({ path = path, mode = "terminal" })
    end, keymaps.DESCRIPTIONS.open_terminal)
  end)

  keymaps.register_which_key(resolved)
end

return M
