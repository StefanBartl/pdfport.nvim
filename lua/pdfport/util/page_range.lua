---@module 'pdfport.util.page_range'
---@brief Page-range picker for terminal/float modes.
---@description
--- Prompts for a page-range string ("1-3,5,7") and parses it into an
--- explicit page list, so terminal/float open-flows can offer the same
--- page-selection ability extract_opts.pages already supports programmatically.

local M = {}

---@param input string
---@return integer[]|nil  nil = no explicit selection (caller falls back to its own default)
function M.parse(input)
  input = vim.trim(input or "")
  if input == "" then return nil end

  local pages = {}
  local seen = {}
  for part in input:gmatch("[^,]+") do
    part = vim.trim(part)
    local a, b = part:match("^(%d+)%s*-%s*(%d+)$")
    if a and b then
      a, b = tonumber(a), tonumber(b)
      if a and b and a <= b then
        for p = a, b do
          if not seen[p] then
            seen[p] = true
            pages[#pages + 1] = p
          end
        end
      end
    else
      local n = tonumber(part)
      if n then
        n = math.floor(n)
        if not seen[n] then
          seen[n] = true
          pages[#pages + 1] = n
        end
      end
    end
  end

  if #pages == 0 then return nil end
  table.sort(pages)
  return pages
end

---@param callback fun(pages: integer[]|nil): nil  called with nil if the prompt was cancelled or left blank
---@return nil
function M.prompt(callback)
  require("lib.nvim.ui.kit").input({
    title = "pdfport pages (e.g. 1-3,5 — blank = default): ",
    on_submit = function(input)
      callback(M.parse(input))
    end,
  })
end

return M
