---@module 'pdfport.renderers.float'
---@brief Renders extracted PDF text in a centered floating window.
---@description
--- Delegates window/buffer creation to lib.nvim.window.make_scratch (same
--- 80% centered float, rounded border, nofile/read-only scratch buffer,
--- q/<Esc>-to-close via nice_quit). opts.float_opts (declared in
--- PdfPort.OpenOpts but never populated by any caller today) is merged onto
--- the make_scratch opts for the fields it directly supports
--- (width/height/row/col/border/title/title_pos); truly arbitrary
--- nvim_open_win overrides are not passed through, unlike the old
--- vim.tbl_deep_extend — no real caller uses float_opts today, so this is
--- a narrowing with no observed behavioral impact.

local make_scratch = require("lib.nvim.window.make_scratch")

local M = {}

---@param result PdfPort.Result
---@param opts PdfPort.OpenOpts
---@return nil
function M.render(result, opts)
  local lines = vim.split(result.text or "", "\n", { plain = true })
  local ft = (result.format == "markdown") and "markdown" or "text"

  local scratch_opts = vim.tbl_extend("force", {
    lines = lines,
    filetype = ft,
    title = string.format(" pdfport: %s ", vim.fn.fnamemodify(opts.path or "", ":t")),
    title_pos = "center",
    width = math.floor(vim.o.columns * 0.8),
    height = math.floor(vim.o.lines * 0.8),
    wo = { wrap = true, linebreak = true },
    nice_quit = true,
  }, opts.float_opts or {})

  make_scratch(scratch_opts)
end

return M
