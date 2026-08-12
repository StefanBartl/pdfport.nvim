---@module 'pdfport.core.rasterize'
---@brief Rasterizes a single PDF page to a PNG file via pdftoppm.
---@description
--- Extracted from renderers/terminal.lua's former local `rasterize()` so the
--- same pdftoppm invocation is usable outside the terminal renderer's
--- display-and-delete flow. This module only shells out and hands back a
--- PNG path — it never displays or deletes anything; callers own the
--- lifecycle of the file they get back (renderers/terminal.lua still
--- deletes its own tempname()-based PNGs after display; pdfport.render_page()
--- does not).

local platform = require("pdfport.platform")
local uv = vim.uv or vim.loop

local M = {}

---@param path string
---@param page integer
---@param opts? PdfPort.RenderPageOpts
---@param callback fun(png_path: string|nil, err: string|nil): nil
---@return nil
function M.render_page(path, page, opts, callback)
  opts = opts or {}

  if not platform.has("pdftoppm") then
    callback(nil, "pdftoppm not found (install poppler-utils)")
    return
  end

  local dpi = opts.dpi or 216
  -- pdftoppm appends ".png" itself (-singlefile), so the base passed to it
  -- must not already carry the extension.
  local base = opts.output_path and (opts.output_path:gsub("%.png$", "")) or vim.fn.tempname()

  local args = {
    "-png",
    "-r",
    tostring(dpi),
    "-f",
    tostring(page),
    "-l",
    tostring(page),
    "-singlefile",
    path,
    base,
  }

  local stderr = uv.new_pipe(false)
  if not stderr then
    callback(nil, "failed to create stderr pipe")
    return
  end

  local stderr_chunks = {}

  uv.spawn("pdftoppm", {
    args = args,
    stdio = { nil, nil, stderr },
  }, function(code, _)
    if stderr and not stderr:is_closing() then stderr:close() end
    vim.schedule(function()
      local png = base .. ".png"
      if code ~= 0 or vim.fn.filereadable(png) ~= 1 then
        callback(nil, string.format("pdftoppm exited %d: %s", code, table.concat(stderr_chunks)))
        return
      end
      callback(png, nil)
    end)
  end)

  stderr:read_start(function(_, data)
    if data then stderr_chunks[#stderr_chunks + 1] = data end
  end)
end

return M
