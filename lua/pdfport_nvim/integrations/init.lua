---@module 'pdfport_nvim.integrations'
---@brief Unified file-tree integration for pdfport.nvim.
---@description
--- Auto-detects the active file-tree by buffer filetype and dispatches accordingly.
--- Each individual integration can also be used directly.
---
--- Supported trees:
---   neo-tree  → pdfport_nvim.integrations.neotree
---   nvim-tree → pdfport_nvim.integrations.nvim_tree
---   netrw     → pdfport_nvim.integrations.netrw
---   oil.nvim  → pdfport_nvim.integrations.oil

local M = {}

---@return string|nil  pdf_path, or nil if cursor is not on a PDF
function M.current_pdf_path()
  local ok_api, api = pcall(vim.api.nvim_get_current_buf)
  local bufnr = ok_api and api or vim.api.nvim_get_current_buf()
  local ft    = vim.bo[bufnr].filetype

  -- neo-tree
  if ft == "neo-tree" then
    local ok_nt, manager = pcall(require, "neo-tree.sources.manager")
    if ok_nt then
      local state = manager.get_state_for_window()
      if state and state.tree then
        local node = state.tree:get_node()
        if node then return node:get_id() end
      end
    end
    return nil
  end

  -- nvim-tree
  if ft == "NvimTree" then
    local ok_nvt, tree_api = pcall(require, "nvim-tree.api")
    if ok_nvt then
      local node = tree_api.tree.get_node_under_cursor()
      if node then return node.absolute_path end
    end
    return nil
  end

  -- netrw
  if ft == "netrw" then
    local dir  = vim.b.netrw_curdir
    local file = vim.fn.expand("<cfile>")
    if dir and file and file ~= "" then
      local sep = (dir:sub(-1) == "/" or dir:sub(-1) == "\\") and "" or "/"
      return dir .. sep .. file
    end
    return nil
  end

  -- oil.nvim
  if ft == "oil" then
    local ok_oil, oil = pcall(require, "oil")
    if ok_oil then
      local dir   = oil.get_current_dir()
      local entry = oil.get_cursor_entry()
      if dir and entry and entry.name then
        return dir .. entry.name
      end
    end
    return nil
  end

  return nil
end

---@param opts? PdfPort.OpenOpts  optional extra opts (mode, split, backend_id…)
---@return nil
function M.open_current(opts)
  local path = M.current_pdf_path()
  if not path then
    vim.notify("pdfport_nvim: cursor is not on a PDF (or unsupported file-tree)", vim.log.levels.WARN)
    return
  end
  if not path:lower():match("%.pdf$") then
    vim.notify("pdfport_nvim: not a PDF: " .. path, vim.log.levels.WARN)
    return
  end

  local merged = vim.tbl_deep_extend("force", {
    path  = path,
    mode  = "buffer",
    split = "vsplit",
    focus = true,
  }, opts or {})

  require("pdfport_nvim").open(merged)
end

return M
