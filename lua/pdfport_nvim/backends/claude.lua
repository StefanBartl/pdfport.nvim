---@module 'pdfport_nvim.backends.claude'
---@brief Extraction backend using the Anthropic Claude API.
---@description
--- Sends the PDF as a base64-encoded document to the Anthropic Messages API.
--- Runs curl asynchronously via lib.nvim.cross.uv.spawn_capture.
--- Requires: ANTHROPIC_API_KEY, curl, internet connection.

local platform = require("pdfport_nvim.platform")
local spawn_capture = require("lib.nvim.cross.uv.spawn_capture")

---@type PdfPort.ConfigurableBackend
local M = {
  id   = "claude",
  name = "Anthropic Claude API",
  capabilities = {
    markdown     = true,
    tables       = true,
    ocr          = true,
    remote       = true,
    gpu_optional = false,
  },
}

---@type PdfPort.Config|nil
local _config = nil

---@param config PdfPort.Config
---@return nil
function M._set_config(config)
  _config = config
end

---@return boolean
function M.available()
  if not platform.has("curl") then return false end
  local key = (_config and _config.claude_api_key) or vim.env.ANTHROPIC_API_KEY
  return type(key) == "string" and key ~= ""
end

---@param path string
---@return string|nil base64
---@return string|nil error_msg
local function read_base64(path)
  if not platform.has("base64") then
    return nil, "base64 binary not found on PATH"
  end
  local result = vim.fn.system({ "base64", "-w", "0", path })
  if vim.v.shell_error ~= 0 then
    return nil, "base64 encoding failed"
  end
  return result:gsub("%s+$", ""), nil
end

---@param base64_pdf string
---@param prompt string
---@param model string
---@return string json
local function build_request(base64_pdf, prompt, model)
  local safe_prompt = prompt:gsub('"', '\\"'):gsub("\n", "\\n")
  local safe_model  = model:gsub('"', '\\"')
  return string.format([[{
  "model": "%s",
  "max_tokens": 4096,
  "messages": [{
    "role": "user",
    "content": [{
      "type": "document",
      "source": { "type": "base64", "media_type": "application/pdf", "data": "%s" }
    }, {
      "type": "text",
      "text": "%s"
    }]
  }]
}]], safe_model, base64_pdf, safe_prompt)
end

---@param path string
---@param opts PdfPort.InternalExtractOpts
---@return PdfPort.Result|nil
function M.extract(path, opts)
  local api_key = (_config and _config.claude_api_key) or vim.env.ANTHROPIC_API_KEY
  if not api_key or api_key == "" then
    local result = {
      status = "error", text = nil, format = "markdown", backend = "claude",
      pages_processed = nil, error = "claude: ANTHROPIC_API_KEY not set",
    }
    if type(opts.__callback) == "function" then opts.__callback(result) end
    return result
  end

  local model = opts.model or "claude-opus-4-5"
  local prompt = opts.prompt or table.concat({
    "Extract all text content from this PDF document.",
    "Format the output as clean Markdown.",
    "Preserve headings, lists, tables and code blocks.",
    "Do not add commentary or preamble.",
  }, " ")

  local b64, b64_err = read_base64(path)
  if not b64 then
    local result = {
      status = "error", text = nil, format = "markdown", backend = "claude",
      pages_processed = nil,
      error = "claude: " .. (b64_err or "base64 encoding failed"),
    }
    if type(opts.__callback) == "function" then opts.__callback(result) end
    return result
  end

  local json_body  = build_request(b64, prompt, model)
  local body_file  = vim.fn.tempname() .. ".json"
  local f          = io.open(body_file, "w")
  if not f then
    return {
      status = "error", text = nil, format = "markdown", backend = "claude",
      pages_processed = nil, error = "claude: failed to write temp request file",
    }
  end
  f:write(json_body); f:close()

  local timeout_ms = opts.timeout_ms or 60000
  local argv = {
    "curl", "-s", "-X", "POST",
    "https://api.anthropic.com/v1/messages",
    "-H", "Content-Type: application/json",
    "-H", "x-api-key: " .. api_key,
    "-H", "anthropic-version: 2023-06-01",
    "-d", "@" .. body_file,
  }

  spawn_capture(argv, { timeout_ms = timeout_ms }, function(spawn_result)
    vim.fn.delete(body_file)

    if spawn_result.timed_out then
      local result = {
        status = "error", text = nil, format = "markdown", backend = "claude",
        pages_processed = nil,
        error = string.format("claude: HTTP request timed out after %d ms", timeout_ms),
      }
      if type(opts.__callback) == "function" then opts.__callback(result) end
      return
    end

    if not spawn_result.ok then
      local result = {
        status = "error", text = nil, format = "markdown", backend = "claude",
        pages_processed = nil,
        error = string.format("curl exited %d: %s", spawn_result.code, spawn_result.stderr),
      }
      if type(opts.__callback) == "function" then opts.__callback(result) end
      return
    end

    local raw = spawn_result.stdout
    local ok_json, decoded = pcall(vim.json.decode, raw)
    if not ok_json or type(decoded) ~= "table" then
      local result = {
        status = "error", text = nil, format = "markdown", backend = "claude",
        pages_processed = nil,
        error = "claude: invalid JSON response: " .. raw:sub(1, 200),
      }
      if type(opts.__callback) == "function" then opts.__callback(result) end
      return
    end

    if decoded.type == "error" then
      local api_err = (decoded.error and decoded.error.message) or "unknown API error"
      local result = {
        status = "error", text = nil, format = "markdown", backend = "claude",
        pages_processed = nil, error = "claude API error: " .. api_err,
      }
      if type(opts.__callback) == "function" then opts.__callback(result) end
      return
    end

    local text_parts = {}
    for _, block in ipairs(decoded.content or {}) do
      if block.type == "text" and type(block.text) == "string" then
        text_parts[#text_parts + 1] = block.text
      end
    end

    local result = {
      status = "ok", text = table.concat(text_parts, "\n"),
      format = "markdown", backend = "claude",
      pages_processed = nil, error = nil,
    }
    if type(opts.__callback) == "function" then opts.__callback(result) end
  end)

  return nil
end

return M
