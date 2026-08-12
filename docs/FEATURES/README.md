# Features

pdfport.nvim moves content in two directions — PDF → text/Markdown
(**backends**) and something → PDF (**producers**) — through the same
lazy-registry/fallback-chain shape on both sides, plus four ways to display
what comes out the read side (**renderers**). This folder replaces the old
single `docs/FEATURES.md`: with seven backends, nine producers, four
renderers and a resolver/dispatcher/composer core, one flat file had grown
past the point of being a useful index.

- [BACKENDS.md](BACKENDS.md) — the seven PDF → text/Markdown extraction backends.
- [PRODUCERS.md](PRODUCERS.md) — the nine something → PDF creation/merge producers.
- [RENDERING.md](RENDERING.md) — the four output renderers and the page-range picker.
- [CORE.md](CORE.md) — the resolver/dispatcher/composer architecture, caching, health check, and diagnostics.
- [INTEGRATIONS.md](INTEGRATIONS.md) — file-tree and fuzzy-finder integrations, which-key, batch-open.

See [../commands.md](../commands.md) for the full command/Lua-API reference and
[../configuration.md](../configuration.md) for every `setup()` option.
