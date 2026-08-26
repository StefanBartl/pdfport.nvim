---@module 'pdfport.bindings.keymaps'
---@brief The five file-tree actions, declared once for every integration.
---@description
--- netrw, oil and nvim-tree bind the same five things and differ in exactly
--- one respect: how the path under the cursor is found. That one difference
--- used to be surrounded by three copies of the same forty lines, so a change
--- to what a key does had three places to be made and two places to be
--- forgotten. `M.actions(get_path)` is that shape now, parameterized by the
--- one thing that actually varies.
---
--- Binding goes through `lib.nvim.bindings.keymap`'s registry, which is what
--- makes a wrong action name in the user's table say so instead of silently
--- binding nothing. The config shape is unchanged: `false` still disables a
--- single action, `nil` still takes the default. What is new is that an
--- override may now be a *list* of keys, and that which-key gets its group
--- label from the same declaration rather than from a hand-rolled function.
---
--- neo-tree is the exception and still goes through `M.resolve`: it does not
--- take mappings via `vim.keymap.set` at all, but as a table of lhs to
--- command name that it installs itself.

local M = {}

---@class PdfPort.KeymapOpts
---@field open? string|string[]|false
---@field open_text? string|string[]|false
---@field open_system? string|string[]|false
---@field open_terminal? string|string[]|false
---@field open_batch? string|string[]|false
---@field preset? boolean  # `false` binds nothing at all
---@field which_key? table|boolean

---@type table<string, string>
M.DEFAULTS = {
  open = "<leader>po",
  open_text = "<leader>pt",
  open_system = "<leader>ps",
  open_terminal = "<leader>pi",
  open_batch = "<leader>pb",
}

---@type table<string, string>
M.DESCRIPTIONS = {
  open = "mode picker",
  open_text = "extract to buffer",
  open_system = "open with system application",
  open_terminal = "terminal image preview",
  open_batch = "batch-open selected PDFs",
}

--- Actions bound in Visual mode instead of Normal mode.
---@type table<string, boolean>
M.VISUAL_ACTIONS = {
  open_batch = true,
}

--- Declaration order: what the docs and `:checkhealth` read top to bottom.
---@type string[]
M.ORDER = { "open", "open_text", "open_system", "open_terminal", "open_batch" }

---@internal
---@param path string
---@return boolean
local function is_pdf(path)
  return path:lower():match("%.pdf$") ~= nil
end

--- The five actions, over a tree-specific path getter.
---
--- `open` is the only one that says why nothing happened: it is the key a user
--- presses on purpose, while the other three are reached from the picker it
--- opens or from a selection, where a notification per non-PDF entry would be
--- noise.
---@param get_path fun(): string|nil  # The path under the cursor, tree-specific.
---@param notify table  # A `pdfport.util.notify` instance for this integration.
---@return table<string, Lib.Keymap.Action>
function M.actions(get_path, notify)
  ---@param mode string
  ---@return fun(): nil
  local function open_as(mode)
    return function()
      local path = get_path()
      if not path or not is_pdf(path) then return end
      require("pdfport").open({
        path = path,
        mode = mode,
        split = mode == "buffer" and "vsplit" or nil,
        focus = mode == "buffer" or nil,
      })
    end
  end

  return {
    open = {
      default = M.DEFAULTS.open,
      desc = M.DESCRIPTIONS.open,
      rhs = function()
        local path = get_path()
        if not path or not is_pdf(path) then
          notify.warn("not a PDF file")
          return
        end
        require("pdfport.util.picker").pick_and_open(path)
      end,
    },
    open_text = {
      default = M.DEFAULTS.open_text,
      desc = M.DESCRIPTIONS.open_text,
      rhs = open_as("buffer"),
    },
    open_system = {
      default = M.DEFAULTS.open_system,
      desc = M.DESCRIPTIONS.open_system,
      rhs = open_as("system"),
    },
    open_terminal = {
      default = M.DEFAULTS.open_terminal,
      desc = M.DESCRIPTIONS.open_terminal,
      rhs = open_as("terminal"),
    },
    open_batch = {
      default = M.DEFAULTS.open_batch,
      desc = M.DESCRIPTIONS.open_batch,
      mode = "v",
      rhs = function()
        require("pdfport.util.batch").open_selected(get_path)
      end,
    },
  }
end

--- Bind the five actions buffer-locally in one file-tree buffer.
---@param buf integer
---@param surface string  # Which integration, so two trees keep separate records.
---@param get_path fun(): string|nil
---@param notify table
---@param opts? PdfPort.KeymapOpts
---@return Lib.Keymap.Registered[]
function M.bind(buf, surface, get_path, notify, opts)
  ---@type Lib.Keymap.Spec
  local spec = {
    which_key = { prefix = "<leader>p", group = "pdfport" },
    order = M.ORDER,
    actions = M.actions(get_path, notify),
  }
  return require("lib.nvim.bindings.keymap").register(
    "pdfport",
    spec,
    opts,
    { buffer = buf, surface = surface }
  )
end

--- Resolve the configured lhs per action.
---
--- Only neo-tree still needs this: it installs mappings itself from a table of
--- lhs to command name, so what it wants is the keys, not the binding.
---@param opts? PdfPort.KeymapOpts  nil per-field falls back to M.DEFAULTS; false disables
---@return table<string, string|false>
function M.resolve(opts)
  opts = opts or {}
  local resolved = {}
  for action, default in pairs(M.DEFAULTS) do
    local v = opts[action]
    -- A list override is legal everywhere else; neo-tree's table is keyed by
    -- lhs, so the first one is the one it can take.
    if type(v) == "table" then v = v[1] end
    resolved[action] = (v == nil) and default or v
  end
  return resolved
end

--- Label `<leader>p` for which-key.
---
--- Per-key descriptions are deliberately not sent: which-key reads the
--- mappings and their `desc` itself, so repeating them here would only give
--- one string a second place to drift from.
---@param _resolved? table  # Unused; kept so existing callers do not break.
---@return nil
function M.register_which_key(_resolved)
  require("lib.nvim.bindings.keymap.which_key").add_group({
    prefix = "<leader>p",
    group = "pdfport",
  })
end

return M
