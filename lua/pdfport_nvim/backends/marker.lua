---@module 'pdfport_nvim.backends.marker'
---@brief Extraction backend using the marker-pdf Python tool.
---@description
--- marker-pdf converts PDFs to Markdown with high fidelity.
--- Install: pip install marker-pdf

local platform = require("pdfport_nvim.platform")
local uv       = vim.uv or vim.loop

---@type PdfPort.Backend
local M = {
  id   = "marker",
  name = "marker-pdf (AI Markdown extraction)",
  capabilities = {
    markdown     = true,
    tables       = true,
    ocr          = true,
    remote       = false,
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

  local args = { path, tmp_dir, "--output_format", "markdown" }
  if opts.max_pages then
    args[#args + 1] = "--max_pages"
    args[#args + 1] = tostring(opts.max_pages)
  end

  local stderr_chunks = {}
  local stderr        = uv.new_pipe(false)
  if not stderr then
    vim.fn.delete(tmp_dir, "rf")
    return {
      status = "error", text = nil, format = "markdown", backend = "marker",
      pages_processed = nil, error = "marker: failed to create stderr pipe",
    }
  end

  local timeout_ms = opts.timeout_ms or 120000
  local timer      = uv.new_timer()
  if not timer then
    vim.fn.delete(tmp_dir, "rf")
    return {
      status = "error", text = nil, format = "markdown", backend = "marker",
      pages_processed = nil, error = "marker: failed to create timeout timer",
    }
  end

  local function cleanup()
    if timer  and not timer:is_closing()  then timer:stop(); timer:close() end
    if stderr and not stderr:is_closing() then stderr:close() end
  end

  ---@type uv_process_t|nil
  local handle

  handle = uv.spawn("marker_single", {
    args  = args,
    stdio = { nil, nil, stderr },
  }, function(code, _)
    cleanup()
    local err_text = table.concat(stderr_chunks)

    vim.schedule(function()
      if code ~= 0 then
        vim.fn.delete(tmp_dir, "rf")
        local result = {
          status = "error", text = nil, format = "markdown", backend = "marker",
          pages_processed = nil,
          error = string.format("marker_single exited %d: %s", code, err_text),
        }
        if type(opts.__callback) == "function" then opts.__callback(result) end
        return
      end

      local stem    = vim.fn.fnamemodify(path, ":t:r")
      local md_path = tmp_dir .. "/" .. stem .. "/" .. stem .. ".md"

      if vim.fn.filereadable(md_path) ~= 1 then
        local pattern = tmp_dir:gsub("\\", "/") .. "/**/*.md"
        local found   = vim.fn.glob(pattern, false, true)
        if #found > 0 then
          md_path = found[1]
        else
          local all = vim.fn.glob(tmp_dir:gsub("\\", "/") .. "/**/*", false, true)
          vim.fn.delete(tmp_dir, "rf")
          local result = {
            status = "error", text = nil, format = "markdown", backend = "marker",
            pages_processed = nil,
            error = string.format("marker_single: no .md file in %s. Present: %s",
              tmp_dir, table.concat(all, ", ")),
          }
          if type(opts.__callback) == "function" then opts.__callback(result) end
          return
        end
      end

      local lines = vim.fn.readfile(md_path)
      local text  = table.concat(lines, "\n")
      vim.fn.delete(tmp_dir, "rf")

      local result = {
        status = "ok", text = text, format = "markdown", backend = "marker",
        pages_processed = opts.max_pages, error = nil,
      }
      if type(opts.__callback) == "function" then opts.__callback(result) end
    end)
  end)

  if not handle then
    vim.fn.delete(tmp_dir, "rf")
    return {
      status = "error", text = nil, format = "markdown", backend = "marker",
      pages_processed = nil, error = "marker: failed to spawn marker_single",
    }
  end

  stderr:read_start(function(_, data)
    if data then stderr_chunks[#stderr_chunks + 1] = data end
  end)

  timer:start(timeout_ms, 0, function()
    if handle and not handle:is_closing() then handle:kill(15) end
    cleanup()
    vim.schedule(function()
      vim.fn.delete(tmp_dir, "rf")
      local result = {
        status = "error", text = nil, format = "markdown", backend = "marker",
        pages_processed = nil,
        error = string.format("marker: timed out after %d ms", timeout_ms),
      }
      if type(opts.__callback) == "function" then opts.__callback(result) end
    end)
  end)

  return nil
end

return M
