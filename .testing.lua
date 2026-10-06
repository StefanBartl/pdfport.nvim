-- DEBUG-TEMP
vim.api.nvim_create_autocmd({ "BufAdd", "BufWipeout", "BufDelete", "BufUnload", "BufEnter" }, {
  callback = function(ev)
    if ev.buf <= 3 then
      io.stderr:write(("DBG %s buf=%d name=[%s] cur=%d%s%s"):format(ev.event, ev.buf, vim.api.nvim_buf_get_name(ev.buf), vim.api.nvim_get_current_buf(), debug.traceback("", 2):sub(1, 700), string.char(10)))
    end
  end,
})
-- .testing.lua -- configuration of testing.nvim for this project.
-- Written by `testing migrate`; edit freely (it is never overwritten). Every key is optional; the
-- keys are documented in testing.nvim's docs/CONFIG.md. Loading this file executes it (same trust
-- as running the specs).
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
  isolated = "none",
  -- Environment variables the specs read; a child editor inherits an allowlist only (never secrets).
  env_allow = { "MAGICK_*" },
}
