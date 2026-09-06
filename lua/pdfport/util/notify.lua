---@module 'pdfport.util.notify'
---@brief Lightweight vim.notify wrapper for pdfport.nvim.
---@description
--- Delegates prefixing and level dispatch to lib.nvim.notify.create(prefix)
--- (same "<prefix> <msg>" shape this module already used). `debug(msg, cfg)`
--- has no lib.nvim.notify equivalent — it only emits when `cfg.debug` is
--- truthy, a plugin-specific gate lib.nvim's own always-emit `.debug()`
--- doesn't have — so it stays a thin wrapper around the delegated notifier.

local lib_notify = require("lib.nvim.notify")

local M = {}

--- What `M.create` hands back.
---
--- A named class rather than the inline table type this used to carry: inside
--- a table literal a `fun(...): nil` swallows everything after its return
--- type, so LuaLS only ever saw the `info` field. `warn`, `error` and `debug`
--- then read as undefined at every call site.
---@class PdfPort.Notifier
---@field info  fun(msg: string): nil
---@field warn  fun(msg: string): nil
---@field error fun(msg: string): nil
---@field debug fun(msg: string, cfg: table): nil  Emits only when `cfg.debug` is truthy.

---@param prefix string
---@return PdfPort.Notifier
function M.create(prefix)
  local notifier = lib_notify.create(prefix)

  return {
    info = notifier.info,
    warn = notifier.warn,
    error = notifier.error,
    debug = function(msg, cfg)
      if cfg and cfg.debug then notifier.debug(msg) end
    end,
  }
end

return M
