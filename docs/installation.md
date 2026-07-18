# Installation

## Requirements

- Neovim >= 0.9
- At least one extraction backend (see [Backends](configuration.md#backends))

pdfport.nvim only does anything once one of its commands or its Lua API is invoked, so it
should always be loaded lazily — via `cmd = {...}` (recommended) rather than `lazy = false`
or `event = "VeryLazy"`.

## lazy.nvim

```lua
{
  "StefanBartl/pdfport.nvim",
  dependencies = { "StefanBartl/lib.nvim" },
  cmd = { "PdfPort", "PdfPortText", "PdfPortFloat", "PdfPortSystem", "PdfPortTerminal", "PdfPortHealth" },
  opts = {
    default_backend = "auto",
    fallback_chain  = { "pdftotext", "pdfplumber", "marker", "docling", "ollama", "claude" },
  },
}
```

## packer.nvim

```lua
use({
  "StefanBartl/pdfport.nvim",
  dependencies = { "StefanBartl/lib.nvim" },
  cmd = { "PdfPort", "PdfPortText", "PdfPortFloat", "PdfPortSystem", "PdfPortTerminal", "PdfPortHealth" },
  config = function()
    require("pdfport_nvim").setup({
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
require("pdfport_nvim").setup({ default_backend = "auto" })
```

vim-plug has no built-in lazy-loading by command; wrap the commands yourself or call
`setup()` eagerly (`extract`/`open` are cheap until a PDF is actually opened).

## mini.deps

```lua
local add = MiniDeps.add
add({ source = "StefanBartl/pdfport.nvim" })
require("pdfport_nvim").setup({ default_backend = "auto" })
```
