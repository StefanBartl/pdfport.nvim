# pdfport.nvim — test suite

Framework-free headless specs. No plenary, no busted: `run.lua` loads each
spec, hands it the shared `harness.lua`, and exits non-zero on the first
failure — the same shape used across the sibling plugins.

## Running

From the repo root, with `lib.nvim` checked out as a sibling directory:

```bash
nvim --headless -u NONE -c "set rtp+=." -c "set rtp+=../lib.nvim" -c "luafile TESTS/run.lua" -c "qa!"
```

A successful run ends with `PDFPORT_TESTS_OK`. CI runs exactly this command.

`lib.nvim` is the only checkout the suite needs. `ui.nvim`, `ai.nvim`,
telescope, fzf-lua, neo-tree, nvim-tree and oil are all replaced in
`package.loaded` wherever they are reached, so the result is the same with or
without them installed.

## No external tools required

**No producer and no extraction tool is ever executed.** Every
`spawn_capture`, `vim.system`, `uv.spawn` and `io.popen` path is cut at a seam
that is replaced in `package.loaded` *before* the module under test is
required — `H.with_modules` exists for exactly that ordering, since each
module binds its dependencies to upvalues when its body runs, and patching a
field afterwards comes too late. What the specs assert instead is **the argv
that would have been spawned**: the command, its flags, their order, and the
resolved input/output paths. That is where the bugs in a wrapper around a CLI
actually live, and running the CLI would not check it any better.

Two kinds of subprocess do still happen, both cheap and both unavoidable
without faking Neovim itself:

* `vim.fn.executable()` probes, via `lib.nvim.core`, wherever a spec exercises
  the *real* `pdfport.platform` (`smoke_spec`, the live-registry section of
  `health_spec`, `:PdfPort backends`). These spawn nothing.
* That same live-registry `available()` walk reaches the two Python backends'
  real modules, whose `available()` runs `python -c "import pdfplumber"` /
  `import docling` once each (memoized afterwards). Harmless on a machine with
  no Python: it fails fast and the backend reports "unavailable".

Nothing here reaches the network, writes to the user's real extraction cache,
or produces a PDF.

## Specs

