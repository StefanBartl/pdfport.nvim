---@module 'pdfport_nvim.config.DEFAULTS'
---@brief Default configuration values for pdfport.nvim.
---@description
--- Read this file to see every configurable key and its default. Pass any
--- subset of these to require("pdfport_nvim").setup({...}) — user values are
--- deep-merged on top (see config/init.lua).

---@return PdfPort.Config
return function()
  return {
    default_backend = "auto",
    fallback_chain  = { "pdftotext", "pdfplumber", "marker", "docling", "ollama", "claude" },
    extract_opts = {
      max_pages  = nil,
      timeout_ms = 30000,
    },
    render_opts = {
      mode                 = "buffer",
      split                = "vsplit",
      focus                = true,
      terminal_dpi         = 216,
      terminal_size_ratio  = { width = 0.9, height = 0.8 },
    },
    claude_api_key = nil,
    ollama_host    = "http://localhost:11434",
    ollama_model   = "llava",
    debug          = false,
  }
end
