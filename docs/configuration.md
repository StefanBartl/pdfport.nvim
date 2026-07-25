# Configuration

```lua
require("pdfport").setup({
  default_backend = "auto",          -- "auto" | backend id
  fallback_chain  = {                -- order tried when default_backend = "auto"
    "pdftotext", "pdfplumber", "marker", "docling", "ollama", "claude"
  },
  extract_opts = {
    max_pages  = nil,                -- nil = all pages
    timeout_ms = 30000,
    cache      = true,               -- cache successful extractions across sessions (mtime-invalidated)
  },
  render_opts = {
    mode                = "buffer",  -- "buffer"|"float"|"terminal"|"system"
    split               = "vsplit",  -- "vsplit"|"split"|"tab"|"current"
    focus               = true,
    terminal_dpi        = 216,       -- pdftoppm rasterization DPI (terminal mode)
    terminal_size_ratio = {          -- fraction of the editor size used by the image
      width  = 0.9,
      height = 0.8,
    },
  },
  claude_api_key = nil,              -- or set ANTHROPIC_API_KEY env var
  ollama_host    = "http://localhost:11434",
  ollama_model   = "llava",
  auto_open_on_read = false,        -- opt-in BufReadCmd *.pdf: `:e file.pdf` invokes the mode picker
  debug          = false,
})
```

See [lua/pdfport/config/DEFAULTS.lua](../lua/pdfport/config/DEFAULTS.lua) for the
authoritative default values and [lua/pdfport/@types/init.lua](../lua/pdfport/@types/init.lua)
for full field types (LSP completion works out of the box via `---@type PdfPort.Config`).

Backends are registered lazily: `setup()` only registers lightweight proxies for the
builtins below, and the real module for a given backend is only `require`d the first time
the resolver actually calls `available()`/`extract()` on it.

## Backends

| ID          | Requires                                    | Output   |
|-------------|---------------------------------------------|----------|
| pdftotext   | `pdftotext` (poppler-utils)                 | plain    |
| pdfplumber  | Python + `pip install pdfplumber`           | plain    |
| marker      | `pip install marker-pdf`                    | Markdown |
| docling     | `pip install docling`                       | Markdown |
| ollama      | `ollama`, `pdftoppm`, `curl`                | Markdown |
| tesseract   | `tesseract`, `pdftoppm` (OCR fallback)      | plain    |
| claude      | `curl`, `base64`, `ANTHROPIC_API_KEY`       | Markdown |

## Caching

Successful extractions are cached across Neovim restarts (`lib.nvim.cache.disk`), keyed by
path + backend id + page-range and invalidated by the source file's mtime — editing the PDF
on disk transparently invalidates its cache entry. Disable per `setup()` call with
`extract_opts.cache = false`, or clear everything with
`require("pdfport.util.cache").clear()`.
