---@module 'pdfport.util.trace'
---@brief The debug trace of a dispatch or a create: one line per call, only when `config.debug` is on.
---@description
--- `emit` takes a function that builds the line, not the line: with `debug` off the function is never
--- called, so the path shortening and the string formatting cost nothing. lib.nvim has no gate-able
--- `debug` (see `util/notify.lua`), so the gate stays local.

local M = {}

---@type PdfPort.Notifier|nil
local notifier

---Send the line `build()` returns, when `cfg.debug` is truthy.
---@param cfg PdfPort.Config|nil
---@param build fun(): string
---@return nil
function M.emit(cfg, build)
  if not (cfg and cfg.debug) then return end
  notifier = notifier or require("pdfport.util.notify").create("[pdfport]")
  notifier.debug(build(), cfg)
end

---Milliseconds since `t0` (a `uv.hrtime()` value).
---@param t0 integer
---@return number
function M.ms_since(t0)
  return ((vim.uv or vim.loop).hrtime() - t0) / 1e6
end

---A path for a one-line trace: home-relative, and cut from the left when long.
---@param path string
---@return string
function M.short(path)
  local p = vim.fn.fnamemodify(path, ":~")
  if #p > 60 then p = "..." .. p:sub(-57) end
  return p
end

return M
