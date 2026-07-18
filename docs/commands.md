# Commands & Lua API

## Commands

| Command                   | Description                               |
|----------------------------|-------------------------------------------|
| `:PdfPort [path]`         | Open PDF with interactive mode picker     |
| `:PdfPortText [path]`     | Extract to buffer (auto backend)          |
| `:PdfPortFloat [path]`    | Extract to floating window                |
| `:PdfPortSystem [path]`   | Open with system application               |
| `:PdfPortTerminal [path]` | Render as terminal image                   |
| `:PdfPortHealth`          | Run `:checkhealth pdfport_nvim`            |

All commands accept an optional path argument; if omitted they use the word under the cursor (`<cfile>`) or the current buffer.

See [docs/BINDINGS.md](BINDINGS.md) for the full keymap/command/autocmd cheatsheet.

## Lua API

```lua
local p = require("pdfport_nvim")

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
```

## Health check

```
:checkhealth pdfport_nvim
```

Reports status for: core modules, all backends (available/unavailable), renderers, integrations, and the live registry.
