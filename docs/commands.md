# Commands & Lua API

## Commands

One command, `:PdfPort [subcommand] [path]` (built via
[`lib.nvim.usercmd.composer`](https://github.com/StefanBartl/lib.nvim), with
`<Tab>` completion — `.pdf` files are prioritized, `<cfile>` is suggested when
completing with no input yet).

| Command                   | Description                               |
|----------------------------|-------------------------------------------|
| `:PdfPort [path]`         | Open PDF with interactive mode picker     |
| `:PdfPort text [path]`     | Extract to buffer (auto backend)          |
| `:PdfPort float [path] [pages=…]` | Extract to floating window (prompts for a page range unless `pages=` is given) |
| `:PdfPort system [path]`   | Open with system application               |
| `:PdfPort terminal [path] [pages=…]` | Render as terminal image (prompts for a page range unless `pages=` is given) |
| `:PdfPort backends`        | List all registered backends with live availability |
| `:PdfPort create [path]`   | Create a PDF from an image/markdown/text/html/office file (path arg, `<cfile>`, or current buffer) |
| `:PdfPort merge <output.pdf> <a.pdf> <b.pdf> ...` | Merge two or more PDFs into one |
| `:PdfPort producers`       | List all registered creation producers with live availability |
| `:PdfPort health`          | Run `:checkhealth pdfport`            |

All subcommands accept an optional path argument; if omitted they use the word under the cursor (`<cfile>`) or the current buffer.

`float` and `terminal` prompt for a page range first (`vim.ui.input`, e.g. `1-3,5` — blank
means the default: all pages for `float`, page 1 for `terminal`; `<Esc>` cancels without
opening anything).

**Skipping the prompt:** pass `pages=` and the prompt is not shown at all:

```vim
:PdfPort float report.pdf pages=1-3,5
:PdfPort terminal report.pdf pages=2
```

The prompt is fine when a human is driving, but it makes these two
subcommands unusable from a script, a mapping, or another plugin — there is
no way to answer it non-interactively. A `pages=` value that parses to no
page number at all (`pages=`, `pages=abc`) is reported and nothing opens,
rather than silently falling back to the prompt or to the whole document:
the caller asked for a specific range, and quietly doing something else is
what goes unnoticed in a script.

See [docs/BINDINGS.md](BINDINGS.md) for the full keymap/command/autocmd cheatsheet.

## Lua API

```lua
local p = require("pdfport")

-- Open a PDF
p.open({ path = "/some/file.pdf", mode = "buffer", split = "vsplit" })

-- Extract text without rendering
p.extract({
  path = "/some/file.pdf",
  max_pages = 5,
  __callback = function(result)
    if result.status == "ok" then
      print(result.text)
    end
  end,
})

-- Same "open PDF as…" mode picker :PdfPort uses, for OTHER plugins to embed
-- instead of hand-rolling their own two/three-item chooser. "System
-- application" is always one of the choices — see
-- lua/pdfport/util/picker.lua's module docs.
p.pick_open("/some/file.pdf", {
  title = "Open PDF as…",
  -- Route the system entry through your own opener (e.g. for WSL path
  -- translation) instead of pdfport's `system` renderer:
  system_open = function(path) end,
  -- Put "system application" first, for callers whose pre-pdfport
  -- behaviour was "always the system viewer":
  system_first = true,
})

-- Register a custom backend
p.register_backend({
  id        = "my_tool",
  name      = "My custom extractor",
  available = function() return vim.fn.executable("my_tool") == 1 end,
  extract   = function(path, opts)
    -- must call opts.__callback(result) asynchronously
  end,
})

-- Create a PDF from images (the reverse of open/extract)
p.create({
  inputs = { "/some/a.png", "/some/b.png" },  -- order = page order
  output = "/some/out.pdf",                    -- optional; default: next to the first input
  from   = "image",                            -- optional; guessed from the extension otherwise
  __callback = function(result)
    if result.status == "ok" then
      print(result.path)
    end
  end,
})

p.can_create("image") -- true if a producer (img2pdf/magick) is available

-- Create a PDF from Markdown text directly (opts.text/opts.bufnr require opts.from + opts.output)
p.create({
  text   = "# Title\n\nSome text.",
  from   = "markdown",
  output = "/some/out.pdf",
})

-- Register a custom producer
p.register_producer({
  id        = "my_producer",
  name      = "My custom producer",
  accepts   = { "image" },
  available = function() return vim.fn.executable("my_tool") == 1 end,
  create    = function(req)
    -- must call req.__callback(result) asynchronously
  end,
})

-- Merge two or more existing PDFs into one (qpdf -> pdftk -> Ghostscript)
p.merge({
  inputs = { "/some/a.pdf", "/some/b.pdf" },  -- at least 2, in output order
  output = "/some/merged.pdf",                -- required, no default
  __callback = function(result)
    if result.status == "ok" then
      print(result.path)
    end
  end,
})

-- Rasterize a single page to a real, caller-owned PNG (same pdftoppm
-- primitive the `terminal` renderer uses internally, without the
-- display-and-delete): lets other plugins (e.g. images.nvim) show a PDF
-- page as an image without depending on pdfport's terminal renderer.
p.render_page("/some/file.pdf", 1, { dpi = 216 }, function(png_path, err)
  if err then return end
  -- png_path is real and caller-owned; delete it yourself when done
end)
```

See [docs/ROADMAP/PDF_CREATE.md](ROADMAP/PDF_CREATE.md) for the full design and roadmap
(P0–P3 shipped: image/Markdown/text/HTML/Office producers + `merge()`; P2 caller wiring
into `filetree.nvim`/`images.nvim`/`markdown.nvim` all shipped too).

## Health check

```
:checkhealth pdfport
```

Reports status for: core modules, all backends (available/unavailable), creation producers, renderers, integrations, and the live registry.
