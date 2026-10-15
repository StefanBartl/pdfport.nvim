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

local M = {}

---How long pdftoppm may run before it is killed (ms), when the caller gives no `timeout_ms`.
---@type integer
M.DEFAULT_TIMEOUT_MS = 30000

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

  -- spawn_capture owns the process: a timer kills pdftoppm at the limit and the
  -- callback below runs exactly once, whichever of exit and timeout comes first.
  local timeout_ms = opts.timeout_ms or M.DEFAULT_TIMEOUT_MS
  require("lib.nvim.cross.uv.spawn_capture")(
    vim.list_extend({ "pdftoppm" }, args),
    { timeout_ms = timeout_ms },
    function(result)
      local png = base .. ".png"
      if result.timed_out then
        -- A kill that lands while pdftoppm is writing leaves a truncated PNG behind (seen on
        -- Windows at high dpi). The caller gets no path for it, so nobody else would delete it,
        -- and at a caller-chosen `output_path` it would pass a later "does the file exist" check.
        vim.fn.delete(png)
        callback(nil, string.format("pdftoppm timed out after %d ms", timeout_ms))
        return
      end
      -- spawn_capture reports "could not start the child" as code -1 without a signal; a real
      -- pdftoppm never exits with -1.
      if result.code == -1 and result.signal == 0 and not result.ok then
        callback(nil, string.format("failed to spawn pdftoppm: %s", result.stderr))
        return
      end
      if not result.ok or vim.fn.filereadable(png) ~= 1 then
        callback(nil, string.format("pdftoppm exited %d: %s", result.code, result.stderr))
        return
      end
      callback(png, nil)
    end
  )
end

return M
