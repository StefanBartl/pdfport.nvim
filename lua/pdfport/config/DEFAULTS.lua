---@module 'pdfport.config.DEFAULTS'
---@brief Default configuration values for pdfport.nvim.
---@description
--- Read this file to see every configurable key and its default. Pass any
--- subset of these to require("pdfport").setup({...}) — user values are
--- deep-merged on top (see config/init.lua).

---@return PdfPort.Config
return function()
  return {
    default_backend = "auto",
    fallback_chain = {
      "pdftotext",
      "pdfplumber",
      "marker",
      "docling",
      "ollama",
      "tesseract",
      "claude",
    },
    extract_opts = {
      max_pages = nil,
      timeout_ms = 30000,
      cache = true,
    },
    render_opts = {
      mode = "buffer",
      split = "vsplit",
      focus = true,
      terminal_dpi = 216,
      terminal_size_ratio = { width = 0.9, height = 0.8 },
    },
    claude_api_key = nil,
    ollama_host = "http://localhost:11434",
    ollama_model = "llava",
    auto_open_on_read = false,
    -- Indicator while a backend extracts. OCR/AI backends run for minutes;
    -- needs lib.nvim, silently a no-op without it.
    progress_style = "auto",
    debug = false,
  }
end
