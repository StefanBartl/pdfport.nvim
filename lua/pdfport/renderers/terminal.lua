---@module 'pdfport.renderers.terminal'
---@brief Renders PDF pages as images in the terminal.
---@description
--- Rasterizes pages via pdftoppm (delegated to core/rasterize.lua, shared
--- with the public pdfport.render_page() API) then displays via chafa,
--- kitty icat, or imgcat. Unlike render_page(), the PNG here is a
--- throwaway tempname() deleted when the display job exits.

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
---Runs `argv` in a fresh terminal split without a shell command line (no
---quoting rules to get wrong on pwsh/cmd) and deletes `png_path` exactly
---once, when the job ends -- or at once if it could not be started.
---@param argv string[]
---@param png_path string
---@return nil
local function run_in_terminal(argv, png_path)
  local cleaned = false
  local function cleanup()
    if cleaned then return end
    cleaned = true
    vim.fn.delete(png_path)
  end

  local prev_win = vim.api.nvim_get_current_win()
  vim.cmd("new")
  local win = vim.api.nvim_get_current_win()
  local opts = {
    on_exit = function()
      cleanup()
    end,
  }
  -- jobstart() raises (E475) for a program that is not executable instead of
  -- returning 0/-1, so the failure has to be caught to clean up after it.
  local started, job = pcall(function()
    if vim.fn.has("nvim-0.11") == 1 then
      opts.term = true
      return vim.fn.jobstart(argv, opts)
    end
    return vim.fn.termopen(argv, opts) ---@diagnostic disable-line: deprecated
  end)
  if not started or type(job) ~= "number" or job <= 0 then
    notify.error(
      "could not start " .. tostring(argv[1]) .. (started and "" or (": " .. tostring(job)))
    )
    cleanup()
    if win ~= prev_win and vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
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
    local width = math.floor(vim.o.columns * ratio.width)
    local height = math.floor(vim.o.lines * ratio.height)

    local argv
    if tool == "chafa" then
      if not platform.has("chafa") then
        notify.warn("chafa not installed")
        vim.fn.delete(png_path)
        return
      end
      argv = { "chafa", string.format("--size=%dx%d", width, height), png_path }
    elseif tool == "kitty" then
      argv = { platform.has("kitten") and "kitten" or "kitty", "icat", png_path }
    elseif tool == "imgcat" then
      argv = { "imgcat", png_path }
    else
      vim.fn.delete(png_path)
      return
    end
    run_in_terminal(argv, png_path)
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
