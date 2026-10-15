---@module 'pdfport.producers.soffice'
---@brief Office (docx/odt/xlsx/pptx) → PDF producer using LibreOffice's
---@brief headless CLI.
---@description
--- The only realistic option for office formats. Heavyweight and slow on
--- its first start (LibreOffice spins up a full user profile), but one
--- invocation covers docx/odt/xlsx/pptx alike. Install: LibreOffice. The binary is
--- resolved through `lib.nvim.deps` like the browser of the chromium producer: on the PATH,
--- else at one of the `paths` that `docs/install.json` declares for `soffice` (the Windows
--- installer does not put LibreOffice on the PATH).
---
--- `--convert-to pdf --outdir <dir>` always writes `<stem>.pdf` next to the
--- input inside `<dir>` — soffice does not accept an explicit output
--- filename — so this producer converts into a scratch dir and renames the
--- result to `req.output` itself.

local uv = vim.uv or vim.loop
local platform = require("pdfport.platform")
local spawn_capture = require("lib.nvim.cross.uv.spawn_capture")

--- See the note on `Producer` in `@types/init.lua`: declared as a class so
--- the methods defined below the literal count as implementing it.
---@class PdfPort.Producer.Soffice : PdfPort.Producer
local M = {
  id = "soffice",
  name = "soffice (LibreOffice)",
  accepts = { "office" },
  capabilities = {
    batch = false,
    lossless = false,
    styling = false,
    toc = false,
    remote = false,
  },
}

---@internal
--- The binary, resolved through `lib.nvim.deps.require_tool`: this plugin's own `soffice` declaration in
--- `docs/install.json` is the single source of truth that `M.available()`, `M.create()` and
--- `pdfport.health` all resolve through. `silent`: a miss is reported by the callers (the result's
--- `error`, `:checkhealth pdfport`).
---@return string|nil
local function resolve_soffice()
  local ok, deps = pcall(require, "lib.nvim.deps")
  if not ok then
    -- a lib.nvim without `deps` (an old one): the PATH, as before this producer used the declared paths
    return platform.has("soffice") and "soffice" or nil
  end
  return deps.require_tool("pdfport.nvim", "soffice", { silent = true })
end

--- The binary `M.create()` would run, or nil -- the same probe, not a second copy of it. Public so
--- `:checkhealth pdfport` can name the exact binary this producer would use.
---@return string|nil
function M.resolved_binary()
  return resolve_soffice()
end

---@return boolean
function M.available()
  return resolve_soffice() ~= nil
end

---@param req PdfPort.InternalCreateOpts
---@return PdfPort.CreateResult|nil
function M.create(req)
  local binary = resolve_soffice()
  if not binary then
    local result = {
      status = "error",
      path = nil,
      producer = "soffice",
      pages = nil,
      error = "soffice: LibreOffice not found (soffice on the PATH, or installed in its default folder)",
    }
    if type(req.__callback) == "function" then req.__callback(result) end
    return nil
  end

  local input = req.inputs[1]
  local stem = vim.fn.fnamemodify(input, ":t:r")

  local outdir = vim.fn.stdpath("cache") .. "/pdfport.nvim/tmp/soffice-" .. tostring(uv.hrtime())
  vim.fn.mkdir(outdir, "p")

  local argv = {
    binary,
    "--headless",
    "--convert-to",
    "pdf",
    "--outdir",
    outdir,
    input,
  }

  local timeout_ms = req.timeout_ms or 60000

  local function cleanup()
    pcall(vim.fn.delete, outdir, "rf")
  end

  spawn_capture(argv, { timeout_ms = timeout_ms }, function(spawn_result)
    local result
    if spawn_result.timed_out then
      result = {
        status = "error",
        path = nil,
        producer = "soffice",
        pages = nil,
        error = string.format("soffice: timed out after %d ms", timeout_ms),
      }
    elseif not spawn_result.ok then
      result = {
        status = "error",
        path = nil,
        producer = "soffice",
        pages = nil,
        error = string.format("soffice exited %d: %s", spawn_result.code, spawn_result.stderr),
      }
    else
      local produced = outdir .. "/" .. stem .. ".pdf"
      if uv.fs_stat(produced) == nil then
        result = {
          status = "error",
          path = nil,
          producer = "soffice",
          pages = nil,
          error = "soffice: conversion reported success but no output file was found",
        }
      else
        local ok_rename = uv.fs_rename(produced, req.output)
        if ok_rename then
          result =
            { status = "ok", path = req.output, producer = "soffice", pages = nil, error = nil }
        else
          result = {
            status = "error",
            path = nil,
            producer = "soffice",
            pages = nil,
            error = string.format("soffice: could not move output to %s", req.output),
          }
        end
      end
    end
    cleanup()
    if type(req.__callback) == "function" then req.__callback(result) end
  end)

  return nil
end

return M
