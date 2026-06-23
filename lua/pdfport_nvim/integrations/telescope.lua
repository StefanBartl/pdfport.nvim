---@module 'pdfport_nvim.integrations.telescope'
---@brief Telescope previewer integration for pdfport.nvim.
---@description
--- Usage — attach to a single picker:
---
---   local pdfport_tel = require("pdfport_nvim.integrations.telescope")
---   require("telescope.builtin").find_files({
---     previewer = pdfport_tel.previewer({ max_pages = 3 }),
---   })
---
--- Usage — attach globally via filetype_hook:
---
---   require("telescope").setup({
---     defaults = {
---       preview = { filetype_hook = pdfport_tel.filetype_hook },
---     },
---   })

local M = {}

---@param opts? { backend_id?: string, max_pages?: integer }
---@return table  Telescope previewer
function M.previewer(opts)
  opts = opts or {}

  local previewers = require("telescope.previewers")
  local pdfport    = require("pdfport_nvim")

  ---@type table<string, string>
  local cache = {}

  return previewers.new_buffer_previewer({
    title = "PDF (pdfport)",

    define_preview = function(self, entry, _)
      local path = entry.path or entry.filename or entry.value
      if not path or not path:lower():match("%.pdf$") then return end

      local bufnr = self.state.bufnr
      if not vim.api.nvim_buf_is_valid(bufnr) then return end

      local function write(text, ft)
        local lines = vim.split(text, "\n", { plain = true })
        vim.bo[bufnr].modifiable = true
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
        vim.bo[bufnr].filetype   = ft or "text"
        vim.bo[bufnr].modifiable = false
      end

      if cache[path] then
        write(cache[path], "markdown")
        return
      end

      write("-- pdfport: extracting... --", "text")

      pdfport.extract({
        path       = path,
        backend_id = opts.backend_id,
        max_pages  = opts.max_pages or 5,
        __callback = function(result)
          if not vim.api.nvim_buf_is_valid(bufnr) then return end
          local text = result.text or ("-- pdfport error: " .. (result.error or "unknown") .. " --")
          cache[path] = text
          write(text, result.format == "markdown" and "markdown" or "text")
        end,
      })
    end,
  })
end

---@param filepath string
---@param bufnr integer
---@param _ table
---@return boolean  true = hook handled, false = use default
function M.filetype_hook(filepath, bufnr, _)
  if not filepath or not filepath:lower():match("%.pdf$") then return false end

  local pdfport = require("pdfport_nvim")

  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "-- pdfport: loading... --" })
  vim.bo[bufnr].modifiable = false

  pdfport.extract({
    path      = filepath,
    max_pages = 5,
    __callback = function(result)
      if not vim.api.nvim_buf_is_valid(bufnr) then return end
      local text  = result.text or ""
      local lines = vim.split(text, "\n", { plain = true })
      vim.bo[bufnr].modifiable = true
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
      vim.bo[bufnr].filetype   = "markdown"
      vim.bo[bufnr].modifiable = false
    end,
  })

  return true
end

return M
