---@module 'pdfport.platform'
---@brief OS detection and external tool availability for pdfport.nvim.
---@description
--- Cached runtime checks for OS type and binary availability.
--- All checks are memoized after first evaluation.

local M = {}

-- OS/WSL detection delegates to lib.nvim.cross.platform (uname + env-var +
-- /proc fallback chain — more robust than a single sysname match / a single
-- /proc/version read, and cached internally there too).
local lib_is_windows = require("lib.nvim.cross.platform.is_windows")
local lib_is_macos   = require("lib.nvim.cross.platform.is_macos")
local lib_is_linux   = require("lib.nvim.cross.platform.is_linux")
local lib_is_wsl     = require("lib.nvim.cross.platform.is_wsl")

---@type table<string, boolean>
local _exe_cache = {}

---@return "windows"|"macos"|"linux"|"unknown"
function M.os()
  if lib_is_windows() then return "windows" end
  if lib_is_macos() then return "macos" end
  if lib_is_linux() or lib_is_wsl() then return "linux" end
  return "unknown"
end

---@return boolean
function M.is_wsl()
  return lib_is_wsl()
end

-- has/first_available delegate to lib.nvim.core, which memoizes per binary
-- name internally (this module's own version re-checked vim.fn.executable
-- every call for names not yet in _exe_cache). _exe_cache itself stays —
-- it's still used below for has_python_module's "pymod:<module>" checks,
-- a different kind of probe (shells out to `python -c "import module"`).

---@param exe string
---@return boolean
function M.has(exe)
  return require("lib.nvim.core").has_exec(exe)
end

---@param executables string[]
---@return string|nil
function M.first_available(executables)
  return require("lib.nvim.core").first_available(executables)
end

---@type string|nil
local _python_cache = nil
---@type boolean
local _python_resolved = false

---@return string|nil
function M.python()
  if _python_resolved then return _python_cache end
  _python_resolved = true
  _python_cache = M.first_available({ "python3", "python", "py" })
  return _python_cache
end

---@param module string
---@return boolean
function M.has_python_module(module)
  local cache_key = "pymod:" .. module
  if _exe_cache[cache_key] ~= nil then return _exe_cache[cache_key] end
  local python = M.python()
  if not python then
    _exe_cache[cache_key] = false
    return false
  end
  vim.fn.system({ python, "-c", "import " .. module })
  local result = (vim.v.shell_error == 0)
  _exe_cache[cache_key] = result
  return result
end

---@return string|nil
function M.open_cmd()
  local os = M.os()
  if     os == "macos"   then return "open"
  elseif os == "windows" then return "start"
  else   return M.first_available({ "xdg-open", "wsl-open" })
  end
end

---@return "ueberzug"|"chafa"|"kitty"|"imgcat"|nil
function M.best_terminal_renderer()
  if M.has("ueberzugpp") or M.has("ueberzug") then return "ueberzug" end
  local term      = vim.env.TERM or ""
  local term_prog = vim.env.TERM_PROGRAM or ""
  if term == "xterm-kitty" or term_prog == "kitty" then
    if M.has("kitten") or M.has("kitty") then return "kitty" end
  end
  if M.has("imgcat") then return "imgcat" end
  if M.has("chafa")  then return "chafa"  end
  return nil
end

function M.reset_cache()
  _exe_cache      = {}
  _python_cache   = nil
  _python_resolved = false
end

return M
