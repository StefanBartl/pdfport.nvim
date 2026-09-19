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

---Keys `setup()` accepts and, for the option tables among them, their own
---keys -- mirrors `@types/init.lua`'s `PdfPort.ExtractOpts`/`RenderOpts`/
---`CreateOpts`. `true` means any value goes (arrays and opaque nested maps
---like `create_chain`); a nested table validates that one level of sub-keys.
---@type table<string, true|table<string, true>>
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
    terminal_dpi = true,
    terminal_size_ratio = true,
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
---Drop what cannot be merged, and say so. A misspelled key would otherwise
---land in `_cfg` as a dead field with the default still in force --
---silently, since `vim.tbl_deep_extend("force", ...)` accepts anything.
---@param opts table
---@return table clean  the accepted subset, nested option tables copied
---@return string[] issues
local function sanitize(opts)
  local DEFAULTS = defaults()
  local clean, issues = {}, {}
  for key, value in pairs(opts) do
    local known = KNOWN[key]
    if known == nil then
      issues[#issues + 1] = describe_unknown(key, KNOWN, "")
    elseif type(DEFAULTS[key]) == "table" and type(value) ~= "table" then
      issues[#issues + 1] =
        string.format("option '%s' must be a table, got %s -- using the default", key, type(value))
    elseif type(known) == "table" then
      local nested = {}
      for sub_key, sub_value in pairs(value) do
        if known[sub_key] then
          nested[sub_key] = sub_value
        else
          issues[#issues + 1] = describe_unknown(sub_key, known, key .. ".")
        end
      end
      clean[key] = nested
    else
      clean[key] = value
    end
  end
  table.sort(issues)
  return clean, issues
end

---Unknown keys and mistyped option tables are reported once here and again
---by `:checkhealth pdfport` (see `M.issues()`); they never reach the merge.
---@param opts? PdfPort.Config
---@return nil
function M.setup(opts)
  local clean, issues = sanitize(type(opts) == "table" and opts or {})
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
