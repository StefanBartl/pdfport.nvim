# Concept — PDF creation as a public API

Status: **P0–P3 implemented (2026-08-09)** — the scaffolding plus the image
producers (`img2pdf`/`magick`), the text/Markdown producer (`pandoc`, with
engine auto-detection), the HTML producers (`weasyprint`/`chromium`), the
Office producer (`soffice`) and the merge producers
(`qpdf`/`pdftk`/`ghostscript`, through `pdfport.merge()`), plus
`pdfport.create()`/`can_create()`/`merge()` (including `text`/`bufnr` inputs via
`util/tmpfile.lua`), `:PdfPort create`/`:PdfPort merge`/`:PdfPort producers`,
tests and documentation. See [docs/FEATURES/](../FEATURES/). **P2 (wiring up
the callers) is complete:** `filetree.nvim` (`util/pdf.create()` plus
`features/system/pdf_create`), `images.nvim` (`convert.to_pdf`/`M.export` route
asynchronously through `pdfport.create()` when it is available, otherwise the
previous `magick` path unchanged) and `markdown.nvim` (`:Markdown export pdf`,
the new `markdown.commands.export`, following `markdown.commands.image`
exactly) — each documented in its own repository. The concept itself is as of
2026-08-07.

Today pdfport can only *read*: PDF to text/Markdown (`backends/`,
`core/dispatcher.lua`), or a PDF page to an image (internally, in
`renderers/terminal.lua`). This document describes the other direction —
**something to PDF** — shaped so that it primarily works as an **API for other
plugins** (`images.nvim`, `markdown.nvim`, `filetree.nvim`), not just as a user
command.

The guiding idea: pdfport is the one place in this setup that holds
PDF-specific knowledge — which tool can do what, how it is invoked, what
happens on Windows. Every other plugin calls in, and knows about neither
`pandoc` nor `magick` nor a fallback chain.

---

## 1. Why in pdfport at all, rather than per plugin

What exists today is already a threefold duplication in slow motion:

- `images.nvim` has `images.convert.to_pdf` — ImageMagick, one image, no
  options, a synchronous `vim.system():wait()`.
- `markdown.nvim` has no export, and that would be the obvious next wish
  (`:Markdown export pdf`).
- `filetree.nvim` has nothing at all, but would naturally offer exporting a
  selection (several images into one PDF).

Left to themselves, each plugin would grow its own tool detection, its own
error handling, its own Windows quirk. This is exactly the case pdfport already
has a registry, a resolver, a fallback chain, a progress indicator and
`platform.has()` for — creation is structurally the same problem as extraction,
with the arrow reversed.

---

## 2. Tools — weighing the alternatives

First, the thing that decides the shape: **no single tool covers every input.**
`pandoc` is not a PDF producer but a converter, and for PDF it *always* needs
an external engine. So this cannot be a "we'll use pandoc" decision; it is a
chain per input kind.

### Image to PDF

| Tool | Assessment |
|---|---|
| **`img2pdf`** (Python) | **First choice.** Lossless: embeds the JPEG/PNG data *unchanged* rather than re-encoding it. Tiny package, no system dependency, handles several images into one PDF, takes page size and margins as arguments. Downside: needs Python, which is not everywhere. |
| **ImageMagick** (`magick a.png b.png out.pdf`) | **Second choice, and the pragmatic default.** Assumed present in this setup anyway (`images.nvim` builds on `magick`, see its `convert.lua`), and can do multi-image to multi-page PDF natively. Downside: it recompresses, so PDFs come out larger and marginally worse. |
| `typst` / LaTeX with `\includegraphics` | Overkill for "image in, PDF out", but interesting the moment headers, footers, a title or captions come into it (a gallery export as a contact-sheet-like document). |
| Ghostscript | Cannot read an image at all. Relevant for *merging and compressing* finished PDFs, not here. |

### Markdown/text to PDF

| Tool | Assessment |
|---|---|
| **`typst compile`** | **First choice for "without the baggage".** A single binary (~30 MB), no TeX distribution, compiles in milliseconds, good typography out of the box. Downside: Markdown is not its input language — it needs either pandoc in front of it or a small Markdown-to-Typst template of one's own. |
| **`pandoc --pdf-engine=…`** | **First choice for correctness.** Handles Markdown dialects, footnotes, citations, tables of contents, templates. But: it strictly requires an engine. Engine search order: `tectonic` (fetches TeX packages itself, no 4 GB TeXLive) → `typst` (pandoc ≥ 3.1.11 supports `--pdf-engine=typst`) → `xelatex`/`lualatex`/`pdflatex` → `weasyprint`/`wkhtmltopdf` (the HTML detour, with worse page breaks). |
| `mdview.nvim` plus browser printing | Present in this ecosystem, but the path runs through a browser tab and a manual print dialog — not scriptable. Rejected. |
| `md-to-pdf`, `mdpdf` (npm) | A Node dependency for something pandoc and typst do better. Rejected. |

