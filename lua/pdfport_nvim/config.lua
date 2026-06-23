---@module 'pdfport_nvim.config'
---@brief Configuration management for pdfport.nvim.

local M = {}

---@type PdfPort.Config
local _cfg = nil

---@return PdfPort.Config
local function defaults()
  return {
    default_backend = "auto",
    fallback_chain  = { "pdftotext", "pdfplumber", "marker", "docling", "ollama", "claude" },
    extract_opts = {
      max_pages  = nil,
      timeout_ms = 30000,
    },
    render_opts = {
      mode  = "buffer",
      split = "vsplit",
      focus = true,
    },
    claude_api_key = nil,
    ollama_host    = "http://localhost:11434",
    ollama_model   = "llava",
    debug          = false,
  }
end

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
