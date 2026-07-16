```
      _  __             _                   _
 _ __ | |/ _|_ __   ___ | |_ __ _ __      __(_)_ __ ___
| '_ \| | |_| '_ \ / _ \| __/ _` |\ \ /\ / /| | '_ ` _ \
| |_) | |  _| |_) | (_) | || (_| | \ V  V / | | | | | | |
| .__/|_|_| | .__/ \___/ \__\__,_|  \_/\_/  |_|_| |_| |_|
|_|         |_|
```

[![Neovim](https://img.shields.io/badge/Neovim-%3E%3D%200.9-57A143?logo=neovim&logoColor=white)](https://neovim.io)
[![Lua](https://img.shields.io/badge/Lua-blue?logo=lua&logoColor=white)](https://www.lua.org)

# pdfport.nvim

A Neovim plugin for extracting and displaying PDF content using a pluggable backend/renderer architecture.

> Pairs well with [StefanBartl/lib.nvim](https://github.com/StefanBartl/lib.nvim) — pdfport.nvim
> automatically uses its `hover_select` UI for a nicer mode picker when it's installed, falling
> back to `vim.ui.select` otherwise.

## Features

- **Multiple extraction backends** — pdftotext, pdfplumber, marker-pdf, docling, Claude API, Ollama
- **Multiple renderers** — scratch buffer (split/vsplit/tab), floating window, system application, terminal image
- **File-tree integrations** — neo-tree, nvim-tree, netrw, oil.nvim; unified `open_current()` auto-detects the active tree
- **Fuzzy-finder integrations** — Telescope previewer, fzf-lua preview function
- **Lazy-load friendly** — guard in `plugin/`, commands registered on first `setup()` call
- **which-key support** — every keymap gets a description under the `<leader>p` group when [which-key.nvim](https://github.com/folke/which-key.nvim) is installed
- **Health check** — `:checkhealth pdfport_nvim`

See [docs/BINDINGS.md](docs/BINDINGS.md) for the full keymap/command/autocmd cheatsheet and
[docs/ROADMAP.md](docs/ROADMAP.md) for planned work.

## Requirements

- Neovim >= 0.9
- At least one extraction backend (see below)

## Installation

pdfport.nvim only does anything once one of its commands or its Lua API is invoked, so it
should always be loaded lazily — via `cmd = {...}` (recommended) rather than `lazy = false`
or `event = "VeryLazy"`.

### lazy.nvim

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

### packer.nvim

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

### vim-plug

```vim
Plug 'StefanBartl/pdfport.nvim'
```

```lua
" after plug#end()
require("pdfport_nvim").setup({ default_backend = "auto" })
```

vim-plug has no built-in lazy-loading by command; wrap the commands yourself or call
`setup()` eagerly (`extract`/`open` are cheap until a PDF is actually opened).

### mini.deps

```lua
local add = MiniDeps.add
add({ source = "StefanBartl/pdfport.nvim" })
require("pdfport_nvim").setup({ default_backend = "auto" })
```

## Configuration

```lua
require("pdfport_nvim").setup({
  default_backend = "auto",          -- "auto" | backend id
  fallback_chain  = {                -- order tried when default_backend = "auto"
    "pdftotext", "pdfplumber", "marker", "docling", "ollama", "claude"
  },
  extract_opts = {
    max_pages  = nil,                -- nil = all pages
    timeout_ms = 30000,
  },
  render_opts = {
    mode                = "buffer",  -- "buffer"|"float"|"terminal"|"system"
    split               = "vsplit",  -- "vsplit"|"split"|"tab"|"current"
    focus               = true,
    terminal_dpi        = 216,       -- pdftoppm rasterization DPI (terminal mode)
    terminal_size_ratio = {          -- fraction of the editor size used by the image
      width  = 0.9,
      height = 0.8,
    },
  },
  claude_api_key = nil,              -- or set ANTHROPIC_API_KEY env var
  ollama_host    = "http://localhost:11434",
  ollama_model   = "llava",
  debug          = false,
})
```

See [lua/pdfport_nvim/config/DEFAULTS.lua](lua/pdfport_nvim/config/DEFAULTS.lua) for the
authoritative default values and [lua/pdfport_nvim/@types/init.lua](lua/pdfport_nvim/@types/init.lua)
for full field types (LSP completion works out of the box via `---@type PdfPort.Config`).

## Backends

| ID          | Requires                                    | Output   |
|-------------|---------------------------------------------|----------|
| pdftotext   | `pdftotext` (poppler-utils)                 | plain    |
| pdfplumber  | Python + `pip install pdfplumber`           | plain    |
| marker      | `pip install marker-pdf`                    | Markdown |
| docling     | `pip install docling`                       | Markdown |
| claude      | `curl`, `base64`, `ANTHROPIC_API_KEY`       | Markdown |
| ollama      | `ollama`, `pdftoppm`, `curl`                | Markdown |

## Commands

| Command                   | Description                               |
|---------------------------|-------------------------------------------|
| `:PdfPort [path]`         | Open PDF with interactive mode picker     |
| `:PdfPortText [path]`     | Extract to buffer (auto backend)          |
| `:PdfPortFloat [path]`    | Extract to floating window                |
| `:PdfPortSystem [path]`   | Open with system application              |
| `:PdfPortTerminal [path]` | Render as terminal image                  |
| `:PdfPortHealth`          | Run `:checkhealth pdfport_nvim`           |

All commands accept an optional path argument; if omitted they use the word under the cursor (`<cfile>`) or the current buffer.

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

## File-tree integrations

Every integration shares the same four actions (`open`, `open_text`, `open_system`,
`open_terminal`), defaulting to `<leader>po/pt/ps/pi` — see
[docs/BINDINGS.md](docs/BINDINGS.md) for the full table. Pass `false` for any action to
disable that keymap; if [which-key.nvim](https://github.com/folke/which-key.nvim) is
installed, active keymaps are auto-registered with descriptions under `<leader>p`.

### neo-tree

```lua
local pdfport_neo = require("pdfport_nvim.integrations.neotree")

