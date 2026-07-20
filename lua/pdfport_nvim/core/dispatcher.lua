---@module 'pdfport_nvim.core.dispatcher'
---@brief Central dispatch logic for pdfport.nvim.
---@description
--- Coordinates callers (integrations, commands) with backend/renderer pairs.
--- Flow: validate path → resolve backend → extract async → render on main thread.

local uv       = vim.uv or vim.loop
local resolver = require("pdfport_nvim.core.resolver")
local registry = require("pdfport_nvim.core.registry")
local notify   = require("pdfport_nvim.util.notify").create("[pdfport_nvim.dispatcher]")

local M = {}

---@type PdfPort.Config|nil
local _config = nil

---@param config PdfPort.Config
---@return nil
function M._set_config(config)
  _config = config
end

---@param msg string
---@param backend_id? PdfPort.BackendId
---@return PdfPort.Result
local function err_result(msg, backend_id)
  return {
    status          = "error",
    text            = nil,
    format          = "plain",
    backend         = backend_id or "none",
    pages_processed = nil,
    error           = msg,
  }
end

---@param path string
---@return boolean ok
---@return string|nil error_msg
local function validate_path(path)
  if type(path) ~= "string" or path == "" then
    return false, "pdfport_nvim: path must be a non-empty string"
  end
  local stat = uv.fs_stat(path)
  if not stat then
    return false, string.format("pdfport_nvim: file not found: %s", path)
  end
  if stat.type ~= "file" then
    return false, string.format("pdfport_nvim: not a regular file: %s", path)
  end
  return true, nil
end

---@param opts PdfPort.OpenOpts|PdfPort.InternalExtractOpts
---@param callback fun(result: PdfPort.Result): nil
---@return nil
function M.dispatch(opts, callback)
  assert(type(opts) == "table",          "opts must be a table")
  assert(type(opts.path) == "string",    "opts.path must be a string")
  assert(type(callback) == "function",   "callback must be a function")

  local ok, err = validate_path(opts.path)
  if not ok then
    vim.schedule(function() callback(err_result(err or "unknown path error")) end)
    return
  end

  if opts.mode == "system" then
    local sys_renderer = registry.get_renderer("system")
    if not sys_renderer then
      vim.schedule(function() callback(err_result("pdfport_nvim: system renderer not registered")) end)
      return
    end
    vim.schedule(function()
      sys_renderer({ status = "ok", text = nil, format = "plain", backend = "system",
                     pages_processed = nil, error = nil }, opts)
    end)
    return
  end

  if opts.mode == "terminal" then
    local term_renderer = registry.get_renderer("terminal")
    if not term_renderer then
      vim.schedule(function() callback(err_result("pdfport_nvim: terminal renderer not registered")) end)
      return
    end
    vim.schedule(function()
      term_renderer({ status = "ok", text = opts.path, format = "plain", backend = "terminal",
                      pages_processed = nil, error = nil }, opts)
    end)
    return
  end

  local backend, resolve_err = resolver.resolve(opts.backend_id)
  if not backend then
    vim.schedule(function() callback(err_result(resolve_err or "pdfport_nvim: no backend resolved")) end)
    return
  end

  local cfg_extract = (_config and _config.extract_opts) or {}

  ---@type PdfPort.InternalExtractOpts
  local extract_opts = vim.tbl_deep_extend("force", cfg_extract, {
    pages      = (opts --[[@as PdfPort.OpenOpts]]).pages,
    max_pages  = (opts --[[@as PdfPort.OpenOpts]]).max_pages,
    prompt     = (opts --[[@as PdfPort.OpenOpts]]).prompt,
    model      = (opts --[[@as PdfPort.OpenOpts]]).model,
    timeout_ms = (opts --[[@as PdfPort.OpenOpts]]).timeout_ms,
    __callback = callback,
  })

  local path       = opts.path
  local backend_id = backend.id

  ---@type fun(p: string, o: PdfPort.InternalExtractOpts): PdfPort.Result|nil
  local extract_fn = backend.extract

  vim.schedule(function()
    local ok_extract, result = pcall(
      ---@type fun(...): any
      (extract_fn),
      path,
      extract_opts
    )

    if not ok_extract then
      callback(err_result(
        string.format("pdfport_nvim: backend '%s' threw: %s", backend_id, tostring(result)),
        backend_id
      ))
      return
    end

    if result ~= nil then callback(result) end
  end)
end

---@param opts PdfPort.OpenOpts
---@return nil
function M.open(opts)
  assert(type(opts) == "table",       "opts must be a table")
  assert(type(opts.path) == "string", "opts.path must be a string")

  local cfg_render = (_config and _config.render_opts) or {}
  local mode = opts.mode or cfg_render.mode or "buffer"
  opts.mode  = mode

  M.dispatch(opts, function(result)
    if result.status == "error" then
      notify.error(result.error or "unknown extraction error")
      return
    end

    local renderer = registry.get_renderer(mode)
    if not renderer then
      notify.error(string.format("renderer '%s' not registered", mode))
      return
    end

    local render_opts = vim.tbl_deep_extend("force", cfg_render, opts)
    renderer(result, render_opts)
  end)
end

return M
