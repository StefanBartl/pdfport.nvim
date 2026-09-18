# Contributing to pdfport.nvim

Thank you for your interest! Bugs, ideas and questions are welcome in the
[issue tracker](https://github.com/StefanBartl/pdfport.nvim/issues); pull
requests very welcome.

## Getting the repository into a session

Clone it and either symlink the checkout into your plugin directory or add it
to the runtime path directly:

```lua
vim.opt.rtp:prepend("/path/to/pdfport.nvim")
require("pdfport").setup({})
```

[lib.nvim](https://github.com/StefanBartl/lib.nvim) has to be on the runtime
path too — `:PdfPort` is built on its user-command composer. Beyond that you
need at least one extraction backend on `PATH`; `pdftotext` from poppler is the
cheapest one to install and the one most specs assume.

## Ground rules

- Lua only, idiomatic Neovim Lua. 2-space indentation, `stylua.toml` decides
  the rest.
- **This plugin drives tools; it does not parse PDFs.** Every capability is a
  thin, well-behaved wrapper around an external program. A pure-Lua PDF parser
  does not belong here — the value is in the resolution, the fallback chain,
  the cache and the uniform interface, not in reimplementing poppler.
- **A missing tool is a message, never an error.** Backends and producers are
  resolved at runtime and required lazily — one `require` only once a backend
  is actually chosen. Nothing may throw at `setup()` because a CLI is absent,
  and the absence has to be visible in `:checkhealth pdfport`.
- **Everything goes through the registry.** `core/registry.lua` and
  `core/resolver.lua` own which backend or producer answers a request.
  `register_backend()` and `register_producer()` are public for a reason: a new
  one is a registration, not a branch in the dispatcher.
- **One mode picker, and it is public.** `pick_open()` exists because the
  picker used to live twice and the two copies had already drifted in their
  labels and in whether "system application" was offered at all. There is one
  canonical list now, it always appends "system application" when a caller's
  list omits it, and embedding plugins — filetree.nvim, gopath.nvim,
  markdown.nvim, documentation.nvim — call it instead of building their own.
  Do not add a second prompt anywhere.
- **The cache is keyed on mtime.** A successful extraction persists across
  restarts and is invalidated when the PDF changes. A cache hit deliberately
  skips the progress indicator, which is correct but can look like nothing
  happened — do not "fix" that by starting the indicator earlier.
- **Secrets never reach `ps`.** The `claude` backend writes its API key into a
  temporary curl `-K` config file (best-effort `0600`, real on POSIX, a no-op
  on Windows) and deletes it once the request completes. Do not simplify that
  into a `-H "x-api-key: …"` argv element when touching
  `backends/claude.lua`.
- Commands are registered through `lib.nvim.bindings.usercmd.composer`.
- Descriptive commit messages.

## Project layout

| Path | Contains |
| --- | --- |
| `lua/pdfport/core/` | `registry`, `resolver`, `dispatcher`, `composer` (creation and conflict handling), `rasterize` |
| `lua/pdfport/backends/` | One file per extraction backend: pdftotext, pdfplumber, marker, docling, ollama, claude, gemini, tesseract |
| `lua/pdfport/producers/` | One file per creation or merge producer: img2pdf, magick, pandoc, weasyprint, chromium, soffice, qpdf, pdftk, ghostscript |
| `lua/pdfport/renderers/` | Where an extraction ends up: buffer, float, system, terminal |
| `lua/pdfport/integrations/` | The file-tree adapters (neotree, nvim_tree, netrw, oil) and the fuzzy-finder ones (telescope, fzf) |
| `lua/pdfport/util/` | The cache, path canonicalization, the page-range parser, the picker, batch handling, temp files, spawn environment, notifications |
| `lua/pdfport/platform/` | Per-OS differences |
| `lua/pdfport/bindings/`, `config/` | The `:PdfPort` route tree and keymaps; `DEFAULTS.lua` and validation |
| `doc/`, `docs/` | The vimdoc, and everything the README links to |
| `TESTS/` | The spec suite |

## Adding a backend or a producer

Both follow the same shape, which is why they live in parallel directories.

1. Add the module under `lua/pdfport/backends/` or `lua/pdfport/producers/`,
   modelled on the closest existing one.
2. Declare availability as a runtime check, and make it cheap — it runs for
   `:PdfPort backends` and for `:checkhealth pdfport`.
3. Register it rather than adding a branch anywhere. Nothing outside the
   registry should know the new name.
4. Require anything heavy lazily, inside the call, not at module load.
5. Report progress through the shared machinery, and honour `on_conflict` for
   anything that writes a file.
6. Declare the CLI tool in [`install.json`](install.json) with a real `why` —
   that string is what a user reads in the deps popup — and add it to
   `health.lua`.
7. Add a spec under `TESTS/`. Specs assert on the composed argv, not on running
   the tool: CI has no poppler, no chromium and no model.
8. Document it in [`FEATURES/BACKENDS.md`](FEATURES/BACKENDS.md) or
   [`FEATURES/PRODUCERS.md`](FEATURES/PRODUCERS.md), and in
   [`configuration.md`](configuration.md) if it adds an option.

## Adding a file-tree integration

Only for third-party trees — filetree.nvim needs none, because it calls
`pdfport.pick_open()` directly.

1. Add the adapter under `lua/pdfport/integrations/`, exposing the same five
   actions every other one does: `open`, `open_text`, `open_system`,
   `open_terminal`, `open_batch`.
2. Accept `false` for any action to disable that keymap, and register the rest
   with which-key descriptions under `<leader>p`.
3. Teach `open_current()` to detect the new tree.
4. Document the setup snippet in [`integrations.md`](integrations.md) and the
   keys in [`BINDINGS.md`](BINDINGS.md).

## Tests

`TESTS/` is a headless spec suite over the argv composition, the resolver, the
registry and the page-range parser — nothing in it runs an external tool.

```
nvim --headless -u NONE -c "set rtp+=." -c "set rtp+=../lib.nvim" \
  -c "luafile TESTS/run.lua" -c "qa!"
```

Exit 0 is a pass; lib.nvim is expected as a sibling checkout.
[GitHub Actions](../.github/workflows/ci.yml) runs it plus stylua and luacheck
on every push and pull request to `main`.

## Workflow

1. Fork the repository.
2. Branch as `feature/<name>`.
3. Make the change, add a spec, update the affected pages under `docs/`.
4. Open a PR with a clear description of what changed and why — and name the
   external tool it needs, if any.
