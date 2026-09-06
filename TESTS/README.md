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

## No external tools required

Every backend in these specs is a fake (`harness.fake_backend`) with a
hard-coded `available()`. Nothing here shells out to `pdftotext`, Python,
Ollama or Tesseract, so the suite gives the same result on a bare CI runner
as on a fully-equipped machine. What it covers is load errors and
chain-resolution logic — not real PDF extraction, which cannot be verified
without the tools and a corpus.

## Specs

| Spec | Covers |
| --- | --- |
| `install_spec_spec.lua` | `docs/install.json` itself: it validates with **zero** errors through the real parser, `gs` declares its Windows spellings, and every tool is optional with a non-empty `why` and at least one package. The file is data nothing else reads, so a typo there surfaces only as a tool quietly missing from `:checkhealth` — which looks exactly like a tool nobody declared. |
| `page_range_spec.lua` | `util.page_range.parse` — ranges, dedup, sorting, reversed ranges, junk input |
| `rasterize_args_spec.lua` | `core.rasterize.args` — the pdftoppm command line for one page, especially the all-or-nothing `-x -y -W -H` crop window |
| `registry_spec.lua` | backend/renderer registration, input guards, defensive copies, and the lazy-proxy contract |
| `resolver_spec.lua` | fallback-chain resolution: explicit request, `default_backend`, `auto`, nothing available |
| `producer_spec.lua` | the registry's producer half + `core.composer` (the `create()` mirror of dispatcher/resolver), against fake producers |
| `smoke_spec.lua` | every module loads, `setup()` is idempotent, commands/renderers/health are wired |
| `open_done_spec.lua` | `pdfport.open`'s `on_done` signal settles exactly once on every path (runs last — it calls `setup()` and performs real opens) |

## Ordering

`run.lua`'s spec order is deliberate: `registry_spec` and `producer_spec`
assert that the built-in backend/producer modules are **not** yet in
`package.loaded` (that is the lazy-proxy contract), so they must run before
`smoke_spec` (which requires all seven backends on purpose) and
`open_done_spec` (which calls `setup()` and performs real opens).

## Adding a spec

Create `TESTS/<name>_spec.lua` returning `function(H) ... end`, then add its
filename to the `specs` list in `run.lua`. Use `H.eq`/`H.ok`/`H.falsy`/
`H.match`/`H.eq_list` for assertions and `H.fake_backend` whenever a test
would otherwise depend on a real extraction tool.
