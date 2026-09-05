# Health

```vim
:checkhealth pdfport
```

Ten sections. Every backend/producer/renderer is independently `warn` (not
`error`) when its tool is missing — pdfport degrades to whatever chain
member *is* installed, so one missing tool is never fatal on its own.

| Section | Checks |
|---|---|
| `pdfport: core` | Core modules load (`pdfport.platform`, `pdfport.core.registry`, and the rest of the module list) |
| `pdfport: extraction backends` | Each entry in `fallback_chain`, in order: `pdftotext` (poppler-utils), `pdfplumber`/`docling` (needs a python3/python/py interpreter first, then the pip package), `marker` (`marker_single`), `ollama` (binary **and** the daemon actually running on `localhost:11434`), `tesseract` (+ `pdftoppm`), `claude` (`ANTHROPIC_API_KEY` set, and `vim.base64.encode` — Neovim 0.10+) |
| `pdfport: creation producers` | `img2pdf`, `magick`, `pandoc` (found **and** a PDF engine — tectonic/typst/xelatex/lualatex/pdflatex — on PATH), `weasyprint`, `chromium` (any Chromium-family browser), `soffice` |
| `pdfport: merge producers` | `qpdf`, `pdftk`, `ghostscript` (`gs`/`gswin64c`/`gswin32c`) — `pdfport.merge()`'s own chain, separate from the creation producers above |
| `pdfport: renderers` | `buffer`/`float` (always `ok`, built in), `system` (the resolved system PDF opener) |
| `pdfport: terminal image renderer` | The best available of `chafa`, `kitten`, `imgcat` — `warn` plus an install list if none is found |
| `pdfport: integrations` | Each optional host plugin: `ok` if loaded, `info` (not `warn`) if not — inactive is not a problem. `netrw` is always `ok` (built-in). `lib.nvim` itself is checked here too (required for `:PdfPort`), plus `lib.nvim.ui.kit` (enhanced mode picker vs. `vim.ui.select` fallback) |
| `pdfport: registered backends` | The **live** registry from the running `setup()` — `warn` if `setup()` was never called, then one `ok`/`warn` line per registered backend's actual availability |
| `pdfport: registered producers` | Same, for producers |
| `pdfport: declared tools (lib.nvim.deps)` | Cross-check against [install.json](install.json) — the same list `:Lib deps show pdfport.nvim` reads |

The two "registered" sections (backends/producers) are the ones that
actually reflect *this session*: the earlier "extraction backends" /
"creation producers" sections probe the filesystem/PATH directly and are
true regardless of whether `setup()` ran, while these two read the live
registry and go straight to `warn` if it's empty.
