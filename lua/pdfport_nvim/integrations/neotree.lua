---@module 'pdfport_nvim.integrations.neotree'
---@brief Neo-tree integration for pdfport.nvim.
---@description
--- Usage in neotree config:
---
---   local pdfport_neo = require("pdfport_nvim.integrations.neotree")
---   opts.commands = vim.tbl_extend("force", opts.commands, pdfport_neo.commands())
---   opts.filesystem.window.mappings = vim.tbl_extend(
---     "force", opts.filesystem.window.mappings, pdfport_neo.keymaps()
---   )

local M = {}

---@param state table
---@return string|nil
local function node_path(state)
  if not state then return nil end
  local tree = state.tree
  if not tree then return nil end
  local node = tree:get_node()
  if not node then return nil end
  return node:get_id()
end

---@param path string
---@return boolean
local function is_pdf(path)
  if not path or path == "" then return false end
  return path:lower():match("%.pdf$") ~= nil
end

---@param path string
---@return nil
local function pick_mode_and_open(path)
  local pdfport = require("pdfport_nvim")

  local choices = {
    { label = "Plain text  (pdftotext)",  mode = "buffer",   backend = "pdftotext" },
    { label = "Markdown    (marker)",      mode = "buffer",   backend = "marker"    },
    { label = "Markdown    (docling)",     mode = "buffer",   backend = "docling"   },
    { label = "Markdown    (Claude AI)",   mode = "buffer",   backend = "claude"    },
    { label = "Markdown    (Ollama AI)",   mode = "buffer",   backend = "ollama"    },
    { label = "Float window (auto)",       mode = "float",    backend = nil         },
    { label = "Terminal preview",          mode = "terminal", backend = nil         },
    { label = "System application",        mode = "system",   backend = nil         },
  }

  local items = { [#choices] = nil }
  for i, c in ipairs(choices) do items[i] = c.label end

  -- Try hover_select for a richer picker; fall back to vim.ui.select
  local hover_ok, hover = pcall(require, "lib.nvim.ui.hover_select")
  local function on_select(_, idx)
    if not idx then return end
    local choice = choices[idx]
    if not choice then return end
    pdfport.open({ path = path, mode = choice.mode, backend_id = choice.backend, focus = true })
  end

  if hover_ok then
    hover.open({ title = "Open PDF as…", items = items, auto_width = true, on_select = on_select })
  else
    vim.ui.select(items, { prompt = "Open PDF as:" }, function(_, idx)
      if idx then on_select(nil, idx) end
    end)
  end
end

---@return table<string, fun(state: table): nil>
function M.commands()
  return {
    pdfport_open = function(state)
      local path = node_path(state)
      if not path or not is_pdf(path) then
        vim.notify("pdfport_nvim: not a PDF file", vim.log.levels.WARN)
        return
      end
      pick_mode_and_open(path)
    end,

    pdfport_text = function(state)
      local path = node_path(state)
      if not path or not is_pdf(path) then return end
      require("pdfport_nvim").open({ path = path, mode = "buffer", split = "vsplit", focus = true })
    end,

    pdfport_system = function(state)
      local path = node_path(state)
      if not path or not is_pdf(path) then return end
      require("pdfport_nvim").open({ path = path, mode = "system" })
    end,

    pdfport_terminal = function(state)
      local path = node_path(state)
      if not path or not is_pdf(path) then return end
      require("pdfport_nvim").open({ path = path, mode = "terminal" })
    end,
  }
end

---@return table<string, string>
function M.keymaps()
  return {
    ["<leader>po"] = "pdfport_open",
    ["<leader>pt"] = "pdfport_text",
    ["<leader>ps"] = "pdfport_system",
    ["<leader>pi"] = "pdfport_terminal",
  }
end

return M
