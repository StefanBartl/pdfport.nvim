---@module 'pdfport.renderers.system'
---@brief Opens a PDF with the operating system's default application.
---@description
--- Dispatch is delegated to lib.nvim.cross.open_default — the shared helper
--- that already handles Windows/WSL/macOS/Linux correctly, including the
--- `cmd.exe /C start` quoting/tokenizing hazard (it uses `explorer.exe` on
--- native Windows, never a bare `start`, which is a cmd.exe built-in and not
--- an executable jobstart/libuv could spawn without a shell). It spawns the
--- viewer detached, so it outlives Neovim.

local M = {}
local open_default = require("lib.nvim.cross.open_default")
local notify = require("pdfport.util.notify").create("[pdfport.system]")

---@param _result PdfPort.Result
---@param opts PdfPort.OpenOpts
---@return nil
function M.render(_result, opts)
  local path = opts.path
  if not path or path == "" then
    notify.error("no path provided")
    return
  end

  local ok, err = open_default(path)
  if not ok then
    notify.error(err or "could not open the PDF with the system default application")
  end
end

return M
