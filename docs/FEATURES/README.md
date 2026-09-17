# Features

A PDF is the one file type an editor has no answer for: opening it shows
binary, and every workaround is a different external tool with a different
command line. This plugin makes that one question — "what do I want to do with
this PDF?" — and drives whichever tool can answer it.

| Area | Does |
| --- | --- |
| **Extraction** | Seven backends — pdftotext, pdfplumber, marker-pdf, docling, Claude, Ollama, tesseract as an OCR fallback — resolved lazily, with a fallback chain and a cross-session cache invalidated by the file's mtime |
| **Rendering** | A scratch buffer (split, vsplit or tab), a floating window, the system application, or a terminal image. `float` and `terminal` prompt for a page range like `1-3,5` |
| **Creation** | Nine producers — img2pdf, magick, pandoc, weasyprint, chromium, soffice, qpdf, pdftk, ghostscript — turning an image, Markdown, text, HTML or an Office file into a PDF |
| **Merging** | Two or more PDFs into one, over the same resolve and conflict machinery |
| **Rasterization** | `render_page()` writes one page to a caller-owned PNG — the primitive other plugins build a PDF preview on |
| **The mode picker** | `pick_open()` is public: other plugins ask the "open PDF as…" question with pdfport's list instead of hand-rolling a dialog, and it still works when pdfport is not installed |

Backends like `marker`, `docling`, `ollama`, `claude` and `gemini` extract to Markdown
rather than plain text, which is what makes
[mdview.nvim](https://github.com/StefanBartl/mdview.nvim) a good place to send
the output.

pdfport.nvim moves content in two directions — PDF → text/Markdown
(**backends**) and something → PDF (**producers**) — through the same
lazy-registry/fallback-chain shape on both sides, plus four ways to display
what comes out the read side (**renderers**). This folder replaces the old
single `docs/FEATURES.md`: with eight backends, nine producers, four
renderers and a resolver/dispatcher/composer core, one flat file had grown
past the point of being a useful index.

- [BACKENDS.md](BACKENDS.md) — the eight PDF → text/Markdown extraction backends.
- [PRODUCERS.md](PRODUCERS.md) — the nine something → PDF creation/merge producers.
- [RENDERING.md](RENDERING.md) — the four output renderers and the page-range picker.
- [CORE.md](CORE.md) — the resolver/dispatcher/composer architecture, caching, health check, and diagnostics.
- [INTEGRATIONS.md](INTEGRATIONS.md) — file-tree and fuzzy-finder integrations, which-key, batch-open.

See [../commands.md](../commands.md) for the full command/Lua-API reference and
[../configuration.md](../configuration.md) for every `setup()` option.
