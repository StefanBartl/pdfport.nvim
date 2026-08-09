---@module 'pdfport.util.tmpfile'
---@brief Materializes buffer/text creation inputs to a real file on disk.
---@description
--- pdfport.create() producers spawn external CLIs, which need a real path —
--- opts.text/opts.bufnr have no path of their own. Writes into
--- stdpath("cache")/pdfport.nvim/tmp; callers are responsible for calling
--- M.cleanup() on the returned path once the producer's result is in,
--- success or failure (core/composer.lua does this).

local uv = vim.uv or vim.loop

local M = {}

---@type table<PdfPort.InputKind, string>
local EXT_FOR_KIND = {
  markdown = "md",
  text = "txt",
  html = "html",
}

---@internal
---@return string
local function tmp_dir()
  local dir = vim.fn.stdpath("cache") .. "/pdfport.nvim/tmp"
  vim.fn.mkdir(dir, "p")
  return dir
end

---@internal
---@param kind PdfPort.InputKind
---@return string
local function tmp_path(kind)
  local ext = EXT_FOR_KIND[kind] or "txt"
  local name = string.format("%d_%d.%s", uv.hrtime(), math.random(1, 1000000), ext)
  return tmp_dir() .. "/" .. name
end

---@param content string
---@param kind PdfPort.InputKind
---@return string path
function M.write_text(content, kind)
  local path = tmp_path(kind)
  vim.fn.writefile(vim.split(content, "\n", { plain = true }), path)
  return path
end

---@param bufnr integer
---@param kind PdfPort.InputKind
---@return string path
function M.write_buffer(bufnr, kind)
  local path = tmp_path(kind)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  vim.fn.writefile(lines, path)
  return path
end

---@param path string
---@return nil
function M.cleanup(path)
  vim.schedule(function()
    pcall(vim.fn.delete, path)
  end)
end

return M
