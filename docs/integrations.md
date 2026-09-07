# Integrations

## File-tree integrations

### filetree.nvim — no adapter needed

[filetree.nvim](https://github.com/StefanBartl/filetree.nvim) is not in the
list below and does not need to be: it calls
[`pdfport.pick_open()`](../lua/pdfport/init.lua) itself. Hitting a PDF in it
asks exactly the question `:PdfPort` asks, with the same choices and the same
labels, and it keeps working when pdfport.nvim is not installed at all.

That is the intended shape for a plugin from the same collection — an adapter
here exists for trees this repository cannot change. If you are writing one,
`pick_open()` is the public entry point; see
[WORKFLOW.md](WORKFLOW.md#pdfportpick_open-instead-of-hand-rolling-a-mode-prompt).

### Third-party trees: the shared five actions

The four adapters below exist for trees this repository cannot change, and each
of them exposes the same five actions: `open`, `open_text`, `open_system`,
`open_terminal` (normal mode, defaulting to `<leader>po/pt/ps/pi`) and `open_batch`
(visual mode, defaulting to `<leader>pb`, batch-opens every PDF in the selection) — see
[docs/BINDINGS.md](BINDINGS.md) for the full table. Pass `false` for any action to
disable that keymap; if [which-key.nvim](https://github.com/folke/which-key.nvim) is
installed, active keymaps are auto-registered with descriptions under `<leader>p`.

### neo-tree

```lua
local pdfport_neo = require("pdfport.integrations.neotree")

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
require("pdfport.integrations.nvim_tree").setup({
  open          = "<leader>po",
  open_text     = "<leader>pt",
  open_system   = "<leader>ps",
  open_terminal = "<leader>pi",
})
```

### netrw

```lua
require("pdfport.integrations.netrw").setup()
-- Registers <leader>p* keymaps in every netrw FileType buffer
```

### oil.nvim

```lua
require("pdfport.integrations.oil").setup()
```

### Unified (auto-detect active tree)

```lua
local integrations = require("pdfport.integrations")
-- Detects neo-tree / nvim-tree / netrw / oil by buffer filetype
integrations.open_current({ split = "vsplit" })
```

## Fuzzy-finder integrations

### Telescope

```lua
local pdfport_tel = require("pdfport.integrations.telescope")

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
local pdfport_fzf = require("pdfport.integrations.fzf")
require("fzf-lua").files({
  preview = pdfport_fzf.preview_fn({ max_pages = 3 }),
})
```
