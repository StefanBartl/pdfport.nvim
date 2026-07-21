# Zentrale Prinzipien — applied to pdfport.nvim

Audit of pdfport.nvim against
[`Zentrale-Prinzipien.md`](E:/repos/Notes/MyNotes/Checklists/Lua/Zentrale-Prinzipien.md).
Status: ✅ good · 🟡 partial / improvable · ❌ gap (action item) · ➖ N/A.

## lib.nvim usage (the "WICHTIG" preamble)

| Helper | Status | Notes |
|---|---|---|
| `lib.notify` | ❌ | `util/notify.lua` wraps `vim.notify` directly, no `lib.nvim.notify` delegation. |
| `lib.map` | ❌ | integrations call `vim.keymap.set` directly. |
| `lib.usercmd` | ❌ | `bindings/usrcmds.lua` uses `nvim_create_user_command` directly. |
| `lib.autocmd` / `lib.augroup` | ❌ | `bindings/autocmds.lua` uses raw `nvim_create_autocmd` / `nvim_create_augroup` (albeit centralized — see §4 below). |
| `lib.cross` | 🟡 | `platform/init.lua` reimplements OS/tool detection instead of delegating; same posture as `filetree.nvim`'s own `util.platform`. |
| `lib.hover_select` | ✅ | `util/picker.lua` and `bindings/usrcmds.lua` both `pcall(require, "lib.nvim.ui.hover_select")`, falling back to `vim.ui.select`. |
| `lib.lazy` | ➖ | no lazy-proxy needed at this scale; `plugin/pdfport.lua`'s guard + `cmd = {...}` lazy-loading in the README covers it externally. |
| `lib.memo` | ➖ | no memoization use case beyond `platform.lua`'s own explicit, plugin-lifetime cache (see §7). |

**Note:** unlike `filetree.nvim`, pdfport.nvim does not declare `lib.nvim` as a hard
dependency at all — every touchpoint above is a soft, `pcall`-guarded optional enhancement
(see README: "Pairs well with lib.nvim"). This is a deliberate choice, not an oversight: the
plugin is meant to work fully standalone.

## The 10 principles

**1. Events bündeln, Logik entkoppeln** — ✅
Each file-tree integration (`netrw`, `oil`, `nvim-tree`) owns exactly one `FileType`
autocmd for its own distinct filetype pattern, registered through the shared
`bindings/autocmds.lua` helper — no two modules react to the same event, and the binding
logic itself is centralized rather than duplicated per integration.

**2. Eigene Logik lazy laden** — 🟡
`plugin/pdfport.lua` only sets a load guard; nothing else runs until `setup()` or an
integration's `setup()` is called explicitly (`cmd = {...}` in the README keeps it out of
startup entirely). *Gap:* `backends/init.lua`'s `M.load_all()` unconditionally `require`s
all six backend modules at `setup()` time, rather than deferring each backend's `require`
until the resolver actually picks it. The cost is small (each backend module is cheap to
load — no heavy work happens until `.extract()` runs) but it's not truly lazy per-backend.

**3. Kontext statt Mehrfach-API-Zugriffe** — ✅
`dispatcher.lua` builds `extract_opts` once per call from config + request opts (single
merge, not repeated lookups); there are no `CursorMoved`/`TextChanged`-class hot paths
anywhere in the plugin that would call for a shared context object.

**4. Autocommand-Gruppen sauber nutzen** — ✅
`bindings/autocmds.lua`'s `M.on_filetype` creates a named augroup with `clear = true`
before binding — re-running `setup()` is idempotent. This directly fixed a real bug this
session: `nvim_tree.lua` previously registered its `FileType` autocmd with no augroup at
all, silently duplicating keymaps on repeated `setup()` calls.

**5. Event oder Command?** — ✅
Everything is either an explicit `:PdfPort*` command or a buffer-local keymap inside a
file-tree buffer, both requiring deliberate user action. Nothing runs automatically on
buffer/window events.

**6. Treesitter notwendig oder nicht?** — ➖ (N/A)
pdfport.nvim uses no Treesitter anywhere; correctly so — there is no syntax-semantic need
(it renders extracted text/Markdown, it doesn't parse Lua/other source).

**7. Cache vorhanden und explizit?** — ✅
`platform/init.lua` caches OS detection, executable checks, Python-module checks and the
resolved Python interpreter in explicit module-locals (`_exe_cache`, `_os_cache`,
`_python_cache`), with an explicit `M.reset_cache()` escape hatch. Scope is correctly
runtime-only (not `stdpath`-persisted) — these are "is this tool on PATH right now"
answers, not data that should survive across sessions.

**8. Allokationen im Hot-Path vermeiden** — ➖ (N/A)
No hot paths exist (no `CursorMoved`/`TextChanged` handlers at all). Extraction/rendering
happens once per explicit user-triggered `open()`/`extract()` call.

**9. Debugbarkeit eingeplant?** — 🟡
`config.debug` gates a single `vim.notify(..., DEBUG)` in `init.lua`'s `setup()`, and
`:checkhealth pdfport` gives full visibility into registry/backend/renderer state on
demand. *Gap:* no per-dispatch debug tracing (e.g. "resolved backend X for request on path
Y") — errors are visible via the `PdfPort.Result.error` field, but a successful dispatch
leaves no debug trail even with `debug = true`.

**10. Laufzeit wichtiger als Startup?** — ✅
No recurring `CursorMoved`/`BufEnter` handlers exist to begin with; the only "runtime" cost
is the async subprocess spawn on explicit user action, already non-blocking via
`vim.uv.spawn` + `vim.schedule`. Startup cost is ~zero given `cmd = {...}` lazy-loading.

## Summary

Structurally sound (named augroups via a shared helper, event choice, cache scope). The two
concrete action items are the same shape as `filetree.nvim`'s own audit: **lib.nvim
adoption remains optional-by-design** here (not a gap, a deliberate standalone-first
choice) and **per-backend lazy loading** in `backends/init.lua` is the one real,
worth-fixing gap. See [ROADMAP.md](../ROADMAP.md) for prioritization.
