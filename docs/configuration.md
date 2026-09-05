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
  create_opts = {
    page_size  = "A4",
    margin     = "20mm",
    dpi        = 300,               -- image path only
    fit        = "contain",         -- "contain"|"fill"|"native"
    timeout_ms = 60000,             -- creation can run longer than extraction
  },
  create_chain = {                  -- per input-kind producer fallback chain
    image    = { "img2pdf", "magick" },
    markdown = { "pandoc" },
    text     = { "pandoc" },
    html     = { "weasyprint", "chromium" },
    office   = { "soffice" },
    pdf      = { "qpdf", "pdftk", "ghostscript" },  -- merge chain, used by pdfport.merge()
  },
  pdf_engine     = "auto",          -- pandoc --pdf-engine preference:
                                     -- "auto"|"tectonic"|"typst"|"xelatex"|"lualatex"|"pdflatex"
  claude_api_key = nil,              -- or set ANTHROPIC_API_KEY env var
  ollama_host    = "http://localhost:11434",
  ollama_model   = "llava",
  auto_open_on_read = false,        -- opt-in BufReadCmd *.pdf: `:e file.pdf` invokes the mode picker
  progress_style = "auto",          -- indicator while a backend extracts; see below
  debug          = false,

  -- One-time "which CLI tools does this plugin want, and why" popup on first
  -- setup() after install (via lib.nvim.deps). false disables it here, in the
  -- spec passed to setup() — no vim.g needed. See the root README.
  deps_popup = true,
})
```

### Progress indicator

An extraction is not instant: `marker`, `docling`, `ollama` and `tesseract` run
an OCR/AI pipeline that can take minutes on a large PDF, and the default
`timeout_ms` is 30s (backends raise it to 120s). Because extraction is
asynchronous, nothing was on screen while it ran — indistinguishable from a
command that silently did nothing.

`progress_style` picks how that is reported, via
[`lib.nvim.progress`](https://github.com/StefanBartl/lib.nvim/blob/main/lua/lib/nvim/progress/README.md):
`"auto"` (default; prefers fidget.nvim, else `vim.notify`), `"notify"`,
`"statusline"`, `"fidget"`, `"float"`, `"kit"`.

`lib.nvim` is a required dependency of pdfport, so this always works. Two
details worth knowing:

- **It lives in the dispatcher**, not in the backends — so all seven get it,
  and a backend you register yourself does too, for free.
- **It cannot be cancelled.** Backends spawn through `spawn_capture`, which
  does not expose a killable handle, so `"float"`/`"kit"`'s abort prompt would
  close the indicator while the process kept running. `timeout_ms` is the only
  real bound on a runaway extraction. Prefer `"notify"` or `"statusline"` here.

A cache hit starts no indicator at all (it returns immediately), and the
~150ms delay guard means a fast `pdftotext` run never flashes any UI.

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

## Creation producers

The reverse direction: something → PDF, via `pdfport.create()`/`:PdfPort create`.

| ID          | Accepts          | Requires                          | Notes                              |
|-------------|------------------|------------------------------------|-------------------------------------|
| img2pdf     | image            | `pip install img2pdf`              | First choice: lossless, embeds source data unchanged |
| magick      | image            | ImageMagick (`magick` on PATH)     | Pragmatic default; recompresses    |
| pandoc      | markdown, text   | `pandoc` + one PDF engine          | Engine auto-detected: tectonic → typst → xelatex → lualatex → pdflatex, or pin one via `pdf_engine` |
| weasyprint  | html             | `pip install weasyprint`           | First choice for HTML: CSS Paged Media |
| chromium    | html             | a Chromium-family browser on PATH  | Fallback: chromium/chromium-browser/google-chrome/chrome/msedge |
| soffice     | office           | LibreOffice (`soffice` on PATH)    | docx/odt/xlsx/pptx in one call     |
| qpdf        | pdf (merge)      | `qpdf` on PATH                     | First choice for `pdfport.merge()` |
| pdftk       | pdf (merge)      | `pdftk` on PATH                    | Merge fallback #2                  |
| ghostscript | pdf (merge)      | `gs`/`gswin64c`/`gswin32c` on PATH | Merge fallback #3, last resort     |

`inputs` (file paths) covers the common case; `text`/`bufnr` (with required `from` + `output`)
are materialized to a temp file via `util/tmpfile.lua` first and cleaned up again once the
producer's result is in — producers only ever see a real path either way.

Producers are registered lazily, the same way as backends: `setup()` only registers
lightweight proxies, and the real module is only `require`d the first time the composer
actually calls `available()`/`create()` on it.

## Caching

Successful extractions are cached across Neovim restarts (`lib.nvim.cache.disk`), keyed by
path + backend id + page-range and invalidated by the source file's mtime — editing the PDF
on disk transparently invalidates its cache entry. Disable per `setup()` call with
`extract_opts.cache = false`, or clear everything with
`require("pdfport.util.cache").clear()`.
