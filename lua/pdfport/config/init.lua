---@module 'pdfport.config'
---@brief Configuration management for pdfport.nvim.
---@description
--- See config/DEFAULTS.lua for every configurable key and its default value.

local M = {}

local defaults = require("pdfport.config.DEFAULTS")

---@type PdfPort.Config
local _cfg = nil

---@param opts? PdfPort.Config
---@return nil
function M.setup(opts)
  _cfg = vim.tbl_deep_extend("force", defaults(), opts or {})
end

---@return PdfPort.Config
function M.get()
  return _cfg or defaults()
end

return M