| Spec | Covers |
| --- | --- |
| `install_spec_spec.lua` | `docs/install.json` itself: it validates with **zero** errors through the real parser, `gs` declares its Windows spellings, and every tool is optional with a non-empty `why` and at least one package. The file is data nothing else reads, so a typo there surfaces only as a tool quietly missing from `:checkhealth` — which looks exactly like a tool nobody declared. |
| `page_range_spec.lua` | `util.page_range.parse` — ranges, dedup, sorting, reversed ranges, junk input |
| `rasterize_args_spec.lua` | `core.rasterize.args` — the pdftoppm command line for one page, especially the all-or-nothing `-x -y -W -H` crop window |
| `registry_spec.lua` | backend/renderer registration, input guards, defensive copies, and the lazy-proxy contract |
| `resolver_spec.lua` | fallback-chain resolution: explicit request, `default_backend`, `auto`, nothing available |
| `cache_variant_spec.lua` | the extraction cache's `path::backend::variant` discriminator — page range, prompt hash, model |
| `producer_spec.lua` | the registry's producer half + `core.composer` (the `create()` mirror of dispatcher/resolver), against fake producers |
| `ai_backends_spec.lua` | the claude/gemini/ollama contract with `ai.nvim`: optional dependency, request shape, per-request model/host/key |
| `smoke_spec.lua` | every module loads, `setup()` is idempotent, commands/renderers/health are wired |
| `producer_argv_spec.lua` | **all nine producers' command lines** and the four callback branches each of them has (clean exit, non-zero exit with stderr, timeout, tool not installed), plus `producers.load_custom` and the broken-module proxy |
| `backend_argv_spec.lua` | the five shelling extraction backends — pdftotext's `-f/-l` span, pdfplumber's and docling's generated Python, marker's output-directory search and its `**/*.md` recovery, tesseract's per-page pdftoppm→tesseract chain — plus `backends.load_custom` |
| `config_util_spec.lua` | `config/DEFAULTS` (fresh table per call, chain order), `config.setup`'s merge/reset semantics, `util.notify`'s `cfg.debug` gate, `util.spawn_env`'s two shapes, and `platform`'s OS/opener/terminal-tool detection |
| `tmpfile_cache_spec.lua` | `util.tmpfile`'s extension-per-kind, buffer/text materialization and deferred cleanup; `util.cache`'s key composition, mtime invalidation, refusal to cache failures, and corrupt-store recovery |
| `dispatcher_spec.lua` | `core.dispatcher.dispatch`: path validation, the two renderer-only short circuits, extract-option merge, cache consult/write/disable, a raising backend, the progress indicator's lifecycle, `open()`'s render wiring — and `core.rasterize.render_page`'s spawn plus its `.png` base handling |
| `picker_batch_spec.lua` | `util.picker`'s "system application is always an option" guarantee, `system_first`/`system_open`/`on_cancel`, the `vim.ui.select` fallback; `util.page_range.prompt`; `util.batch`'s selection walk, dedup, cursor restore and settled-outcome summary |
| `renderers_spec.lua` | `buffer` against real buffers and windows (header, CR stripping, filetype, reuse, every split mode, `focus=false`); `float`'s `make_scratch` options; `system`'s delegation and its two error paths; `terminal`'s `:terminal` command line for chafa/kitty/imgcat and every way it declines |
| `bindings_spec.lua` | every `:PdfPort` route, the argument→`<cfile>`→current-buffer path resolution, `pages=`, the `.pdf`-first completion; the five keymap actions, `resolve()`, `bind()`; the FileType and BufReadCmd autocmds |
| `integrations_spec.lua` | each tree's path resolver (neo-tree node id, nvim-tree absolute path, netrw's string-built path incl. separators, oil's dir+entry), `open_current`, each `setup()`'s autocmd, neo-tree's commands and its per-mode mappings table, and the telescope/fzf previewer gates |
| `public_api_spec.lua` | `require("pdfport")` itself: the argument guards, `config()`'s deep copy, `render_page`/`can_render_page_crop`, **the `github_stats.nvim` contract** (`can_create("markdown") == true`, then `create{text,from,output,on_conflict,__callback}`), `merge()`'s pinned `from = "pdf"`, the default notifications, and `setup()`'s wiring |
| `health_spec.lua` | `:checkhealth pdfport` against a chosen tool set: every section, a fully equipped machine (no errors), a bare one (warnings, not errors), and the in-between cases — pandoc without an engine, the curl gate in front of the API keys, ai.nvim present/absent |
| `open_done_spec.lua` | `pdfport.open`'s `on_done` signal settles exactly once on every path (runs last — it calls `setup()` and performs real opens) |

## Ordering

`run.lua`'s spec order is deliberate, in two halves.

`registry_spec` and `producer_spec` assert that the built-in backend/producer
modules are **not** yet in `package.loaded` (that is the lazy-proxy contract),
so everything that requires one has to run after them: `ai_backends_spec`,
`smoke_spec`, all eleven specs listed after it, and `open_done_spec`.

Those eleven also assume `setup()` has run at least once. Each one that
changes global state — the config singleton, the resolver/dispatcher/composer
configs, the registered verb — calls `require("pdfport").setup({})` again on
its way out, so the next spec starts from the defaults.

## Adding a spec

Create `TESTS/<name>_spec.lua` returning `function(H) ... end`, then add its
filename to the `specs` list in `run.lua`. Use `H.eq`/`H.ok`/`H.falsy`/
`H.match`/`H.eq_list` for assertions.

For anything that would otherwise touch an external tool:

* `H.with_modules(replacements, fn)` — replace `package.loaded` entries for
  the duration, with `H.UNLOAD` to force a module to re-run its body against
  them. This is the seam; use it rather than patching a field on a module that
  has already bound its dependencies.
* `H.spawn_recorder()` — a `spawn_capture` stand-in recording every argv. Set
  `rec.result` for the branch under test (built with `H.spawn_result{...}`)
  and `rec.on_call` to stand in for what the tool would have left on disk.
* `H.fake_platform(present, python)` — decide which executables and Python
  modules exist.
