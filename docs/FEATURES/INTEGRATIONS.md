# Integrations

File-tree keymaps, fuzzy-finder previews, and the unified dispatch layer
that ties a file-tree's "which path is under the cursor" logic to
`pdfport.open()`. See [docs/BINDINGS.md](../BINDINGS.md) for the full
keymap/command/autocmd cheatsheet — this file covers what each integration
module does and how it plugs in.

## Unified dispatcher (`pdfport.integrations`)

`M.current_pdf_path()` auto-detects the active file-tree by the current
buffer's `filetype` (`neo-tree`/`NvimTree`/`netrw`/`oil`) and returns the
path under the cursor for whichever one matches, without the caller needing
to know which tree is active. `M.open_current(opts)` builds on it: resolves
the path, warns and bails if the cursor isn't on a `.pdf` (or the tree is
unsupported), then calls `pdfport.open()` with `{ mode = "buffer", split =
"vsplit", focus = true }` merged under any `opts` passed in.

- **Module:** `lua/pdfport/integrations/init.lua`
- **Accessor:** `pdfport.integrations()`

## neo-tree integration

Declarative — no `setup()` call. Exposes `commands()` and `keymaps()` for
the host config to merge into neo-tree's own `opts.commands` /
`opts.filesystem.window.mappings`. `keymaps()` accepts an opts table where
any action can be set to `false` to disable that default binding. The
visual-mode `open_batch` action is nested under a `["v"]` key in the
returned mappings table (neo-tree's own per-mode shape), rather than a
top-level entry like the other three integrations.

- **Module:** `lua/pdfport/integrations/neotree.lua`

## nvim-tree integration

Imperative — `require("pdfport.integrations.nvim_tree").setup(opts)`
registers buffer-local keymaps via `lib.nvim.map`, augroup `pdfport_tree`
on `FileType NvimTree`. Same per-action `false`-to-disable opts shape as
neo-tree.

- **Module:** `lua/pdfport/integrations/nvim_tree.lua`

## netrw integration

netrw has no Lua API, so paths are derived manually: `vim.b.netrw_curdir` +
`vim.fn.expand("<cfile>")` joined with the right path separator. Registered
via `setup()`, augroup `pdfport_netrw` on `FileType netrw`.

- **Module:** `lua/pdfport/integrations/netrw.lua`

## oil.nvim integration

`require("pdfport.integrations.oil").setup(opts)`, augroup `pdfport_oil` on
`FileType oil`. Path resolution combines `oil.get_current_dir()` and
`oil.get_cursor_entry()`.

- **Module:** `lua/pdfport/integrations/oil.lua`

## Telescope integration

Not a file-tree — a previewer for Telescope's picker preview pane. Two ways
to attach:

- `previewer(opts)` — pass into a single picker's `previewer` field to preview `.pdf` results inline (extracted text, not raw bytes).
- `filetype_hook` — attach once, globally, via `defaults.preview.filetype_hook` in Telescope's own `setup()`, so every picker gets PDF previews without opting in per-call.

`opts.max_pages` bounds how much of a long PDF gets extracted just for a
preview pane.

- **Module:** `lua/pdfport/integrations/telescope.lua`

## fzf-lua integration

Same idea for fzf-lua: `preview_fn(opts)` returns a `fun(filepath, bufnr,
opts)` suitable for a picker's `preview` field
(`require("fzf-lua").files({ preview = pdfport_fzf.preview_fn({ max_pages = 3 }) })`).
Keeps a small internal `_cache` table keyed by filepath so re-previewing the
same result while scrolling a picker doesn't re-extract every keystroke.

- **Module:** `lua/pdfport/integrations/fzf.lua`

## Which-key

If `which-key.nvim` is installed, every resolved file-tree keymap is
registered with a description under the `<leader>p` group automatically —
no separate configuration, and a no-op if which-key isn't present.

- **Module:** `lua/pdfport/bindings/keymaps.lua`

## Batch-open

The visual-mode `open_batch` action (`<leader>pb` by default) walks the
selected line range and re-runs the owning integration's own cursor-based
path resolver per line, opening every `.pdf` it finds — mode `buffer`,
unfocused, one after another.

- **Module:** `lua/pdfport/util/batch.lua`
