---@module 'pdfport.util.path'
---@brief One spelling per file, so a path can be used as an identity.
---@description
--- Every entry point hands pdfport a path in whatever spelling its source
--- happened to have: `:PdfPort text ./a.pdf` a relative one, a file tree an
--- absolute one, `nvim_buf_get_name()` a fully resolved one. On macOS the
--- last of those is the sharpest case -- `vim.fn.tempname()` reports
--- `/var/folders/...` while a buffer name for the very same file reports
--- `/private/var/folders/...`, because `/var` is a symlink and Neovim
--- resolves buffer names through the OS.
---
--- That matters because `util.cache` keys extraction results on the path
--- string. A key that changes with the caller's spelling is not a key: the
--- same document extracts twice under two entries, and a relative spelling
--- is worse than wasteful -- `./doc.pdf` names a different file in every
--- directory, so two documents that share a relative name and an mtime
--- second can answer each other's text.
---
--- `canonical()` is the one function that settles it, and `core.dispatcher`
--- is the one place that calls it: every extraction passes through there.

local uv = vim.uv or vim.loop

local M = {}

---The canonical spelling of `path`: absolute, `..`-free and symlink-resolved.
---
---`uv.fs_realpath` does the real work -- on Windows it also answers the long
---name in the on-disk case (see backends/marker.lua for the 8.3 form
---`%TEMP%` hands out). It needs the file to exist, though, and answers nil
---otherwise, so `:p` runs first: it absolutizes against the cwd and expands
---`~`, which is both the input realpath wants and the best that can be said
---about a path that is not there yet.
---@param path string
---@return string
function M.canonical(path)
  if type(path) ~= "string" or path == "" then return path end

  local abs = vim.fn.fnamemodify(path, ":p")

  -- `type(real) == "string"` rather than a bare truth test: `fs_realpath` has
  -- an async overload that answers a request handle, so its declared type is
  -- `string|uv.uv_fs_t` and the handle half must never land in a cache key.
  local real = uv.fs_realpath(abs)
  if type(real) == "string" then return real end

  return abs
end

return M