### HTML to PDF

`weasyprint` (clean CSS paged media, Python) → `chromium --headless
--print-to-pdf` (available everywhere, but with a dreadful command line and
dreadful default margins) → `wkhtmltopdf` (unmaintained, an old WebKit engine,
last link only).

### Office to PDF

`soffice --headless --convert-to pdf --outdir <dir> <file>` covers
docx/odt/xlsx/pptx in one call. Heavyweight and slow on first start, but the
only realistic option. Optional, and last in line.

### PDF to PDF (merging, phase 2)

`qpdf --empty --pages a.pdf b.pdf -- out.pdf` (small, exact, no re-encoding) →
`pdftk` → Ghostscript. Not part of the first stage, but the API is cut so that
it can be added later without a break.

### Conclusion

First stage: **`img2pdf` → `magick`** for images, **`pandoc` (plus an engine) →
`typst`** for text and Markdown. Everything else is additional producers in the
same registry, not a rebuild.

---

## 3. Architecture

Deliberately a mirror image of the existing read path, so nobody has to learn
two patterns:

```
                READING (today)                  WRITING (new)
  API           pdfport.open/extract             pdfport.create
  Coordination  core/dispatcher.lua              core/composer.lua
  Selection     core/resolver.lua                core/resolver.lua  (extended)
  Registry      registry.register_backend        registry.register_producer
  Implementation backends/*.lua                  producers/*.lua
  Output        renderers/*.lua                  (a file on disk)
```

New files:

```
lua/pdfport/producers/init.lua      -- lazy proxy registration, like backends/init.lua
lua/pdfport/producers/img2pdf.lua
lua/pdfport/producers/magick.lua
lua/pdfport/producers/pandoc.lua
lua/pdfport/producers/typst.lua
lua/pdfport/producers/weasyprint.lua   -- phase 2
lua/pdfport/producers/soffice.lua      -- phase 2
lua/pdfport/core/composer.lua
lua/pdfport/util/tmpfile.lua        -- materialize buffer/string inputs
```

Reused unchanged: `platform.has`, `util/notify`, the progress indicator from
`dispatcher.lua` (which moves into a small shared helper for this rather than
being copied), and `lib.nvim.cross.uv.spawn_capture`.

**No cache.** The read path caches because the same PDF is read repeatedly; an
export is a one-off, explicit action with a target path — the same reasoning
already written down for `to_pdf` in `images.convert`.

### The producer interface

```lua
---@alias PdfPort.InputKind "image"|"markdown"|"html"|"text"|"office"|"pdf"

---@class PdfPort.ProducerCapabilities
---@field batch boolean      # several inputs into one document
---@field lossless boolean   # embeds the source data unchanged
---@field styling boolean    # honours page size / margins / template
---@field toc boolean        # can generate a table of contents
---@field remote boolean     # needs the network

---@class PdfPort.Producer
---@field id PdfPort.ProducerId
---@field name string
---@field accepts PdfPort.InputKind[]
---@field capabilities PdfPort.ProducerCapabilities
---@field available fun(): boolean
---@field create fun(req: PdfPort.InternalCreateOpts): PdfPort.CreateResult|nil
```

`create` follows `Backend.extract`'s convention exactly: an asynchronous
producer returns `nil` and calls `req.__callback`, a synchronous one returns a
result directly — the composer handles both (see `dispatcher.lua:228`).

### The result

```lua
---@class PdfPort.CreateResult
---@field status "ok"|"error"|"partial"
---@field path string|nil        # the file that was produced
---@field producer PdfPort.ProducerId
---@field pages integer|nil
---@field error string|nil
```

---

## 4. The public API

One entry point, deliberately in the same shape as `open`/`extract` (a table
in, `__callback` out):

```lua
require("pdfport").create({
  -- Input: exactly one of inputs / text / bufnr
  inputs  = { "/path/a.png", "/path/b.png" },  -- files; order is page order
  -- text = "# Title\n\nParagraph",            -- content directly
  -- bufnr = 0,                                -- buffer content

  from    = "image",          -- optional; otherwise guessed from extension/`filetype`
  output  = "/path/out.pdf",  -- optional; default: beside the first input, same stem

  producer_id = nil,          -- optional; nil = automatic, via the chain
  on_conflict = "overwrite",  -- "overwrite" | "suffix" (out-1.pdf) | "error"

  opts = {                    -- all optional; producers ignore what they do not know
    page_size = "A4",
    margin    = "20mm",
    dpi       = 300,          -- image path only
    fit       = "contain",    -- "contain" | "fill" | "native"
    title     = nil,
    toc       = false,        -- text path only
    template  = nil,          -- a pandoc/typst template
    timeout_ms = 60000,
  },

  __callback = function(res) ... end,  -- optional; without it, fire-and-forget with notify
})
```

