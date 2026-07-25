-- smoke.lua — headless regression smoke test for pdfport.nvim.
--
-- Runs the plugin against a stub backend (no real extraction tool required)
-- and asserts the core invariants: setup()/config load, lazy backend
-- registration + resolution, the dispatcher's error/cache/callback paths,
-- keymap disable + visual-mode-aware which-key resolution, and the small
-- pure-function utilities (page_range, cache).
--
-- Usage (from the repo root):
--   nvim --clean --headless -u NONE -l test/smoke.lua
--
-- Exit code 0 = all checks passed; 1 = a check failed (message printed).

-- ":p" resolves to absolute first, so `root` survives any later cwd change.
local this = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(this, ":p:h:h")
vim.opt.rtp:prepend(root)
-- lib.nvim is a required dependency; add a sibling checkout if present.
local sibling_lib = vim.fn.fnamemodify(root, ":h") .. "/lib.nvim"
if vim.fn.isdirectory(sibling_lib) == 1 then
  vim.opt.rtp:prepend(sibling_lib)
end

local passed, failed = 0, 0
local function check(name, ok, detail)
  if ok then
    passed = passed + 1
    print("  ok   " .. name)
  else
    failed = failed + 1
    print("  FAIL " .. name .. (detail and ("  — " .. detail) or ""))
  end
end
local function eq(name, got, want)
  check(name, got == want, ("got %s want %s"):format(vim.inspect(got), vim.inspect(want)))
end

-- ── setup() + config ─────────────────────────────────────────────────────────
local pdfport = require("pdfport")
do
  local ok = pcall(pdfport.setup, {})
  check("setup() runs without error", ok)

  local cfg = pdfport.config()
  eq("config: default_backend default", cfg.default_backend, "auto")
  check("config: fallback_chain includes tesseract",
    vim.tbl_contains(cfg.fallback_chain, "tesseract"))
  eq("config: extract_opts.cache default true", cfg.extract_opts.cache, true)
  eq("config: auto_open_on_read default false", cfg.auto_open_on_read, false)
end

-- ── lazy backend loading: setup() must not require any builtin backend ──────
do
  local untouched = true
  for _, mod in ipairs({
    "pdfport.backends.claude", "pdfport.backends.ollama", "pdfport.backends.marker",
    "pdfport.backends.docling", "pdfport.backends.pdfplumber", "pdfport.backends.tesseract",
  }) do
    if package.loaded[mod] ~= nil then untouched = false end
  end
  check("setup() does not eagerly require any builtin backend module", untouched)

  local registry = require("pdfport.core.registry")
  check("registry: all 7 builtins registered", #registry.backend_ids() == 7,
    "ids=" .. table.concat(registry.backend_ids(), ","))

  -- Touching .available() on exactly one backend must load only that module.
  local b = registry.get_backend("pdftotext")
  check("registry.get_backend('pdftotext') found", b ~= nil)
  pcall(b.available)
  check("pdftotext.available() lazily loads pdfport.backends.pdftotext",
    package.loaded["pdfport.backends.pdftotext"] ~= nil)
  check("...but does not load an unrelated backend (pdfport.backends.claude)",
    package.loaded["pdfport.backends.claude"] == nil)
end

