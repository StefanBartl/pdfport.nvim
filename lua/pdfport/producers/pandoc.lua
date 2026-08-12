---@module 'pdfport.producers.pandoc'
---@brief Markdown/text → PDF producer using the pandoc CLI.
---@description
--- pandoc is a converter, not a PDF engine — it always needs one behind it.
--- Engine search order (unless `pdf_engine` is set to something other than
--- "auto"): tectonic (self-fetches TeX packages, no 4GB TeXLive) → typst
--- (pandoc >= 3.1.11 supports --pdf-engine=typst) → xelatex → lualatex →
--- pdflatex. Install: apt/brew/winget install pandoc, plus one engine.

local platform = require("pdfport.platform")
local spawn_capture = require("lib.nvim.cross.uv.spawn_capture")
local spawn_env = require("pdfport.util.spawn_env")

---@type PdfPort.ConfigurableProducer
local M = {
  id = "pandoc",
  name = "pandoc",
  accepts = { "markdown", "text" },
  capabilities = {
    batch = false,
    lossless = false,
    styling = true,
    toc = true,
    remote = false,
  },
}

---@type PdfPort.Config|nil
local _config = nil

---@param cfg PdfPort.Config
---@return nil
function M._set_config(cfg)
  _config = cfg
end

---@internal Order matters: earlier engines are cheaper/lighter to have installed.
local ENGINE_CHAIN = { "tectonic", "typst", "xelatex", "lualatex", "pdflatex" }

---@internal
---@return string|nil
local function resolve_engine()
  local preferred = _config and _config.pdf_engine
  if preferred and preferred ~= "auto" then return platform.has(preferred) and preferred or nil end
  for _, engine in ipairs(ENGINE_CHAIN) do
    if platform.has(engine) then return engine end
  end
  return nil
end

---@return boolean
function M.available()
  return platform.has("pandoc") and resolve_engine() ~= nil
end

---@param req PdfPort.InternalCreateOpts
---@return PdfPort.CreateResult|nil
function M.create(req)
  local engine = resolve_engine()
  if not engine then
    local result = {
      status = "error",
      path = nil,
      producer = "pandoc",
      pages = nil,
      error = "pandoc: no PDF engine found (tectonic/typst/xelatex/lualatex/pdflatex)",
    }
    if type(req.__callback) == "function" then req.__callback(result) end
    return nil
  end

  local input = req.inputs[1]
  -- Relative image paths in the source break once pandoc compiles from a
  -- temp dir (text/bufnr inputs) — anchor resource resolution back to the
  -- source file's own directory.
  local resource_dir = vim.fn.fnamemodify(input, ":h")

  local argv = {
    "pandoc",
    input,
    "-o",
    req.output,
    "--pdf-engine=" .. engine,
    "--resource-path=" .. resource_dir,
  }
  if req.toc then argv[#argv + 1] = "--toc" end
  if req.title and req.title ~= "" then
    argv[#argv + 1] = "--metadata"
    argv[#argv + 1] = "title=" .. req.title
  end
  if req.template and req.template ~= "" then
    argv[#argv + 1] = "--template"
    argv[#argv + 1] = req.template
  end

  local timeout_ms = req.timeout_ms or 60000

  spawn_capture(argv, { timeout_ms = timeout_ms, env = spawn_env.array() }, function(spawn_result)
    local result
    if spawn_result.timed_out then
      result = {
        status = "error",
        path = nil,
        producer = "pandoc",
        pages = nil,
        error = string.format("pandoc: timed out after %d ms", timeout_ms),
      }
    elseif spawn_result.ok then
      result = {
        status = "ok",
        path = req.output,
        producer = "pandoc",
        pages = nil,
        error = nil,
      }
    else
      result = {
        status = "error",
        path = nil,
        producer = "pandoc",
        pages = nil,
        error = string.format("pandoc exited %d: %s", spawn_result.code, spawn_result.stderr),
      }
    end
    if type(req.__callback) == "function" then req.__callback(result) end
  end)

  return nil
end

return M
