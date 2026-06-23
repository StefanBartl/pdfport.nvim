---@module 'pdfport_nvim.health'
---@brief :checkhealth provider for pdfport.nvim.
---@description Accessible via :checkhealth pdfport_nvim

local M = {}

local health  = vim.health or require("health")
local h_ok    = health.ok    or health.report_ok
local h_warn  = health.warn  or health.report_warn
local h_err   = health.error or health.report_error
local h_start = health.start or health.report_start
local h_info  = health.info  or health.report_info

local ok_platform, platform = pcall(require, "pdfport_nvim.platform")
local ok_registry, registry = pcall(require, "pdfport_nvim.core.registry")

local function check_exe(name, required)
  if not ok_platform then return false end
  if platform.has(name) then
    h_ok(name .. " found on PATH")
    return true
  end
  if required then
    h_err(name .. " NOT found on PATH (required)")
  else
    h_warn(name .. " NOT found on PATH (optional)")
  end
  return false
end

local function check_core()
  h_start("pdfport_nvim: core")

  if not ok_platform then
    h_err("pdfport_nvim.platform failed to load: " .. tostring(platform))
  else
    h_ok("pdfport_nvim.platform loads")
  end

  if not ok_registry then
    h_err("pdfport_nvim.core.registry failed to load: " .. tostring(registry))
  else
    h_ok("pdfport_nvim.core.registry loads")
  end

  for _, mod in ipairs({ "pdfport_nvim", "pdfport_nvim.core.resolver", "pdfport_nvim.core.dispatcher" }) do
    local ok_mod, _ = pcall(require, mod)
    if ok_mod then h_ok(mod .. " loads") else h_err(mod .. " failed to load") end
  end
end

local function check_backends()
  h_start("pdfport_nvim: extraction backends")

  if not ok_platform then
    h_err("platform module unavailable – cannot check tool executables")
    return
  end

  -- pdftotext
  if check_exe("pdftotext", false) then
    h_ok("pdftotext backend: ready")
  else
    h_warn("pdftotext backend: install poppler-utils")
  end

  -- pdfplumber
  if platform.has("python3") then
    h_ok("python3 found")
    if platform.has_python_module("pdfplumber") then
      h_ok("pdfplumber: available")
    else
      h_warn("pdfplumber: not installed  (pip install pdfplumber)")
    end
  else
    h_warn("python3 NOT found – pdfplumber/docling/marker unavailable")
  end

  -- marker
  if check_exe("marker_single", false) then
    h_ok("marker backend: ready")
  else
    h_warn("marker backend: marker_single not on PATH  (pip install marker-pdf)")
  end

  -- docling
  if platform.has("python3") then
    if platform.has_python_module("docling") then
      h_ok("docling: available")
    else
      h_warn("docling: not installed  (pip install docling)")
    end
  end

  -- ollama
  if check_exe("ollama", false) then
    h_ok("ollama binary found")
    local code = vim.fn.system("curl -s -o /dev/null -w '%{http_code}' http://localhost:11434/api/tags 2>/dev/null")
    if code and code:match("^200") then
      h_ok("ollama daemon running on localhost:11434")
    else
      h_warn("ollama daemon not running  (ollama serve)")
    end
  else
    h_warn("ollama: not installed (optional)")
  end

  -- claude
  if check_exe("curl", true) then
    local key = vim.env.ANTHROPIC_API_KEY
    if key and key ~= "" then
      h_ok("ANTHROPIC_API_KEY set (" .. #key .. " chars)")
    else
      h_warn("ANTHROPIC_API_KEY not set – claude backend unavailable")
      h_info("Set: export ANTHROPIC_API_KEY=sk-ant-...")
    end
    if check_exe("base64", false) then
      h_ok("base64 binary found (required for claude backend)")
    else
      h_warn("base64 not found – claude backend will fail on PDF encode")
    end
  end
end

local function check_renderers()
  h_start("pdfport_nvim: renderers")

  if not ok_platform then h_err("platform module unavailable"); return end

  h_ok("buffer renderer: built-in")
  h_ok("float renderer: built-in")

  local sys = platform.open_cmd()
  if sys then h_ok("system renderer: " .. sys) else h_err("system renderer: no open command found") end

  h_start("pdfport_nvim: terminal image renderer")
  check_exe("pdftoppm", false)

  local tool = platform.best_terminal_renderer()
  if tool then
    h_ok("best renderer: " .. tool)
  else
    h_warn("no terminal image renderer found")
    h_info("Install one of: chafa, ueberzugpp, kitten, imgcat")
  end

  check_exe("ueberzugpp", false)
  check_exe("chafa",      false)
end

local function check_integrations()
  h_start("pdfport_nvim: integrations")

  local function probe(mod, label)
    local found, _ = pcall(require, mod)
    if found then h_ok(label .. " found – integration available")
    else          h_info(label .. " not loaded – integration inactive") end
  end

  probe("neo-tree",           "neo-tree.nvim")
  probe("nvim-tree.api",      "nvim-tree")
  probe("oil",                "oil.nvim")
  probe("telescope",          "telescope.nvim")
  probe("fzf-lua",            "fzf-lua")

  -- netrw is built-in, always available
  h_ok("netrw: built-in (always available)")

  local hover_ok, _ = pcall(require, "lib.nvim.ui.hover_select")
  if hover_ok then
    h_ok("lib.nvim.ui.hover_select found – enhanced mode picker active")
  else
    h_info("lib.nvim.ui.hover_select not found – using vim.ui.select fallback")
  end
end

local function check_registry_state()
  h_start("pdfport_nvim: registered backends")

  if not ok_registry then
    h_warn("registry unavailable – call require('pdfport_nvim').setup() first")
    return
  end

  local backends = registry.all_backends and registry.all_backends() or {}
  if #backends == 0 then
    h_warn("No backends registered – call require('pdfport_nvim').setup() first")
    return
  end

  for _, b in ipairs(backends) do
    local avail_ok, avail = pcall(b.available)
    if avail_ok and avail then
      h_ok(string.format("%-14s  available", b.id))
    else
      h_warn(string.format("%-14s  unavailable", b.id))
    end
  end
end

function M.check()
  check_core()
  check_backends()
  check_renderers()
  check_integrations()
  check_registry_state()
end

return M
