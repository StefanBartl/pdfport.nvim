---@module 'pdfport.backends.marker'
---@brief Extraction backend using the marker-pdf Python tool.
---@description
--- marker-pdf converts PDFs to Markdown with high fidelity.
--- Runs marker_single asynchronously via lib.nvim.cross.uv.spawn_capture.
--- Install: pip install marker-pdf

local platform = require("pdfport.platform")
local spawn_capture = require("lib.nvim.cross.uv.spawn_capture")

--- See the note on `Backend` in `@types/init.lua`: declared as a class so
--- the methods defined below the literal count as implementing it.
---@class PdfPort.Backend.Marker : PdfPort.Backend
local M = {
  id = "marker",
  name = "marker-pdf (AI Markdown extraction)",
  capabilities = {
    markdown = true,
    tables = true,
    ocr = true,
    remote = false,
    gpu_optional = true,
  },
}

---@return boolean
function M.available()
  return platform.has("marker_single")
end

---@param path string
---@param opts PdfPort.InternalExtractOpts
---@return PdfPort.Result|nil
function M.extract(path, opts)
  local tmp_dir = vim.fn.tempname()
  vim.fn.mkdir(tmp_dir, "p")

  -- Resolve the short name out before anything globs this directory.
  -- `tempname()` sits under %TEMP%, which on Windows is the 8.3 form
  -- (`C:/Users/STEFAN~1/...`) for any profile name over eight characters --
  -- and `vim.fn.glob` reads its argument as a *pattern*, where `~1` is a
  -- home-directory reference it cannot resolve. It then returns an empty list
  -- rather than an error, so the recovery search below found nothing and the
  -- "Present: ..." line in the failure message listed an empty directory that
  -- was not empty. Only after mkdir: fs_realpath needs the path to exist.
  do
    local uv = vim.uv or vim.loop
    local real = uv.fs_realpath(tmp_dir)
    if real then tmp_dir = real end
  end

  local args = { path, tmp_dir, "--output_format", "markdown" }
  if opts.max_pages then
    args[#args + 1] = "--max_pages"
    args[#args + 1] = tostring(opts.max_pages)
  end

  local timeout_ms = opts.timeout_ms or 120000
  local argv = { "marker_single" }
  for _, a in ipairs(args) do
    argv[#argv + 1] = a
  end

  spawn_capture(argv, { timeout_ms = timeout_ms }, function(spawn_result)
    if spawn_result.timed_out then
      vim.fn.delete(tmp_dir, "rf")
      local result = {
        status = "error",
        text = nil,
        format = "markdown",
        backend = "marker",
        pages_processed = nil,
        error = string.format("marker: timed out after %d ms", timeout_ms),
      }
      if type(opts.__callback) == "function" then opts.__callback(result) end
      return
    end

    if not spawn_result.ok then
      vim.fn.delete(tmp_dir, "rf")
      local result = {
        status = "error",
        text = nil,
        format = "markdown",
        backend = "marker",
        pages_processed = nil,
        error = string.format(
          "marker_single exited %d: %s",
          spawn_result.code,
          spawn_result.stderr
        ),
      }
      if type(opts.__callback) == "function" then opts.__callback(result) end
      return
    end

    local stem = vim.fn.fnamemodify(path, ":t:r")
    local md_path = tmp_dir .. "/" .. stem .. "/" .. stem .. ".md"

    if vim.fn.filereadable(md_path) ~= 1 then
      local pattern = tmp_dir:gsub("\\", "/") .. "/**/*.md"
      local found = vim.fn.glob(pattern, false, true)
      if #found > 0 then
        md_path = found[1]
      else
        local all = vim.fn.glob(tmp_dir:gsub("\\", "/") .. "/**/*", false, true)
        vim.fn.delete(tmp_dir, "rf")
        local result = {
          status = "error",
          text = nil,
          format = "markdown",
          backend = "marker",
          pages_processed = nil,
          error = string.format(
            "marker_single: no .md file in %s. Present: %s",
            tmp_dir,
            table.concat(all, ", ")
          ),
        }
        if type(opts.__callback) == "function" then opts.__callback(result) end
        return
      end
    end

    local lines = vim.fn.readfile(md_path)
    local text = table.concat(lines, "\n")
    vim.fn.delete(tmp_dir, "rf")

    local result = {
      status = "ok",
      text = text,
      format = "markdown",
      backend = "marker",
      pages_processed = opts.max_pages,
      error = nil,
    }
    if type(opts.__callback) == "function" then opts.__callback(result) end
  end)

  return nil
end

return M
