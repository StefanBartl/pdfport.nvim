---@module 'pdfport_nvim.platform'
---@brief OS detection and external tool availability for pdfport.nvim.
---@description
--- Cached runtime checks for OS type and binary availability.
--- All checks are memoized after first evaluation.

local M = {}

local uv = vim.uv or vim.loop

---@type table<string, boolean>
local _exe_cache = {}

---@type string|nil
local _os_cache = nil

---@return "windows"|"macos"|"linux"|"unknown"
function M.os()
  if _os_cache then return _os_cache end
  local sysname = (uv.os_uname() or {}).sysname or ""
  if     sysname:match("Windows") then _os_cache = "windows"
  elseif sysname:match("Darwin")  then _os_cache = "macos"
  elseif sysname:match("Linux")   then _os_cache = "linux"
  else                                 _os_cache = "unknown"
  end
  return _os_cache
end

---@return boolean
function M.is_wsl()
  if M.os() ~= "linux" then return false end
  local f = io.open("/proc/version", "r")
  if not f then return false end
  local content = f:read("*a")
  f:close()
  return content:lower():find("microsoft") ~= nil
end

---@param exe string
---@return boolean
function M.has(exe)
  if _exe_cache[exe] ~= nil then return _exe_cache[exe] end
  local result = vim.fn.executable(exe) == 1
  _exe_cache[exe] = result
  return result
end

---@param executables string[]
---@return string|nil
function M.first_available(executables)
  for i = 1, #executables do
    if M.has(executables[i]) then return executables[i] end
  end
  return nil
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
  _os_cache       = nil
  _python_cache   = nil
  _python_resolved = false
end

return M
