---@module 'pdfport_nvim.integrations.neotree'
---@brief Neo-tree integration for pdfport.nvim.
---@description
--- Usage in neotree config:
---
---   local pdfport_neo = require("pdfport_nvim.integrations.neotree")
---   opts.commands = vim.tbl_extend("force", opts.commands, pdfport_neo.commands())
---   opts.filesystem.window.mappings = vim.tbl_extend(
---     "force", opts.filesystem.window.mappings, pdfport_neo.keymaps()
---   )
---
--- Pass `false` for any action to disable that default keymap, e.g.:
---
---   pdfport_neo.keymaps({ open_system = false })

local M = {}

local notify  = require("pdfport_nvim.util.notify").create("[pdfport_nvim.neotree]")
local picker  = require("pdfport_nvim.util.picker")
local keymaps = require("pdfport_nvim.bindings.keymaps")

---@param state table
---@return string|nil
local function node_path(state)
  if not state then return nil end
  local tree = state.tree
  if not tree then return nil end
  local node = tree:get_node()
  if not node then return nil end
  return node:get_id()
end

---@param path string
---@return boolean
local function is_pdf(path)
  if not path or path == "" then return false end
  return path:lower():match("%.pdf$") ~= nil
end

---@return table<string, fun(state: table): nil>
function M.commands()
  return {
    pdfport_open = function(state)
      local path = node_path(state)
      if not path or not is_pdf(path) then
        notify.warn("not a PDF file")
        return
      end
      picker.pick_and_open(path)
    end,

    pdfport_text = function(state)
      local path = node_path(state)
      if not path or not is_pdf(path) then return end
      require("pdfport_nvim").open({ path = path, mode = "buffer", split = "vsplit", focus = true })
    end,

    pdfport_system = function(state)
      local path = node_path(state)
      if not path or not is_pdf(path) then return end
      require("pdfport_nvim").open({ path = path, mode = "system" })
    end,

    pdfport_terminal = function(state)
      local path = node_path(state)
      if not path or not is_pdf(path) then return end
      require("pdfport_nvim").open({ path = path, mode = "terminal" })
    end,
  }
end

---@type table<string, string>
local COMMAND_NAMES = {
  open          = "pdfport_open",
  open_text     = "pdfport_text",
  open_system   = "pdfport_system",
  open_terminal = "pdfport_terminal",
}

---@param opts? PdfPort.KeymapOpts
---@return table<string, string>
function M.keymaps(opts)
  local resolved = keymaps.resolve(opts)
  keymaps.register_which_key(resolved)

  local map = {}
  for action, lhs in pairs(resolved) do
    if lhs then map[lhs] = COMMAND_NAMES[action] end
  end
  return map
end

return M
