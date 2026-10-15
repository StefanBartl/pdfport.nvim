-- TESTS/rasterize_timeout_spec.lua -- pdfport.core.rasterize.render_page: a pdftoppm that never ends.
--
-- render_page used to start pdftoppm with no time limit, so a broken or huge PDF left the caller
-- waiting forever and its callback was never called. The process handling (timer, kill, one callback)
-- is lib.nvim's `cross.uv.spawn_capture`; what is pinned here is what render_page asks of it and how
-- it reports each outcome. The spawner is replaced by a double, so no poppler is needed and nothing
-- really waits.

return function(H)
  local platform = require("pdfport.platform")
  local rasterize = require("pdfport.core.rasterize")

  local real_has = platform.has
  local real_spawn = package.loaded["lib.nvim.cross.uv.spawn_capture"]
  local seen

  ---Run render_page against a spawner double that answers with `result`.
  ---@param result table
  ---@param opts? table
  ---@return string|nil png
  ---@return string|nil err
  ---@return integer calls  how often the callback ran
  local function run(result, opts)
    platform.has = function()
      return true
    end
    package.loaded["lib.nvim.cross.uv.spawn_capture"] = function(argv, spawn_opts, on_done)
      seen = { argv = argv, opts = spawn_opts }
      on_done(result)
    end
    local png, err, calls = nil, nil, 0
    local ok, perr = pcall(rasterize.render_page, "/tmp/doc.pdf", 1, opts, function(p, e)
      calls = calls + 1
      png, err = p, e
    end)
    platform.has = real_has
    package.loaded["lib.nvim.cross.uv.spawn_capture"] = real_spawn
    H.ok(ok, "render_page does not raise: " .. tostring(perr))
    return png, err, calls
  end

  -- A hanging pdftoppm: the time limit fires and the caller hears about it exactly once --------
  local png, err, calls = run(
    { ok = false, code = -1, signal = 0, stdout = "", stderr = "", timed_out = true },
    {
      timeout_ms = 5,
    }
  )
  H.eq(png, nil, "timeout: no PNG")
  H.eq(err, "pdftoppm timed out after 5 ms", "timeout: the message names the limit")
  H.eq(calls, 1, "timeout: the callback runs exactly once")
  H.eq(seen.argv[1], "pdftoppm", "the command is pdftoppm")
  H.eq(seen.opts.timeout_ms, 5, "opts.timeout_ms reaches the spawner")

  -- No timeout given: the default applies, so no caller can wait forever by accident ------------
  run({ ok = true, code = 0, signal = 0, stdout = "", stderr = "", timed_out = false })
  H.eq(seen.opts.timeout_ms, rasterize.DEFAULT_TIMEOUT_MS, "no opts: the default limit is passed")
  H.eq(rasterize.DEFAULT_TIMEOUT_MS, 30000, "and it is the 30 s of the extraction paths")

  -- The other outcomes keep their old shape ---------------------------------------------------
  png, err =
    run({ ok = false, code = 1, signal = 0, stdout = "", stderr = "boom", timed_out = false })
  H.eq(png, nil, "failure: no PNG")
  H.eq(err, "pdftoppm exited 1: boom", "failure: exit code and stderr are reported")

  local out = vim.fn.tempname()
  vim.fn.writefile({ "png" }, out .. ".png")
  png, err = run({ ok = true, code = 0, signal = 0, stdout = "", stderr = "", timed_out = false }, {
    output_path = out .. ".png",
  })
  H.eq(png, out .. ".png", "success: the PNG path comes back")
  H.eq(err, nil, "success: no error")
  vim.fn.delete(out .. ".png")

  png, err = run({ ok = true, code = 0, signal = 0, stdout = "", stderr = "", timed_out = false }, {
    output_path = out .. "-missing.png",
  })
  H.eq(png, nil, "exit 0 but no file: no PNG")
  H.match(err, "pdftoppm exited 0", "...and an error")

  -- A kill that lands mid-write leaves a truncated PNG: it must not survive the timeout -------
  local partial = vim.fn.tempname() .. ".png"
  vim.fn.writefile({ "truncated" }, partial)
  png = run(
    { ok = false, code = -1, signal = 0, stdout = "", stderr = "", timed_out = true },
    { output_path = partial, timeout_ms = 5 }
  )
  H.eq(png, nil, "timeout with a partial file: no PNG")
  H.eq(vim.fn.filereadable(partial), 0, "timeout: the truncated PNG is deleted")
  vim.fn.delete(partial)

  -- A pdftoppm that could not be started keeps naming the spawn, not an exit code ------------
  png, err = run({
    ok = false,
    code = -1,
    signal = 0,
    stdout = "",
    stderr = "failed to spawn: pdftoppm",
    timed_out = false,
  })
  H.eq(png, nil, "spawn failure: no PNG")
  H.match(err, "failed to spawn pdftoppm", "spawn failure: the message says it did not start")

  -- The ollama vision path: a timed-out rasterize also deletes its partial PNG ----------------
  local real_system = vim.system
  local real_ai = package.loaded["ai"]
  local real_ollama = package.loaded["pdfport.backends.ollama"]
  local partial_png
  package.loaded["ai"] = {
    ask = function() end,
  }
  package.loaded["pdfport.backends.ollama"] = nil
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.system = function(cmd, sys_opts, on_exit)
    seen = { argv = cmd, opts = sys_opts }
    partial_png = cmd[#cmd] .. ".png"
    vim.fn.writefile({ "truncated" }, partial_png)
    on_exit({ code = 124, signal = 15, stdout = "", stderr = "" })
    return {}
  end
  local ollama = require("pdfport.backends.ollama")
  ollama._set_config({ ollama_model = "llava" })
  local got
  local started_ok, started_err = pcall(ollama.extract, "/tmp/doc.pdf", {
    pages = { 2 },
    timeout_ms = 7,
    __callback = function(result)
      got = result
    end,
  })
  vim.wait(2000, function()
    return got ~= nil
  end, 10)
  vim.system = real_system
  package.loaded["ai"] = real_ai
  package.loaded["pdfport.backends.ollama"] = real_ollama

  H.ok(started_ok, "ollama.extract does not raise: " .. tostring(started_err))
  H.ok(got, "ollama: the timed-out run settles")
  H.eq(seen.opts.timeout, 7, "ollama: opts.timeout_ms reaches vim.system as `timeout`")
  H.eq(got.status, "error", "ollama: a timeout is an error result")
  H.eq(got.error, "ollama: rasterizing page 2 timed out", "ollama: the message names the page")
  H.eq(vim.fn.filereadable(partial_png), 0, "ollama: the truncated PNG is deleted")
  vim.fn.delete(partial_png)
end
