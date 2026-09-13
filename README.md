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

PDFs in Neovim, in both directions: reading them and writing them. Reading
means extracting and displaying a PDF's content through a pluggable backend;
writing means creating one — from an image, Markdown, text, HTML or an Office
file, or merging several — through a pluggable producer. Both sides degrade to
a clear message rather than an error when a tool is not there.

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
> dependency — see [Requirements](docs/requirements.md).

---

## Documentation

Start at [docs/README.md](docs/README.md), which says what is where and which
question each page answers.

**The Basics**

- [Requirements](docs/requirements.md) — this plugin's job is to drive external tools, so this is the interesting part.
- [Installation](docs/installation.md) — a spec per plugin manager.
- [Quickstart](docs/quickstart.md) — the first thing to run after installing.

**Configuration**

- [What you get with the defaults](docs/what-you-get.md) — the full command/API surface at a glance.
- [All options](docs/configuration.md) — every `setup()` option, and the extraction backend table.
- [Command reference](docs/commands.md) — every command, its arguments, and the Lua API.
- [Bindings cheatsheet](docs/BINDINGS.md) — every keymap, user command and autocommand this plugin registers.

**The Rest**

- [Features](docs/FEATURES/README.md) — one page per area: [the core](docs/FEATURES/CORE.md), [rendering](docs/FEATURES/RENDERING.md), [the backends it reads with](docs/FEATURES/BACKENDS.md), [the producers it writes with](docs/FEATURES/PRODUCERS.md), [the integrations](docs/FEATURES/INTEGRATIONS.md).
- [Integrations](docs/integrations.md) — which other plugins reach this one and how, starting with the file trees.
- [Workflow](docs/WORKFLOW.md) — how the pieces combine once several backends and producers are available at once, and the gotchas worth knowing before they cost a debugging session.
- [Health check](docs/health.md) — the ten `:checkhealth pdfport` sections, and which findings are actually problems.
- [Contributing](docs/CONTRIBUTING.md) — ground rules, project layout, and how to add a backend or a producer.
- [Feedback](https://github.com/StefanBartl/pdfport.nvim/issues) — bugs, feature requests and usage questions; broader discussion in [Discussions](https://github.com/StefanBartl/pdfport.nvim/discussions).

`:help pdfport` is the same reference inside the editor.

---

## License

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

pdfport.nvim is released under the [MIT License](https://opensource.org/licenses/MIT).
