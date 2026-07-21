---@module 'pdfport.bindings.keymaps'
---@brief Default keymap table and optional which-key registration.
---@description
--- Every file-tree integration resolves its keymaps against M.DEFAULTS and
--- accepts `false` per-action to disable a mapping entirely. Passing the
--- resolved table to M.register_which_key() adds descriptions to which-key
--- (folke/which-key.nvim) when it is installed; a no-op otherwise.

local M = {}

---@class PdfPort.KeymapOpts
---@field open? string|false
---@field open_text? string|false
---@field open_system? string|false
---@field open_terminal? string|false

---@type table<string, string>
M.DEFAULTS = {
  open          = "<leader>po",
  open_text     = "<leader>pt",
  open_system   = "<leader>ps",
  open_terminal = "<leader>pi",
}

---@type table<string, string>
M.DESCRIPTIONS = {
  open          = "pdfport: mode picker",
  open_text     = "pdfport: extract to buffer",
  open_system   = "pdfport: open with system application",
  open_terminal = "pdfport: terminal image preview",
}

---@param opts? PdfPort.KeymapOpts  nil per-field falls back to M.DEFAULTS; false disables
---@return table<string, string|false>
function M.resolve(opts)
  opts = opts or {}
  local resolved = {}
  for action, default in pairs(M.DEFAULTS) do
    local v = opts[action]
    resolved[action] = (v == nil) and default or v
  end
  return resolved
end

---@param resolved table<string, string|false>  result of M.resolve()
---@return nil
function M.register_which_key(resolved)
  local ok, wk = pcall(require, "which-key")
  if not ok then return end

  local spec = { { "<leader>p", group = "pdfport" } }
  for action, lhs in pairs(resolved) do
    if lhs then
      spec[#spec + 1] = { lhs, desc = M.DESCRIPTIONS[action] or ("pdfport: " .. action), mode = "n" }
    end
  end
  pcall(wk.add, spec)
end

return M
