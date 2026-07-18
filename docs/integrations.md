# Integrations

## File-tree integrations

Every integration shares the same four actions (`open`, `open_text`, `open_system`,
`open_terminal`), defaulting to `<leader>po/pt/ps/pi` — see
[docs/BINDINGS.md](BINDINGS.md) for the full table. Pass `false` for any action to
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
