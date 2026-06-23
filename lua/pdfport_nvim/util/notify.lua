---@module 'pdfport_nvim.util.notify'
---@brief Lightweight vim.notify wrapper for pdfport.nvim.

local M = {}

---@param prefix string
---@return { info: fun(msg: string): nil, warn: fun(msg: string): nil, error: fun(msg: string): nil, debug: fun(msg: string, cfg: table): nil }
function M.create(prefix)
  local function notify(msg, level)
    vim.notify(prefix .. " " .. msg, level)
  end

  return {
    info  = function(msg) notify(msg, vim.log.levels.INFO)  end,
    warn  = function(msg) notify(msg, vim.log.levels.WARN)  end,
    error = function(msg) notify(msg, vim.log.levels.ERROR) end,
    debug = function(msg, cfg)
      if cfg and cfg.debug then notify(msg, vim.log.levels.DEBUG) end
    end,
  }
end

return M
