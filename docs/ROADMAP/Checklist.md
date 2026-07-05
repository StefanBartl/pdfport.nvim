# Lua/Neovim Checklist — applied to pdfport.nvim

Audit against
[`Checklist.md`](E:/repos/Notes/MyNotes/Checklists/Lua/Checklist.md).
✅ good · 🟡 partial · ❌ gap · ➖ N/A for this plugin.

Several sections of this checklist overlap directly with
[Arch&Coding.md](Arch%26Coding.md) (same source-checklist content, audited from a slightly
different angle) — this document cross-references rather than re-deriving those verdicts.

## Schnell-Check (10 Punkte, vor jedem Merge) — mostly ✅
- Central error pattern (`pcall` + structured `Result`) — ✅, see Arch&Coding §1.
- Type guards (`type()`/`assert`) before API access — ✅ (`core/dispatcher.lua`,
  `core/registry.lua` assert on every public entry).
- Buffer/window validity checked before use — 🟡, see Arch&Coding §3.
- No global state — ✅.
- One responsibility per module — ✅.
- `cleanup_all()` — ❌ no such unified function; not critical yet (renderers open
  standalone splits/floats/buffers the user manages themselves, nothing persistent to sweep).
- `table.concat` / preallocated tables — ✅ (every backend's stdout/stderr collector).
- `@module`/`@param`/`@return` complete — ✅.
- Pure functions / testable shape — 🟡 (shape is testable, nothing tests it — see §6 below).
- Import order — ✅ pragmatic, see Arch&Coding "Annotations-/Import-Regeln".

## PR-Review-Checkliste — 🟡
Sicherheit/Fehlerbehandlung, Buffer-/Window-Management, Neovim-API-Nutzung: same verdicts as
[Arch&Coding.md](Arch%26Coding.md) §1/§3/§7 (🟡/🟡/✅). UI-State-Management is ➖ N/A —
renderers are stateless (`render(result, opts)` then done; no persistent UI state to
snapshot/restore). *Gap:* not every change ships a test (see §6).

## Coding-Checkliste (beim Implementieren) — 🟡
- Functional streaming (Filter/Source/Sink/Pump) — ➖ N/A; whole-text extraction per PDF is
  fine at this scale, nothing streams line-by-line.
- Strings/Tables — ✅, see Arch&Coding "Tables/Strings/GC/CPU".
- Performance quick-wins — ✅: async via `vim.uv.spawn` everywhere subprocess work happens;
  the few synchronous `vim.fn.system()` calls (`has_python_module`, `base64` encode,
  `pdftoppm` rasterize-sync in `ollama.lua`) are short, one-shot, and not hot-path.
- Neovim-API safety — 🟡, see Arch&Coding §3.
- State/data models (getter/setter, `__index` defaults) — ➖ N/A; no complex state machine
  exists to warrant one.
- GC control — ➖ N/A; every backend's `cleanup()` closes its timer/pipes consistently, no
  long-lived accumulating handles.
- Lazy-loading config — 🟡, same gap as [Zentral-Prinzipien.md §2](Zentral-Prinzipien.md)
  (`backends/init.lua` eager `load_all()`).

## Architektur-Checkliste — ✅
`core/registry.lua` (storage) / `core/resolver.lua` (selection policy) / `core/dispatcher.lua`
(orchestration) is precisely the checklist's ports-and-adapters shape: backends and
renderers are swappable, testable-in-isolation adapters behind a documented interface
(`PdfPort.Backend`, the renderer `fun(result, opts)` signature) — the checklist's
"registries/factories for tools/adapters" and "DI enables mock spawns in tests" requirements
are structurally satisfied even though no tests currently exercise that seam (see §6).

## Anti-Pattern-Check — ✅
No global mutable state leaking across modules (module-local `_cfg`/registry tables); no API
call without a preceding guard where validity actually matters; no string concatenation in a
loop; no closures created inside a tight loop (`ollama.lua`'s `process_next()` recursive
chain is a deliberate serial-async page sequence, not a loop-closure antipattern).

## Import- und Dateistruktur-Check — 🟡
`@types/`, `util/`, `platform/`, `bindings/`, `config/` are cleanly separated, mirroring
`filetree.nvim`'s own convention. *Gap (closed by this session):* `.luarc.json` was missing
at the project root — added alongside this audit (see [ROADMAP.md](../ROADMAP.md)).

## Performance-Spickzettel (Hotpaths) — ✅ (N/A — no hotpaths)
`table.concat` over string-concat, async via `vim.uv`, no per-keystroke or per-event code at
all — unlike `filetree.nvim` (which has real `CursorMoved`-driven hotpaths for
preview/highlight), pdfport.nvim has nothing that runs more than once per explicit user
action.

## Sortier- / Einfüge-/Lösch-/Such-Algorithmen, Komplexität, Bitoperationen — ➖
Reference material; pdfport.nvim implements no custom data structures or sort/search hot
loops. `resolver.lua`'s fallback-chain resolution is a linear scan over at most a handful of
backend ids — not algorithmically interesting enough to warrant this section's tooling.

## Reviewer-Notizen — ➖ (template, not filled in for this pass)

## Concentrated action items
Same as [Arch&Coding.md](Arch%26Coding.md): no automated tests · eager backend `require` in
`backends/init.lua` · no unified window-lifecycle helper. Plus: `.luarc.json` gap closed by
this session (see [ROADMAP.md](../ROADMAP.md)).
