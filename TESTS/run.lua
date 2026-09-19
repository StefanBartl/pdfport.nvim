-- TESTS/run.lua — headless test runner for pdfport.nvim.
--
-- Run from the repo root (lib.nvim must be reachable as a sibling):
--   nvim --headless -u NONE -c "set rtp+=." -c "set rtp+=../lib.nvim" \
--        -c "luafile TESTS/run.lua" -c "qa!"
--
-- Loads every *_spec.lua listed below, runs it against the shared harness,
-- prints a per-spec result, and exits non-zero if any spec fails.

local dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

--- Straight to stdout rather than through `print`: a spec that opens a window
--- forces a redraw that swallows `print`'s pending newline, running two spec
--- results together on one line.
---@param s string
local function say(s)
  io.stdout:write(s, "\n")
end

-- Must stay inside the pcall for the same reason the per-spec dofile below
-- does: a broken harness.lua must fail the run loudly, not just abort before
-- the ok/fail sentinel is ever printed (which a headless nvim would still
-- exit 0 for).
local harness_ok, H_or_err = pcall(dofile, dir .. "harness.lua")
if not harness_ok then
  say(("FAIL  harness.lua\n      %s"):format(tostring(H_or_err)))
  os.exit(1)
end
local H = H_or_err

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
  -- Pure: it calls the dispatcher's cache-key helper directly and loads
  -- no backend, so it is free of the lazy-proxy ordering constraint below.
  "cache_variant_spec.lua",
  "producer_spec.lua",
  -- Before smoke_spec for the same reason registry_spec is: it loads the
  -- claude/ollama backend modules (and unloads them again), which the
  -- lazy-proxy assertions above must not see.
  "ai_backends_spec.lua",
  "smoke_spec.lua",
  -- After smoke_spec, for the mirror image of its reason: each of these
  -- loads producer/backend/renderer modules with their spawn seam replaced,
  -- which the lazy-proxy assertions in registry_spec/producer_spec above
  -- must not see. They also rely on setup() having run once already.
  "producer_argv_spec.lua",
  "backend_argv_spec.lua",
  "config_util_spec.lua",
  "tmpfile_cache_spec.lua",
  "dispatcher_spec.lua",
  "picker_batch_spec.lua",
  "renderers_spec.lua",
  "bindings_spec.lua",
  "integrations_spec.lua",
  "public_api_spec.lua",
  "health_spec.lua",
  -- Last on purpose: it calls setup() and performs real opens, which
  -- loads producer/backend modules. registry_spec and producer_spec
  -- assert those are NOT yet in package.loaded, so anything that
  -- requires them has to run after both.
  "open_done_spec.lua",
}

local failed = 0
for _, name in ipairs(specs) do
  -- dofile itself must stay inside the pcall: a syntax error or a failing
  -- top-level require while *loading* a spec would otherwise abort this
  -- loop before os.exit(1) below runs, and nvim's headless "luafile an
  -- erroring file" still exits 0 -- turning a broken spec into a silent
  -- pass instead of a reported failure.
  local ok, run_or_err = pcall(dofile, dir .. name)
  if ok then
    ok, run_or_err = pcall(run_or_err, H)
  end
  if ok then
    say(("ok    %s"):format(name))
  else
    failed = failed + 1
    say(("FAIL  %s\n      %s"):format(name, tostring(run_or_err)))
  end
end

if failed > 0 then
  say(("\n%d spec(s) failed"):format(failed))
  os.exit(1)
end

say("\nPDFPORT_TESTS_OK")
