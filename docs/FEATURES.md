# Features

Overview of pdfport.nvim's capabilities. See [README.md](../README.md) for a
quick install/usage snippet, [docs/commands.md](commands.md) for the full
command/Lua-API reference, and [docs/configuration.md](configuration.md) for
every `setup()` option.

## Contents

- [Reading: PDF → text/Markdown](#reading-pdf--textmarkdown)
- [Creation: something → PDF](#creation-something--pdf)
- [Rendering & display](#rendering--display)
- [File-tree & fuzzy-finder integrations](#file-tree--fuzzy-finder-integrations)
- [Caching](#caching)
- [Health check](#health-check)

---

## Reading: PDF → text/Markdown

`pdfport.open()`/`pdfport.extract()` resolve a **backend** through a
configurable fallback chain (`fallback_chain`) and extract PDF content as
plain text or Markdown:

| Backend    | Requires                               | Output   |
|------------|------------------------------------------|----------|
| pdftotext  | `pdftotext` (poppler-utils)               | plain    |
| pdfplumber | Python + `pip install pdfplumber`         | plain    |
| marker     | `pip install marker-pdf`                  | Markdown |
| docling    | `pip install docling`                     | Markdown |
| ollama     | `ollama`, `pdftoppm`, `curl`               | Markdown |
| tesseract  | `tesseract`, `pdftoppm` (OCR fallback)     | plain    |
| claude     | `curl`, `base64`, `ANTHROPIC_API_KEY`      | Markdown |

Custom backends can be added via `pdfport.register_backend()`.

## Creation: something → PDF *(2026-08-09)*

`pdfport.create()`/`:PdfPort create` is the reverse direction: given one or
more input files, resolve a **producer** through a per-input-kind fallback
chain (`create_chain`) and write a PDF. Mirrors the read path's shape exactly
(`registry.register_producer`, `core/composer.lua`, lazy-loaded
`producers/*.lua`) so the same mental model applies to both directions.

**P0–P3 — shipped:** image, markdown/text, HTML, office, and PDF-merge inputs.

| Producer    | Accepts        | Requires                        | Notes                          |
|-------------|----------------|----------------------------------|-----------------------------------|
| img2pdf     | image          | `pip install img2pdf`            | First choice: lossless            |
| magick      | image          | ImageMagick (`magick` on PATH)   | Pragmatic default; recompresses   |
| pandoc      | markdown, text | `pandoc` + one PDF engine        | Engine auto-detected: tectonic -> typst -> xelatex -> lualatex -> pdflatex |
| weasyprint  | html           | `pip install weasyprint`         | First choice for HTML: clean CSS Paged Media |
| chromium    | html           | a Chromium-family browser on PATH | Fallback: chromium/chromium-browser/google-chrome/chrome/msedge, headless print-to-pdf |
| soffice     | office         | LibreOffice (`soffice` on PATH)  | docx/odt/xlsx/pptx in one call, converts via a scratch dir |
| qpdf        | pdf (merge)    | `qpdf` on PATH                   | First choice for `pdfport.merge()`: exact, no re-encoding |
| pdftk       | pdf (merge)    | `pdftk` on PATH                  | Merge fallback #2 |
| ghostscript | pdf (merge)    | `gs`/`gswin64c`/`gswin32c` on PATH | Merge fallback #3, last resort: recompresses |

```lua
require("pdfport").create({
  inputs = { "/path/a.png", "/path/b.png" },  -- order = page order
  -- output, from, producer_id, on_conflict, opts.{page_size,margin,dpi,fit,...} all optional
})

-- Or create directly from text/a buffer (requires from + output; no path to guess from)
require("pdfport").create({
  text   = "# Title\n\nSome text.",
  from   = "markdown",
  output = "/path/out.pdf",
})

-- Merge two or more existing PDFs into one
require("pdfport").merge({
  inputs = { "/path/a.pdf", "/path/b.pdf" },
  output = "/path/merged.pdf",
})
```

`:PdfPort create [path]` creates a PDF from an image/markdown/text/html/office
file (path arg, `<cfile>`, or current buffer); `:PdfPort merge <output.pdf>
<a.pdf> <b.pdf> ...` merges two or more existing PDFs; `:PdfPort producers`
lists every registered producer (including the merge producers) with live
availability, same as `:PdfPort backends` does for extraction backends.

**P2 caller wiring shipped (2026-08-09), all three:** `filetree.nvim`
(`util/pdf.create()` + the `pdf_create` feature), `images.nvim`
(`convert.to_pdf`/`M.export` route through `pdfport.create()` when
available, else the previous `magick`-only path unchanged), and
`markdown.nvim` (`:Markdown export pdf`) — each documented in its own repo.
Full design and phased plan in
[docs/ROADMAP/PDF_CREATE.md](ROADMAP/PDF_CREATE.md).

## Rendering & display

Four renderers, selectable per call or via `render_opts.mode`:

| Mode     | What it does |
|----------|---------------|
| `buffer` | Extracted text/Markdown in a scratch buffer (split/vsplit/tab) |
| `float`  | Extracted text in a centered floating window; page-range prompt |
| `system` | Opens the original PDF with the OS default application |
| `terminal` | Rasterizes a page via `pdftoppm`, displays with chafa/kitty/imgcat; page-range prompt |

## File-tree & fuzzy-finder integrations

Buffer-local keymaps (`<leader>po/pt/ps/pi/pb`) for neo-tree, nvim-tree,
netrw, and oil.nvim — see [docs/BINDINGS.md](BINDINGS.md). Telescope
(previewer + global `filetype_hook`) and fzf-lua (preview function)
integrations for showing PDF content inline in a picker.

## Caching

Successful extractions are cached across Neovim restarts
(`lib.nvim.cache.disk`), keyed by path + backend id + page-range and
invalidated by the source file's mtime. Opt out per `setup()` call with
`extract_opts.cache = false`. Creation has no cache — an export is a
one-off, explicit action with a target path, not a repeated read.

## Health check

`:checkhealth pdfport` reports: core module load status, backend
availability, **producer availability**, renderer availability, integration
status, and the live registry state for both backends and producers.
