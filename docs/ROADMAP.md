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
- ~~Add automated test coverage~~ — [test/smoke.lua](../test/smoke.lua), headless,
  stub-backend-based; covers `setup()`, lazy backend registration/resolution, the
  dispatcher's error/cache paths, and the disable/which-key keymap logic. Run via
  `nvim --clean --headless -u NONE -l test/smoke.lua` (see [test/README.md](../test/README.md)).
- ~~Make backend loading truly lazy~~ — `backends/init.lua`'s `M.load_all()` now registers
  each builtin as a lazy proxy; the real module is only `require`d the first time the
  resolver actually touches `available()`/`extract()` on it, not unconditionally at
  `setup()` time.

## Features

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
