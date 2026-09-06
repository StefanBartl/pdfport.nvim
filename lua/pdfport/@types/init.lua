---@module 'pdfport.types'
---@brief EmmyLua type definitions for pdfport.nvim.

-- #############################################################################
-- Backend types
-- #############################################################################

---@alias PdfPort.BackendId
---| "pdftotext"   -- poppler-utils CLI tool
---| "pdfplumber"  -- Python pdfplumber library
---| "marker"      -- marker-pdf AI-assisted extraction
---| "docling"     -- IBM docling structured extraction
---| "claude"      -- Anthropic Claude API (remote)
---| "ollama"      -- Local ollama multimodal model
---| "tesseract"   -- Local tesseract OCR fallback
---| string        -- Custom/third-party backend identifier

---@class PdfPort.BackendCapabilities
---@field markdown boolean       # Can produce Markdown output
---@field tables boolean         # Reliably extracts tables
---@field ocr boolean            # Works on scanned/image PDFs
---@field remote boolean         # Requires network access
---@field gpu_optional boolean   # Can use GPU but does not require it

--- One text-extraction backend.
---
--- **Implementations declare a subclass, not `---@type PdfPort.Backend`.**
--- A backend module is a table literal carrying the data fields, with
--- `available`/`extract` defined as functions underneath it. Against a
--- `@type` annotation LuaLS checks the literal alone and reports both
--- methods as missing -- they are not, they are three lines further down.
--- `---@class PdfPort.Backend.Foo : PdfPort.Backend` makes the later
--- `function M.extract(...)` a definition of that class's field instead.
--- Same for `Producer` below.
---@class PdfPort.Backend
---@field id PdfPort.BackendId
---@field name string
---@field capabilities PdfPort.BackendCapabilities
---@field available fun(): boolean
---@field extract fun(path: string, opts: PdfPort.InternalExtractOpts): PdfPort.Result|nil

---@class PdfPort.StatefulBackend : PdfPort.Backend
---@field _last_result? PdfPort.Result

---@class PdfPort.ConfigurableBackend : PdfPort.Backend
---@field _set_config? fun(config: PdfPort.Config): nil

---@class PdfPort.ExtractOpts
---@field pages? integer[]
---@field max_pages? integer
---@field prompt? string
---@field model? string
---@field timeout_ms? integer
---@field path? string
---@field cache? boolean  # Cache successful extractions across sessions, keyed by path+backend+page-range and invalidated by mtime (default true)

---@class PdfPort.InternalExtractOpts : PdfPort.ExtractOpts
---@field __callback? fun(result: PdfPort.Result): nil
---@field backend_id? PdfPort.BackendId
---@field mode? PdfPort.RendererMode

-- #############################################################################
-- Renderer types
-- #############################################################################

---@alias PdfPort.RendererMode
---| "buffer"    -- Scratch buffer
---| "terminal"  -- Terminal image rendering
---| "system"    -- OS default application
---| "float"     -- Floating window

---@alias PdfPort.RendererSplit
---| "vsplit"   -- Open to the right
---| "split"    -- Open below
---| "tab"      -- Open in a new tab
---| "current"  -- Replace the current window

---@alias PdfPort.TerminalTool "chafa"|"kitty"|"imgcat"

---@class PdfPort.TerminalSizeRatio
---@field width number   # Fraction of vim.o.columns (0.0–1.0)
---@field height number  # Fraction of vim.o.lines (0.0–1.0)

---@class PdfPort.RenderOpts
---@field mode PdfPort.RendererMode
---@field path? string
---@field backend_id? PdfPort.BackendId
---@field split? PdfPort.RendererSplit
---@field float_opts? table
---@field terminal_tool? PdfPort.TerminalTool
---@field terminal_dpi? integer
---@field terminal_size_ratio? PdfPort.TerminalSizeRatio
---@field focus? boolean
---@field pages? integer[]

---@class PdfPort.OpenOpts : PdfPort.RenderOpts
---@field path string
---@field max_pages? integer
---@field prompt? string
---@field model? string
---@field timeout_ms? integer

---@class PdfPort.RenderPageCrop
---@field x integer   # Left edge of the window, in pixels of the page *as rendered at this call's dpi*
---@field y integer   # Top edge, same units
---@field w integer   # Window width in pixels; the PNG comes back this wide
---@field h integer   # Window height in pixels

---@class PdfPort.RenderPageOpts
---@field dpi? integer          # Rasterization DPI passed to pdftoppm (default 216)
---@field output_path? string   # Base path for the PNG (".png" appended/stripped as needed); default a fresh vim.fn.tempname()
---@field crop? PdfPort.RenderPageCrop # Rasterize only this window of the page (pdftoppm's `-x -y -W -H`) instead of the whole page. **Cost, not convenience:** a consumer magnifying a page raises `dpi` to get real detail, and a full page then grows with the square of it — measured on a dense A4 text page, 176 ms at 216 dpi against 2 653 ms at 1 094 dpi. Asking for a window the size of the *original* page keeps the work, the PNG and the wait flat instead: 120–600 ms at every one of those dpi values, because the number of pixels produced never changes and only the resolution they are sampled from does. Coordinates are in the coordinate system of the page at `dpi`, so a caller stepping dpi up scales them by the same factor.

