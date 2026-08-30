---@module 'pdfport.health'
---@brief :checkhealth provider for pdfport.nvim.
---@description Accessible via :checkhealth pdfport

local M = {}

local health = vim.health or require("health")
local h_ok = health.ok or health.report_ok
local h_warn = health.warn or health.report_warn
local h_err = health.error or health.report_error
local h_start = health.start or health.report_start
local h_info = health.info or health.report_info

local ok_platform, platform = pcall(require, "pdfport.platform")
local ok_registry, registry = pcall(require, "pdfport.core.registry")

---@internal
---@param name string     executable to probe on PATH
---@param required boolean  true reports missing as an error, false as a warning
---@return boolean found
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

---@internal
---Reports whether pdfport's own core modules (platform, registry, resolver,
---dispatcher) load without error.
---@return nil
local function check_core()
  h_start("pdfport: core")

  if not ok_platform then
    h_err("pdfport.platform failed to load: " .. tostring(platform))
  else
    h_ok("pdfport.platform loads")
  end

  if not ok_registry then
    h_err("pdfport.core.registry failed to load: " .. tostring(registry))
  else
    h_ok("pdfport.core.registry loads")
  end

  for _, mod in ipairs({ "pdfport", "pdfport.core.resolver", "pdfport.core.dispatcher" }) do
    local ok_mod, _ = pcall(require, mod)
    if ok_mod then
      h_ok(mod .. " loads")
    else
      h_err(mod .. " failed to load")
    end
  end
end

