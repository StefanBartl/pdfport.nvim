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

---The pdftoppm argument list for one page.
---
---A function of its own, and public, so the flags are assertable without
---poppler installed and without a PDF — the same reason `util/page_range.lua`
---is a pure parser. Everything below it is process handling, which a test
---cannot say anything useful about.
---
---`-x -y -W -H` are appended only as a complete set: pdftoppm reads a partial
---window as a window anyway (the missing edges default to 0 / the page), so a
---half-filled crop table would silently rasterize a region nobody asked for.
---A caller that means "the whole page" passes no crop at all.
---@param path string
---@param page integer
---@param dpi integer
---@param base string Output base path, without the `.png` pdftoppm appends
---@param crop? PdfPort.RenderPageCrop
---@return string[]
function M.args(path, page, dpi, base, crop)
  local args = {
    "-png",
    "-r",
    tostring(dpi),
    "-f",
    tostring(page),
    "-l",
    tostring(page),
    "-singlefile",
  }

  if crop then
    assert(
      type(crop.x) == "number"
        and type(crop.y) == "number"
        and type(crop.w) == "number"
        and type(crop.h) == "number",
      "pdfport.render_page: opts.crop needs x, y, w and h"
    )
    assert(
      crop.x >= 0 and crop.y >= 0 and crop.w >= 1 and crop.h >= 1,
      "pdfport.render_page: opts.crop needs x,y >= 0 and w,h >= 1"
    )
    vim.list_extend(args, {
      "-x",
      tostring(math.floor(crop.x)),
      "-y",
      tostring(math.floor(crop.y)),
      "-W",
      tostring(math.floor(crop.w)),
      "-H",
      tostring(math.floor(crop.h)),
    })
  end

  args[#args + 1] = path
  args[#args + 1] = base
  return args
end

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

  local args = M.args(path, page, dpi, base, opts.crop)

  local stderr = uv.new_pipe(false)
  if not stderr then
    callback(nil, "failed to create stderr pipe")
    return
  end

  local stderr_chunks = {}

  -- luv's meta declares every uv.spawn option required (cwd, env, uid, gid,
  -- verbatim, detached, hide), which no real caller passes.
  ---@diagnostic disable-next-line: missing-fields
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
