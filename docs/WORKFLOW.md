# Workflow — getting real use out of pdfport.nvim day to day

Every feature here is documented on its own elsewhere (`docs/FEATURES/`).
This is the different question: once seven backends, nine producers, four
renderers and a resolver/dispatcher/composer core all exist, *how do they
actually combine* into something worth reaching for regularly, rather than
a pile of independently-correct pieces you have to re-derive the interplay
of every time.

## Reading a PDF: picking a mode for the context you're in

`:PdfPort [path]` (no subcommand) is the general-purpose entry point — the
interactive mode picker offers `buffer`/`float`/`terminal`/`system`, plus
backend-specific buffer choices (pdftotext, marker, docling, claude,
ollama). Skip the picker once you know what you want:

| Situation | Command | Why |
|---|---|---|
| Reading/searching text at length, want it to persist | `:PdfPort text` | scratch buffer, reused across repeat opens of the same file, `vsplit` by default |
| Quick glance, don't want to touch window layout | `:PdfPort float` | centered float, `q`/`<Esc>` closes, prompts for a page range first |
| Need the real PDF (forms, embedded fonts, annotations) | `:PdfPort system` | hands off to the OS default app, no extraction at all |
| In a terminal that supports images, want a visual page | `:PdfPort terminal` | rasterizes via `pdftoppm`, displays with chafa/kitty/imgcat, prompts for a page range |

