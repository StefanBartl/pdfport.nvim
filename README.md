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

> Requires [StefanBartl/lib.nvim](https://github.com/StefanBartl/lib.nvim) — the `:PdfPort`
> command itself is built on `lib.nvim.usercmd.composer`. It also automatically uses
> lib.nvim's UI kit for a nicer mode picker when available, falling back to `vim.ui.select`
> otherwise.

## Features

- **Multiple extraction backends** — pdftotext, pdfplumber, marker-pdf, docling, Claude API, Ollama
- **Multiple renderers** — scratch buffer (split/vsplit/tab), floating window, system application, terminal image
- **File-tree integrations** — neo-tree, nvim-tree, netrw, oil.nvim; unified `open_current()` auto-detects the active tree
- **Fuzzy-finder integrations** — Telescope previewer, fzf-lua preview function
- **Lazy-load friendly** — guard in `plugin/`, commands registered on first `setup()` call
- **which-key support** — every keymap gets a description under the `<leader>p` group when [which-key.nvim](https://github.com/folke/which-key.nvim) is installed
- **Health check** — `:checkhealth pdfport_nvim`

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
    fallback_chain  = { "pdftotext", "pdfplumber", "marker", "docling", "ollama", "claude" },
  },
}
```

```vim
:PdfPort             " open PDF with interactive mode picker
:PdfPort text        " extract to buffer
:PdfPort health      " run :checkhealth pdfport_nvim
```

## File-tree integrations

Adds `<leader>po/pt/ps/pi` keymaps to neo-tree, nvim-tree, netrw, and oil.nvim — see
[docs/integrations.md](docs/integrations.md) for setup snippets.

## Documentation

- [Installation](docs/installation.md) — requirements and setup for lazy.nvim, packer.nvim, vim-plug, and mini.deps.
- [Configuration](docs/configuration.md) — all `setup()` options and the extraction backend table.
- [Commands](docs/commands.md) — user commands, the Lua API, and the health check.
- [Integrations](docs/integrations.md) — file-tree integrations (neo-tree, nvim-tree, netrw, oil.nvim) and fuzzy-finder integrations (Telescope, fzf-lua).
- [Bindings cheatsheet](docs/BINDINGS.md) — full keymap/command/autocmd reference.
- [Roadmap](docs/ROADMAP.md) — planned work and audit notes.