-- #############################################################################
-- Producer types (PDF creation — the reverse of extraction)
-- #############################################################################

---@alias PdfPort.InputKind "image"|"markdown"|"html"|"text"|"office"|"pdf"

---@alias PdfPort.ProducerId
---| "img2pdf"     -- Python img2pdf CLI (lossless image embed)
---| "magick"      -- ImageMagick `magick` CLI
---| "pandoc"      -- pandoc + a PDF engine (markdown/text)
---| "weasyprint"  -- Python weasyprint CLI (html)
---| "chromium"    -- Chromium-family headless print-to-pdf (html)
---| "soffice"     -- LibreOffice headless (office)
---| "qpdf"        -- qpdf CLI (pdf merge)
---| "pdftk"       -- pdftk CLI (pdf merge)
---| "ghostscript" -- Ghostscript (pdf merge)
---| string        -- Custom/third-party producer identifier

---@class PdfPort.ProducerCapabilities
---@field batch boolean      # Multiple inputs → one document
---@field lossless boolean   # Embeds source data unchanged
---@field styling boolean    # Page size/margin/template are honored
---@field toc boolean        # Can generate a table of contents
---@field remote boolean     # Requires network access

---@class PdfPort.CreateOpts
---@field inputs? string[]      # File paths, in page order; exactly one of inputs/text/bufnr
---@field text? string          # Content directly; requires opts.from and opts.output
---@field bufnr? integer        # Buffer content; requires opts.from and opts.output
---@field output? string
---@field from? PdfPort.InputKind
---@field producer_id? PdfPort.ProducerId
---@field on_conflict? "overwrite"|"suffix"|"error"
---@field opts? PdfPort.CreateOpts
---@field __callback? fun(result: PdfPort.CreateResult): nil
---@field page_size? string
---@field margin? string
---@field dpi? integer
---@field fit? "contain"|"fill"|"native"
---@field title? string
---@field toc? boolean
---@field template? string
---@field timeout_ms? integer

---@class PdfPort.CreateResult
---@field status PdfPort.ResultStatus
---@field path string|nil        # Path of the created file
---@field producer PdfPort.ProducerId
---@field pages integer|nil
---@field error string|nil

---@class PdfPort.InternalCreateOpts : PdfPort.CreateOpts
---@field inputs string[]
---@field output string
---@field on_conflict "overwrite"|"suffix"|"error"
---@field __callback? fun(result: PdfPort.CreateResult): nil

---@class PdfPort.Producer
---@field id PdfPort.ProducerId
---@field name string
---@field accepts PdfPort.InputKind[]
---@field capabilities PdfPort.ProducerCapabilities
---@field available fun(): boolean
---@field create fun(req: PdfPort.InternalCreateOpts): PdfPort.CreateResult|nil

---@class PdfPort.ConfigurableProducer : PdfPort.Producer
---@field _set_config? fun(config: PdfPort.Config): nil

-- #############################################################################
-- Result types
-- #############################################################################

---@alias PdfPort.ResultStatus
---| "ok"
---| "error"
---| "partial"

---@class PdfPort.Result
---@field status PdfPort.ResultStatus
---@field text string|nil
---@field format "plain"|"markdown"
---@field backend PdfPort.BackendId
---@field pages_processed integer|nil
---@field error string|nil

-- #############################################################################
-- Config types
-- #############################################################################

---@class PdfPort.Config
---@field default_backend? PdfPort.BackendId|"auto"
---@field fallback_chain? PdfPort.BackendId[]
---@field extract_opts? PdfPort.ExtractOpts
---@field render_opts? PdfPort.RenderOpts
---@field create_opts? PdfPort.CreateOpts
---@field create_chain? table<PdfPort.InputKind, PdfPort.ProducerId[]>  # "pdf" entry is the merge chain, used by pdfport.merge()
---@field pdf_engine? string  # pandoc --pdf-engine preference: "auto"|"tectonic"|"typst"|"xelatex"|...
---@field claude_api_key? string
---@field ollama_host? string
---@field ollama_model? string
---@field auto_open_on_read? boolean  # Opt-in BufReadCmd *.pdf that auto-invokes the mode picker on `:e file.pdf` (default false)
---@field progress_style? "auto"|"notify"|"statusline"|"fidget"|"float"|"kit"  # Indicator while a backend extracts; needs lib.nvim, no-op without it (default "auto")
---@field deps_popup? boolean  # Show the lib.nvim.deps "declared tools" popup once, ever, on first setup() after install (default true; needs lib.nvim.deps — a no-op without it)
---@field debug? boolean

-- #############################################################################
-- Integration types
-- #############################################################################

---@class PdfPort.TelescopePreviewOpts
---@field backend_id? PdfPort.BackendId
---@field max_pages? integer

---@class PdfPort.FzfPreviewOpts
---@field backend_id? PdfPort.BackendId
---@field max_pages? integer

return {}
