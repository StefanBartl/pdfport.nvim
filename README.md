# pdfport.nvim

A Neovim plugin for extracting and displaying PDF content using a pluggable backend/renderer architecture.

## Features

- **Multiple extraction backends** — pdftotext, pdfplumber, marker-pdf, docling, Claude API, Ollama
- **Multiple renderers** — scratch buffer (split/vsplit/tab), floating window, system application, terminal image
- **File-tree integrations** — neo-tree, nvim-tree, netrw, oil.nvim; unified `open_current()` auto-detects the active tree
- **Fuzzy-finder integrations** — Telescope previewer, fzf-lua preview function
- **Lazy-load friendly** — guard in `plugin/`, commands registered on first `setup()` call
- **Health check** — `:checkhealth pdfport_nvim`

## Requirements

- Neovim >= 0.9
- At least one extraction backend (see below)

## Installation

### lazy.nvim

```lua
{
  "StefanBartl/pdfport.nvim",
  cmd = { "PdfPort", "PdfPortText", "PdfPortFloat", "PdfPortSystem", "PdfPortTerminal", "PdfPortHealth" },
  opts = {
    default_backend = "auto",
    fallback_chain  = { "pdftotext", "pdfplumber", "marker", "docling", "ollama", "claude" },
  },
}
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
    mode  = "buffer",                -- "buffer"|"float"|"terminal"|"system"
    split = "vsplit",                -- "vsplit"|"split"|"tab"|"current"
    focus = true,
  },
  claude_api_key = nil,              -- or set ANTHROPIC_API_KEY env var
  ollama_host    = "http://localhost:11434",
  ollama_model   = "llava",
  debug          = false,
})
```

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

### neo-tree

```lua
local pdfport_neo = require("pdfport_nvim.integrations.neotree")

require("neo-tree").setup({
  commands = vim.tbl_extend("force", {}, pdfport_neo.commands()),
  filesystem = {
    window = {
      mappings = vim.tbl_extend("force", {}, pdfport_neo.keymaps()),
    },
  },
})
```

Default keymaps (inside neo-tree buffer):

| Key          | Action                       |
|--------------|------------------------------|
| `<leader>po` | Mode picker                  |
| `<leader>pt` | Extract to buffer (vsplit)   |
| `<leader>ps` | Open with system application |
| `<leader>pi` | Terminal image preview       |

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