`system` and `terminal` both bypass backend resolution completely —
`core/dispatcher.lua` special-cases both modes before `resolver.resolve()`
ever runs. That means they work with **zero** extraction backends
installed; if you've only got `pdftoppm` and a terminal image tool, `:PdfPort
terminal` still works even though every text backend reports unavailable in
`:checkhealth`.

`float`/`terminal` prompt for a page range up front because both are worse
fits for a whole long document than `buffer` is (float wraps at 80% width,
terminal renders one rasterized image per page). If you already know you
want the whole thing, `buffer` skips the prompt entirely.

## Backend fallback: what actually happens when your preferred backend is missing

`fallback_chain` (default: `pdftotext, pdfplumber, marker, docling, ollama,
tesseract, claude`) is not a strict preference order you have to match
exactly — `core/resolver.lua` builds the real chain per call:

1. An explicit `backend_id` (e.g. `pdfport.open({ backend_id = "claude" })`) goes first.
2. Otherwise `default_backend` (if set, not `"auto"`) goes first.
3. `fallback_chain` fills the rest.
4. Any backend registered but *not* in `fallback_chain` (a custom one via `register_backend()`) is appended at the end — always reachable, never silently dropped.
5. Deduplicated, then walked in order; the first one whose `available()` returns `true` wins.

So requesting `claude` when `ANTHROPIC_API_KEY` isn't set does **not** error
out — it silently falls through to the rest of `fallback_chain` (pdftotext,
pdfplumber, ...) and you get a result from whatever's actually installed,
with no indication in the result itself that your explicit choice was
skipped. If that matters, check `:checkhealth pdfport` or
`registry.diagnostics()` (`:PdfPort backends`) *before* the call, not after
a plain-text result surprises you when you asked for `claude`'s Markdown
output.

Same shape on the write side: `pdfport.create()` resolves a **producer**
per input kind via `create_chain[kind]` (e.g. `create_chain.html =
{ "weasyprint", "chromium" }`) — `producer_id` explicit request first, then
the kind's chain, same dedup/fallback logic as `resolver.lua`.

## Lazy-proxy loading: when a backend module actually gets `require`d

`setup()` registers all seven backends and nine producers as lazy proxies
(`backends/init.lua`'s `make_lazy_backend`, mirrored by
`producers/init.lua`'s `make_lazy_producer`) — a lightweight stand-in table,
not the real module. The real `require("pdfport.backends.claude")` (or
`ollama`, `marker`, ...) only happens the first time the resolver's fallback
walk reaches that id far enough to call `.available()` on it.

Two consequences worth knowing before you go debugging a "why hasn't my
custom `_set_config` value taken effect" problem:

- **Position in the chain matters for load timing, not just result.** If `pdftotext` is available and first in the chain, `claude.lua`/`ollama.lua` may never get `require`d at all in a given session — no wasted work parsing/loading modules you're not going to use, but also no `_set_config` call on them, no side effects from their top-level code, until the walk actually reaches them.
- **A backend/producer that fails to `require`** (syntax error, missing dependency at Lua level, not at CLI-tool level) reports `available() == false` from the proxy rather than throwing at `setup()` time — `load_failed` is cached so it isn't retried every call. If a backend you expect to be available never shows up in `registry.diagnostics()` as available, check for a Lua-level load error, not just the CLI tool's presence on PATH.

Custom backends/producers registered via `pdfport.register_backend()`/
`register_producer()` are **not** lazy — they're already real tables by the
time you pass them in, so they load whenever your own code loads them.

## The resolve → extract/create → render pipeline, end to end

Read side (`core/dispatcher.lua`):

```
opts.path validated (exists, regular file)
  -> mode == "system"/"terminal"? render directly, skip everything below
  -> resolver.resolve(opts.backend_id) -> backend
  -> cache check (path + backend id + page-range variant)
  -> progress indicator started (lib.nvim.progress, no-op if absent)
  -> backend.extract(path, extract_opts)  [pcall'd]
  -> cache write on success
  -> callback(result)
  -> [M.open() only] registry.get_renderer(opts.mode) -> renderer(result, render_opts)
```

Write side (`core/composer.lua`) is the same shape with backend -> producer
and extract -> create, plus one extra step: an input kind has to be known
before a producer can be resolved (`opts.from`, or guessed from the file
extension — `.png` -> `image`, `.md` -> `markdown`, `.html` -> `html`,
`.docx`/`.odt`/`.xlsx`/`.pptx` -> `office`; `text`/`bufnr` inputs must pass
`opts.from` explicitly since there's no extension to guess from).

`pdfport.merge()` is not a separate pipeline — it's `composer.create()` with
`from` fixed to `"pdf"`, so `on_conflict`, progress, and the tmpfile cleanup
path all apply to a merge exactly like any other creation call.

## Caching: what it does and doesn't cover

Extraction results are cached on disk (`lib.nvim.cache.disk`), keyed by
`path + backend_id + page-range-variant`, invalidated by the source file's
mtime. This means:

- Switching `backend_id` for the same file is a cache **miss**, not a stale hit — each backend gets its own cache entry.
- Re-running the exact same `:PdfPort text` on an unchanged file is instant on the second call, backend never invoked.
- `pdfport.create()`/`merge()` have **no** cache at all — every creation call re-runs the producer, by design (an export has a target path; re-running it is a deliberate action, not a repeated read).

Opt out per call with `extract_opts.cache = false` when iterating on a
backend that isn't yet deterministic (see next section).

## Developing/debugging a new backend or producer with `TESTS/`

`TESTS/` is a framework-free headless suite (no plenary, no busted) —
`run.lua` loads each `*_spec.lua`, hands it `harness.lua`, exits non-zero on
first failure:

```bash
nvim --headless -u NONE -c "set rtp+=." -c "set rtp+=../lib.nvim" -c "luafile TESTS/run.lua" -c "qa!"
```

Every backend in the suite is `H.fake_backend` — a stub with a hard-coded
`available()`, nothing shells out to a real tool. That means the suite
verifies **chain-resolution logic**, not real extraction: whether the
resolver picks the right id given `default_backend`/`fallback_chain`/
`backend_id`, whether the registry rejects malformed registrations, whether
`setup()` stays idempotent. It cannot tell you whether your new backend's
`extract()` actually parses `pdftotext`'s output correctly — that still
needs a real install and a real PDF, manually, outside the suite.

When adding a new backend or producer:

1. Write it against the shape `registry.lua` asserts on registration — backend: `{ id, available(), extract(path, opts) }`; producer: `{ id, accepts, available(), create(req) }`.
2. Add a case to `resolver_spec.lua` (or `producer_spec.lua`) using `H.fake_backend`/an equivalent fake producer if the chain-resolution behavior around it needs covering — e.g. "does it get skipped when unavailable and the chain falls through to the next entry."
3. Run the suite locally before wiring it into `backends/init.lua`'s `BUILTIN_BACKENDS`/`producers/init.lua`'s `BUILTIN_PRODUCERS` — a spec failure there is cheaper to chase down than a `:checkhealth`-reported "unavailable" with no further detail.
4. Mind spec order: `registry_spec.lua` asserts the seven built-in backend modules are **not yet** in `package.loaded` (the lazy-proxy contract) — it must run before `smoke_spec.lua`, which requires all of them on purpose. A new spec that also touches lazy-loading needs to respect that same ordering constraint in `run.lua`'s `specs` list.
5. For CLI-tool-dependent behavior the suite can't cover, verify manually against `:checkhealth pdfport` (reports the live registry state — per-id availability from an actual `setup()` call, not just a static tool-on-PATH check) before trusting the new entry in a real session.

## Combining renderers with the picker integrations

The file-tree integrations (neo-tree/nvim-tree/netrw/oil) all resolve "path
under cursor" differently but funnel into the same
`pdfport.integrations().open_current(opts)` (or their own `keymaps()`), which
defaults to `mode = "buffer", split = "vsplit", focus = true`. Overriding
`opts.mode` there gets you `float`/`terminal`/`system` from a tree keymap
without writing a new command — e.g. binding a second keymap to
`open_current({ mode = "terminal" })` for a quick visual check without
leaving the tree.

Telescope/fzf-lua previewers are a separate path — they call extraction
directly for the preview pane (`opts.max_pages` bounds it), not through
`open()`, so they never touch a renderer at all; what you see in the
preview pane is raw extracted text/Markdown, not a rendered buffer.

## Gotchas worth knowing before they cost you a debugging session

- **`system`/`terminal` never populate `result.text`.** If you're chaining `pdfport.open()`'s callback into something that reads the extracted text, those two modes hand the renderer a synthetic `status = "ok"` result with `text = nil` — there's nothing to read. Only `buffer`/`float` (and `pdfport.extract()` directly) return real text.
- **A cache hit skips the progress indicator entirely** — `start_progress()` is only invoked past the cache check, so a repeated call on an unchanged file returns near-instantly with no visible indicator at all, which is correct but can look like the command silently did nothing on a fast machine.
- **`on_conflict = "suffix"` caps at `-9999`.** Past that, `composer.create()` returns an error rather than looping forever — relevant if a script calls `pdfport.create()` in a tight loop against the same output stem.
- **`claude` backend never leaks the API key to `ps`.** It's written to a temporary curl `-K` config file (best-effort `0600`, real on POSIX, a no-op on Windows) rather than passed as a `-H` argv element, deleted once the request completes — don't "simplify" this into a direct `-H "x-api-key: ..."` invocation when touching `backends/claude.lua`.

## Cross-references

- [docs/FEATURES/BACKENDS.md](FEATURES/BACKENDS.md), [PRODUCERS.md](FEATURES/PRODUCERS.md), [RENDERING.md](FEATURES/RENDERING.md), [CORE.md](FEATURES/CORE.md), [INTEGRATIONS.md](FEATURES/INTEGRATIONS.md) — what each piece does in isolation.
- [docs/BINDINGS.md](BINDINGS.md) — every keymap/command/autocmd, with defaults and override syntax.
- [docs/configuration.md](configuration.md) — every `setup()` key, including `fallback_chain`/`create_chain`/`render_opts`.
- [TESTS/README.md](../TESTS/README.md) — running the suite, adding a spec, the fake-backend/fake-producer harness.
