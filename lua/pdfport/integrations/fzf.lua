---@module 'pdfport.integrations.fzf'
---@brief fzf-lua previewer integration for pdfport.nvim.
---@description
--- Usage:
---
---   local pdfport_fzf = require("pdfport.integrations.fzf")
---   require("fzf-lua").files({
---     preview = pdfport_fzf.preview_fn({ max_pages = 3 }),
---   })

local M = {}

---@type table<string, string>
local _cache = {}

---@param opts? { backend_id?: string, max_pages?: integer }
---@return fun(filepath: string, bufnr: integer, opts: table): nil
function M.preview_fn(opts)
  opts = opts or {}
  local pdfport = require("pdfport")

  return function(filepath, bufnr, _)
    if not filepath or not filepath:lower():match("%.pdf$") then return end
    if not vim.api.nvim_buf_is_valid(bufnr) then return end

    local function write(text, ft)
      local lines = vim.split(text, "\n", { plain = true })
      vim.bo[bufnr].modifiable = true
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
      vim.bo[bufnr].filetype   = ft or "text"
      vim.bo[bufnr].modifiable = false
    end

    if _cache[filepath] then
      write(_cache[filepath], "markdown")
      return
    end

    write("pdfport: extracting...", "text")

    pdfport.extract({
      path       = filepath,
      backend_id = opts.backend_id,
      max_pages  = opts.max_pages or 5,
      __callback = function(result)
        if not vim.api.nvim_buf_is_valid(bufnr) then return end
        local text = result.text or ("error: " .. (result.error or ""))
        _cache[filepath] = text
        write(text, result.format == "markdown" and "markdown" or "text")
      end,
    })
  end
end

return M
