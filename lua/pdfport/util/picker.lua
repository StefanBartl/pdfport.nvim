---@module 'pdfport.util.picker'
---@brief Shared "open PDF as…" mode picker used by all file-tree integrations,
---the `:PdfPort` command, and — through `pdfport.pick_open()` — by other
---plugins that embed pdfport.nvim.
---@description
--- One canonical choice list for every place pdfport asks "how do you want
--- this PDF opened?". It used to be two (this module plus a hand-maintained
--- copy inside `bindings/usrcmds.lua`), which is exactly how one of them
--- silently drifts out of the other.
---
--- ## The system-application guarantee
---
--- "System application" is ALWAYS in the list — `M.choices()` appends it when
--- a caller-supplied list omits it, rather than trusting every call site to
--- remember. Rationale: whatever pdfport can do inside Neovim, handing the
--- file to the OS viewer must stay one keystroke away. It is the only entry
--- that needs no external CLI, no backend and no configuration, so it is also
--- the only entry guaranteed to work — a picker that can leave the user with
--- no working option is worse than no picker at all.
---
--- Falls back to `vim.ui.select` when lib.nvim's `kit.select` is not installed.

local M = {}

---@class PdfPort.PickerChoice
---@field label string
---@field mode PdfPort.RendererMode
---@field backend PdfPort.BackendId|nil

---The system entry, kept separate from DEFAULT_CHOICES so `M.choices()` can
---re-append it to any list that lost it.
---@type PdfPort.PickerChoice
local SYSTEM_CHOICE = { label = "System application", mode = "system", backend = nil }

---@type PdfPort.PickerChoice[]
local DEFAULT_CHOICES = {
  { label = "Buffer      (auto)", mode = "buffer", backend = nil },
  { label = "Plain text  (pdftotext)", mode = "buffer", backend = "pdftotext" },
  { label = "Markdown    (marker)", mode = "buffer", backend = "marker" },
  { label = "Markdown    (docling)", mode = "buffer", backend = "docling" },
  { label = "Markdown    (Claude AI)", mode = "buffer", backend = "claude" },
  { label = "Markdown    (Ollama AI)", mode = "buffer", backend = "ollama" },
  { label = "Float window (auto)", mode = "float", backend = nil },
  { label = "Terminal preview", mode = "terminal", backend = nil },
  SYSTEM_CHOICE,
}

---@class PdfPort.PickerOpts
---@field title? string                                  picker title (default "Open PDF as…")
---@field choices? PdfPort.PickerChoice[]                replaces the default list; the
---system entry is appended when missing (see module docs)
---@field system_first? boolean                          move "System application" to the top —
---for callers whose previous behaviour was "always the system viewer", so the
---old one-keystroke path stays the first thing under the cursor
---@field system_open? fun(path: string): nil            handle the system entry yourself
---instead of going through pdfport's `system` renderer. For embedders that
---already own an OS-opener (WSL path translation, open.nvim delegation, …)
---and want that exact code path whether or not pdfport is installed
---@field on_cancel? fun(): nil                          dismissed without choosing

---The choice list a picker will show, with the system entry guaranteed
---present. Exposed so callers can inspect or filter it — filtering cannot
---remove the system entry, it is re-appended here.
---@param opts? PdfPort.PickerOpts
---@return PdfPort.PickerChoice[]
function M.choices(opts)
  opts = opts or {}
  local list = {}
  local has_system = false
  for _, c in ipairs(opts.choices or DEFAULT_CHOICES) do
    if c.mode == "system" then has_system = true end
    list[#list + 1] = c
  end
  if not has_system then list[#list + 1] = SYSTEM_CHOICE end
  return list
end

---@internal
---`system_first` without relying on a comparison-sort's stability.
---@param list PdfPort.PickerChoice[]
---@return PdfPort.PickerChoice[]
local function system_to_front(list)
  local out = {}
  for _, c in ipairs(list) do
    if c.mode == "system" then out[#out + 1] = c end
  end
  for _, c in ipairs(list) do
    if c.mode ~= "system" then out[#out + 1] = c end
  end
  return out
end

---Ask how to open `path`, then open it that way.
---@param path string
---@param opts? PdfPort.PickerOpts
---@return nil
function M.pick_and_open(path, opts)
  opts = opts or {}
  local pdfport = require("pdfport")
  local page_range = require("pdfport.util.page_range")

  local choices = M.choices(opts)
  if opts.system_first then choices = system_to_front(choices) end

  local items = {}
  for i, c in ipairs(choices) do
    items[i] = c.label
  end

  local function on_select(_, idx)
    if not idx then return end
    local choice = choices[idx]
    if not choice then return end

    if choice.mode == "system" and type(opts.system_open) == "function" then
      opts.system_open(path)
      return
    end

    if choice.mode == "float" or choice.mode == "terminal" then
      page_range.prompt(function(pages)
        pdfport.open({
          path = path,
          mode = choice.mode,
          backend_id = choice.backend,
          focus = true,
          pages = pages,
        })
      end)
      return
    end
    pdfport.open({ path = path, mode = choice.mode, backend_id = choice.backend, focus = true })
  end

  local title = opts.title or "Open PDF as…"

  local kit_ok, kit = pcall(require, "lib.nvim.ui.kit")
  if kit_ok and type(kit.select) == "function" then
    kit.select({
      title = title,
      items = items,
      on_select = on_select,
      -- Cancelling means "never mind" — opening it anyway in some default
      -- mode would defeat the point of asking.
      on_cancel = opts.on_cancel or function() end,
    })
  else
    vim.ui.select(items, { prompt = title .. ":" }, function(_, idx)
      if idx then
        on_select(nil, idx)
      elseif opts.on_cancel then
        opts.on_cancel()
      end
    end)
  end
end

return M
