---@module 'pdfport.integrations.fzf'
---@brief fzf-lua previewer integration for pdfport.nvim.
---@description
--- Usage:
---
---   local pdfport_fzf = require("pdfport.integrations.fzf")
---   require("fzf-lua").files({
---     preview = pdfport_fzf.preview_fn({ max_pages = 3 }),
---   })

local path = require("pdfport.util.path")

local M = {}

---@type table<string, string>
local _cache = {}

---A different `preview_fn({ backend_id = ..., max_pages = ... })` call is a
---different extraction of the same file — the key has to carry both, or one
---picker's config silently serves another's cached result. Same shape as
---`util/cache.lua`'s `path::backend::variant`.
---
---`filepath` is canonicalized first: this module's `_cache` is its own,
---separate from `util/cache.lua`'s disk cache, and fzf-lua hands the
---previewer whatever spelling its own file listing produced -- not
---necessarily the canonical one `core.dispatcher` keys the disk cache on.
---Without this, the same document could extract twice under two spellings
---(wasteful) or, worse, two different documents sharing a relative name in
---different cwds could serve each other's cached text -- the exact
---path-spelling hazard `util/cache.lua`'s own fix (fea0623) closed for the
---disk cache, left open here for this module's in-memory one.
---@param filepath string
---@param backend_id string|nil
---@param max_pages integer
---@return string
local function cache_key(filepath, backend_id, max_pages)
  return string.format("%s::%s::%s", path.canonical(filepath), backend_id or "auto", max_pages)
end

---@param opts? { backend_id?: string, max_pages?: integer }
---@return fun(filepath: string, bufnr: integer, opts: table): nil
function M.preview_fn(opts)
  opts = opts or {}
  local pdfport = require("pdfport")
  local max_pages = opts.max_pages or 5

  return function(filepath, bufnr, _)
    if not filepath or not filepath:lower():match("%.pdf$") then return end
    if not vim.api.nvim_buf_is_valid(bufnr) then return end

    local function write(text, ft)
      local lines = vim.split(text, "\n", { plain = true })
      vim.bo[bufnr].modifiable = true
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
      vim.bo[bufnr].filetype = ft or "text"
      vim.bo[bufnr].modifiable = false
    end

    local key = cache_key(filepath, opts.backend_id, max_pages)
    if _cache[key] then
      write(_cache[key], "markdown")
      return
    end

    write("pdfport: extracting...", "text")

    pdfport.extract({
      path = filepath,
      backend_id = opts.backend_id,
      max_pages = max_pages,
      __callback = function(result)
        if not vim.api.nvim_buf_is_valid(bufnr) then return end
        local text = result.text or ("error: " .. (result.error or ""))
        _cache[key] = text
        write(text, result.format == "markdown" and "markdown" or "text")
      end,
    })
  end
end

return M
