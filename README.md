```
      _  __             _                   _
 _ __ | |/ _|_ __   ___ | |_ __ _ __      __(_)_ __ ___
| '_ \| | |_| '_ \ / _ \| __/ _` |\ \ /\ / /| | '_ ` _ \
| |_) | |  _| |_) | (_) | || (_| | \ V  V / | | | | | | |
| .__/|_|_| | .__/ \___/ \__\__,_|  \_/\_/  |_|_| |_| |_|
|_|         |_|
```

[![CI](https://github.com/StefanBartl/pdfport.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/StefanBartl/pdfport.nvim/actions/workflows/ci.yml)
[![Neovim](https://img.shields.io/badge/Neovim-%3E%3D%200.9-57A143?logo=neovim&logoColor=white)](https://neovim.io)
[![Lua](https://img.shields.io/badge/Lua-blue?logo=lua&logoColor=white)](https://www.lua.org)

# pdfport.nvim

A Neovim plugin for extracting and displaying PDF content using a pluggable backend/renderer architecture.

> Requires [StefanBartl/lib.nvim](https://github.com/StefanBartl/lib.nvim) — the `:PdfPort`
> command itself is built on `lib.nvim.usercmd.composer`. It also automatically uses
> lib.nvim's UI kit for a nicer mode picker when available, falling back to `vim.ui.select`
> otherwise.

> Backends like `marker`, `docling`, `ollama`, and `claude` extract PDFs to Markdown —
> [`mdview.nvim`](https://github.com/StefanBartl/mdview.nvim), a sister plugin from the
> same author, is a good fit for previewing that output.

## Table of contents

- [Features](#features)
- [Quickstart](#quickstart)
- [File-tree integrations](#file-tree-integrations)
- [Documentation](#documentation)

## Features

- **Multiple extraction backends** — pdftotext, pdfplumber, marker-pdf, docling, Claude API, Ollama, tesseract (OCR fallback) — loaded lazily, one `require` only when actually resolved
- **Multiple renderers** — scratch buffer (split/vsplit/tab), floating window, system application, terminal image
- **Page-range picker** — `float`/`terminal` modes prompt for a page range (`1-3,5`)
- **Cross-session cache** — successful extractions persist across restarts, invalidated by the PDF's mtime
- **File-tree integrations** — neo-tree, nvim-tree, netrw, oil.nvim; unified `open_current()` auto-detects the active tree; visual-mode batch-open (`<leader>pb`) for multiple selected PDFs
- **Fuzzy-finder integrations** — Telescope previewer, fzf-lua preview function
- **Optional `BufReadCmd`** — `:e file.pdf` can auto-invoke the mode picker (`auto_open_on_read`, opt-in)
- **Lazy-load friendly** — guard in `plugin/`, commands registered on first `setup()` call
- **which-key support** — every keymap gets a description under the `<leader>p` group when [which-key.nvim](https://github.com/folke/which-key.nvim) is installed
- **Health check** — `:checkhealth pdfport`
- **Declared, installable external tools** — `docs/install.json` lists every optional CLI tool (poppler, tesseract, ollama, chafa, …) with why it matters; `:Lib deps show pdfport.nvim` reports what's missing, `:Lib deps install pdfport.nvim` offers to install it (via [lib.nvim.deps](https://github.com/StefanBartl/lib.nvim/blob/main/lua/lib/nvim/deps/README.md)). A popup shows this automatically the first time `setup()` runs after installing pdfport.nvim — disable it **right in this plugin's own spec**: `require("pdfport").setup({ deps_popup = false })`. `vim.g.lib_nvim_deps_disable_first_run = true` (every plugin) / `vim.g.lib_nvim_deps_disabled_plugins = { "pdfport.nvim" }` also still work, for turning it off without touching any plugin's config.

## Quickstart

Requires Neovim >= 0.9, [lib.nvim](https://github.com/StefanBartl/lib.nvim), and at least one extraction backend (see
[Backends](docs/configuration.md#backends)).

```lua
-- lazy.nvim
{
  "StefanBartl/pdfport.nvim",
  dependencies = { "StefanBartl/lib.nvim" },
  cmd = { "PdfPort" },
  opts = {
    default_backend = "auto",
    fallback_chain  = { "pdftotext", "pdfplumber", "marker", "docling", "ollama", "tesseract", "claude" },
  },
}
```

```vim
:PdfPort             " open PDF with interactive mode picker
:PdfPort text        " extract to buffer
:PdfPort backends    " list registered backends with live availability
:PdfPort health      " run :checkhealth pdfport
:Lib deps show pdfport.nvim      " which optional tools are missing, and why they matter
:Lib deps install pdfport.nvim   " compose + confirm an install command for what's missing
```

## File-tree integrations

Adds `<leader>po/pt/ps/pi` (normal mode) and `<leader>pb` (visual mode, batch-open) keymaps
to neo-tree, nvim-tree, netrw, and oil.nvim — see [docs/integrations.md](docs/integrations.md)
for setup snippets.

## Documentation

- [Installation](docs/installation.md) — requirements and setup for lazy.nvim, packer.nvim, vim-plug, and mini.deps.
- [Configuration](docs/configuration.md) — all `setup()` options and the extraction backend table.
- [Commands](docs/commands.md) — user commands, the Lua API, and the health check.
- [Integrations](docs/integrations.md) — file-tree integrations (neo-tree, nvim-tree, netrw, oil.nvim) and fuzzy-finder integrations (Telescope, fzf-lua).
- [Bindings cheatsheet](docs/BINDINGS.md) — full keymap/command/autocmd reference.
- [Roadmap](docs/ROADMAP.md) — planned work and audit notes.
