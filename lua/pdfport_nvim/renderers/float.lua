---@module 'pdfport_nvim.renderers.float'
---@brief Renders extracted PDF text in a centered floating window.

local M = {}

local api = vim.api

---@param result PdfPort.Result
---@param opts PdfPort.OpenOpts
---@return nil
function M.render(result, opts)
  local lines  = vim.split(result.text or "", "\n", { plain = true })
  local ft     = (result.format == "markdown") and "markdown" or "text"

  local width  = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines   * 0.8)
  local row    = math.floor((vim.o.lines   - height) / 2)
  local col    = math.floor((vim.o.columns - width)  / 2)

  local bufnr = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].filetype   = ft
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].buftype    = "nofile"

  local float_cfg = vim.tbl_deep_extend("force", {
    relative  = "editor",
    width     = width,
    height    = height,
    row       = row,
    col       = col,
    style     = "minimal",
    border    = "rounded",
    title     = string.format(" pdfport: %s ", vim.fn.fnamemodify(opts.path or "", ":t")),
    title_pos = "center",
  }, opts.float_opts or {})

  local win = api.nvim_open_win(bufnr, true, float_cfg)
  vim.wo[win].wrap      = true
  vim.wo[win].linebreak = true

  for _, key in ipairs({ "q", "<Esc>" }) do
    api.nvim_buf_set_keymap(bufnr, "n", key, "", {
      noremap  = true,
      silent   = true,
      callback = function()
        if api.nvim_win_is_valid(win) then
          api.nvim_win_close(win, true)
        end
      end,
    })
  end
end

return M
