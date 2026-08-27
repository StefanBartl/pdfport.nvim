---@module 'pdfport.util.spawn_env'
---@brief Completed subprocess environment for `pandoc`/`pdftotext`/`ollama`
---(and the `pdftoppm`/`curl` calls the ollama backend shells out to), in the
---array format `lib.nvim.cross.uv.spawn_capture` (raw libuv `uv.spawn`)
---expects.
---@description
--- A subprocess started via libuv inherits exactly Neovim's own process
--- environment, not an interactive login shell's — version-manager-managed
--- installs (`pandoc`/`pdftotext` via Homebrew's `shellenv`, `pipx`, etc.)
--- are the main risk here, not OS-keyring auth. `lib.nvim.cross.run.env`
--- fixes exactly this: `.array()` is the array-of-`"KEY=VALUE"` shape
--- `spawn_capture` (raw libuv `uv.spawn`) wants, `.apply()` below is the
--- `vim.system`-shaped dict for the two `vim.fn.system` call sites in
--- `backends/ollama.lua`, which has no env parameter at all.

local M = {}

M.array = require("lib.nvim.cross.run.env").array

---Spawn options for a `vim.system` call, with a completed `env` folded in.
---Convenience for the module's own `vim.system(cmd, spawn_env.opts())` call
---sites — mirrors `lib.nvim.cross.run.env.apply()` but named locally so
---call sites don't need to know which shape a given runner expects.
---@param spawn_opts? table
---@return table
function M.opts(spawn_opts)
  return require("lib.nvim.cross.run.env").apply(spawn_opts)
end

return M
