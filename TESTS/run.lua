-- TESTS/run.lua — headless test runner for pdfport.nvim.
--
-- Run from the repo root (lib.nvim must be reachable as a sibling):
--   nvim --headless -u NONE -c "set rtp+=." -c "set rtp+=../lib.nvim" \
--        -c "luafile TESTS/run.lua" -c "qa!"
--
-- Loads every *_spec.lua listed below, runs it against the shared harness,
-- prints a per-spec result, and exits non-zero if any spec fails.

local dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local H = dofile(dir .. "harness.lua")

-- The repo itself has to be on the runtimepath when invoked via `-l`, which
-- (unlike `-c "set rtp+=."`) does not add the cwd.
local repo = vim.fs.normalize(dir .. "..")
vim.opt.rtp:append(repo)
package.path = table.concat({
  repo .. "/lua/?.lua",
  repo .. "/lua/?/init.lua",
  package.path,
}, ";")

-- Order matters: registry_spec asserts that the built-in backend modules are
-- NOT yet loaded (the lazy-proxy contract), so it has to run before
-- smoke_spec, which requires every one of them on purpose.
local specs = {
  "install_spec_spec.lua",
  "page_range_spec.lua",
  "rasterize_args_spec.lua",
  "registry_spec.lua",
  "resolver_spec.lua",
  "producer_spec.lua",
  "smoke_spec.lua",
  -- Last on purpose: it calls setup() and performs real opens, which
  -- loads producer/backend modules. registry_spec and producer_spec
  -- assert those are NOT yet in package.loaded, so anything that
  -- requires them has to run after both.
  "open_done_spec.lua",
}

--- Straight to stdout rather than through `print`: a spec that opens a window
--- forces a redraw that swallows `print`'s pending newline, running two spec
--- results together on one line.
---@param s string
local function say(s)
  io.stdout:write(s, "\n")
end

local failed = 0
for _, name in ipairs(specs) do
  local run = dofile(dir .. name)
  local ok, err = pcall(run, H)
  if ok then
    say(("ok    %s"):format(name))
  else
    failed = failed + 1
    say(("FAIL  %s\n      %s"):format(name, tostring(err)))
  end
end

if failed > 0 then
  say(("\n%d spec(s) failed"):format(failed))
  os.exit(1)
end

say("\nPDFPORT_TESTS_OK")
