# Roadmap

Ideas and candidates for future work. Nothing here is committed to a release; move an
item up when you actually start it.

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
