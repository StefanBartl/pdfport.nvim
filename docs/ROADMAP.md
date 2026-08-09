# Roadmap

Ideas and candidates for future work. Nothing here is committed to a release; move an
item up when you actually start it.

## Checklist audits & implementation plan

pdfport.nvim was audited against the project checklists. Full per-rule status:
- [Zentral-Prinzipien.md](ROADMAP/Zentral-Prinzipien.md)
- [Arch&Coding.md](ROADMAP/Arch%26Coding.md)
- [Checklist.md](ROADMAP/Checklist.md)
- Reusable patterns for filetree.nvim: [NEOTREE_FEATURES.md](ROADMAP/NEOTREE_FEATURES.md)

**Prioritized action items surfaced by the audits:**
1. **(minor) Unified window-lifecycle helper** — `buffer`/`float`/`terminal` renderers each
   hand-roll their own window creation/validity checks. Only worth centralizing if a fourth
   window-based renderer is added; not an active problem today.

Done, moved out of this list (2026-07):
- ~~Add automated test coverage~~ — [TESTS/](../TESTS), headless, framework-free,
  stub-backend-based; four specs (`page_range`, `registry`, `resolver`, `smoke`) cover
  `setup()`, lazy backend registration/resolution, the dispatcher's error/cache paths, and
  the disable/which-key keymap logic. Run via `TESTS/run.lua`, gated in CI (see
  [.github/workflows/ci.yml](../.github/workflows/ci.yml)). The earlier standalone
  `test/smoke.lua` this superseded has been removed (2026-08) — it was dead weight, not
  wired into CI, and drifting out of sync with the actual suite.
- ~~Make backend loading truly lazy~~ — `backends/init.lua`'s `M.load_all()` now registers
  each builtin as a lazy proxy; the real module is only `require`d the first time the
  resolver actually touches `available()`/`extract()` on it, not unconditionally at
  `setup()` time.

## Features

Open:
- **Expose page rasterization as a public API.** `renderers/terminal.lua`
  already rasterizes a PDF page to a throwaway PNG via `pdftoppm` (its local
  `rasterize()`, deleted again ~2s after display) — every ingredient for a
  general "PDF page → image file" API already exists internally, it just
  isn't reusable outside this one renderer. Extract it into something like
  `require("pdfport").render_page(path, page, opts, callback)` that returns
  a real (non-throwaway) PNG path via callback instead of display-and-delete.
  This is what would let `images.nvim` (or any other consumer) show a PDF
  page without pdfport depending on images.nvim or reimplementing rasterization
  itself — pdfport owns the PDF-specific part (backend selection, `pdftoppm`
  invocation, DPI/page-range handling), the caller decides what to do with
  the resulting image. images.nvim's own roadmap explicitly points here now
  instead of carrying a "PDF page as image" item itself (see
  `images.nvim/docs/ROADMAP/README.md` and `CROSS-PLUGIN.md`, 2026-08-06).

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
  section. See [docs/FEATURES.md](FEATURES.md). Of P2 (caller wiring),
  `filetree.nvim` is now wired (`util/pdf.create()` + `pdf_create` feature,
  documented there); `images.nvim`/`markdown.nvim` wiring remains open (own
  repos) — full design in [ROADMAP/PDF_CREATE.md](ROADMAP/PDF_CREATE.md).

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

## Deferred cleanup (noted during the 2026-07 checklist pass)

- The four file-tree integrations (`neotree`, `nvim_tree`, `netrw`, `oil`) still each
  re-implement their own buffer-local dispatch glue around the shared
  `util/picker.lua` / `bindings/autocmds.lua` helpers. A natural next step, once
  `lib.nvim` is available as an edit target from this workspace, would be to move
  `util/picker.lua` (and possibly `bindings/autocmds.lua`) there so other
  `StefanBartl/*.nvim` plugins can reuse the same file-tree dispatch pattern instead of
  each plugin re-inventing it.
- `renderers/terminal.lua`'s `chafa`/`kitty`/`imgcat` invocation goes through
  `vim.cmd("split | terminal ...")` with `vim.fn.shellescape()`. This works across
  platforms today (Neovim's `shellescape()` adapts to `'shell'`), but if a more exotic
  Windows shell setup ever breaks it, prefer `vim.fn.jobstart()` with an args table
  instead of a shell string.
