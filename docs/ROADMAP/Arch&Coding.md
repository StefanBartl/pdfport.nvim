# Architektur- & Codierungsrichtlinien — applied to pdfport.nvim

Audit against
[`Arch&Coding-Regeln.md`](E:/repos/Notes/MyNotes/Checklists/Lua/Arch&Coding-Regeln.md).
✅ good · 🟡 partial · ❌ gap · ➖ N/A.

## 1. Sicherheitsprinzipien & Fehlerbehandlung — 🟡
Every backend returns a structured `PdfPort.Result { status, text, format, backend,
pages_processed, error }` instead of throwing — effectively the checklist's
`{ ok, result, err }` wrapper under a different field name. External/optional calls
(`pcall(require, "lib.nvim.ui.hover_select")`, backend `require`s, the extraction callback
in `dispatcher.dispatch`) are `pcall`-guarded. `notify()` (`util/notify.lua`) is only ever
called from integrations/renderers, never from `core/` or `backends/`. *Gap:* no distinct
named error types (`InvalidStateError` etc.) — just a string `error` field. Acceptable at
this scale (a handful of failure modes per backend, all surfaced to the user via one
`vim.notify` call), but worth naming if the backend count grows further.

## 2. Modularisierung & Strukturprinzipien — ✅
Clear one-responsibility layering: `core/{registry,resolver,dispatcher}.lua` (storage /
selection policy / orchestration), `backends/*.lua` (one file per extraction tool),
`renderers/*.lua` (one file per output mode), `integrations/*.lua` (one file per
file-tree/fuzzy-finder), `bindings/`, `util/`, `platform/`, `config/`. No global mutable
state: config lives behind `config.setup()`/`config.get()`, backends/renderers behind
`registry.register_*()`/`registry.get_*()` — literally the checklist's "central tool
registry" pattern, named `core/registry.lua`. Private helpers (`current_node_path`,
`is_pdf`, etc.) are locals, never exported.

## 3. Buffer- & Window-Management — 🟡
`renderers/float.lua` and `renderers/buffer.lua` validate before acting
(`api.nvim_win_is_valid(win)` in float's close-keymap callback; `ensure_editor_win()` in
buffer.lua checks window config/filetype before switching). *Gap:* no unified
`open_window()`/`close_window()`/`cleanup_all()` API — each renderer (`buffer`, `float`,
`terminal`) hand-rolls its own window creation. `renderers/terminal.lua`'s
`vim.defer_fn(function() vim.fn.delete(png_path) end, 2000)` cleanup callbacks don't
re-validate anything before deleting the temp PNG — low risk (deleting an already-deleted
temp file is a silent no-op, not a crash), but it's exactly the "deferred callbacks must
re-validate handles" case the checklist calls out.

## 4. Methoden, Metatables & Datenmodelle — ✅ (mostly by design)
No metatables anywhere in the plugin — correctly so: the data model is flat
(`PdfPort.Result`, `PdfPort.Config`, `PdfPort.Backend`), with no need for `__index`
inheritance, ring buffers, or shared-metatable memoization at this scale. Plain `M`-tables
throughout.

## 5. Dokumentation & Annotationen — ✅
Every module has `---@module` + `---@brief` (often `---@description`); public functions
carry `---@param`/`---@return`. Types are centralized in `@types/init.lua` with
`---@alias`/`---@class`/`---@field` (expanded this session with `PdfPort.RendererSplit`,
`PdfPort.TerminalTool`, `PdfPort.TerminalSizeRatio`). *Minor gap vs. convention:* `@types`
is a single file rather than split per concern (the pattern noted from `github_stats.nvim`
in this repo's own `NEOTREE_FEATURES.md`) — acceptable at the current ~130-line size, would
warrant splitting only if it keeps growing.

## 6. Testbarkeit & Lesbarkeit — ❌
**The single clearest gap.** No `test/` directory and no automated test of any kind — unlike
`filetree.nvim`'s `test/smoke.lua` (headless, stub adapter). Functions are mostly pure-ish
in shape (backends take `path` + `opts`, return a `Result` via callback; no hidden global
dependencies), which means they'd be straightforward to test, but nothing currently
verifies this beyond manual headless smoke-checks run ad hoc during development sessions.

## 7. Fehlerbehandlung & Validierung (Sicherheit) — ✅
`dispatcher.validate_path()` checks type, `uv.fs_stat`, and file-vs-directory before any
backend runs. Every backend guards pipe/timer/spawn-creation failure with an explicit
`Result { status = "error" }` rather than letting a nil handle propagate.

## 8. Performance & Speicher — ✅ (mostly N/A)
No hot loops exist. Text is rendered via one `vim.split` + one `nvim_buf_set_lines` call
(not per-line API calls) in `buffer.lua`/`float.lua`. No debounce/backpressure machinery is
needed since there's no repeating background work — the one `vim.defer_fn` chain in
`terminal.lua` is a deliberate serial page-render sequence, not a hot path.

## 9. Cache hitting — ✅
`platform.lua`'s exe/OS/python caches are exactly "cache queries with high match-rate in
memory" — string-keyed by tool name, which is appropriate given the call frequency
(a handful of lookups per `:checkhealth` run or backend `.available()` check, not per
keystroke).

## 10. Schwache Tabellen & Memoisierung — ➖
No use case: nothing is per-buffer/per-object keyed state needing GC-friendly weak-table
cleanup. `platform.lua`'s cache is intentionally plugin-lifetime-scoped, not per-object.

## 11. Spezialfälle — 🟡
Cross-platform branching (`platform.os()`, `open_cmd()`, `best_terminal_renderer()`,
`python()`) is the module's entire purpose and is handled centrally rather than inline
per-caller. The "NVIM-Config spezifisch" lib.nvim requirements are soft/optional here (see
[Zentral-Prinzipien.md](Zentral-Prinzipien.md)) — same posture as `filetree.nvim`, called
out explicitly rather than left implicit.

## Annotations- / Import-Regeln — ✅ (pragmatic)
Import order is consistent within each file (`local platform = require(...)`, `local uv =
vim.uv or vim.loop` at the top of every backend), though it doesn't map cleanly onto the
checklist's 8-step System→Debug→Config→State→UI→Controller→Keymaps order — that order
targets UI-heavy plugins with state/controller layers, which pdfport.nvim's simpler
backend/renderer shape doesn't have. Treated as N/A-by-shape rather than a gap.

## Tables / Strings / GC / CPU — ✅
Every backend collects subprocess stdout/stderr via `chunks[#chunks + 1] = data` then a
single `table.concat(chunks)` in the exit callback — never string concatenation in a read
loop. No hand-rolled recursion where an iterative approach is needed (there is no tree/list
walk in this plugin at all).

## Concentrated action items
1. **No automated tests** — biggest gap. A `test/smoke.lua` in the shape of
   `filetree.nvim`'s (headless `require()` chain + a stub/fake backend) would cover the
   riskiest surface: `setup()`, dispatcher resolution, and the disable/which-key keymap
   logic added this session.
2. **`backends/init.lua` eager `load_all()`** — defer each backend's `require` to
   resolution time instead of loading all six upfront (see
   [Zentral-Prinzipien.md §2](Zentral-Prinzipien.md)).
3. **No unified window lifecycle helper** across `buffer`/`float`/`terminal` renderers —
   minor; only worth doing if a fourth window-based renderer is added.
