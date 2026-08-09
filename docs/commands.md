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
| `:PdfPort float [path]`    | Extract to floating window (prompts for a page range) |
| `:PdfPort system [path]`   | Open with system application               |
| `:PdfPort terminal [path]` | Render as terminal image (prompts for a page range) |
| `:PdfPort backends`        | List all registered backends with live availability |
| `:PdfPort create [path]`   | Create a PDF from an image (path arg, `<cfile>`, or current buffer) |
| `:PdfPort producers`       | List all registered creation producers with live availability |
| `:PdfPort health`          | Run `:checkhealth pdfport`            |

All subcommands accept an optional path argument; if omitted they use the word under the cursor (`<cfile>`) or the current buffer.

`float` and `terminal` prompt for a page range first (`vim.ui.input`, e.g. `1-3,5` — blank
means the default: all pages for `float`, page 1 for `terminal`; `<Esc>` cancels without
opening anything).

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
```

See [docs/ROADMAP/PDF_CREATE.md](ROADMAP/PDF_CREATE.md) for the full design and roadmap
(P0, shipped: image → PDF via `img2pdf`/`magick`; P1+: Markdown/HTML/Office producers).

## Health check

```
:checkhealth pdfport
```

Reports status for: core modules, all backends (available/unavailable), creation producers, renderers, integrations, and the live registry.
