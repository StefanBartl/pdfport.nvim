# Requirements

## Required

| | |
| --- | --- |
| Neovim | **0.9+** |
| [lib.nvim](https://github.com/StefanBartl/lib.nvim) | `:PdfPort` is built on its user-command composer, and its UI kit gives the mode picker its look |
| At least one extraction backend | required to read anything — `pdftotext` from poppler is the usual first choice |

## Optional

Detected at runtime, and each costs exactly the one feature it powers:

| | |
| --- | --- |
| `pdftotext` (poppler), `pdfplumber`, `marker`, `docling`, `tesseract` | Extraction backends, from fastest to most thorough |
| Ollama, the Claude API | Extraction to Markdown through a model |
| `img2pdf`, `magick`, `pandoc`, `weasyprint`, chromium, `soffice` | Creation producers, one per input kind |
| `qpdf`, `pdftk`, `ghostscript` | Merging |
| `chafa` and a capable terminal | The terminal image renderer |
| [which-key.nvim](https://github.com/folke/which-key.nvim) | Descriptions for every keymap under the `<leader>p` group |

All of them are declared in [install.json](install.json) with why each
matters, and read by lib.nvim's
[deps module](https://github.com/StefanBartl/lib.nvim/blob/main/lua/lib/nvim/deps/README.md).
`:Lib deps show pdfport.nvim` reports what is missing;
`:Lib deps install pdfport.nvim` composes and confirms an install command. A
popup shows this once, the first time `setup()` runs after installing — turn it
off in this plugin's own spec with
`require("pdfport").setup({ deps_popup = false })`, or globally with
`vim.g.lib_nvim_deps_disable_first_run = true`.
