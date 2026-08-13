# Rendering

The output side of the read path: once a backend has extracted text/Markdown
(or, for `system`/`terminal`, without extracting at all), a **renderer**
decides how it reaches the screen. Four builtins, selectable per call
(`opts.mode`) or via `render_opts.mode` in `setup()`; registered in
`pdfport.setup()` against `core/registry.lua`'s renderer table
(`reg.register_renderer(id, rm.render)`), keyed by mode string.

`core/dispatcher.lua`'s `M.open()` picks the renderer after a successful
extraction (or, for `system`/`terminal`, short-circuits dispatch entirely —
see [CORE.md](CORE.md)) and merges `render_opts` from config under the
per-call `opts` before invoking `renderer(result, render_opts)`.

## buffer renderer

Puts extracted text/Markdown into a scratch buffer named
`pdfport://<filename-stem>` (reused across repeated opens of the same file).
Prepends a one-line HTML-comment header (`<!-- pdfport: name | backend: id |
format: fmt -->`), sets `filetype` to `markdown` or `text` based on
`result.format`, and marks the buffer `nofile`/`bufhidden=hide`/
`swapfile=false`/non-modifiable after writing.

`opts.split` controls placement: `nil`/`"current"` replaces the current
window (default), `"vsplit"` opens to the right, `"split"` opens below,
`"tab"` opens a new tab. Before placing the buffer it steers away from
sidebar/float windows (`ensure_editor_win()` checks filetype
neo-tree/NvimTree/netrw and `win_get_config().relative`) so opening a PDF
from a tree sidebar doesn't clobber the tree itself. `opts.focus = false`
returns focus to the original window after opening (or `wincmd p` if that
window no longer exists).

- **Module:** `lua/pdfport/renderers/buffer.lua`
- **Default split:** `render_opts.split = "vsplit"`

## float renderer

Centered floating window via `lib.nvim.window.make_scratch` — 80%
width/height, rounded border, read-only scratch buffer, `q`/`<Esc>` to
close (`nice_quit`). Title shows the PDF's filename. `opts.float_opts` (rarely
populated by any caller) merges onto the scratch opts for the fields
`make_scratch` directly supports (width/height/row/col/border/title/
title_pos) — not an arbitrary `nvim_open_win` override passthrough.

Used for a quick look without touching the window layout; the `:PdfPort`
interactive picker and `:PdfPort float` both prompt for a page range first
(`util/page_range.prompt`) since floats default to `wrap = true` and are a
worse fit for a whole long document.

- **Module:** `lua/pdfport/renderers/float.lua`

## system renderer

Opens the *original PDF file* (not extracted text) with the OS default
application, via `platform.open_cmd()` (`xdg-open`/`open`/`start`
equivalent) and `vim.fn.jobstart({ cmd, path }, { detach = true })`. No
backend/extraction involved at all — `core/dispatcher.lua` special-cases
`opts.mode == "system"` before backend resolution even runs, so this mode
works with zero backends installed.

- **Module:** `lua/pdfport/renderers/system.lua`

## terminal renderer

Rasterizes one or more pages via `pdftoppm` (delegated to
`core/rasterize.lua`, the same primitive the public `pdfport.render_page()`
API exposes — see [CORE.md](CORE.md)) then displays each PNG with whichever
terminal image tool is available: ueberzug++, chafa, kitty (`kitten icat`/
`kitty icat`), or imgcat, chosen by `platform.best_terminal_renderer()` or
forced via `opts.terminal_tool`. Like `system`, this bypasses backend
resolution entirely — `core/dispatcher.lua` special-cases `opts.mode ==
"terminal"` the same way.

Multiple pages render sequentially (`render_next(idx)`, 500ms apart) each in
their own `split | terminal <tool> ...` window. Unlike `render_page()`'s
caller-owned PNG, the PNG here is a `vim.fn.tempname()` deleted ~2s after
display (`vim.defer_fn`) — a throwaway, not something calling code should
rely on existing past that window.

- **Module:** `lua/pdfport/renderers/terminal.lua`
- **Config:** `opts.terminal_dpi` (default `216`), `opts.terminal_size_ratio` (default `{ width = 0.9, height = 0.8 }`), `opts.terminal_tool`
- **Requires:** `pdftoppm` + one of chafa/ueberzug++/kitty/imgcat

## Page-range picker

`float` and `terminal` both prompt for a page range before rendering
(`util/page_range.prompt`, invoked from `bindings/usrcmds.lua`) since both
are worse fits for an entire long document than `buffer` is. The parsed
range flows into `opts.pages`, forwarded through `extract_opts.pages` on the
backend side and, for `terminal`, directly into the rasterize loop.

## Custom renderer registration

Any `fun(result: PdfPort.Result, opts: PdfPort.RenderOpts): nil` can be
registered under a new mode string via `core/registry.lua`'s
`register_renderer(mode, fn)` and then requested with
`opts.mode = "<your-mode>"` — there's no restriction to the four builtins.

- **Module:** `lua/pdfport/core/registry.lua` (`M.register_renderer`, `M.get_renderer`, `M.renderer_modes`)
