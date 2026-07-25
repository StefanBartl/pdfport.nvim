# pdfport.nvim — Automated Tests

Headless, no real extraction tool required (a stub backend covers the
dispatcher/resolver/cache paths). Exit 0 = pass, 1 = fail.

- **[smoke.lua](smoke.lua)** — setup()/config, lazy backend registration +
  resolution, dispatcher error/cache paths, keymap disable + visual-mode-aware
  which-key resolution, and the `page_range`/`cache` pure-function utilities.

```bash
cd /path/to/pdfport.nvim
nvim --clean --headless -u NONE -l test/smoke.lua
```

`lib.nvim` is a required dependency — the script adds a sibling
`../lib.nvim` checkout to `rtp` automatically if one exists next to this repo.