Plus these two, because both are needed immediately in practice:

```lua
require("pdfport").register_producer(p)            -- as register_backend
require("pdfport").can_create("markdown")          -- boolean, for callers' soft deps
require("pdfport").merge({ inputs, output, ... })  -- phase 2, qpdf/Ghostscript
```

And for completeness, the opposite direction already noted in
[ROADMAP.md](../ROADMAP.md): `render_page(path, page, opts, cb)` (a PDF page to
a PNG). Same signature shape, same registry thinking; it should be designed
together with this concept, so `images.nvim` addresses both directions the same
way.

### Commands

Inside the existing one-verb composer (`:PdfPort <sub>`), with no new flat
commands:

```
:PdfPort create              " the current buffer, to a PDF beside it
:PdfPort create <file…>      " one or more files into one PDF
:PdfPort producers           " diagnostics, as `:PdfPort backends`
```

A visual selection in the file tree into one PDF runs through
`util/batch.lua`, which already knows how to resolve line by line.

### Configuration

```lua
require("pdfport").setup({
  create_opts = { page_size = "A4", margin = "20mm", dpi = 300, timeout_ms = 60000 },
  create_chain = {                       -- per input kind, like fallback_chain
    image    = { "img2pdf", "magick" },
    markdown = { "pandoc", "typst" },
    html     = { "weasyprint", "chromium", "wkhtmltopdf" },
    office   = { "soffice" },
  },
  pdf_engine = "auto",                   -- pandoc: auto|tectonic|typst|xelatex|…
})
```

---

## 5. Wiring up the three callers

Everywhere a **soft dependency through `pcall`**, as is usual across this
ecosystem: without pdfport, the previous behaviour stands.

### `images.nvim` — done (2026-08-09)

