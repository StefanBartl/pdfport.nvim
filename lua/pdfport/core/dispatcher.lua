---@module 'pdfport.core.dispatcher'
---@brief Central dispatch logic for pdfport.nvim.
---@description
--- Coordinates callers (integrations, commands) with backend/renderer pairs.
--- Flow: validate path → canonicalize it → resolve backend → extract async →
--- render on main thread.

local uv = vim.uv or vim.loop
local resolver = require("pdfport.core.resolver")
local registry = require("pdfport.core.registry")

local M = {}

---@type PdfPort.Config|nil
local _config = nil

---@param config PdfPort.Config
---@return nil
function M._set_config(config)
  _config = config
end

local ok_progress, progress_mod = pcall(require, "lib.nvim.progress")

---@internal
---Starts a progress indicator for an extraction, or nil when lib.nvim isn't
---installed. This lives in the dispatcher rather than in each backend because
---the dispatcher is the one place every extraction passes through — all eight
---backends get it without knowing about it.
---
---Deliberately no `on_cancel`: backends spawn through `spawn_capture`, which
---does not hand back a killable handle, so registering one would close the
---indicator while the process kept running. The per-backend `timeout_ms` is the
---only real bound on a runaway extraction.
---@param backend_id string
---@param path string
---@return table|nil
local function start_progress(backend_id, path)
  if not ok_progress then return nil end
  local handle = progress_mod.create({
    title = "[pdfport]",
    style = (_config and _config.progress_style) or "auto",
  })
  handle:update({
    text = string.format("%s: %s", backend_id, vim.fn.fnamemodify(path, ":t")),
  })
  return handle
end

---@internal
---@param msg string
---@param backend_id? PdfPort.BackendId
---@return PdfPort.Result
local function err_result(msg, backend_id)
  return {
    status = "error",
    text = nil,
    format = "plain",
    backend = backend_id or "none",
    pages_processed = nil,
    error = msg,
  }
end

---@internal
---@param path string
---@return boolean ok
---@return string|nil error_msg
local function validate_path(path)
  if type(path) ~= "string" or path == "" then
    return false, "pdfport: path must be a non-empty string"
  end
  local stat = uv.fs_stat(path)
  if not stat then return false, string.format("pdfport: file not found: %s", path) end
  if stat.type ~= "file" then
    return false, string.format("pdfport: not a regular file: %s", path)
  end
  return true, nil
end

