---@module 'pdfport.producers.soffice'
---@brief Office (docx/odt/xlsx/pptx) → PDF producer using LibreOffice's
---@brief headless CLI.
---@description
--- The only realistic option for office formats. Heavyweight and slow on
--- its first start (LibreOffice spins up a full user profile), but one
--- invocation covers docx/odt/xlsx/pptx alike. Install: LibreOffice
--- (soffice on PATH).
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

---@return boolean
function M.available()
  return platform.has("soffice")
end

---@param req PdfPort.InternalCreateOpts
---@return PdfPort.CreateResult|nil
function M.create(req)
  local input = req.inputs[1]
  local stem = vim.fn.fnamemodify(input, ":t:r")

  local outdir = vim.fn.stdpath("cache") .. "/pdfport.nvim/tmp/soffice-" .. tostring(uv.hrtime())
  vim.fn.mkdir(outdir, "p")

  local argv = {
    "soffice",
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