`images.convert.to_pdf` is now the thin switch: if pdfport is there and
`can_create("image")` reports a producer, the export goes that way
(asynchronous, lossless via `img2pdf`, otherwise `magick` — which producer
wins is pdfport's own `create_chain` to decide); otherwise the previous
synchronous `magick` path stands word for word as the fallback. Implemented
almost exactly as sketched below, except with an `on_done(ok, out_or_err)`
instead of a synchronous return value — the pdfport path is async and the
magick path calls `on_done` synchronously, so that `images.export()` (the
public `:Image export` entry point) treats both the same way instead of
distinguishing two calling conventions:

```lua
function M.to_pdf(path, on_done)
  local ok, pdfport = pcall(require, "pdfport")
  if ok and pdfport.can_create("image") then
    pdfport.create({ inputs = { path }, from = "image", __callback = function(result)
      if on_done then on_done(result.status == "ok", result.path or result.error) end
    end })
    return nil, nil
  end
  -- … the previous magick path unchanged, calling on_done synchronously …
end
```

**Not implemented**, and deliberately out of scope: `:Image gallery` or a
multi-selection producing **one** multi-page PDF rather than n separate files.
It would be a sensible follow-up, but it is a new UI/selection feature inside
images.nvim, not a matter of wiring.

### `markdown.nvim` — done (2026-08-09)

`:Markdown export pdf` — the new `markdown.commands.export`, following
`markdown.commands.image` (the existing images.nvim wiring) exactly: an
unmodified buffer with a file on disk exports that file directly
(`from = "markdown"`); an unsaved or new buffer exports the buffer content
instead (`bufnr = 0`, `from = "markdown"`, `output` set explicitly — pdfport
materializes it itself through `util/tmpfile.lua`). The plugin knows about
neither pandoc nor an engine; the "nothing installed" disappointment is
pdfport's to phrase, not markdown.nvim's (`can_create("markdown")` gates the
subcommand before it runs). Gated behind `config.feature_enabled("export")`,
like every other `:Markdown` subcommand.

### `filetree.nvim` — done (2026-08-09)

`util/pdf.lua` was already "the one place where filetree talks to pdfport", and
gained `M.create(paths, opts)`. Target resolution works as it does for
`trash`/`copy_move` (marked nodes, otherwise the node under the cursor; a
directory node expands to its immediate child files, not recursively) in the
new `features/system/pdf_create` feature (key `gP`), which always asks through
`filetree.util.confirm` (= `lib.nvim.ui.kit.confirm`) before anything is
written. One PDF per input file — no merging of a multi-selection into a shared
PDF, which would make no sense anyway for mixed file types in one folder.

> **Already fixed (2026-08-07):** `filetree/util/pdf.lua`'s `M.has_pdfport()`
> and `M.open()` were already calling `require("pdfport")` correctly rather
> than `require("pdfport_nvim")` before this pass — the bug from the personal
> roadmap no longer existed by then.

---

## 6. Pitfalls, decided up front

- **Never a shell string, always an argument table.** The `cmd /c start` `&`
  bug (2026-07-25, five repos) came from exactly that. Every producer spawns
  through `spawn_capture` with an `argv` table.
- **ImageMagick on Windows**: `magick` is the invocation; `convert.exe`
  collides with Windows' own `convert`. So `platform.has("magick")`, never
  `convert`.
- **A target-path conflict** is a deliberate decision by the caller
  (`on_conflict`), not a silent overwrite in the core. Default for the
  commands: `suffix`; for the API call: whatever the caller sets, with
  `overwrite` as the default, because that is how `images.convert.to_pdf`
  behaves today.
- **A buffer with no file, or a `text` input**, lands in
  `stdpath("cache")/pdfport.nvim/tmp` via `util/tmpfile.lua` and is deleted
  after the run — including on failure (`vim.schedule` plus `pcall`).
- **Relative image paths in Markdown** break when compilation happens in a
  temp directory. pandoc and typst are therefore invoked with
  `--resource-path` / `--root` pointing at the source file's directory.
- **Timeouts**: creation is allowed to take a while (a first LaTeX run, an
  soffice start), so the default is 60 s rather than the read path's 30 s.
- **Progress** comes for free once the composer uses the same `start_progress`
  helper as the dispatcher — which moves out of `dispatcher.lua` into a shared
  module for that.

---

## 7. Stages

1. ~~**P0 — scaffolding and images.**~~ **Done (2026-08-09).** The `@types`
   extension, `registry.register_producer`, `core/composer.lua`,
   `producers/img2pdf.lua` and `producers/magick.lua`,
   `pdfport.create`/`can_create`, `:PdfPort create`, `:PdfPort producers`, the
   `health.lua` section, and tests (`TESTS/producer_spec.lua`). The API is
   usable from here (`opts.inputs` = file paths; `text`/`bufnr` inputs stayed
   for P1). Still open at that point: the actual wiring inside `images.nvim`
   (P2).
2. ~~**P1 — text.**~~ **Done (2026-08-09), with a reduced cut.**
   `producers/pandoc.lua` with internal engine auto-detection (tectonic →
   typst → xelatex → lualatex → pdflatex, via `--pdf-engine`),
   `from = "markdown"|"text"`, and `util/tmpfile.lua` (`opts.text`/`opts.bufnr`
   in `pdfport.create()`, requiring `from` and `output`, cleaned up after the
   result callback). No separate `producers/typst.lua`: per section 2, typst as
   a direct Markdown source needs pandoc in front of it or a template of its
   own anyway, which is the same thing as pandoc's `--pdf-engine=typst` rather
   than a second top-level producer. `:Markdown export pdf` itself remained P2
   (caller wiring).
3. ~~**P2 — wire up the callers.**~~ **Done (2026-08-09), all three.** The
   filetree bugfix (`pdfport_nvim`) was found already fixed. `filetree.nvim`:
   `util/pdf.create()` plus the `pdf_create` feature (marks / node under cursor
   / folder, confirmed through `lib.nvim.ui.kit`). `images.nvim`:
   `convert.to_pdf`/`M.export` route asynchronously through `pdfport.create()`
   when available, otherwise `magick` unchanged. `markdown.nvim`:
   `:Markdown export pdf` (`markdown.commands.export`, following the
   `commands.image` pattern exactly). All three documented in their own
   repositories. Not implemented: `:Image gallery` / a multi-selection into one
   shared multi-page PDF — a UI feature inside images.nvim, not wiring; see
   section 5.
4. ~~**P3 — breadth.**~~ **Done (2026-08-09).** `weasyprint`/`chromium` (HTML),
   `soffice` (Office), and `pdfport.merge()` over `qpdf`/`pdftk`/`ghostscript`
   (registered as ordinary "pdf" producers; `merge()` is a thin wrapper around
   `composer.create({ from = "pdf" })`).

## 8. Tests

Following `TESTS/registry_spec.lua`/`resolver_spec.lua`: headless, and with no
framework. A **stub producer** that needs no external binary covers
registration, chain resolution per `InputKind`, `on_conflict`, both the
synchronous *and* the `__callback` return paths, and the "no producer
available" failure. The real producers stay untested in CI — the same line
taken for the extraction backends.
