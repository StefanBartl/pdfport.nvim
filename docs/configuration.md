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
  debug          = false,
})
```

See [lua/pdfport/config/DEFAULTS.lua](../lua/pdfport/config/DEFAULTS.lua) for the
authoritative default values and [lua/pdfport/@types/init.lua](../lua/pdfport/@types/init.lua)
for full field types (LSP completion works out of the box via `---@type PdfPort.Config`).

## Backends

| ID          | Requires                                    | Output   |
|-------------|---------------------------------------------|----------|
| pdftotext   | `pdftotext` (poppler-utils)                 | plain    |
| pdfplumber  | Python + `pip install pdfplumber`           | plain    |
| marker      | `pip install marker-pdf`                    | Markdown |
| docling     | `pip install docling`                       | Markdown |
| claude      | `curl`, `base64`, `ANTHROPIC_API_KEY`       | Markdown |
| ollama      | `ollama`, `pdftoppm`, `curl`                | Markdown |
