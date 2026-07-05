---@module 'pdfport_nvim.types'
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
---| string        -- Custom/third-party backend identifier

---@class PdfPort.BackendCapabilities
---@field markdown boolean       # Can produce Markdown output
---@field tables boolean         # Reliably extracts tables
---@field ocr boolean            # Works on scanned/image PDFs
---@field remote boolean         # Requires network access
---@field gpu_optional boolean   # Can use GPU but does not require it

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

---@alias PdfPort.TerminalTool "ueberzug"|"chafa"|"kitty"|"imgcat"

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
---@field default_backend PdfPort.BackendId|"auto"
---@field fallback_chain PdfPort.BackendId[]
---@field extract_opts PdfPort.ExtractOpts
---@field render_opts PdfPort.RenderOpts
---@field claude_api_key? string
---@field ollama_host? string
---@field ollama_model? string
---@field debug boolean

-- #############################################################################
-- Integration types
-- #############################################################################

---@class PdfPort.TelescopePreviewOpts
---@field backend_id? PdfPort.BackendId
---@field max_pages? integer

---@class PdfPort.FzfPreviewOpts
---@field backend_id? PdfPort.BackendId
---@field max_pages? integer

---@alias uv_process_t any

return {}