---@internal
---Reports availability of each extraction backend's external dependency
---(CLI tool, python module, or API key/env var).
---@return nil
local function check_backends()
  h_start("pdfport: extraction backends")

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
  local python = platform.python()
  if python then
    h_ok(python .. " found")
    if platform.has_python_module("pdfplumber") then
      h_ok("pdfplumber: available")
    else
      h_warn("pdfplumber: not installed  (pip install pdfplumber)")
    end
  else
    h_warn("no python interpreter found (python3/python/py) – pdfplumber/docling unavailable")
  end

  -- marker
  --
  -- Not in `docs/install.json`, and that is not an oversight: `marker-pdf` is
  -- a pip package with no OS-package-manager entry anywhere, so a spec entry
  -- would need a `pkg` map it cannot honestly fill and `:Lib deps install`
  -- would compose a command that fails. Same line the spec already draws
  -- around pdfplumber and docling, which are probed here and declared
  -- nowhere for the same reason.
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
    local out =
      vim.fn.system({ "curl", "-s", "-w", "\n%{http_code}", "http://localhost:11434/api/tags" })
    local code = out and out:match("(%d%d%d)%s*$")
    if code == "200" then
      h_ok("ollama daemon running on localhost:11434")
    else
      h_warn("ollama daemon not running  (ollama serve)")
    end
  else
    h_warn("ollama: not installed (optional)")
  end

  -- tesseract
  if check_exe("tesseract", false) then
    h_ok("tesseract backend: ready (requires pdftoppm too)")
  else
    h_warn("tesseract backend: not on PATH  (install tesseract-ocr)")
  end

  -- claude
  --
  -- `false`, not `true`: curl is optional. Only the claude backend and the
  -- ollama daemon check use it, both optional, and `backends/claude.lua`'s
  -- own `available()` returns false without it rather than failing. Reporting
  -- it as required made one `:checkhealth pdfport` run contradict itself --
  -- an error here, a warning three sections down where `docs/install.json`
  -- declares `required: false`. The spec was the half that was right.
  if check_exe("curl", false) then
    local key = vim.env.ANTHROPIC_API_KEY
    if key and key ~= "" then
      h_ok("ANTHROPIC_API_KEY set (" .. #key .. " chars)")
    else
      h_warn("ANTHROPIC_API_KEY not set – claude backend unavailable")
      h_info("Set: export ANTHROPIC_API_KEY=sk-ant-...")
    end
    -- The claude backend encodes in-process via vim.base64.encode now; the
    -- external `base64` binary is no longer involved (and never existed on
    -- Windows, nor supported `-w 0` on macOS).
    if type(vim.base64) == "table" and type(vim.base64.encode) == "function" then
      h_ok("vim.base64.encode available (used for PDF encoding)")
    else
      h_warn("vim.base64.encode missing - needs Neovim 0.10+ for the claude backend")
    end
  end
end

---@internal
---Reports availability of each creation producer's external dependency
---(img2pdf: Python module/CLI; magick: ImageMagick CLI).
---@return nil
local function check_producers()
  h_start("pdfport: creation producers")

  if not ok_platform then
    h_err("platform module unavailable – cannot check tool executables")
    return
  end

  if check_exe("img2pdf", false) then
    h_ok("img2pdf producer: ready (lossless image -> PDF)")
  else
    h_warn("img2pdf producer: not on PATH  (pip install img2pdf)")
  end

  if check_exe("magick", false) then
    h_ok("magick producer: ready (image -> PDF, ImageMagick)")
  else
    h_warn("magick producer: not on PATH  (install ImageMagick)")
  end

  if check_exe("pandoc", false) then
    local engine =
      platform.first_available({ "tectonic", "typst", "xelatex", "lualatex", "pdflatex" })
    if engine then
      h_ok("pandoc producer: ready (markdown/text -> PDF, engine: " .. engine .. ")")
    else
      h_warn("pandoc producer: pandoc found but no PDF engine on PATH")
      h_info("Install one of: tectonic, typst, xelatex, lualatex, pdflatex")
    end
  else
    h_warn("pandoc producer: not on PATH  (install pandoc)")
  end

  if check_exe("weasyprint", false) then
    h_ok("weasyprint producer: ready (html -> PDF)")
  else
    h_warn("weasyprint producer: not on PATH  (pip install weasyprint)")
  end

  local browser = platform.first_available({
    "chromium",
    "chromium-browser",
    "google-chrome",
    "chrome",
    "msedge",
  })
  if browser then
    h_ok("chromium producer: ready (html -> PDF, browser: " .. browser .. ")")
  else
    h_warn("chromium producer: no Chromium-family browser on PATH (optional html fallback)")
  end

  if check_exe("soffice", false) then
    h_ok("soffice producer: ready (office -> PDF)")
  else
    h_warn("soffice producer: not on PATH  (install LibreOffice)")
  end

  h_start("pdfport: merge producers (pdfport.merge())")

  if check_exe("qpdf", false) then
    h_ok("qpdf producer: ready (pdf merge)")
  else
    h_warn("qpdf producer: not on PATH  (install qpdf)")
  end

  if check_exe("pdftk", false) then
    h_ok("pdftk producer: ready (pdf merge)")
  else
    h_warn("pdftk producer: not on PATH  (install pdftk)")
  end

  local gs = platform.first_available({ "gs", "gswin64c", "gswin32c" })
  if gs then
    h_ok("ghostscript producer: ready (pdf merge, exe: " .. gs .. ")")
  else
    h_warn("ghostscript producer: no gs/gswin64c/gswin32c on PATH (last-resort merge fallback)")
  end
end

---@internal
---Reports availability of each render mode, including the terminal-image tool detection.
---@return nil
local function check_renderers()
  h_start("pdfport: renderers")

  if not ok_platform then
    h_err("platform module unavailable")
    return
  end

  h_ok("buffer renderer: built-in")
  h_ok("float renderer: built-in")

  local sys = platform.open_cmd()
  if sys then
    h_ok("system renderer: " .. sys)
  else
    h_err("system renderer: no open command found")
  end

  h_start("pdfport: terminal image renderer")
  check_exe("pdftoppm", false)

  local tool = platform.best_terminal_renderer()
  if tool then
    h_ok("best renderer: " .. tool)
  else
    h_warn("no terminal image renderer found")
    h_info("Install one of: chafa, ueberzugpp, kitten, imgcat")
  end

  check_exe("ueberzugpp", false)
  check_exe("chafa", false)
end

---@internal
---Reports which file-tree/picker plugins are present and whether lib.nvim
---(a hard dependency for :PdfPort) is installed.
---@return nil
local function check_integrations()
  h_start("pdfport: integrations")

  local function probe(mod, label)
    local found, _ = pcall(require, mod)
    if found then
      h_ok(label .. " found – integration available")
    else
      h_info(label .. " not loaded – integration inactive")
    end
  end

  probe("neo-tree", "neo-tree.nvim")
  probe("nvim-tree.api", "nvim-tree")
  probe("oil", "oil.nvim")
  probe("telescope", "telescope.nvim")
  probe("fzf-lua", "fzf-lua")
  probe("which-key", "which-key.nvim")

  -- netrw is built-in, always available
  h_ok("netrw: built-in (always available)")

  -- lib.nvim itself is required (the :PdfPort command is built on
  -- lib.nvim.bindings.usercmd.composer); lib.nvim.ui.kit stays a soft enhancement.
  local composer_ok = pcall(require, "lib.nvim.bindings.usercmd.composer")
  if composer_ok then
    h_ok("lib.nvim found – :PdfPort available")
  else
    h_err('lib.nvim not found – :PdfPort will fail to load; install "StefanBartl/lib.nvim"')
  end

  local kit_ok, _ = pcall(require, "lib.nvim.ui.kit")
  if kit_ok then
    h_ok("lib.nvim.ui.kit found – enhanced mode picker active")
  else
    h_info("lib.nvim.ui.kit not found – using vim.ui.select fallback")
  end
end

---@internal
---Reports per-backend availability from the live registry, which only has
---entries once require("pdfport").setup() has run.
---@return nil
local function check_registry_state()
  h_start("pdfport: registered backends")

  if not ok_registry then
    h_warn("registry unavailable – call require('pdfport').setup() first")
    return
  end

  local backends = registry.all_backends and registry.all_backends() or {}
  if #backends == 0 then
    h_warn("No backends registered – call require('pdfport').setup() first")
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

  h_start("pdfport: registered producers")

  local producers = registry.all_producers and registry.all_producers() or {}
  if #producers == 0 then
    h_warn("No producers registered – call require('pdfport').setup() first")
    return
  end

  for _, p in ipairs(producers) do
    local avail_ok, avail = pcall(p.available)
    if avail_ok and avail then
      h_ok(string.format("%-14s  available", p.id))
    else
      h_warn(string.format("%-14s  unavailable", p.id))
    end
  end
end

---@internal
---Reports pdfport's own docs/install.json via lib.nvim.deps — the same
---tools check_backends() already probes, but with each tool's declared
---`why` and a pointer to `:Lib deps show pdfport.nvim` for the install
---command. Silently does nothing if lib.nvim.deps isn't available (older
---lib.nvim) or pdfport ships no spec.
---@return nil
local function check_deps()
  local ok_deps, deps_health = pcall(require, "lib.nvim.deps.health")
  if not ok_deps then return end
  h_start("pdfport: declared tools (lib.nvim.deps)")
  deps_health.report_for("pdfport.nvim")
end

---Runs all :checkhealth pdfport sections: core, backends, renderers,
---integrations, declared-tools (lib.nvim.deps), and the live registry state.
---@return nil
function M.check()
  check_core()
  check_backends()
  check_producers()
  check_renderers()
  check_integrations()
  check_deps()
  check_registry_state()

  require("lib.nvim.bindings.usercmd.composer").checkhealth("PdfPort")
end

return M
