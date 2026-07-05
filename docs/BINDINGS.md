# Bindings Cheatsheet

All keymaps, user commands, and autocmds registered by pdfport.nvim.

## Table of contents

- [Keymaps](#keymaps)
- [User commands](#user-commands)
- [Autocmds](#autocmds)
- [Which-key](#which-key)

---

## Keymaps

Registered per file-tree integration once its `setup()` (or `.keymaps()` for neo-tree) is
called. Every action can be overridden or disabled (`false`) via the integration's `opts`
table — see [README.md](../README.md#file-tree-integrations) for setup snippets.

| Default      | Action        | Description                       |
|--------------|---------------|------------------------------------|
| `<leader>po` | `open`          | Mode picker (interactive)         |
| `<leader>pt` | `open_text`     | Extract to buffer (vsplit)        |
| `<leader>ps` | `open_system`   | Open with system application      |
| `<leader>pi` | `open_terminal` | Terminal image preview            |

These are buffer-local and only active inside the corresponding file-tree buffer
(neo-tree, nvim-tree, netrw, oil.nvim). Defaults live in
[lua/pdfport_nvim/bindings/keymaps.lua](../lua/pdfport_nvim/bindings/keymaps.lua).

Disabling an action:

```lua
require("pdfport_nvim.integrations.oil").setup({ open_system = false })
```

## User commands

Defined in [lua/pdfport_nvim/bindings/usrcmds.lua](../lua/pdfport_nvim/bindings/usrcmds.lua).
All accept an optional `[path]` argument; if omitted they fall back to `<cfile>` and then
the current buffer name.

| Command                   | Description                               |
|----------------------------|-------------------------------------------|
| `:PdfPort [path]`         | Open PDF with interactive mode picker     |
| `:PdfPortText [path]`     | Extract to buffer (auto backend)          |
| `:PdfPortFloat [path]`    | Extract to floating window                |
| `:PdfPortSystem [path]`   | Open with system application               |
| `:PdfPortTerminal [path]` | Render as terminal image                   |
| `:PdfPortHealth`          | Run `:checkhealth pdfport_nvim`            |

## Autocmds

Registered via the shared helper in
[lua/pdfport_nvim/bindings/autocmds.lua](../lua/pdfport_nvim/bindings/autocmds.lua). Each
integration owns one idempotent augroup — calling `setup()` again clears and re-creates it
instead of accumulating duplicate keymaps.

| Augroup               | FileType pattern | Registered by                                    |
|------------------------|------------------|---------------------------------------------------|
| `pdfport_netrw`       | `netrw`          | `integrations/netrw.lua`                          |
| `pdfport_oil`         | `oil`            | `integrations/oil.lua`                            |
| `pdfport_nvim_tree`   | `NvimTree`       | `integrations/nvim_tree.lua`                       |

neo-tree does not use autocmds — its commands/keymaps are registered declaratively via
`opts.commands` / `opts.filesystem.window.mappings`.

## Which-key

If [which-key.nvim](https://github.com/folke/which-key.nvim) is installed, every resolved
keymap is registered with a description under the `<leader>p` group automatically
(`lua/pdfport_nvim/bindings/keymaps.lua`). No configuration needed; disabled if which-key
is not present.
