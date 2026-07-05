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
1. **Add automated test coverage** — the one gap all three audits agree on. No `test/`
   directory exists at all today. A `test/smoke.lua` in the shape of `filetree.nvim`'s
   (headless `require()` chain + a stub/fake backend) should cover `setup()`, dispatcher
   resolution, and the disable/which-key keymap logic added in the 2026-07 checklist pass.
2. **Make backend loading truly lazy** — `backends/init.lua`'s `M.load_all()` `require`s
   all six backend modules unconditionally at `setup()` time. Defer each backend's
   `require` to the point the resolver actually picks it, instead of loading all six
   upfront.
3. **(minor) Unified window-lifecycle helper** — `buffer`/`float`/`terminal` renderers each
   hand-roll their own window creation/validity checks. Only worth centralizing if a fourth
   window-based renderer is added; not an active problem today.

## Features

- [ ] OCR fallback backend for scanned/image-only PDFs without a vision model (e.g. `tesseract`).
- [ ] Page-range picker UI for `terminal`/`float` modes (currently only `extract_opts.max_pages`/`pages`).
- [ ] Caching extracted text across sessions (currently only in-memory per Telescope/fzf-lua session).

## Commands

- [ ] `:PdfPortBackends` — list all registered backends with live availability (currently only via `:checkhealth`).

## Keymaps

- [ ] Visual-mode / operator-pending mappings for batch-opening multiple selected files in a tree.

## Autocmds

- [ ] Optional `BufReadCmd` for `*.pdf` to auto-invoke the mode picker when a PDF is opened directly (`:e file.pdf`), instead of requiring a file-tree or `:PdfPort`.

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
