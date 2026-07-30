-- luacheck configuration for pdfport.nvim
std = "luajit"
read_globals = { "vim" }

-- The plugin-load guard writes vim.g.loaded_pdfport, and the buffer/window
-- renderers set buffer-local options (`vim.bo[buf].modifiable = false` and
-- friends). Assigning through vim.bo/vim.wo is the documented API, but
-- luacheck reads the whole `vim` table as read-only and flags it, so these
-- are declared writable explicitly.
globals = { "vim.g", "vim.b", "vim.bo", "vim.wo", "vim.opt" }

-- The codebase favours readability over an 80/120 column cap; stylua already
-- enforces a 100-column target where it can break lines safely.
max_line_length = false

-- Backend `extract(path, opts)` and renderer `(result, opts)` signatures are
-- fixed by the dispatcher, so several implementations legitimately ignore an
-- argument. Underscore-prefixed names are skipped by luacheck already; this
-- silences the remainder rather than renaming across a stable interface.
ignore = {
  "212", -- unused argument
}

-- The specs stub vim.* fields and replace registry entries to observe
-- behaviour without invoking real extraction tools.
files["TESTS/"] = {
  ignore = {
    "122", -- setting a read-only field of a global (vim.*)
  },
}
