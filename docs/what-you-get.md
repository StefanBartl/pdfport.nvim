# What you get with the defaults

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
[commands.md](commands.md).
