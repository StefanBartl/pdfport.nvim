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
    create_opts = {
      page_size = "A4",
      margin = "20mm",
      dpi = 300,
      fit = "contain",
      timeout_ms = 60000,
    },
    -- Per input-kind producer fallback chain for pdfport.create(). Only
    -- "image" has a shipped producer today (img2pdf → magick); the other
    -- kinds are pre-wired here so producers/*.lua can register into them
    -- later (see docs/ROADMAP/PDF_CREATE.md) without a config shape change.
    create_chain = {
      image = { "img2pdf", "magick" },
      markdown = {},
      html = {},
      office = {},
    },
    pdf_engine = "auto",
    claude_api_key = nil,
    ollama_host = "http://localhost:11434",
    ollama_model = "llava",
    auto_open_on_read = false,
    -- Indicator while a backend extracts. OCR/AI backends run for minutes;
    -- needs lib.nvim, silently a no-op without it.
    progress_style = "auto",
    -- One-time "which CLI tools does this plugin want, and why" popup on
    -- first setup() after install (via lib.nvim.deps). Set to false to
    -- disable it for this plugin specifically, right here in the spec
    -- passed to setup() — no vim.g needed. See README "Optional external
    -- tools".
    deps_popup = true,
    debug = false,
  }
end