---@see pdfport.core.resolver.resolve  Backend selection happens here before extraction
---@param opts PdfPort.OpenOpts|PdfPort.InternalExtractOpts
---@param callback fun(result: PdfPort.Result): nil
---@return nil
---@internal
---The third component of the extraction cache key (`path::backend::variant`),
---the one that says *which* extraction of that file this is.
---
---The page range alone is not enough for the model-backed backends. `claude`,
---`gemini` and `ollama` also take `prompt` and `model`, and both change what
---comes back for the very same pages -- so a key without them serves the
---answer to "list every table" when the next call asks "summarise in one
---sentence", silently and looking freshly computed. Measured before this
---existed: two different prompts, one HTTP call, identical answers.
---
---The two are appended only when at least one is set, so every backend that
---has neither (pdftotext, pdfplumber, marker, docling, tesseract) keeps
---byte-for-byte the key it had before and its existing cache entries stay
---valid. The prompt is hashed rather than embedded: it is arbitrary
---user text of arbitrary length, and this is a lookup key, not a record of
---what was asked.
---@param extract_opts PdfPort.InternalExtractOpts
---@return string
function M._cache_variant(extract_opts)
  local variant = (extract_opts.pages and #extract_opts.pages > 0)
      and table.concat(extract_opts.pages, ",")
    or tostring(extract_opts.max_pages or "all")

  if extract_opts.prompt or extract_opts.model then
    variant = string.format(
      "%s::%s::%s",
      variant,
      vim.fn.sha256(extract_opts.prompt or ""):sub(1, 16),
      extract_opts.model or ""
    )
  end

  return variant
end

function M.dispatch(opts, callback)
  assert(type(opts) == "table", "opts must be a table")
  -- Bound here rather than re-read at each use: `ExtractOpts.path` is optional
  -- and `OpenOpts.path` is not, so every later `opts.path` read as maybe-nil
  -- even though this assert had already settled it.
  local path = opts.path
  assert(type(path) == "string", "opts.path must be a string")
  assert(type(callback) == "function", "callback must be a function")

  local ok, err = validate_path(path)
  if not ok then
    vim.schedule(function()
      callback(err_result(err or "unknown path error"))
    end)
    return
  end

  -- From here down there is exactly one spelling of this file. Validation
  -- runs first on purpose, so "file not found" still names the path the
  -- caller actually typed.
  --
  -- This is the only place it has to happen, because it is the only place
  -- every extraction passes through -- and `util.cache` keys on the path
  -- string, so the spelling *is* the identity. Callers do not agree on one:
  -- a command argument may be relative, a file tree gives an absolute path,
  -- and `nvim_buf_get_name()` gives a resolved one (on macOS
  -- `/private/var/...` where `tempname()` says `/var/...`). Keyed raw, the
  -- same document extracts once per spelling -- and a relative key names a
  -- different file in every directory, so two documents sharing a relative
  -- name and an mtime second can answer with each other's text.
  --
  -- Written back into `opts` as well, so the renderers -- which read
  -- `opts.path` after this returns -- name the same file the cache and the
  -- backend did.
  path = require("pdfport.util.path").canonical(path)
  opts.path = path

  if opts.mode == "system" then
    ---@cast opts PdfPort.OpenOpts
    local sys_renderer = registry.get_renderer("system")
    if not sys_renderer then
      vim.schedule(function()
        callback(err_result("pdfport: system renderer not registered"))
      end)
      return
    end
    vim.schedule(function()
      sys_renderer({
        status = "ok",
        text = nil,
        format = "plain",
        backend = "system",
        pages_processed = nil,
        error = nil,
      }, opts)
    end)
    return
  end

  if opts.mode == "terminal" then
    ---@cast opts PdfPort.OpenOpts
    local term_renderer = registry.get_renderer("terminal")
    if not term_renderer then
      vim.schedule(function()
        callback(err_result("pdfport: terminal renderer not registered"))
      end)
      return
    end
    vim.schedule(function()
      term_renderer({
        status = "ok",
        text = path,
        format = "plain",
        backend = "terminal",
        pages_processed = nil,
        error = nil,
      }, opts)
    end)
    return
  end

  local backend, resolve_err = resolver.resolve(opts.backend_id)
  if not backend then
    vim.schedule(function()
      callback(err_result(resolve_err or "pdfport: no backend resolved"))
    end)
    return
  end

  local cfg_extract = (_config and _config.extract_opts) or {}

  -- Cast on the result, not `---@type` on the binding: see composer.lua for
  -- why -- `tbl_deep_extend` types its return as the union of its arguments.
  local extract_opts = vim.tbl_deep_extend("force", cfg_extract, {
    pages = (opts --[[@as PdfPort.OpenOpts]]).pages,
    max_pages = (opts --[[@as PdfPort.OpenOpts]]).max_pages,
    prompt = (opts --[[@as PdfPort.OpenOpts]]).prompt,
    model = (opts --[[@as PdfPort.OpenOpts]]).model,
    timeout_ms = (opts --[[@as PdfPort.OpenOpts]]).timeout_ms,
  })
  ---@cast extract_opts PdfPort.InternalExtractOpts

  local backend_id = backend.id
  local cache_enabled = extract_opts.cache ~= false

  local variant = M._cache_variant(extract_opts)

  if cache_enabled then
    local cached = require("pdfport.util.cache").get(path, backend_id, variant)
    if cached then
      vim.schedule(function()
        callback(cached)
      end)
      return
    end
  end

  -- Started only past the cache check: a cache hit returns immediately and has
  -- nothing to report progress on. Wrapping `callback` here rather than closing
  -- the handle at each exit means every downstream path is covered at once — the
  -- async `__callback`, the synchronous return, and the backend-threw branch all
  -- funnel through this one function.
  local progress = start_progress(backend_id, path)
  if progress then
    local inner_callback = callback
    local closed = false
    callback = function(result)
      if not closed then
        closed = true
        if result and result.status == "error" then
          progress:finish(string.format("%s failed", backend_id))
        else
          progress:finish(string.format("%s done", backend_id))
        end
      end
      inner_callback(result)
    end
  end

  extract_opts.__callback = cache_enabled
      and function(result)
        if result and result.status == "ok" then
          require("pdfport.util.cache").set(path, backend_id, variant, result)
        end
        callback(result)
      end
    or callback

  ---@type fun(p: string, o: PdfPort.InternalExtractOpts): PdfPort.Result|nil
  local extract_fn = backend.extract

  vim.schedule(function()
    local ok_extract, result = pcall(
      ---@type fun(...): any
      extract_fn,
      path,
      extract_opts
    )

    if not ok_extract then
      callback(
        err_result(
          string.format("pdfport: backend '%s' threw: %s", backend_id, tostring(result)),
          backend_id
        )
      )
      return
    end

    if result ~= nil then
      if cache_enabled and result.status == "ok" then
        require("pdfport.util.cache").set(path, backend_id, variant, result)
      end
      callback(result)
    end
  end)
end

---@param opts PdfPort.OpenOpts
---@param on_error? fun(msg: string): nil  Called instead of notifying directly,
---       so the caller (the UI/binding layer) decides how to surface the
---       failure. Defaults to a no-op: callers that don't pass one get silent
---       failure, which matches this module's job of staying decoupled from
---       any particular UI.
---@param on_done? fun(ok: boolean, err: string|nil)  settles exactly once, on
---       every path -- the only way a caller can know an open finished, since
---       dispatch is asynchronous throughout and success is otherwise silent
---@return nil
function M.open(opts, on_error, on_done)
  assert(type(opts) == "table", "opts must be a table")
  assert(type(opts.path) == "string", "opts.path must be a string")
  on_error = on_error or function() end

  -- Guarded because a caller counting outcomes must not be able to
  -- double-count: a renderer that raises still has to settle exactly once.
  local settled = false
  local function settle(ok, err)
    if settled then return end
    settled = true
    if on_done then on_done(ok, err) end
  end

  local cfg_render = (_config and _config.render_opts) or {}
  local mode = opts.mode or cfg_render.mode or "buffer"
  opts.mode = mode

  M.dispatch(opts, function(result)
    if result.status == "error" then
      local err = result.error or "unknown extraction error"
      on_error(err)
      settle(false, err)
      return
    end

    local renderer = registry.get_renderer(mode)
    if not renderer then
      local err = string.format("renderer '%s' not registered", mode)
      on_error(err)
      settle(false, err)
      return
    end

    local render_opts = vim.tbl_deep_extend("force", cfg_render, opts)
    local ok, err = pcall(renderer, result, render_opts)
    if not ok then
      local msg = ("renderer '%s' failed: %s"):format(mode, tostring(err))
      on_error(msg)
      settle(false, msg)
      return
    end
    settle(true, nil)
  end)
end

return M
