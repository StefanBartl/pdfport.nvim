# Core

The architecture underneath both directions: a **resolver** (read side) and
its mirror-image **composer** (write side) pick a backend/producer from a
fallback chain, a **dispatcher** coordinates the read side's full
extract-then-render flow, and a **registry** holds every backend, producer,
and renderer that has been registered. Plus caching and the `:checkhealth`
diagnostics that make the live registry state inspectable.

## Registry

Two independent, append-ordered tables — backends and producers — plus a
mode-keyed renderer table. Registration is idempotent (`register_backend`/
`register_producer` only append to the order list the first time an id is
seen; re-registering the same id just replaces the entry in place) and every
lookup is O(1).

- **Module:** `lua/pdfport/core/registry.lua`
- **Backends:** `register_backend`, `get_backend`, `all_backends`, `backend_ids`, `has_backend`
- **Producers:** `register_producer`, `get_producer`, `all_producers`, `producer_ids`, `has_producer`
- **Renderers:** `register_renderer`, `get_renderer`, `renderer_modes`
- **Diagnostics:** `M.diagnostics()` — human-readable availability listing for every backend/producer plus registered renderer modes; backs `:PdfPort backends` and `:PdfPort producers` (`show_diagnostics()` in `bindings/usrcmds.lua`)

## Resolver (read side)

`core/resolver.lua` builds a backend fallback chain and walks it in order,
returning the first backend whose `available()` returns `true`.

Chain-building priority (`build_chain(requested)`):

1. An explicit `backend_id` passed to `open()`/`extract()` goes first, ahead of everything else.
2. Otherwise, `cfg.default_backend` (when set and not `"auto"`) goes first.
3. `cfg.fallback_chain` (default: pdftotext, pdfplumber, marker, docling, ollama, tesseract, claude) fills the rest, in order.
4. Any registered backend not already in the chain (e.g. a custom one via `register_backend()`) is appended at the end, so a custom backend is always reachable even if the user never added it to `fallback_chain` explicitly.
5. The final list is deduplicated (`lib.lua.tables.dedup_list`) — the same id is only tried once even if it appears via both an explicit request and the default chain.

`M.resolve(requested)` returns `(backend, nil)` on the first available hit
or `(nil, "...Tried: [...]")` naming every id it walked past.
`M.available_backends()` runs the same walk with `"auto"` and returns every
available backend, not just the first — used by `:PdfPort`'s interactive
mode picker to decide which backend-specific choices to offer.

- **Module:** `lua/pdfport/core/resolver.lua`

## Composer (write side)

`core/composer.lua` is the resolver's mirror image for creation: instead of
one global `fallback_chain`, each **input kind** (image/markdown/text/html/
office/pdf) has its own chain in `cfg.create_chain`. `M.resolve(kind,
requested)` builds `{ requested?, ...create_chain[kind] }`, deduplicated the
same way, and returns the first producer that both accepts that kind
(`vim.tbl_contains(producer.accepts, kind)`) and reports itself available.

`M.create(opts, callback)` is composer's dispatch-equivalent, handling the
full write-side flow:

1. Validate that exactly one of `opts.inputs`/`opts.text`/`opts.bufnr` was given.
2. For `text`/`bufnr` inputs (no file path to infer from), require `opts.from` and `opts.output` explicitly — `util/tmpfile.lua` materializes them to a real file first (producers only ever see paths), cleaned up again once the result callback fires, on every exit path.
3. Guess the input kind from the file extension (`EXT_KIND` table) unless `opts.from` was given.
4. Resolve a producer for that kind via the chain above.
5. Resolve the output path, applying `on_conflict` (`"overwrite"` default, `"suffix"` appends `-1`, `-2`, ... before the extension until a free path is found, `"error"` fails if the path already exists).
6. Merge `cfg.create_opts` under the per-call `opts.opts`, call `producer.create(create_opts)`.

`pdfport.merge()` is a thin wrapper that fixes `from = "pdf"` and otherwise
reuses this exact same pipeline — the three merge producers (qpdf/pdftk/
ghostscript) are just producers registered for kind `"pdf"`.

- **Module:** `lua/pdfport/core/composer.lua`

## Dispatcher (read side)

`core/dispatcher.lua`'s `M.dispatch(opts, callback)` is the full read-side
pipeline backing `pdfport.open()`/`pdfport.extract()`:

1. Validate `opts.path` exists and is a regular file (`uv.fs_stat`).
2. Short-circuit entirely for `opts.mode == "system"` or `"terminal"` — both go straight to their renderer with a synthetic `status = "ok"` result, no backend resolution or extraction at all (see [RENDERING.md](RENDERING.md)).
3. Otherwise resolve a backend via `resolver.resolve(opts.backend_id)`.
4. Check the on-disk cache (path + backend id + page-range variant) unless `extract_opts.cache == false`; a hit returns immediately.
5. Start a progress indicator (`lib.nvim.progress`, only if installed) — wraps `callback` once so every exit path (async `__callback`, synchronous return, backend-threw) reports finish/fail exactly once.
6. Call the backend's `extract(path, extract_opts)`, `pcall`'d so a throwing backend becomes a normal error result instead of crashing the caller.
7. On success, write the result to cache before invoking the caller's callback.

`M.open(opts, on_error)` layers rendering on top of `dispatch`: on a
successful extraction it looks up the renderer for `opts.mode` (default
`"buffer"`, or `cfg.render_opts.mode`) and calls it with the merged
`render_opts`; on any error it calls `on_error(msg)` instead (defaults to a
no-op — callers decide how errors surface).

- **Module:** `lua/pdfport/core/dispatcher.lua`

## Rasterization

`core/rasterize.lua` wraps `pdftoppm` page-to-PNG conversion, shared by the
`terminal` renderer (throwaway PNG, deleted ~2s after display) and the
public `pdfport.render_page(path, page, opts, callback)` API (a real,
caller-owned PNG the caller is responsible for deleting) — one shell-out
implementation, two different lifetime contracts on top of it.

- **Module:** `lua/pdfport/core/rasterize.lua`

## Caching

Successful extractions are cached across Neovim restarts
(`lib.nvim.cache.disk`), keyed by path + backend id + page-range variant
and invalidated by the source file's mtime. Opt out per-call or globally
with `extract_opts.cache = false`. Creation (`pdfport.create()`) has no
cache — an export is a one-off, explicit action with a target path, not a
repeated read.

- **Module:** `lua/pdfport/util/cache.lua` (`get`, `set`), consulted from `core/dispatcher.lua`

## Health check

`:checkhealth pdfport` (`lua/pdfport/health.lua`) runs, in order: core
module load status, per-backend tool/dependency availability, per-producer
tool availability (creation group, then merge group), renderer availability
(including terminal-image tool detection), integration/plugin presence
(neo-tree, nvim-tree, oil, telescope, fzf-lua, which-key, and the hard
`lib.nvim` dependency), declared-tools reporting via `lib.nvim.deps.health`
(if present), and finally the *live* registry state — per-id availability
for every backend and producer actually registered by a prior `setup()`
call, which is empty/warns until `setup()` has run at least once.

- **Module:** `lua/pdfport/health.lua`
