# Producers

The write direction: `pdfport.create()`/`:PdfPort create` (and
`pdfport.merge()`/`:PdfPort merge`) resolve a **producer** through a
per-input-kind fallback chain (`create_chain`) and write a PDF. Mirrors the
read side's shape exactly — `registry.register_producer`,
`core/composer.lua`, lazy-loaded `producers/*.lua` via `make_lazy_producer`
in `producers/init.lua` — so the same mental model applies to both
directions. `setup()` only wires up a lightweight stand-in per producer; the
real module is `require`d the first time the composer's resolver walk
actually calls `available()`/`create()` on it.

Nine builtins across two groups: five **creation** producers (accept an
input kind, write a new PDF) and three **merge** producers (accept `"pdf"`,
combine several into one).

## img2pdf creation producer

Wraps `img2pdf` (`pip install img2pdf`) — lossless, no recompression. First
choice for image inputs in the default `create_chain.image`.

- **Module:** `lua/pdfport/producers/img2pdf.lua`
- **Accepts:** `image`
- **Requires:** `pip install img2pdf`

## magick creation producer

Wraps ImageMagick's `magick` CLI. Pragmatic default/fallback for image
inputs when img2pdf isn't installed; recompresses rather than staying
lossless.

- **Module:** `lua/pdfport/producers/magick.lua`
- **Accepts:** `image`
- **Requires:** ImageMagick (`magick` on PATH)

## pandoc creation producer

Wraps `pandoc`, auto-detecting a PDF engine in priority order: tectonic ->
typst -> xelatex -> lualatex -> pdflatex (`platform.first_available`). The
only producer registered for markdown and text inputs in the default
`create_chain`.

- **Module:** `lua/pdfport/producers/pandoc.lua`
- **Accepts:** `markdown`, `text`
- **Requires:** `pandoc` + one of the PDF engines above on PATH

## weasyprint creation producer

Wraps `weasyprint` (`pip install weasyprint`) for HTML input — first choice
in `create_chain.html`: clean CSS Paged Media support without needing a
browser installed.

- **Module:** `lua/pdfport/producers/weasyprint.lua`
- **Accepts:** `html`
- **Requires:** `pip install weasyprint`

## chromium creation producer

Fallback HTML producer when weasyprint isn't available: headless
print-to-pdf via any Chromium-family browser
(`platform.first_available({ "chromium", "chromium-browser",
"google-chrome", "chrome", "msedge" })`).

- **Module:** `lua/pdfport/producers/chromium.lua`
- **Accepts:** `html`
- **Requires:** a Chromium-family browser on PATH

## soffice creation producer

Wraps LibreOffice's `soffice` CLI. The only producer registered for
`office` inputs — handles docx/odt/xlsx/pptx in one call, converting via a
scratch directory.

- **Module:** `lua/pdfport/producers/soffice.lua`
- **Accepts:** `office`
- **Requires:** LibreOffice (`soffice` on PATH)

**Also used from outside this plugin.** `lib.nvim.hover` calls
`can_create("office")` and then `create()` to preview an office document:
there is no way to show a `.docx` in a float, but there is a way to show a
PDF, so it converts one into the other and rasterizes page 1 through
`render_page()`. That path is opt-in there (`:Lib hover office on`) precisely
because this producer starts LibreOffice, which is seconds on a first run —
worth knowing if a bug report says "the hover freezes on Word documents".

## qpdf merge producer

First choice in `create_chain.pdf` (used by `pdfport.merge()`): exact
concatenation, no re-encoding of page content.

- **Module:** `lua/pdfport/producers/qpdf.lua`
- **Accepts:** `pdf`
- **Requires:** `qpdf` on PATH

## pdftk merge producer

Merge fallback #2, tried after qpdf.

- **Module:** `lua/pdfport/producers/pdftk.lua`
- **Accepts:** `pdf`
- **Requires:** `pdftk` on PATH

## ghostscript merge producer

Merge fallback #3, last resort — recompresses page content rather than
concatenating exactly.

- **Module:** `lua/pdfport/producers/ghostscript.lua`
- **Accepts:** `pdf`
- **Requires:** `gs`/`gswin64c`/`gswin32c` (`platform.first_available`) on PATH

## Custom producer registration

Any Lua table shaped like `{ id, accepts, available(), create(req) }` can be
registered via `pdfport.register_producer()`, participating in the same
per-kind fallback chain as the nine builtins.

- **Module:** `lua/pdfport/init.lua` (`M.register_producer`), `lua/pdfport/core/registry.lua` (`M.register_producer`), `lua/pdfport/producers/init.lua` (`M.load_custom`)
