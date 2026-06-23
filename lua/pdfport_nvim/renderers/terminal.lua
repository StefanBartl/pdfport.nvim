---@module 'pdfport_nvim.renderers.terminal'
---@brief Renders PDF pages as images in the terminal.
---@description
--- Rasterizes pages via pdftoppm then displays via ueberzug++, chafa, kitty icat, or imgcat.

local M        = {}
local platform = require("pdfport_nvim.platform")
local uv       = vim.uv or vim.loop

---@param pdf_path string
---@param page integer
---@param dpi integer
---@param callback fun(png_path: string|nil, err: string|nil): nil
---@return nil
local function rasterize(pdf_path, page, dpi, callback)
  if not platform.has("pdftoppm") then
    callback(nil, "pdftoppm not found (install poppler-utils)")
    return
  end

  local tmp    = vim.fn.tempname()
  local args   = { "-png", "-r", tostring(dpi), "-f", tostring(page), "-l", tostring(page), "-singlefile", pdf_path, tmp }
  local stderr = uv.new_pipe(false)
  if not stderr then callback(nil, "failed to create stderr pipe"); return end

  local stderr_chunks = {}

  uv.spawn("pdftoppm", {
    args  = args,
    stdio = { nil, nil, stderr },
  }, function(code, _)
    if stderr and not stderr:is_closing() then stderr:close() end
    vim.schedule(function()
      local png = tmp .. ".png"
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

---@param path string
---@param interval_ms integer
---@param max_attempts integer
---@param callback fun(exists: boolean): nil
---@return nil
local function wait_for_file(path, interval_ms, max_attempts, callback)
  local attempts = 0
  local timer    = uv.new_timer()
  if not timer then vim.schedule(function() callback(false) end); return end

  timer:start(0, interval_ms, function()
    attempts = attempts + 1
    if vim.fn.filereadable(path) == 1 then
      timer:stop(); timer:close()
      vim.schedule(function() callback(true) end)
      return
    end
    if attempts >= max_attempts then
      timer:stop(); timer:close()
      vim.schedule(function() callback(false) end)
    end
  end)
end

---@param png_path string
---@param tool "ueberzug"|"chafa"|"kitty"|"imgcat"|nil
---@return nil
local function display_png(png_path, tool)
  tool = tool or platform.best_terminal_renderer()
  if not tool then
    vim.notify("pdfport_nvim terminal: no image renderer (install chafa or ueberzug++)", vim.log.levels.ERROR)
    vim.fn.delete(png_path)
    return
  end

  wait_for_file(png_path, 50, 40, function(exists)
    if not exists then
      vim.notify("pdfport_nvim terminal: PNG not found after rasterization", vim.log.levels.ERROR)
      return
    end

    local escaped = vim.fn.shellescape(png_path)
    local width   = math.floor(vim.o.columns * 0.9)
    local height  = math.floor(vim.o.lines   * 0.8)

    if tool == "chafa" or tool == "ueberzug" then
      if not platform.has("chafa") then
        vim.notify("pdfport_nvim terminal: chafa not installed", vim.log.levels.WARN)
        vim.fn.delete(png_path)
        return
      end
      vim.cmd("split | terminal " .. string.format("chafa --size=%dx%d %s", width, height, escaped))
      vim.defer_fn(function() vim.fn.delete(png_path) end, 2000)

    elseif tool == "kitty" then
      local exe = platform.has("kitten") and "kitten" or "kitty"
      vim.cmd("split | terminal " .. exe .. " icat " .. escaped)
      vim.defer_fn(function() vim.fn.delete(png_path) end, 2000)

    elseif tool == "imgcat" then
      vim.cmd("split | terminal imgcat " .. escaped)
      vim.defer_fn(function() vim.fn.delete(png_path) end, 2000)
    end
  end)
end

---@param _result PdfPort.Result
---@param opts PdfPort.OpenOpts
---@return nil
function M.render(_result, opts)
  local path = opts.path
  if not path or path == "" then
    vim.notify("pdfport_nvim terminal: no path provided", vim.log.levels.ERROR)
    return
  end

  local pages = (opts.pages and #opts.pages > 0) and opts.pages or { 1 }
  local tool  = opts.terminal_tool or platform.best_terminal_renderer()
  local dpi   = 216

  local function render_next(idx)
    if idx > #pages then return end
    rasterize(path, pages[idx], dpi, function(png, err)
      if err then
        vim.notify("pdfport_nvim terminal: " .. err, vim.log.levels.ERROR)
        return
      end
      if not png then
        vim.notify("pdfport_nvim terminal: rasterizer returned no PNG", vim.log.levels.ERROR)
        return
      end
      display_png(png, tool)
      vim.defer_fn(function() render_next(idx + 1) end, 500)
    end)
  end

  render_next(1)
end

return M
