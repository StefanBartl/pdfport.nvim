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

---@param prefix string
---@return { info: fun(msg: string): nil, warn: fun(msg: string): nil, error: fun(msg: string): nil, debug: fun(msg: string, cfg: table): nil }
function M.create(prefix)
  local notifier = lib_notify.create(prefix)

  return {
    info = notifier.info,
    warn = notifier.warn,
    error = notifier.error,
    debug = function(msg, cfg)
      if cfg and cfg.debug then
        notifier.debug(msg)
      end
    end,
  }
end

return M