require("neo-tree").setup({
  commands = vim.tbl_extend("force", {}, pdfport_neo.commands()),
  filesystem = {
    window = {
      -- pass { open_system = false } etc. to disable an action
      mappings = vim.tbl_extend("force", {}, pdfport_neo.keymaps()),
    },
  },
})
```

### nvim-tree

```lua
require("pdfport_nvim.integrations.nvim_tree").setup({
  open          = "<leader>po",
  open_text     = "<leader>pt",
  open_system   = "<leader>ps",
  open_terminal = "<leader>pi",
})
```

### netrw

```lua
require("pdfport_nvim.integrations.netrw").setup()
-- Registers <leader>p* keymaps in every netrw FileType buffer
```

### oil.nvim

```lua
require("pdfport_nvim.integrations.oil").setup()
```

### Unified (auto-detect active tree)

```lua
local integrations = require("pdfport_nvim.integrations")
-- Detects neo-tree / nvim-tree / netrw / oil by buffer filetype
integrations.open_current({ split = "vsplit" })
```

## Fuzzy-finder integrations

### Telescope

```lua
local pdfport_tel = require("pdfport_nvim.integrations.telescope")

-- Single picker
require("telescope.builtin").find_files({
  previewer = pdfport_tel.previewer({ max_pages = 3 }),
})

-- Global hook (all pickers)
require("telescope").setup({
  defaults = {
    preview = { filetype_hook = pdfport_tel.filetype_hook },
  },
})
```

### fzf-lua

```lua
local pdfport_fzf = require("pdfport_nvim.integrations.fzf")
require("fzf-lua").files({
  preview = pdfport_fzf.preview_fn({ max_pages = 3 }),
})
```

## Health check

```
:checkhealth pdfport_nvim
```

Reports status for: core modules, all backends (available/unavailable), renderers, integrations, and the live registry.
