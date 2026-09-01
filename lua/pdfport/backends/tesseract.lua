---@module 'pdfport.backends.tesseract'
---@brief OCR fallback backend for scanned/image-only PDFs using tesseract.
---@description
--- Rasterizes each requested page via pdftoppm, then runs tesseract OCR on
--- the page image and concatenates the recognized text. Unlike the other
--- backends' capabilities.ocr = true (marker/docling/ollama/claude), this
--- one has no other extraction ability — it exists purely as an OCR
--- fallback for PDFs where the text-layer backends return nothing useful.
--- Install: apt install tesseract-ocr poppler-utils | brew install tesseract poppler | winget install tesseract poppler

local platform = require("pdfport.platform")
local spawn_capture = require("lib.nvim.cross.uv.spawn_capture")

--- See the note on `Backend` in `@types/init.lua`: declared as a class so
--- the methods defined below the literal count as implementing it.
---@class PdfPort.Backend.Tesseract : PdfPort.Backend
local M = {
  id = "tesseract",
  name = "tesseract (OCR fallback)",
  capabilities = {
    markdown = false,
    tables = false,
    ocr = true,
    remote = false,
    gpu_optional = false,
  },
}

---@return boolean
function M.available()
  return platform.has("tesseract") and platform.has("pdftoppm")
end

---@param path string
---@param opts PdfPort.InternalExtractOpts
---@return PdfPort.Result|nil
function M.extract(path, opts)
  local dpi = 300
  local timeout_ms = opts.timeout_ms or 60000

  -- Two things at once. The default is the initialiser rather than a trailing
  -- `else`, because declared bare `pages` reads as maybe-nil inside
  -- `process_next` below -- a closure does not carry the narrowing the
  -- branches established. And `opts.pages` goes through a local, because
  -- narrowing a *field* does not carry into the assignment that follows it.
  ---@type integer[]
  local pages = { 1 }
  local requested = opts.pages
  if requested and #requested > 0 then
    pages = requested
  elseif opts.max_pages then
    pages = {}
    for i = 1, opts.max_pages do
      pages[i] = i
    end
  end

  local page_texts = {}
  local page_idx = 1

  ---@param msg string
  ---@return nil
  local function finish_error(msg)
    local result = {
      status = "error",
      text = nil,
      format = "plain",
      backend = "tesseract",
      pages_processed = page_idx - 1,
      error = msg,
    }
    if type(opts.__callback) == "function" then opts.__callback(result) end
  end

  local function process_next()
    if page_idx > #pages then
      local result = {
        status = "ok",
        text = table.concat(page_texts, "\n\n"),
        format = "plain",
        backend = "tesseract",
        pages_processed = #pages,
        error = nil,
      }
      local cb = opts.__callback
      if type(cb) == "function" then cb(result) end
      return
    end

    local page = pages[page_idx]
    page_idx = page_idx + 1

    local tmp = vim.fn.tempname()
    local argv_raster = {
      "pdftoppm",
      "-png",
      "-r",
      tostring(dpi),
      "-f",
      tostring(page),
      "-l",
      tostring(page),
      "-singlefile",
      path,
      tmp,
    }

    spawn_capture(argv_raster, { timeout_ms = timeout_ms }, function(raster_result)
      if raster_result.timed_out then
        finish_error(string.format("tesseract: pdftoppm timed out on page %d", page))
        return
      end
      if not raster_result.ok then
        finish_error(
          string.format("tesseract: pdftoppm failed on page %d: %s", page, raster_result.stderr)
        )
        return
      end

      local png = tmp .. ".png"
      if vim.fn.filereadable(png) ~= 1 then
        finish_error(string.format("tesseract: rasterized PNG not found for page %d", page))
        return
      end

      spawn_capture(
        { "tesseract", png, "stdout" },
        { timeout_ms = timeout_ms },
        function(ocr_result)
          vim.fn.delete(png)
          if ocr_result.timed_out then
            finish_error(string.format("tesseract: OCR timed out on page %d", page))
            return
          end
          if not ocr_result.ok then
            finish_error(
              string.format("tesseract: OCR failed on page %d: %s", page, ocr_result.stderr)
            )
            return
          end
          page_texts[#page_texts + 1] = ocr_result.stdout
          process_next()
        end
      )
    end)
  end

  process_next()
  return nil
end

return M
