---@module 'pdfport_nvim.renderers.buffer'
---@brief Renders extracted PDF text into a Neovim scratch buffer.
---@description
--- Split behaviour is controlled by opts.split:
---   nil / "current" : replace the current editor window (default)
---   "vsplit"        : open to the right
---   "split"         : open below
---   "tab"           : open in a new tab

local M = {}

local api = vim.api

---@param path string
---@return string
local function buf_name(path)
  return string.format("pdfport://%s", vim.fn.fnamemodify(path, ":t:r"))
end

---@param name string
---@return integer bufnr
local function get_or_create_buf(name)
  for _, nr in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_valid(nr) and api.nvim_buf_get_name(nr) == name then
      return nr
    end
  end
  local nr = api.nvim_create_buf(false, true)
  api.nvim_buf_set_name(nr, name)
  return nr
end

---@param line string
---@return string
local function strip_cr(line)
  return (line:gsub("\r$", ""))
end

---@return integer  orig_win (0 = no switch needed)
local function ensure_editor_win()
  local cur_win = api.nvim_get_current_win()
  local cur_buf = api.nvim_win_get_buf(cur_win)
  local cur_ft  = vim.bo[cur_buf].filetype
  local cur_cfg = api.nvim_win_get_config(cur_win)

  local is_sidebar = cur_ft == "neo-tree" or cur_ft == "NvimTree" or cur_ft == "netrw"
  local is_float   = cur_cfg.relative ~= ""
  if not is_sidebar and not is_float then return 0 end

  local wins = api.nvim_tabpage_list_wins(0)
  for i = #wins, 1, -1 do
    local w = wins[i]
    if w ~= cur_win and api.nvim_win_is_valid(w) then
      local wbuf = api.nvim_win_get_buf(w)
      local wcfg = api.nvim_win_get_config(w)
      local wft  = vim.bo[wbuf].filetype
      if wcfg.relative == "" and wft ~= "neo-tree" and wft ~= "NvimTree" and wft ~= "netrw" then
        api.nvim_set_current_win(w)
        return cur_win
      end
    end
  end
  return 0
end

---@param result PdfPort.Result
---@param opts   PdfPort.OpenOpts
---@return nil
function M.render(result, opts)
  local path  = opts.path or ""
  local name  = buf_name(path)
  local bufnr = get_or_create_buf(name)

  local split = opts.split
  if not split or split == "current" or split == "" then split = "current" end

  local focus = opts.focus ~= false
  local ft    = (result.format == "markdown") and "markdown" or "text"

  local raw_lines = vim.split(result.text or "", "\n", { plain = true })
  local lines     = { [#raw_lines] = "" }
  for i = 1, #raw_lines do lines[i] = strip_cr(raw_lines[i]) end

  vim.bo[bufnr].modifiable = true
  api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  local header = strip_cr(string.format(
    "<!-- pdfport: %s | backend: %s | format: %s -->",
    vim.fn.fnamemodify(path, ":t"), result.backend, result.format
  ))
  api.nvim_buf_set_lines(bufnr, 0, 0, false, { header, "" })

  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].buftype    = "nofile"
  vim.bo[bufnr].bufhidden  = "hide"
  vim.bo[bufnr].filetype   = ft
  vim.bo[bufnr].swapfile   = false

  local orig_win = ensure_editor_win()

  if split == "tab" then
    vim.cmd("tabnew")
    api.nvim_win_set_buf(api.nvim_get_current_win(), bufnr)
  elseif split == "split" then
    vim.cmd("split")
    api.nvim_win_set_buf(api.nvim_get_current_win(), bufnr)
  elseif split == "vsplit" then
    vim.cmd("vsplit")
    api.nvim_win_set_buf(api.nvim_get_current_win(), bufnr)
  else
    api.nvim_win_set_buf(api.nvim_get_current_win(), bufnr)
  end

  if not focus then
    if orig_win ~= 0 and api.nvim_win_is_valid(orig_win) then
      api.nvim_set_current_win(orig_win)
    else
      vim.cmd("wincmd p")
    end
  end
end

return M
