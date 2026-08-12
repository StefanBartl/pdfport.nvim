## Features

Done (2026-08):
- ~~PDF creation as a public API (P0-P3: scaffold, images, Markdown/text,
  HTML, Office, merge).~~ — `producers/` registry mirroring `backends/`,
  [`core/composer.lua`](../lua/pdfport/core/composer.lua) (now also materializing
  `opts.text`/`opts.bufnr` via [`util/tmpfile.lua`](../lua/pdfport/util/tmpfile.lua)),
  [`producers/img2pdf.lua`](../lua/pdfport/producers/img2pdf.lua) +
  [`producers/magick.lua`](../lua/pdfport/producers/magick.lua) +
  [`producers/pandoc.lua`](../lua/pdfport/producers/pandoc.lua) (PDF-engine
  auto-detection) + [`producers/weasyprint.lua`](../lua/pdfport/producers/weasyprint.lua) +
  [`producers/chromium.lua`](../lua/pdfport/producers/chromium.lua) (HTML) +
  [`producers/soffice.lua`](../lua/pdfport/producers/soffice.lua) (Office) +
  [`producers/qpdf.lua`](../lua/pdfport/producers/qpdf.lua) +
  [`producers/pdftk.lua`](../lua/pdfport/producers/pdftk.lua) +
  [`producers/ghostscript.lua`](../lua/pdfport/producers/ghostscript.lua) (merge,
  registered as ordinary "pdf"-kind producers), `pdfport.create()`/`can_create()`/
  `merge()`, `:PdfPort create`/`:PdfPort merge`/`:PdfPort producers`, a `health.lua`
  section. See [docs/FEATURES.md](FEATURES.md). P2 (caller wiring) is done
  too: `filetree.nvim` (`util/pdf.create()` + `pdf_create` feature),
  `images.nvim` (`convert.to_pdf`/`M.export` route through `pdfport.create()`
  when available), and `markdown.nvim` (`:Markdown export pdf`) all wired —
  each documented in its own repo. Full design in
  [ROADMAP/PDF_CREATE.md](ROADMAP/PDF_CREATE.md).

Done (2026-07):
- ~~OCR fallback backend~~ — [`tesseract`](../lua/pdfport/backends/tesseract.lua):
  rasterizes via `pdftoppm`, OCRs via `tesseract … stdout`. In the default fallback chain.
- ~~Page-range picker UI for `terminal`/`float` modes~~ — [`util/page_range.lua`](../lua/pdfport/util/page_range.lua),
  wired into `:PdfPort float`/`:PdfPort terminal`, the root mode picker, and `util/picker.lua`.
- ~~Caching extracted text across sessions~~ — [`util/cache.lua`](../lua/pdfport/util/cache.lua),
  a `lib.nvim.cache.disk`-backed cache keyed by path+backend+page-range, invalidated by the
  source file's mtime. On by default (`extract_opts.cache`, opt out per `setup()` call).

## Commands

Done (2026-07):
- ~~`:PdfPortBackends`~~ — implemented as `:PdfPort backends` (kept inside the single-verb
  composer command rather than a new flat command, consistent with the 2026-07 migration
  away from flat `:PdfPortX` commands). Reuses `registry.diagnostics()`.

## Keymaps

Done (2026-07):
- ~~Visual-mode / operator-pending mappings for batch-opening multiple selected files in a
  tree~~ — `open_batch` (default `<leader>pb`, visual mode), [`util/batch.lua`](../lua/pdfport/util/batch.lua).
  Walks the visual selection line by line and re-runs each integration's existing
  cursor-based path resolver, so no new per-adapter "node at line N" API was needed.

## Autocmds

Done (2026-07):
- ~~Optional `BufReadCmd` for `*.pdf`~~ — `bindings/autocmds.lua`'s `M.register_bufreadcmd()`,
  opt-in via `setup({ auto_open_on_read = true })` (default off).
