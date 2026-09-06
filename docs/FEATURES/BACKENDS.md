# Backends

The read direction: `pdfport.open()`/`pdfport.extract()` resolve a **backend**
through the configurable `fallback_chain` and extract PDF content as plain
text or Markdown. All seven builtins are registered as lazy proxies
(`backends/init.lua`'s `make_lazy_backend`) — `setup()` only wires up a
lightweight stand-in per backend; the real module is `require`d the first
time the resolver's fallback walk actually calls `available()`/`extract()`
on it.

## pdftotext extraction backend

Runs the `pdftotext` CLI (poppler-utils) to pull the text layer straight out
of a PDF. The fastest backend and the only one needing no Python environment
or network access — first in the default `fallback_chain` for that reason.
Produces plain text only; does nothing for scanned/image-only PDFs (no text
layer to read).

- **Module:** `lua/pdfport/backends/pdftotext.lua` (`M.available`, `M.extract`)
- **Config:** `opts.fallback_chain` (default includes `"pdftotext"` first), `opts.extract_opts.timeout_ms` (default `30000`)
- **Requires:** `pdftotext` on PATH (poppler-utils)

## pdfplumber extraction backend

A Python-based extractor (`pip install pdfplumber`) for plain-text output,
tried after pdftotext in the default chain.

- **Module:** `lua/pdfport/backends/pdfplumber.lua`
- **Requires:** a Python interpreter (`python3`/`python`/`py`) with `pdfplumber` installed

## marker extraction backend

Runs `marker_single` (`pip install marker-pdf`) to produce Markdown output,
including tables — the first Markdown-producing backend in the default
chain, ahead of docling/ollama/claude.

- **Module:** `lua/pdfport/backends/marker.lua`
- **Requires:** `marker_single` on PATH (`pip install marker-pdf`)

## docling extraction backend

A second Markdown-producing extractor (`pip install docling`), tried after
marker in the default chain.

- **Module:** `lua/pdfport/backends/docling.lua`
- **Requires:** a Python interpreter with the `docling` module installed

## Ollama vision extraction backend

Rasterizes each requested page via `pdftoppm` and sends the images to a
local Ollama multimodal model (default `llava`), reading text back out of
the model's response — scanned PDFs extracted without sending anything to a
cloud API. Falls back to a non-vision text-prompt path (raw `pdftotext`
output fed to the model as a prompt) when `ollama_model` doesn't match a
known vision-model name pattern (`llava`/`bakllava`/`moondream`/`vision`).

- **Module:** `lua/pdfport/backends/ollama.lua` (`M.available`, `M.extract`)
- **Config:** `opts.ollama_host` (default `"http://localhost:11434"`), `opts.ollama_model` (default `"llava"`)
- **Requires:** `ollama` daemon running, `pdftoppm`, `curl`

## Claude API extraction backend

Sends the PDF as a base64-encoded document to the Anthropic Messages API
(`model` default `claude-opus-4-5`) and reads Markdown back. The API key is
written to a temporary curl config file (`-K`) rather than passed as a
`-H` argv element, so it never appears in `ps`/Process-Explorer output for
the lifetime of the call; the config file gets best-effort `0600`
permissions (a no-op on Windows, real on POSIX) and is deleted once the
request completes.

- **Module:** `lua/pdfport/backends/claude.lua` (`M.available`, `M.extract`)
- **Config:** `opts.claude_api_key` (default `nil`, falls back to `ANTHROPIC_API_KEY` env var)
- **Requires:** `curl` on PATH, `ANTHROPIC_API_KEY` (or `claude_api_key`) set, `vim.base64` (Neovim 0.10+ — encoding is in-process now, no external `base64` binary)

## Tesseract OCR fallback backend

Rasterizes each requested page via `pdftoppm` and OCRs it with `tesseract`.
Unlike marker/docling/ollama/claude (which also set `capabilities.ocr =
true` but can extract via other means too), tesseract has no non-OCR
extraction path at all — it exists purely as the last-resort fallback for
PDFs where the text-layer backends return nothing useful.

- **Module:** `lua/pdfport/backends/tesseract.lua` (`M.available`, `M.extract`)
- **Requires:** `tesseract`, `pdftoppm` on PATH

## Custom backend registration

Any Lua table shaped like `{ id, available(), extract(path, opts) }` can be
registered as an eighth (or further) backend, participating in the same
fallback chain as the seven builtins.

- **Module:** `lua/pdfport/init.lua` (`M.register_backend`), `lua/pdfport/core/registry.lua` (`M.register_backend`)
