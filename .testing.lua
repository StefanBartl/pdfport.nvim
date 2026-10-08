-- .testing.lua -- configuration of testing.nvim for this project.
-- Written by `testing migrate`; edit freely (it is never overwritten). Every key is optional; the
-- keys are documented in testing.nvim's docs/CONFIG.md. Loading this file executes it (same trust
-- as running the specs).
-- lib.nvim opens a one-time "missing tools" welcome float (deps.first_run) from setup() on a machine
-- without its seen-marker, i.e. on every fresh CI runner. It runs from a scheduled callback and would
-- take over the current window during a later spec (picker_batch_spec: "Invalid buffer id"). The
-- specs do not test it, so it is switched off for the run.
vim.g.lib_nvim_deps_disable_first_run = true

return {
  -- Lua module root of the project.
  plugin = "pdfport",
  -- How the spec files are run: "auto" = sniffed per file, "h" = on the project's own TESTS/harness.lua,
  -- "script" = a self-running script in its own process.
  dialect = "h",
  -- Dependencies (directory names) put on the runtimepath: $<NAME>_DIR, .deps/<name>, ../<name>,
  -- stdpath('data')/lazy/<name>.
  deps = { "lib.nvim" },
  -- "none" = all specs in one nvim, "file" = one nvim per spec file
  -- (nothing leaks from one file into the next).
  -- "file": setup() registers :PdfPort and several specs leave pdfport:// buffers or a lib.nvim
  -- which_key autocmd behind; one editor per file keeps all of that from reaching the next spec.
  -- Every spec builds its own fixtures (health_spec stubs the registry and the composer route
  -- check), so a single file also runs alone (`--file`, `--shard`, `--watch`).
  isolated = "file",
  -- Guards (docs/GUARDS.md of testing.nvim). The suite is clean on all of them.
  guards = {
    fs = "error",
    state = "error",
    scheduled_error = "error",
    prompt = "error",
    deprecation = "error",
    -- The specs probe external tools on purpose (see guard_allow.spawn).
    process_net = "error",
  },
  guard_allow = {
    spawn = {
      -- registry_spec probes the optional python packages (pdfplumber, docling) via `python3 -c import`.
      "python3",
      -- ai_backends_spec checks the argv of the pdftotext backend against a missing file.
      "pdftotext",
    },
  },
  -- Environment variables the specs read; a child editor inherits an allowlist only (never secrets).
  env_allow = { "MAGICK_*" },
}
