---@module 'pdfport.renderers.terminal'
---@brief Renders PDF pages as images in the terminal.
---@description
--- Rasterizes pages via pdftoppm (delegated to core/rasterize.lua, shared
--- with the public pdfport.render_page() API) then displays via chafa,
--- kitty icat, or imgcat. Unlike render_page(), the PNG here is a
--- throwaway tempname() deleted shortly after display.

local M = {}
local platform = require("pdfport.platform")
local rasterize_page = require("pdfport.core.rasterize").render_page
local notify = require("pdfport.util.notify").create("[pdfport.terminal]")

---Documented default for `terminal_size_ratio` (mirrors
---`config/DEFAULTS.lua`'s `render_opts.terminal_size_ratio`).
local DEFAULT_SIZE_RATIO = { width = 0.9, height = 0.8 }

---@internal
---Same range check as `config/init.lua`'s `is_unit_fraction`, replicated
---here rather than required: `render()` below is reached directly with the
---caller's raw, un-merged `opts` for `mode="terminal"`
---(`core/dispatcher.lua` never runs it through `config.setup()`'s
---validation for this mode -- see TESTS/dispatcher_spec.lua), so a bad
---`terminal_size_ratio.width`/`.height` reaches `display_png()`'s
---arithmetic unchecked regardless of whether it came from `setup()` or a
---direct per-call option (ERR-22).
---@param value any
---@return boolean
local function is_unit_fraction(value)
  return type(value) == "number" and value > 0 and value <= 1
end

---@internal
---Validate a caller-supplied `terminal_size_ratio`, falling back to the
---documented default for whichever of `width`/`height` is missing or out
---of range, instead of letting bad input reach `display_png()`'s
---`vim.o.columns * size_ratio.width` arithmetic (ERR-22).
---@param size_ratio table?
---@return { width: number, height: number }
local function sanitize_size_ratio(size_ratio)
  if type(size_ratio) ~= "table" then return DEFAULT_SIZE_RATIO end
  return {
    width = is_unit_fraction(size_ratio.width) and size_ratio.width or DEFAULT_SIZE_RATIO.width,
    height = is_unit_fraction(size_ratio.height) and size_ratio.height or DEFAULT_SIZE_RATIO.height,
  }
end

---@internal
---@param path string
---@param interval_ms integer
---@param max_attempts integer
---@param callback fun(exists: boolean): nil
---@return nil
local function wait_for_file(path, interval_ms, max_attempts, callback)
  require("lib.nvim.cross.uv.wait_until")(function()
    return vim.fn.filereadable(path) == 1
  end, { interval_ms = interval_ms, max_attempts = max_attempts }, callback)
end

---@internal
---@param png_path string
---@param tool "chafa"|"kitty"|"imgcat"|nil
---@param size_ratio { width: number, height: number }
---@return nil
local function display_png(png_path, tool, size_ratio)
  tool = tool or platform.best_terminal_renderer()
  if not tool then
    notify.error("no image renderer (install chafa)")
    vim.fn.delete(png_path)
    return
  end

  wait_for_file(png_path, 50, 40, function(exists)
    if not exists then
      notify.error("PNG not found after rasterization")
      return
    end

    local ratio = sanitize_size_ratio(size_ratio)
    local escaped = vim.fn.shellescape(png_path)
    local width = math.floor(vim.o.columns * ratio.width)
    local height = math.floor(vim.o.lines * ratio.height)

    if tool == "chafa" then
      if not platform.has("chafa") then
        notify.warn("chafa not installed")
        vim.fn.delete(png_path)
        return
      end
      vim.cmd("split | terminal " .. string.format("chafa --size=%dx%d %s", width, height, escaped))
      vim.defer_fn(function()
        vim.fn.delete(png_path)
      end, 2000)
    elseif tool == "kitty" then
      local exe = platform.has("kitten") and "kitten" or "kitty"
      vim.cmd("split | terminal " .. exe .. " icat " .. escaped)
      vim.defer_fn(function()
        vim.fn.delete(png_path)
      end, 2000)
    elseif tool == "imgcat" then
      vim.cmd("split | terminal imgcat " .. escaped)
      vim.defer_fn(function()
        vim.fn.delete(png_path)
      end, 2000)
    end
  end)
end

---@param _result PdfPort.Result
---@param opts PdfPort.OpenOpts
---@return nil
function M.render(_result, opts)
  local path = opts.path
  if not path or path == "" then
    notify.error("no path provided")
    return
  end

  local pages = (opts.pages and #opts.pages > 0) and opts.pages or { 1 }
  local tool = opts.terminal_tool or platform.best_terminal_renderer()
  local dpi = opts.terminal_dpi or 216
  local size_ratio = opts.terminal_size_ratio or { width = 0.9, height = 0.8 }

  local function render_next(idx)
    if idx > #pages then return end
    rasterize_page(path, pages[idx], { dpi = dpi }, function(png, err)
      if err then
        notify.error(err)
        return
      end
      if not png then
        notify.error("rasterizer returned no PNG")
        return
      end
      display_png(png, tool, size_ratio)
      vim.defer_fn(function()
        render_next(idx + 1)
      end, 500)
    end)
  end

  render_next(1)
end

return M
