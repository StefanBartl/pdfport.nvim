---@module 'pdfport.renderers.system'
---@brief Opens a PDF with the operating system's default application.

local M        = {}
local platform = require("pdfport.platform")
local notify   = require("pdfport.util.notify").create("[pdfport.system]")

---@param _result PdfPort.Result
---@param opts PdfPort.OpenOpts
---@return nil
function M.render(_result, opts)
  local path = opts.path
  if not path or path == "" then
    notify.error("no path provided")
    return
  end

  local cmd = platform.open_cmd()
  if not cmd then
    notify.error("no system open command found")
    return
  end

  vim.fn.jobstart({ cmd, path }, {
    detach = true,
    on_exit = function(_, code, _)
      if code ~= 0 then
        notify.warn(string.format("%s exited with code %d", cmd, code))
      end
    end,
  })
end

return M
