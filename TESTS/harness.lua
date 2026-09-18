-- TESTS/harness.lua — tiny assertion helper shared by the spec files.
-- Returned to each spec by TESTS/run.lua.

local H = {}

--- Assert equality; raises a descriptive error on mismatch (caught by the runner).
---@param a any # actual
---@param b any # expected
---@param msg string|nil
function H.eq(a, b, msg)
  if a ~= b then
    error(("FAIL %s: expected %q, got %q"):format(msg or "", tostring(b), tostring(a)), 2)
  end
end

--- Assert a truthy value.
---@param v any
---@param msg string|nil
function H.ok(v, msg)
  if not v then error(("FAIL %s: expected truthy, got %q"):format(msg or "", tostring(v)), 2) end
end

--- Assert a falsy value.
---@param v any
---@param msg string|nil
function H.falsy(v, msg)
  if v then error(("FAIL %s: expected falsy, got %q"):format(msg or "", tostring(v)), 2) end
end

--- Assert `s` matches Lua pattern `pat`.
---@param s string
---@param pat string
---@param msg string|nil
function H.match(s, pat, msg)
  if not tostring(s):match(pat) then
    error(("FAIL %s: %q does not match pattern %q"):format(msg or "", tostring(s), pat), 2)
  end
end

--- Assert two list-like tables are element-wise equal.
---@param a any[]|nil
---@param b any[]
---@param msg string|nil
function H.eq_list(a, b, msg)
  if type(a) ~= "table" then
    error(("FAIL %s: expected a table, got %q"):format(msg or "", tostring(a)), 2)
  end
  if #a ~= #b then
    error(
      ("FAIL %s: expected %d element(s) {%s}, got %d {%s}"):format(
        msg or "",
        #b,
        table.concat(b, ","),
        #a,
        table.concat(a, ",")
      ),
      2
    )
  end
  for i = 1, #b do
    if a[i] ~= b[i] then
      error(
        ("FAIL %s: index %d expected %q, got %q"):format(
          msg or "",
          i,
          tostring(b[i]),
          tostring(a[i])
        ),
        2
      )
    end
  end
end

--- A temp fixture file, created, in the one spelling the OS will hand back.
---
--- `vim.fn.tempname()` reports the *logical* path, and on macOS that is under
--- the `/var` symlink -- while anything the same file has been through comes
--- back as `/private/var/...`: a buffer name (Neovim resolves those),
--- `uv.fs_realpath`, and pdfport's own `util.path.canonical`, which the
--- dispatcher applies so a cache key is one string per file. Comparing a raw
--- `tempname()` against any of those is a macOS-only failure that says
--- nothing about the code under test, so fixtures are canonical from the
--- start and a spec compares identities rather than spellings.
---@param suffix string  appended to the temp name, e.g. "-dispatch-spec.pdf"
---@param lines? string[]  file contents; a single "x" by default
---@return string path
function H.tempfile(suffix, lines)
  local path = vim.fn.tempname() .. (suffix or "")
  vim.fn.writefile(lines or { "x" }, path)
  -- `type(real) == "string"`: fs_realpath's async overload answers a request
  -- handle, so its declared type is `string|uv.uv_fs_t`.
  local real = (vim.uv or vim.loop).fs_realpath(path)
  return type(real) == "string" and real or path
end

--- Sentinel for `H.with_modules`: the key is *removed* from `package.loaded`
--- rather than replaced, which is how the module under test is forced to
--- re-run its body against the replacements standing in for its `require`s.
H.UNLOAD = setmetatable({}, {
  __tostring = function()
    return "H.UNLOAD"
  end,
})

