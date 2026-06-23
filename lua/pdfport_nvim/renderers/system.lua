---@module 'pdfport_nvim.renderers.system'
---@brief Opens a PDF with the operating system's default application.

local M        = {}
local platform = require("pdfport_nvim.platform")

---@param _result PdfPort.Result
---@param opts PdfPort.OpenOpts
---@return nil
function M.render(_result, opts)
  local path = opts.path
  if not path or path == "" then
    vim.notify("pdfport_nvim system: no path provided", vim.log.levels.ERROR)
    return
  end

  local cmd = platform.open_cmd()
  if not cmd then
    vim.notify("pdfport_nvim system: no system open command found", vim.log.levels.ERROR)
    return
  end

  vim.fn.jobstart({ cmd, path }, {
    detach = true,
    on_exit = function(_, code, _)
      if code ~= 0 then
        vim.notify(
          string.format("pdfport_nvim system: %s exited with code %d", cmd, code),
          vim.log.levels.WARN
        )
      end
    end,
  })
end

return M
