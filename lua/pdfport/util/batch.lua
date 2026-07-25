---@module 'pdfport.util.batch'
---@brief Visual-mode batch-open: resolve every line in the visual selection
---to a PDF path and open each one.
---@description
--- Reuses each file-tree integration's own cursor-based path resolver
--- unchanged: the selection is walked line by line, the window cursor is
--- moved to each line in turn, and the integration's existing
---`current_node_path()`-style function is called exactly as it already is
--- for the single-node keymaps — no new per-adapter "node at line N" API
--- is required.

local M = {}

---@param resolve_path fun(): string|nil  cursor-based path resolver (same fn the integration's normal-mode actions already use)
---@return nil
function M.open_selected(resolve_path)
  local notify = require("pdfport.util.notify").create("[pdfport.batch]")

  local win = vim.api.nvim_get_current_win()
  local ok_cur, cur = pcall(vim.api.nvim_win_get_cursor, win)

  local start_line = vim.fn.line("'<")
  local end_line   = vim.fn.line("'>")
  if start_line == 0 or end_line == 0 then
    notify.warn("no visual selection")
    return
  end
  if start_line > end_line then start_line, end_line = end_line, start_line end

  local paths = {}
  local seen  = {}
  for line = start_line, end_line do
    pcall(vim.api.nvim_win_set_cursor, win, { line, 0 })
    local ok_path, path = pcall(resolve_path)
    if ok_path and path and not seen[path] and path:lower():match("%.pdf$") then
      seen[path] = true
      paths[#paths + 1] = path
    end
  end

  if ok_cur then pcall(vim.api.nvim_win_set_cursor, win, cur) end

  if #paths == 0 then
    notify.warn("no PDF files in selection")
    return
  end

  local pdfport = require("pdfport")
  for _, p in ipairs(paths) do
    pdfport.open({ path = p, mode = "buffer", split = "vsplit", focus = false }, notify.error)
  end
  notify.info(string.format("opened %d PDF(s)", #paths))
end

return M