--- Run `fn` with `package.loaded` entries replaced, then restore every one.
---
--- The seam for every external tool in this plugin is a top-level `require`
--- (`lib.nvim.cross.uv.spawn_capture`, `pdfport.platform`, …) bound to an
--- upvalue when the module body runs. Replacing the dependency and unloading
--- the module under test in the same call is therefore the only way to
--- observe what *would* have been spawned without spawning it -- patching a
--- field afterwards comes too late, the upvalue is already bound.
---@param replacements table<string, any>  `H.UNLOAD` removes instead of replacing
---@param fn fun()
---@return nil
function H.with_modules(replacements, fn)
  local keys, saved = {}, {}
  for name in pairs(replacements) do
    keys[#keys + 1] = name
  end
  for _, name in ipairs(keys) do
    saved[name] = package.loaded[name]
    local value = replacements[name]
    package.loaded[name] = (value ~= H.UNLOAD) and value or nil
  end

  local ok, err = pcall(fn)

  for _, name in ipairs(keys) do
    package.loaded[name] = saved[name]
  end

  if not ok then error(err, 0) end
end

--- One `Lib.Cross.Uv.SpawnCapture.Result`, defaulting to a clean exit.
---@param overrides table|nil
---@return table
function H.spawn_result(overrides)
  local result = {
    ok = true,
    code = 0,
    signal = 0,
    stdout = "",
    stderr = "",
    timed_out = false,
  }
  for k, v in pairs(overrides or {}) do
    result[k] = v
  end
  return result
end

--- A `lib.nvim.cross.uv.spawn_capture` stand-in that records every argv it is
--- handed and answers with `rec.result` (a successful, silent run by default).
---
--- Recording rather than asserting inline: what a producer got wrong is
--- almost always visible in the argv as a whole (a missing separator, a flag
--- in the wrong position, an input and an output the wrong way round), so the
--- spec reads the list back and looks at it.
---@return table
function H.spawn_recorder()
  local rec = { calls = {}, result = nil, on_call = nil }
  rec.fn = function(argv, opts, on_done)
    rec.calls[#rec.calls + 1] = { argv = argv, opts = opts }
    -- Stands in for what the real tool would have left behind: a producer
    -- that reads its own output back (soffice) needs the file to exist by
    -- the time its callback runs.
    if rec.on_call then rec.on_call(argv, opts) end
    on_done(rec.result or H.spawn_result({}))
  end
  return rec
end

--- A `pdfport.platform` stand-in where exactly `present` is installed, so a
--- producer's `available()` gate is decided by the spec rather than by what
--- happens to be on the machine running it.
---@param present table<string, boolean>  executable names; "pymod:<name>" for python modules
---@param python string|nil  interpreter reported by `python()`; nil = none found
---@return table
function H.fake_platform(present, python)
  return {
    os = function()
      return "linux"
    end,
    is_wsl = function()
      return false
    end,
    has = function(exe)
      return present[exe] == true
    end,
    first_available = function(list)
      for _, exe in ipairs(list) do
        if present[exe] == true then return exe end
      end
      return nil
    end,
    python = function()
      return python
    end,
    has_python_module = function(mod)
      return present["pymod:" .. mod] == true
    end,
    open_cmd = function()
      return "xdg-open"
    end,
    best_terminal_renderer = function()
      return present.chafa and "chafa" or nil
    end,
    reset_cache = function() end,
  }
end

--- Index of `value` in a list, or nil.
---@param list any[]
---@param value any
---@return integer|nil
function H.index_of(list, value)
  for i = 1, #list do
    if list[i] == value then return i end
  end
  return nil
end

--- The argv of the most recent recorded spawn.
---@param rec table
---@return string[]
function H.last_argv(rec)
  local call = rec.calls[#rec.calls]
  if not call then error("FAIL: no command was spawned", 2) end
  return call.argv
end

--- A minimal valid backend, for registry/resolver tests that must not depend
--- on any real extraction tool being installed on the host.
---@param id string
---@param available boolean
---@param on_extract fun()|nil  called when extract() runs, to observe dispatch
---@return table
function H.fake_backend(id, available, on_extract)
  return {
    id = id,
    available = function()
      return available
    end,
    extract = function()
      if on_extract then on_extract() end
      return {
        status = "ok",
        text = "text from " .. id,
        format = "plain",
        backend = id,
      }
    end,
  }
end

--- A minimal valid producer, for composer/producer-registry tests that must
--- not depend on any real PDF-creation tool being installed on the host.
---@param id string
---@param available boolean
---@param accepts PdfPort.InputKind[]|nil  # default { "image" }
---@return table
function H.fake_producer(id, available, accepts)
  return {
    id = id,
    accepts = accepts or { "image" },
    available = function()
      return available
    end,
    create = function(req)
      return {
        status = "ok",
        path = req.output,
        producer = id,
        pages = #req.inputs,
      }
    end,
  }
end

return H
