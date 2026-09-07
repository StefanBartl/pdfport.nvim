> **Beta stage — active development.** This repository is past its first shape and in
> active use, but the surface is not frozen: breaking changes are still possible. Pin a
> commit or tag if you depend on it.

# pdfport.nvim

```
           _  __                  _                _
 _ __   __| |/ _|_ __   ___  _ __| |_   _ ____   _(_)_ __ ___
| '_ \ / _` | |_| '_ \ / _ \| '__| __| | '_ \ \ / / | '_ ` _ \
| |_) | (_| |  _| |_) | (_) | |  | |_ _| | | \ V /| | | | | | |
| .__/ \__,_|_| | .__/ \___/|_|   \__(_)_| |_|\_/ |_|_| |_| |_|
|_|             |_|
```

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Neovim](https://img.shields.io/badge/Neovim-0.9%2B-57A143?logo=neovim&logoColor=white)](https://neovim.io)
[![Lua](https://img.shields.io/badge/Lua-5.1%2FLuaJIT-2C2D72?logo=lua&logoColor=white)](https://www.lua.org)
![Status](https://img.shields.io/badge/status-beta-orange)
[![CI](https://github.com/StefanBartl/pdfport.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/StefanBartl/pdfport.nvim/actions/workflows/ci.yml)

PDFs in Neovim, in both directions: reading them and writing them.

Reading means extracting and displaying a PDF's content through a pluggable
backend; writing means creating one from an image, Markdown, text, HTML or an
Office file, merging several, or rasterizing a single page to PNG — through a
pluggable producer. Both sides run on external tools, and both degrade to a
clear message rather than an error when a tool is not there.

---

## Table of contents

- [Documentation](#documentation)
- [What it does](#what-it-does)
- [Around it](#around-it)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quickstart](#quickstart)
- [What you get with the defaults](#what-you-get-with-the-defaults)
- [Integrations](#integrations)
- [Health check](#health-check)
- [Contributing](#contributing)
- [Feedback](#feedback)
- [License](#license)

---

## Documentation

Start at [docs/README.md](docs/README.md), which says what is where and which
question each page answers.

- [Features](docs/FEATURES/README.md) — one page per area: [the core](docs/FEATURES/CORE.md), [rendering](docs/FEATURES/RENDERING.md), [the backends it reads with](docs/FEATURES/BACKENDS.md), [the producers it writes with](docs/FEATURES/PRODUCERS.md), [the integrations](docs/FEATURES/INTEGRATIONS.md).
- [Installation](docs/installation.md) — what has to be there first, and a spec per plugin manager. This plugin's job is to drive external tools, so the requirements are the interesting part.
- [Configuration](docs/configuration.md) — every `setup()` option, and the extraction backend table.
- [Command reference](docs/commands.md) — every command, its arguments, and the Lua API.
- [Bindings cheatsheet](docs/BINDINGS.md) — every keymap, user command and autocommand this plugin registers.
- [Integrations](docs/integrations.md) — which other plugins reach this one and how, starting with the file trees.
- [Workflow](docs/WORKFLOW.md) — how the pieces combine once several backends and producers are available at once, and the gotchas worth knowing before they cost a debugging session.
- [Health](docs/health.md) — the ten `:checkhealth pdfport` sections, and which findings are actually problems.
- [Contributing](docs/CONTRIBUTING.md) — ground rules, project layout, and how to add a backend or a producer.

`:help pdfport` is the same reference inside the editor.

---

## What it does

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

Backends like `marker`, `docling`, `ollama` and `claude` extract to Markdown
rather than plain text, which is what makes
[mdview.nvim](https://github.com/StefanBartl/mdview.nvim) a good place to send
the output.

---

## Around it

> **[filetree.nvim](https://github.com/StefanBartl/filetree.nvim)** — the file
> tree from the same collection. It does not need an adapter here: it calls
> `pdfport.pick_open()` directly, which is why hitting a PDF in it asks exactly
> the question `:PdfPort` asks.
>
> **[hover.nvim](https://github.com/StefanBartl/hover.nvim)** — previews a PDF
> page, and a `.docx`, in a float. Both go through `render_page()`; the `.docx`
> path converts first, then rasterizes page one.
>
> **[images.nvim](https://github.com/StefanBartl/images.nvim)** — draws that
> same rasterized page in a picker's preview window.
>
> **[markdown.nvim](https://github.com/StefanBartl/markdown.nvim)** — sends
> `:Markdown export pdf` here, and follows a `.pdf` link into a buffer instead
> of the system reader.
>
> **[mdview.nvim](https://github.com/StefanBartl/mdview.nvim)** — previews the
> Markdown the AI and layout backends extract.
>
> All of the above are soft: without them everything else works unchanged.
> [lib.nvim](https://github.com/StefanBartl/lib.nvim) is the one real plugin
> dependency — see [Requirements](#requirements).

---

## Requirements

| | |
| --- | --- |
| Neovim | **0.9+** |
| [lib.nvim](https://github.com/StefanBartl/lib.nvim) | required — `:PdfPort` is built on its user-command composer, and its UI kit gives the mode picker its look |
| At least one extraction backend | required to read anything — `pdftotext` from poppler is the usual first choice |

Everything else is optional, detected at runtime, and costs exactly the one
feature it powers:

| | |
| --- | --- |
| `pdftotext` (poppler), `pdfplumber`, `marker`, `docling`, `tesseract` | Extraction backends, from fastest to most thorough |
| Ollama, the Claude API | Extraction to Markdown through a model |
| `img2pdf`, `magick`, `pandoc`, `weasyprint`, chromium, `soffice` | Creation producers, one per input kind |
| `qpdf`, `pdftk`, `ghostscript` | Merging |
| `chafa` and a capable terminal | The terminal image renderer |
| [which-key.nvim](https://github.com/folke/which-key.nvim) | Descriptions for every keymap under the `<leader>p` group |

All of them are declared in [docs/install.json](docs/install.json) with why each
matters, and read by lib.nvim's
[deps module](https://github.com/StefanBartl/lib.nvim/blob/main/lua/lib/nvim/deps/README.md).
`:Lib deps show pdfport.nvim` reports what is missing;
`:Lib deps install pdfport.nvim` composes and confirms an install command. A
popup shows this once, the first time `setup()` runs after installing — turn it
off in this plugin's own spec with
`require("pdfport").setup({ deps_popup = false })`, or globally with
`vim.g.lib_nvim_deps_disable_first_run = true`.

---

## Installation

```lua
-- lazy.nvim
{
  "StefanBartl/pdfport.nvim",
  dependencies = { "StefanBartl/lib.nvim" },
  cmd = { "PdfPort" },
  opts = {
    default_backend = "auto",
    fallback_chain  = { "pdftotext", "pdfplumber", "marker", "docling", "ollama", "tesseract", "claude" },
  },
}
```

`cmd` is enough for interactive use; the commands are registered on the first
`setup()` call and a guard in `plugin/` keeps startup free. If another plugin
calls into this one — a file tree, a hover — it will load it on demand.
packer.nvim, vim-plug and mini.deps are in
[docs/installation.md](docs/installation.md).

---

## Quickstart

Point it at a PDF and let it ask how you want it:

```vim
:PdfPort
```

The mode picker is the same one every integration shows, and "system
application" is always one of the choices. Then, when you already know:

```vim
:PdfPort text       " extract into a buffer
:PdfPort float      " into a floating window, prompting for a page range
:PdfPort terminal   " as a terminal image, same prompt
:PdfPort system     " hand it to the system application
:PdfPort backends   " which backends are registered, and which resolve right now
```

And the other direction:

```vim
:PdfPort create                                    " a PDF from an image, Markdown, text, HTML or Office file
:PdfPort merge out.pdf a.pdf b.pdf                 " two or more into one
:PdfPort producers                                 " which producers resolve right now
```

Verify your setup any time with:

```vim
:checkhealth pdfport
```

---

## What you get with the defaults

| Command / API | Does |
| --- | --- |
| `:PdfPort [path]` / `open()` | Open a PDF through a backend and a renderer — buffer, float, system or terminal |
| `:PdfPort text` / `extract()` | Extract the text without rendering anything |
| `:PdfPort create` / `create()` | Create a PDF from an image, Markdown, text, HTML or Office file |
| `:PdfPort merge <out> <a> <b> …` / `merge()` | Merge two or more PDFs |
| `:PdfPort backends` / `producers` | The registered sets, with live availability |
| `:PdfPort health` | `:checkhealth pdfport` |
| `pick_open()` | The "open PDF as…" picker, for other plugins to embed rather than rebuild |
| `render_page()` | One page to a caller-owned PNG |
| `can_create()` | Whether a producer exists for a given input kind |
| `register_backend()` / `register_producer()` | Plug in your own |
| `<leader>po` / `pt` / `ps` / `pi` | Open, as text, in the system app, as a terminal image — in a file tree |
| `<leader>pb` | Visual mode: batch-open every PDF in the selection |

`auto_open_on_read` is opt-in: with it, `:e file.pdf` invokes the mode picker
instead of loading binary into a buffer. The full surface is
[docs/commands.md](docs/commands.md).

---

## Integrations

### File trees

[filetree.nvim](https://github.com/StefanBartl/filetree.nvim) needs no adapter:
it calls `pdfport.pick_open()` itself, so a PDF in it asks the same question
`:PdfPort` asks, with the same choices.

For the third-party trees there is one adapter each — **neo-tree**,
**nvim-tree**, **netrw** and **oil.nvim** — and all four share the same five
actions: `open`, `open_text`, `open_system`, `open_terminal` in normal mode
(`<leader>po/pt/ps/pi`) and `open_batch` in visual mode (`<leader>pb`), which
opens every PDF in the selection. `open_current()` auto-detects which tree is
active. Pass `false` for any action to drop that keymap; with
[which-key.nvim](https://github.com/folke/which-key.nvim) installed the rest
are registered with descriptions under `<leader>p`. The setup snippets are in
[docs/integrations.md](docs/integrations.md).

### Fuzzy finders

A Telescope previewer and an fzf-lua preview function, both rendering the first
page rather than showing the file name and hoping.

---

## Health check

```vim
:checkhealth pdfport
```

Ten sections: the core, the extraction backends, the creation producers, the
merge producers, the renderers, the terminal image renderer, the integrations,
the registered backends and producers, and the declared tools. Because this
plugin drives external tools, most of what it reports is *which tools you have*
— [docs/health.md](docs/health.md) says which findings are actually problems.

---

## Contributing

Clone the repository and either symlink it or add it to your runtime path.
[docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) has the ground rules and the
project layout, including where a new backend, producer or renderer plugs in.

Pull requests very welcome.

---

## Feedback

Your feedback is very welcome. Use the
[issue tracker](https://github.com/StefanBartl/pdfport.nvim/issues) to report
bugs, suggest features or ask usage questions; anything more open-ended fits a
[discussion](https://github.com/StefanBartl/pdfport.nvim/discussions).

If you find this plugin useful, a ⭐ on GitHub supports its development.

---

## License

MIT — see [LICENSE](LICENSE).
