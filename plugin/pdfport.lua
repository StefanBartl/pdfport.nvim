-- Guard: load only once, only inside Neovim
if vim.g.loaded_pdfport then return end
vim.g.loaded_pdfport = true

-- Commands are registered lazily via M.setup() which is triggered on first use.
-- If the user wants eager command registration without explicit setup(),
-- they can call require("pdfport").setup() in their config.
