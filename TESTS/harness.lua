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

return H
