# Installation

See [requirements.md](requirements.md) for the full required/optional list.

pdfport.nvim only does anything once one of its commands or its Lua API is invoked, so it
should always be loaded lazily — via `cmd = {...}` (recommended) rather than `lazy = false`
or `event = "VeryLazy"`.

The examples below list `lib.nvim` alone, which is all pdfport needs. Add
`"StefanBartl/ai.nvim"` to `dependencies` as well if you want the `claude`,
`gemini` or `ollama` extraction backends — they route their HTTP requests
through it and report themselves unavailable without it.

## lazy.nvim

```lua
{
  "StefanBartl/pdfport.nvim",
  dependencies = { "StefanBartl/lib.nvim" },
  cmd = { "PdfPort" },
  opts = {
    default_backend = "auto",
    fallback_chain  = { "pdftotext", "pdfplumber", "marker", "docling", "ollama", "tesseract", "claude", "gemini" },
  },
}
```

## packer.nvim

```lua
use({
  "StefanBartl/pdfport.nvim",
  dependencies = { "StefanBartl/lib.nvim" },
  cmd = { "PdfPort" },
  config = function()
    require("pdfport").setup({
      default_backend = "auto",
    })
  end,
})
```

## vim-plug

```vim
Plug 'StefanBartl/pdfport.nvim'
```

```lua
" after plug#end()
require("pdfport").setup({ default_backend = "auto" })
```

vim-plug has no built-in lazy-loading by command; wrap the commands yourself or call
`setup()` eagerly (`extract`/`open` are cheap until a PDF is actually opened).

## mini.deps

```lua
local add = MiniDeps.add
add({ source = "StefanBartl/pdfport.nvim" })
require("pdfport").setup({ default_backend = "auto" })
```
