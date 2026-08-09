---@module 'pdfport.core.composer'
---@brief Central creation ("write") coordination for pdfport.nvim.
---@description
--- The mirror image of core/dispatcher.lua: dispatcher resolves a *backend*
--- for PDF → text, composer resolves a *producer* for something → PDF.
--- Flow: validate inputs → guess/accept input kind → resolve output path
--- (on_conflict) → resolve producer chain → create (async or sync).
---
--- P0 scope: `opts.inputs` (file paths) only. `text`/`bufnr` inputs
--- (materialized via a future util/tmpfile.lua) are P1, see
--- docs/ROADMAP/PDF_CREATE.md.

local uv = vim.uv or vim.loop
local registry = require("pdfport.core.registry")

local M = {}

---@type PdfPort.Config|nil
local _config = nil

---@param config PdfPort.Config
---@return nil
function M._set_config(config)
  _config = config
end

---@internal Extension → input kind guesser, consulted when `opts.from` is absent.
---@type table<string, PdfPort.InputKind>
local EXT_KIND = {
  png = "image",
  jpg = "image",
  jpeg = "image",
  gif = "image",
  bmp = "image",
  webp = "image",
  tiff = "image",
  tif = "image",
  md = "markdown",
  markdown = "markdown",
  html = "html",
  htm = "html",
  txt = "text",
  docx = "office",
  odt = "office",
  xlsx = "office",
  pptx = "office",
}

---@internal
---@param path string
---@return PdfPort.InputKind|nil
local function guess_kind(path)
  local ext = path:match("%.([%w]+)$")
  return ext and EXT_KIND[ext:lower()] or nil
end

---@internal
---@param msg string
---@param producer_id? PdfPort.ProducerId
---@return PdfPort.CreateResult
local function err_result(msg, producer_id)
  return {
    status = "error",
    path = nil,
    producer = producer_id or "none",
    pages = nil,
    error = msg,
  }
end

---@internal Applies `on_conflict` to a candidate output path.
---@param path string
---@param on_conflict "overwrite"|"suffix"|"error"
---@return string|nil path
---@return string|nil error_msg
local function resolve_conflict(path, on_conflict)
  local exists = uv.fs_stat(path) ~= nil
  if not exists or on_conflict == "overwrite" then return path, nil end
  if on_conflict == "error" then
    return nil, string.format("pdfport: output already exists: %s", path)
  end

  -- "suffix": insert -1, -2, ... before the extension until a free path is found.
  local stem, ext = path:match("^(.*)(%.[^./\\]+)$")
  stem = stem or path
  ext = ext or ""
  for i = 1, 9999 do
    local candidate = string.format("%s-%d%s", stem, i, ext)
    if not uv.fs_stat(candidate) then return candidate, nil end
  end
  return nil, "pdfport: could not find a free suffixed output path"
end

---@internal
---@param inputs string[]
---@param explicit_output string|nil
---@return string
local function default_output(inputs, explicit_output)
  if explicit_output and explicit_output ~= "" then return explicit_output end
  local first = inputs[1]
  local stem = first:match("^(.*)%.[^./\\]+$") or first
  return stem .. ".pdf"
end

---@internal Per-kind producer fallback chain, mirroring resolver.build_chain.
---@param kind PdfPort.InputKind
---@param requested PdfPort.ProducerId|nil
---@return PdfPort.ProducerId[]
local function build_chain(kind, requested)
  local cfg = _config or {}
  local kind_chain = (cfg.create_chain and cfg.create_chain[kind]) or {}

  local chain = {}
  if requested then chain[1] = requested end
  for i = 1, #kind_chain do
    if kind_chain[i] ~= requested then chain[#chain + 1] = kind_chain[i] end
  end
  return chain
end

---@param kind PdfPort.InputKind
---@param requested? PdfPort.ProducerId
---@return PdfPort.Producer|nil producer
---@return string|nil error_msg
function M.resolve(kind, requested)
  local chain = build_chain(kind, requested)
  for i = 1, #chain do
    local producer = registry.get_producer(chain[i])
    if producer and vim.tbl_contains(producer.accepts, kind) then
      local ok, avail = pcall(producer.available)
      if ok and avail then return producer, nil end
    end
  end
  return nil,
    string.format(
      "pdfport: no available producer for %q. Tried: [%s]",
      kind,
      table.concat(chain, ", ")
    )
end

---@param kind PdfPort.InputKind
---@return boolean
function M.can_create(kind)
  return (M.resolve(kind)) ~= nil
end

---@see pdfport.core.dispatcher.dispatch  Mirror shape, opposite arrow (something → PDF)
---@param opts PdfPort.CreateOpts|table  # inputs/output/from/producer_id/on_conflict + opts.*
---@param callback fun(result: PdfPort.CreateResult): nil
---@return nil
function M.create(opts, callback)
  assert(type(opts) == "table", "opts must be a table")
  assert(type(callback) == "function", "callback must be a function")

  local inputs = opts.inputs
  if type(inputs) ~= "table" or #inputs == 0 then
    vim.schedule(function()
      callback(err_result("pdfport.create: opts.inputs must be a non-empty list of file paths"))
    end)
    return
  end

  local kind = opts.from or guess_kind(inputs[1])
  if not kind then
    vim.schedule(function()
      callback(
        err_result(
          string.format(
            "pdfport.create: could not guess input kind for %q; pass opts.from",
            inputs[1]
          )
        )
      )
    end)
    return
  end

  local producer, resolve_err = M.resolve(kind, opts.producer_id)
  if not producer then
    vim.schedule(function()
      callback(err_result(resolve_err or "pdfport: no producer resolved"))
    end)
    return
  end

  local output, conflict_err =
    resolve_conflict(default_output(inputs, opts.output), opts.on_conflict or "overwrite")
  if not output then
    vim.schedule(function()
      callback(err_result(conflict_err or "pdfport: output path conflict", producer.id))
    end)
    return
  end

  local cfg_create = (_config and _config.create_opts) or {}

  ---@type PdfPort.InternalCreateOpts
  local create_opts = vim.tbl_deep_extend("force", cfg_create, opts.opts or {}, {
    inputs = inputs,
    output = output,
    on_conflict = opts.on_conflict or "overwrite",
  })

  create_opts.__callback = callback

  ---@type fun(req: PdfPort.InternalCreateOpts): PdfPort.CreateResult|nil
  local create_fn = producer.create

  vim.schedule(function()
    local ok, result = pcall(create_fn, create_opts)

    if not ok then
      callback(
        err_result(
          string.format("pdfport: producer '%s' threw: %s", producer.id, tostring(result)),
          producer.id
        )
      )
      return
    end

    if result ~= nil then callback(result) end
  end)
end

return M
