-- Guard: load only once, only inside Neovim
if vim.g.loaded_pdfport_nvim then return end
vim.g.loaded_pdfport_nvim = true

-- Commands are registered lazily via M.setup() which is triggered on first use.
-- If the user wants eager command registration without explicit setup(),
-- they can call require("pdfport_nvim").setup() in their config.
