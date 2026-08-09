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

## Creation: something → PDF *(new, 2026-08-09)*

`pdfport.create()`/`:PdfPort create` is the reverse direction: given one or
more input files, resolve a **producer** through a per-input-kind fallback
chain (`create_chain`) and write a PDF. Mirrors the read path's shape exactly
(`registry.register_producer`, `core/composer.lua`, lazy-loaded
`producers/*.lua`) so the same mental model applies to both directions.

**P0 + P1 — shipped:** image and markdown/text inputs.

| Producer  | Accepts        | Requires                       | Notes                          |
|-----------|----------------|---------------------------------|-----------------------------------|
| img2pdf   | image          | `pip install img2pdf`           | First choice: lossless            |
| magick    | image          | ImageMagick (`magick` on PATH)  | Pragmatic default; recompresses   |
| pandoc    | markdown, text | `pandoc` + one PDF engine       | Engine auto-detected: tectonic -> typst -> xelatex -> lualatex -> pdflatex |

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
```

`:PdfPort create [path]` creates a PDF from an image (path arg, `<cfile>`, or
current buffer); `:PdfPort producers` lists every registered producer with
live availability, same as `:PdfPort backends` does for extraction backends.

**Not shipped yet (P2–P3):** HTML input (`weasyprint`/`chromium`), Office
input (`soffice`), the actual caller wiring into
`images.nvim`/`markdown.nvim`/`filetree.nvim` (e.g. `:Markdown export pdf`),
and `pdfport.merge()` for combining existing PDFs. Full design and phased
plan in [docs/ROADMAP/PDF_CREATE.md](ROADMAP/PDF_CREATE.md).

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