-- ── registry + resolver, via a stub backend (no real tool required) ─────────
local STUB_ID = "smoke_stub"
do
  local registry = require("pdfport.core.registry")

  ---@type PdfPort.Backend
  local stub = {
    id   = STUB_ID,
    name = "smoke test stub",
    capabilities = { markdown = false, tables = false, ocr = false, remote = false, gpu_optional = false },
    available = function() return true end,
    extract = function(path, opts)
      vim.schedule(function()
        opts.__callback({
          status = "ok", text = "stub text for " .. path, format = "plain",
          backend = STUB_ID, pages_processed = 1, error = nil,
        })
      end)
      return nil
    end,
  }
  pdfport.register_backend(stub)

  check("registry.has_backend(stub)", registry.has_backend(STUB_ID))
  eq("registry.get_backend(stub).id", registry.get_backend(STUB_ID).id, STUB_ID)

  local resolver = require("pdfport.core.resolver")
  resolver._set_config(pdfport.config())
  local resolved, err = resolver.resolve(STUB_ID)
  check("resolver.resolve(stub id) returns the stub", resolved ~= nil and resolved.id == STUB_ID, err)

  -- An unknown id is prepended to the real fallback chain rather than
  -- rejected outright (build_chain's documented behavior) — whether it
  -- resolves to something depends on which real tools this machine has
  -- installed, so only assert the *shape* of the response, not which
  -- branch: either a valid backend table, or nil + a descriptive string.
  local missing, missing_err = resolver.resolve("does_not_exist")
  if missing == nil then
    check("resolver.resolve(unknown id): no match → nil + descriptive error string",
      type(missing_err) == "string" and missing_err:find("no available backend") ~= nil, missing_err)
  else
    check("resolver.resolve(unknown id): fell through to a real available backend",
      type(missing.id) == "string" and type(missing.available) == "function")
  end
end

-- ── dispatcher: invalid path → error result via callback ────────────────────
do
  local dispatcher = require("pdfport.core.dispatcher")
  local got
  dispatcher.dispatch({ path = "" }, function(result) got = result end)
  vim.wait(200, function() return got ~= nil end, 5)
  check("dispatch({path=''}) calls back", got ~= nil)
  check("dispatch({path=''}) reports status=error", got and got.status == "error")

  local got2
  dispatcher.dispatch({ path = "/definitely/does/not/exist.pdf" }, function(result) got2 = result end)
  vim.wait(200, function() return got2 ~= nil end, 5)
  check("dispatch(missing file) reports status=error", got2 and got2.status == "error", vim.inspect(got2))
end

-- ── end-to-end extract() through the stub backend + cache roundtrip ─────────
local tmp_pdf = vim.fn.tempname() .. ".pdf"
do
  vim.fn.writefile({ "%PDF-1.4 smoke test" }, tmp_pdf)

  local got
  pdfport.extract({
    path = tmp_pdf, backend_id = STUB_ID,
    __callback = function(result) got = result end,
  })
  vim.wait(300, function() return got ~= nil end, 5)
  check("extract() via stub backend calls back", got ~= nil)
  eq("extract() result.status", got and got.status, "ok")
  eq("extract() result.backend", got and got.backend, STUB_ID)

  -- Second call should hit the cache and skip the (spied-on) backend entirely.
  local cache = require("pdfport.util.cache")
  local cached = cache.get(tmp_pdf, STUB_ID, "all")
  check("cache: entry was written after a successful extraction", cached ~= nil)
  eq("cache: cached text matches the original result", cached and cached.text, got and got.text)

  local calls = 0
  local registry = require("pdfport.core.registry")
  local real_stub = registry.get_backend(STUB_ID)
  local orig_extract = real_stub.extract
  real_stub.extract = function(...)
    calls = calls + 1
    return orig_extract(...)
  end

  local got3
  pdfport.extract({ path = tmp_pdf, backend_id = STUB_ID, __callback = function(r) got3 = r end })
  vim.wait(200, function() return got3 ~= nil end, 5)
  eq("cache: a second identical extract() is served from cache (backend not re-invoked)", calls, 0)
  eq("cache: cached result still has status ok", got3 and got3.status, "ok")

  real_stub.extract = orig_extract
  cache.clear()
  vim.fn.delete(tmp_pdf)
end

-- ── keymaps: resolve()/disable + visual-mode-aware which-key registration ───
do
  local keymaps = require("pdfport.bindings.keymaps")

  local resolved = keymaps.resolve()
  eq("keymaps.resolve(): open default", resolved.open, "<leader>po")
  eq("keymaps.resolve(): open_batch default", resolved.open_batch, "<leader>pb")

  local disabled = keymaps.resolve({ open_system = false })
  eq("keymaps.resolve({open_system=false}): disabled action stays false", disabled.open_system, false)
  eq("keymaps.resolve({open_system=false}): other actions keep their default", disabled.open_text, "<leader>pt")

  check("keymaps.VISUAL_ACTIONS marks open_batch as visual-mode", keymaps.VISUAL_ACTIONS.open_batch == true)
  check("keymaps.VISUAL_ACTIONS does not mark open as visual-mode", keymaps.VISUAL_ACTIONS.open == nil)

  -- No which-key installed in this headless run: must be a silent no-op, not an error.
  local ok = pcall(keymaps.register_which_key, resolved)
  check("register_which_key() is a no-op without which-key.nvim installed", ok)
end

-- ── page_range: prompt-string parsing ────────────────────────────────────────
do
  local page_range = require("pdfport.util.page_range")
  eq("page_range.parse(''): blank → nil (no explicit selection)", page_range.parse(""), nil)
  eq("page_range.parse(' '): whitespace-only → nil", page_range.parse("   "), nil)
  check("page_range.parse('1-3')", vim.deep_equal(page_range.parse("1-3"), { 1, 2, 3 }))
  check("page_range.parse('5,2,1')  sorts + dedupes", vim.deep_equal(page_range.parse("5,2,1,2"), { 1, 2, 5 }))
  check("page_range.parse('1-2,4-5')  ranges + singles combine",
    vim.deep_equal(page_range.parse("1-2,4-5"), { 1, 2, 4, 5 }))
  eq("page_range.parse('not a page range') → nil (no valid tokens)",
    page_range.parse("not a page range"), nil)
end

-- ── neo-tree keymaps(): normal-mode table + nested visual-mode sub-table ────
do
  local neotree = require("pdfport.integrations.neotree")
  local map = neotree.keymaps()
  check("neotree.keymaps(): open bound at top level", map["<leader>po"] == "pdfport_open")
  check("neotree.keymaps(): open_batch is NOT a top-level (normal-mode) entry",
    map["<leader>pb"] == nil)
  check("neotree.keymaps(): open_batch nested under ['v']",
    type(map["v"]) == "table" and map["v"]["<leader>pb"] == "pdfport_batch")

  local disabled_map = neotree.keymaps({ open_batch = false })
  check("neotree.keymaps({open_batch=false}): no ['v'] sub-table when disabled",
    disabled_map["v"] == nil)
end

-- ── Report ────────────────────────────────────────────────────────────────────
print(("\npdfport.nvim smoke: %d passed, %d failed"):format(passed, failed))
if failed > 0 then
  vim.cmd("cq") -- non-zero exit
else
  vim.cmd("qa!")
end