* `H.fake_backend` / `H.fake_producer` — minimal valid registry entries.
* `H.index_of(list, value)` / `H.last_argv(rec)` — reading an argv back.

## Coverage

Every module under `lua/` has assertion coverage except the ones listed below.

**Deliberately omitted, with reasons:**

* `lua/pdfport/@types/init.lua` — pure `---@meta` annotations, no runtime code.
* `plugin/pdfport.lua` — a three-line `vim.g.loaded_pdfport` guard with no
  branch worth a spec; `smoke_spec` already proves the plugin loads.
* **Actual PDF production and extraction.** Every producer's and backend's
  *argv* is asserted; whether pandoc, Ghostscript, marker or tesseract then
  produce a correct PDF or a correct transcription cannot be verified without
  the tools plus a document corpus, and would not be this suite's job if it
  could. Same line the suite already drew around `spawn_capture`.
* `core/rasterize.render_page`'s **successful poppler run** — the spawn, its
  argv and the `.png` base handling are covered with `uv.spawn` replaced; a
  real rasterization needs poppler and a real PDF.
* `renderers/terminal`'s image display — the `:terminal` command line it would
  run is asserted with `vim.cmd` intercepted; what chafa/kitty/imgcat then draw
  into a pty is not something a headless spec can look at.
* `integrations/telescope.previewer()`'s previewer object and `integrations/fzf`'s
  picker plumbing — both hard-require their picker plugin, neither of which is
  a CI checkout. Their filetype gate and the extraction request behind it *are*
  covered; only the construction of the previewer itself is not.
* The real HTTP request in the `claude`/`gemini`/`ollama` backends — the
  request pdfport builds and every way an answer is turned into a
  `PdfPort.Result` is covered through a faked `ai.nvim`; only the network call
  is not, deliberately.
* `health.check()` **without lib.nvim** — its last line calls the usercmd
  composer unguarded, so such a run raises before the report can be read back.
  It cannot happen in practice: `bindings/usrcmds.lua` requires the composer at
  module level, so pdfport does not load without lib.nvim at all.

## Bugs pinned, not fixed

Three real bugs turned up while writing these specs. Each is pinned with a
`BUG:`-marked assertion recording the *current* behaviour, so the spec goes
red the moment it is fixed and the fix stays a deliberate, separate change.

1. **`backends/tesseract.lua` over-reports `pages_processed` on failure.**
   `finish_error()` reports `page_idx - 1`, but `process_next()` has already
   incremented `page_idx` past the current page by the time any of its
   callbacks can fail — so a failure on page 1 reports one page processed when
   none completed. `backends/ollama.lua`'s identically-shaped `fail()` gets
   this right with `page_idx - 2`; the two were written from the same template
   and only one of them was corrected.
   Pinned in `backend_argv_spec.lua`.

2. **`bindings/autocmds.lua` is not idempotent, though it says it is.** Both
   its module docs and `register_bufreadcmd`'s own comment promise that
   re-registering "clears and re-creates its own augroup instead of
   accumulating". It does not: `lib.nvim.bindings.autocmd.create` resolves a
   *string* `group` through `autocmd.group(name)` without the `clear`
   argument, so the augroup is created once and every later call adds another
   autocmd to it. Visible consequence: a second `require("pdfport").setup()`
   with `auto_open_on_read = true` leaves two `BufReadCmd *.pdf` autocmds, both
   fire for one `:e file.pdf`, and the mode picker opens twice. The fix is for
   the caller to resolve the group itself (`autocmd.group(name, true)`) and
   pass the resulting id.
   Pinned in `bindings_spec.lua`.

3. **The picker previewers cache failures.** `integrations/fzf.lua` and
   `integrations/telescope.lua` both memoize per path with
   `_cache[filepath] = text` *before* anything looks at `result.status`, so an
   error message is cached exactly like a successful extraction.
   `util/cache.lua`, the extraction cache proper, deliberately refuses this.
   Consequence: once a PDF has failed to preview — ollama not started yet,
   poppler not installed yet — every later preview of it replays the stale
   error without retrying, and fzf's `_cache` is module-level, so opening a
   fresh picker does not clear it either.
   Pinned in `integrations_spec.lua`.
