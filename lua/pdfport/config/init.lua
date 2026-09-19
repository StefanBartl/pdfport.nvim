---@module 'pdfport.config'
---@brief Configuration management for pdfport.nvim.
---@description
--- See config/DEFAULTS.lua for every configurable key and its default value.

local M = {}

local defaults = require("pdfport.config.DEFAULTS")
local notify = require("pdfport.util.notify").create("[pdfport.config]")

---@type PdfPort.Config
local _cfg = nil

---What the last `setup()` had to ignore, for `:checkhealth`.
---@type string[]
local _issues = {}

---@internal
---@param value any
---@return boolean ok
---@return string? reason
local function is_positive_number(value)
  if type(value) ~= "number" or value <= 0 then return false, "must be a positive number" end
  return true
end

---@internal
---`terminal_size_ratio.width`/`.height` are a fraction of `vim.o.columns`/
---`vim.o.lines` (see `@types/init.lua`'s `PdfPort.TerminalSizeRatio`) --
---anything outside (0, 1] is either meaningless or, for a non-number,
---crashes `renderers/terminal.lua`'s `vim.o.columns * size_ratio.width`
---(ERR-22: that arithmetic runs inside an async callback with nothing
---above it to catch the error).
---@param value any
---@return boolean ok
---@return string? reason
local function is_unit_fraction(value)
  if type(value) ~= "number" or value <= 0 or value > 1 then
    return false, "must be a number in (0, 1]"
  end
  return true
end

---Keys `setup()` accepts and, for the option tables among them, their own
---keys -- mirrors `@types/init.lua`'s `PdfPort.ExtractOpts`/`RenderOpts`/
---`CreateOpts`. A spec is one of three shapes: `true` accepts any value
---unchanged (arrays and opaque nested maps like `create_chain`, where no
---fixed set of sub-keys exists to check against); a nested table recurses
---into that field's own known sub-keys -- to whatever depth this table
---declares, not just one level, so `render_opts.terminal_size_ratio.width`
---is checked exactly like a top-level key; a function validates the leaf
---value itself (`ok, reason = fn(value)`), for a field whose type is right
---but whose range is not (ERR-22).
---@alias PdfPort.Config.KnownSpec true|table<string, PdfPort.Config.KnownSpec>|fun(value: any): boolean, string?
---@type table<string, PdfPort.Config.KnownSpec>
local KNOWN = {
  default_backend = true,
  fallback_chain = true,
  extract_opts = {
    pages = true,
    max_pages = true,
    prompt = true,
    model = true,
    timeout_ms = true,
    path = true,
    cache = true,
  },
  render_opts = {
    mode = true,
    path = true,
    backend_id = true,
    split = true,
    float_opts = true,
    terminal_tool = true,
    terminal_dpi = is_positive_number,
    terminal_size_ratio = {
      width = is_unit_fraction,
      height = is_unit_fraction,
    },
    focus = true,
    pages = true,
  },
  create_opts = {
    inputs = true,
    text = true,
    bufnr = true,
    output = true,
    from = true,
    producer_id = true,
    on_conflict = true,
    opts = true,
    page_size = true,
    margin = true,
    dpi = true,
    fit = true,
    title = true,
    toc = true,
    template = true,
    timeout_ms = true,
  },
  create_chain = true,
  pdf_engine = true,
  claude_api_key = true,
  gemini_api_key = true,
  ollama_host = true,
  ollama_model = true,
  auto_open_on_read = true,
  progress_style = true,
  deps_popup = true,
  debug = true,
}

---@internal
---`key` with the nearest known one as a hint when there is a plausible one.
---@param key any
---@param known table<string, any>
---@param prefix string
---@return string
local function describe_unknown(key, known, prefix)
  local levenshtein = require("lib.lua.strings.distance").levenshtein
  local name = tostring(key)
  local best, best_distance = nil, nil
  for candidate in pairs(known) do
    local d = levenshtein(name, candidate)
    if d <= 3 and (best_distance == nil or d < best_distance) then
      best, best_distance = candidate, d
    end
  end
  if best then
    return string.format("unknown option '%s%s' (did you mean '%s%s'?)", prefix, name, prefix, best)
  end
  return string.format("unknown option '%s%s'", prefix, name)
end

---@internal
---Drop what cannot be merged, and say so, at whatever depth `known`
---declares -- not just one or two levels. A misspelled or out-of-range leaf
---would otherwise land in `_cfg` as a dead or dangerous field with the
---default silently still in force: `vim.tbl_deep_extend("force", ...)`
---accepts anything, and a downstream consumer trusting an unchecked value
---is the other half of ERR-22 (an invalid VALUE, not just an invalid key).
---
---`spec_defaults` mirrors `known` one field at a time and is only consulted
---for a `true` spec (any value goes): when the default at this path is
---itself a table (`fallback_chain`, `create_chain`, ...) a non-table value
---is still rejected, the same as a field with its own known sub-keys --
---`true` means "do not check what is inside", never "any type at all".
---@param opts table
---@param known table<string, PdfPort.Config.KnownSpec>
---@param spec_defaults table  the default value at this same path, for the `true`-spec table check
---@param prefix string  dotted path so far (e.g. `"render_opts."`, or `""` at the top)
---@return table clean  the accepted subset, nested option tables copied
---@return string[] issues
local function sanitize(opts, known, spec_defaults, prefix)
  local clean, issues = {}, {}
  for key, value in pairs(opts) do
    local spec = known[key]
    local default_value = type(spec_defaults) == "table" and spec_defaults[key] or nil
    if spec == nil then
      issues[#issues + 1] = describe_unknown(key, known, prefix)
    elseif type(default_value) == "table" and type(value) ~= "table" then
      issues[#issues + 1] = string.format(
        "option '%s%s' must be a table, got %s -- using the default",
        prefix,
        key,
        type(value)
      )
    elseif type(spec) == "function" then
      local ok, reason = spec(value)
      if ok then
        clean[key] = value
      else
        issues[#issues + 1] = string.format(
          "option '%s%s' %s -- using the default",
          prefix,
          key,
          reason or "is invalid"
        )
      end
    elseif type(spec) == "table" then
      -- `value` is a table here: either default_value was a table too (just
      -- checked above) or this path has no default of its own (e.g. a
      -- render_opts sub-key absent from DEFAULTS.render_opts) and the
      -- check above never fired -- guard it again for that case.
      if type(value) ~= "table" then
        issues[#issues + 1] = string.format(
          "option '%s%s' must be a table, got %s -- using the default",
          prefix,
          key,
          type(value)
        )
      else
        local nested, nested_issues = sanitize(value, spec, default_value, prefix .. key .. ".")
        clean[key] = nested
        for _, issue in ipairs(nested_issues) do
          issues[#issues + 1] = issue
        end
      end
    else
      clean[key] = value
    end
  end
  return clean, issues
end

---Unknown keys, mistyped option tables, and out-of-range values are
---reported once here and again by `:checkhealth pdfport` (see `M.issues()`);
---none of them reach the merge.
---@param opts? PdfPort.Config
---@return nil
function M.setup(opts)
  local clean, issues = sanitize(type(opts) == "table" and opts or {}, KNOWN, defaults(), "")
  table.sort(issues)
  _issues = issues
  if #issues > 0 then notify.warn("ignored config: " .. table.concat(issues, "; ")) end

  _cfg = vim.tbl_deep_extend("force", defaults(), clean)
end

---@return PdfPort.Config
function M.get()
  return _cfg or defaults()
end

---What the last `setup()` ignored: unknown keys and option tables of the
---wrong type, one human-readable line each. Empty when everything was
---accepted (or `setup()` has not run yet).
---@return string[]
function M.issues()
  return vim.list_extend({}, _issues)
end

return M
