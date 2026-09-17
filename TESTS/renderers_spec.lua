-- TESTS/renderers_spec.lua — the four output renderers.
--
-- `buffer` is exercised against real buffers and windows: it is the default
-- mode, it is pure Neovim API, and there is nothing to fake about it. `float`
-- and `system` delegate their one effect to lib.nvim, so those seams are
-- replaced and what is asserted is the arguments they hand over. `terminal`
-- is the one renderer that shells out, so its rasterizer and its `:terminal`
-- command line are both intercepted -- what a test can say about it is which
-- command it would have run, not what the image looked like.

return function(H)
  -- ------------------------------------------------------- buffer renderer

  do
    local buffer = require("pdfport.renderers.buffer")

    local function render(result, opts)
      buffer.render(result, opts)
      return vim.api.nvim_win_get_buf(vim.api.nvim_get_current_win())
    end

    local bufnr = render(
      { status = "ok", text = "first\r\nsecond\r", format = "plain", backend = "pdftotext" },
      { path = "/docs/annual report.pdf", split = "current" }
    )

    local name = vim.api.nvim_buf_get_name(bufnr)
    H.match(name, "pdfport://annual report$", "the scratch buffer is named pdfport://<stem>")

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    H.match(lines[1], "^<!%-%- pdfport: ", "a provenance header is prepended")
    H.match(lines[1], "annual report%.pdf", "naming the source file")
    H.match(lines[1], "backend: pdftotext", "the backend that produced the text")
    H.match(lines[1], "format: plain", "and the format it is in")
    H.eq(lines[2], "", "followed by a blank line")
    -- Windows line endings survive pdftotext on some documents; left in, they
    -- show up as ^M at the end of every line in the buffer.
    H.eq(lines[3], "first", "the extracted text follows, with any CR stripped")
    H.eq(lines[4], "second", "on every line, including the last")

    H.falsy(vim.bo[bufnr].modifiable, "the buffer is read-only")
    H.eq(vim.bo[bufnr].buftype, "nofile", "and a scratch buffer")
    H.eq(vim.bo[bufnr].bufhidden, "hide", "kept around when hidden, so reopening is instant")
    H.falsy(vim.bo[bufnr].swapfile, "with no swapfile")
    H.eq(vim.bo[bufnr].filetype, "text", "plain output gets the `text` filetype")

    -- Same source file, same buffer: a second open must not leave a pile of
    -- pdfport:// buffers behind.
    local again = render(
      { status = "ok", text = "# Title", format = "markdown", backend = "marker" },
      { path = "/docs/annual report.pdf", split = "current" }
    )
    H.eq(again, bufnr, "rendering the same PDF again reuses its buffer")
    H.eq(vim.bo[bufnr].filetype, "markdown", "markdown output switches the filetype")
    H.eq(
      vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)[3],
      "# Title",
      "and the content is replaced, not appended to"
    )

    -- A result with no text at all still renders: a backend that found an
    -- empty document should show an empty buffer, not raise.
    local empty = render(
      { status = "ok", text = nil, format = "plain", backend = "pdftotext" },
      { path = "/docs/empty.pdf", split = "current" }
    )
    H.eq_list(
      vim.api.nvim_buf_get_lines(empty, 1, -1, false),
      { "", "" },
      "an empty extraction renders as header, blank line, and one empty line"
    )

    -- The split modes, each of which has its own window-creation branch.
    local before_wins = #vim.api.nvim_tabpage_list_wins(0)
    render(
      { status = "ok", text = "x", format = "plain", backend = "b" },
      { path = "/docs/split.pdf", split = "vsplit" }
    )
    H.eq(#vim.api.nvim_tabpage_list_wins(0), before_wins + 1, "split='vsplit' opens a new window")
    vim.cmd("close")

    render(
      { status = "ok", text = "x", format = "plain", backend = "b" },
      { path = "/docs/split.pdf", split = "split" }
    )
    H.eq(#vim.api.nvim_tabpage_list_wins(0), before_wins + 1, "split='split' opens one too")
    vim.cmd("close")

    local tabs_before = #vim.api.nvim_list_tabpages()
    render(
      { status = "ok", text = "x", format = "plain", backend = "b" },
      { path = "/docs/split.pdf", split = "tab" }
    )
    H.eq(#vim.api.nvim_list_tabpages(), tabs_before + 1, "split='tab' opens a new tab")
    vim.cmd("tabclose")

    -- focus=false is what lets util.batch open several PDFs without the
    -- cursor ending up in the last one.
    local origin = vim.api.nvim_get_current_win()
    vim.cmd("vsplit")
    local other = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_win(origin)
    buffer.render(
      { status = "ok", text = "x", format = "plain", backend = "b" },
      { path = "/docs/nofocus.pdf", split = "current", focus = false }
    )
    H.eq(vim.api.nvim_get_current_win(), other, "focus=false hands the cursor back")
    vim.api.nvim_set_current_win(origin)
    if vim.api.nvim_win_is_valid(other) then vim.api.nvim_win_close(other, true) end

    -- An unknown/blank split value is the same as "current", not an error.
    local fallback = render(
      { status = "ok", text = "x", format = "plain", backend = "b" },
      { path = "/docs/blank.pdf", split = "" }
    )
    H.ok(vim.api.nvim_buf_is_valid(fallback), "an empty split value renders in place")
    local nil_split = render(
      { status = "ok", text = "x", format = "plain", backend = "b" },
      { path = "/docs/nilsplit.pdf" }
    )
    H.ok(vim.api.nvim_buf_is_valid(nil_split), "as does no split value at all")

    -- A missing path must not raise: dispatcher.open asserts on it, but the
    -- renderer is registered as a plain function anyone can call.
    local ok_nopath = pcall(buffer.render, {
      status = "ok",
      text = "x",
      format = "plain",
      backend = "b",
    }, { split = "current" })
    H.ok(ok_nopath, "rendering without a path does not raise")
  end

  -- -------------------------------------------------------- float renderer

  do
    local captured
    H.with_modules({
      ["lib.nvim.window.make_scratch"] = function(opts)
        captured = opts
      end,
      ["pdfport.renderers.float"] = H.UNLOAD,
    }, function()
      local float = require("pdfport.renderers.float")

      float.render(
        { status = "ok", text = "line one\nline two", format = "markdown", backend = "docling" },
        { path = "/docs/paper.pdf" }
      )
      H.eq_list(captured.lines, { "line one", "line two" }, "the text is split into lines")
      H.eq(captured.filetype, "markdown", "markdown output sets the filetype")
      H.match(captured.title, "paper%.pdf", "the title names the source file's basename")
      H.eq(captured.title_pos, "center", "centred")
      H.eq(captured.width, 0.8, "at 80% of the editor width")
      H.eq(captured.height, 0.8, "and 80% of its height")
      H.ok(captured.wo.wrap, "with wrapping on, since extracted text has no layout")
      H.ok(captured.nice_quit, "and q/<Esc> bound to close it")

      float.render(
        { status = "ok", text = "x", format = "plain", backend = "pdftotext" },
        { path = "/docs/paper.pdf" }
      )
      H.eq(captured.filetype, "text", "plain output gets the text filetype")

      -- float_opts is a narrowing rather than an arbitrary nvim_open_win
      -- passthrough: the fields make_scratch understands, and no others.
      float.render(
        { status = "ok", text = "x", format = "plain", backend = "b" },
        { path = "/docs/paper.pdf", float_opts = { width = 0.5, border = "single" } }
      )
      H.eq(captured.width, 0.5, "float_opts overrides the default width")
      H.eq(captured.border, "single", "and can set a border")
      H.eq(captured.height, 0.8, "while leaving the fields it does not mention alone")

      local ok_empty = pcall(float.render, { status = "ok", format = "plain", backend = "b" }, {})
      H.ok(ok_empty, "a result with no text and no path still renders")
    end)
  end

  -- ------------------------------------------------------- system renderer

  do
    local opened, notes = {}, {}
    local answer = { true, nil }
    H.with_modules({
      ["lib.nvim.cross.open_default"] = function(path)
        opened[#opened + 1] = path
        return answer[1], answer[2]
      end,
      ["lib.nvim.notify"] = {
        create = function()
          return {
            info = function() end,
            warn = function() end,
            error = function(msg)
              notes[#notes + 1] = msg
            end,
            debug = function() end,
          }
        end,
      },
      ["pdfport.util.notify"] = H.UNLOAD,
      ["pdfport.renderers.system"] = H.UNLOAD,
    }, function()
      local system = require("pdfport.renderers.system")

      system.render({}, { path = "/docs/a.pdf" })
      -- Dispatch goes through lib.nvim's opener, not platform.open_cmd(): it
      -- is the one that knows not to spawn a bare `start` on Windows.
      H.eq_list(opened, { "/docs/a.pdf" }, "the path is handed to lib.nvim's OS opener")
      H.eq(#notes, 0, "and a successful open says nothing")

      system.render({}, {})
      H.eq(#opened, 1, "no path means nothing is opened")
      H.eq(#notes, 1, "and an error is reported")
      H.match(notes[1], "no path provided", "saying what was missing")

      answer = { false, "no handler registered for .pdf" }
      system.render({}, { path = "/docs/a.pdf" })
      H.eq(#notes, 2, "a refused open is reported")
      H.match(notes[2], "no handler registered", "carrying the opener's own reason")

      answer = { false, nil }
      system.render({}, { path = "/docs/a.pdf" })
      H.match(notes[3], "could not open the PDF", "and a refusal with no reason still says so")
    end)
  end

  -- ----------------------------------------------------- terminal renderer

  do
    ---Load the terminal renderer with its rasterizer, its file-waiter, its
    ---notifier and `vim.cmd` all intercepted.
    ---@param present table<string, boolean>  what platform reports installed
    ---@param rasterize fun(path: string, page: integer, opts: table, cb: fun(png: string|nil, err: string|nil))
    ---@param fn fun(terminal: table, state: table)
    local function with_terminal(present, rasterize, fn)
      local state = { commands = {}, errors = {}, warnings = {} }
      local saved_cmd = vim.cmd
      vim.cmd = function(command)
        state.commands[#state.commands + 1] = command
      end
      local ok, err = pcall(function()
        H.with_modules({
          ["pdfport.core.rasterize"] = { render_page = rasterize, args = function() end },
          ["lib.nvim.cross.uv.wait_until"] = function(_, _, cb)
            cb(true)
          end,
          ["lib.nvim.notify"] = {
            create = function()
              return {
                info = function() end,
                warn = function(msg)
                  state.warnings[#state.warnings + 1] = msg
                end,
                error = function(msg)
                  state.errors[#state.errors + 1] = msg
                end,
                debug = function() end,
              }
            end,
          },
          ["pdfport.util.notify"] = H.UNLOAD,
          ["pdfport.platform"] = H.fake_platform(present),
          ["pdfport.renderers.terminal"] = H.UNLOAD,
        }, function()
          fn(require("pdfport.renderers.terminal"), state)
        end)
      end)
      vim.cmd = saved_cmd
      if not ok then error(err, 0) end
    end

    local function serve(png)
      return function(_, _, _, cb)
        cb(png, nil)
      end
    end

    with_terminal({ chafa = true }, serve("/tmp/page.png"), function(terminal, state)
      terminal.render({}, { path = "/docs/a.pdf", pages = { 2 } })
      H.eq(#state.commands, 1, "one terminal is opened per page")
      H.match(state.commands[1], "^split | terminal ", "in a split running a terminal")
      H.match(state.commands[1], "chafa %-%-size=%d+x%d+ ", "driving chafa at a computed size")
      -- shellescape, because this goes through a shell command line rather
      -- than an argv: a path with a space in it would otherwise split.
      H.match(state.commands[1], "page%.png", "with the rasterized page as its argument")
      H.eq(#state.errors, 0, "and nothing is reported as an error")
    end)

    with_terminal({ kitten = true, chafa = true }, serve("/tmp/page.png"), function(terminal, state)
      terminal.render({}, { path = "/docs/a.pdf", terminal_tool = "kitty" })
      H.match(state.commands[1], "kitten icat ", "the kitty tool uses `kitten icat` when available")
    end)

    with_terminal({}, serve("/tmp/page.png"), function(terminal, state)
      terminal.render({}, { path = "/docs/a.pdf", terminal_tool = "kitty" })
      H.match(state.commands[1], "kitty icat ", "falling back to the `kitty` binary itself")
    end)

    with_terminal({}, serve("/tmp/page.png"), function(terminal, state)
      terminal.render({}, { path = "/docs/a.pdf", terminal_tool = "imgcat" })
      H.match(state.commands[1], "^split | terminal imgcat ", "and imgcat is invoked bare")
    end)

    -- chafa named explicitly but not installed: warn rather than opening a
    -- terminal that immediately prints "command not found".
    with_terminal({}, serve("/tmp/page.png"), function(terminal, state)
      terminal.render({}, { path = "/docs/a.pdf", terminal_tool = "chafa" })
      H.eq(#state.commands, 0, "a missing chafa opens no terminal")
      H.eq(#state.warnings, 1, "but warns")
      H.match(state.warnings[1], "chafa not installed", "naming it")
    end)

    with_terminal({}, serve("/tmp/page.png"), function(terminal, state)
      terminal.render({}, { path = "/docs/a.pdf" })
      H.eq(#state.commands, 0, "with no image tool at all, nothing is opened")
      H.eq(#state.errors, 1, "and the failure is reported")
      H.match(state.errors[1], "no image renderer", "pointing at what to install")
    end)

    with_terminal({ chafa = true }, function(_, _, _, cb)
      cb(nil, "pdftoppm exited 1: no such page")
    end, function(terminal, state)
      terminal.render({}, { path = "/docs/a.pdf" })
      H.eq(#state.commands, 0, "a failed rasterize opens no terminal")
      H.eq_list(state.errors, { "pdftoppm exited 1: no such page" }, "and surfaces the error as-is")
    end)

    with_terminal({ chafa = true }, function(_, _, _, cb)
      cb(nil, nil)
    end, function(terminal, state)
      terminal.render({}, { path = "/docs/a.pdf" })
      H.match(state.errors[1], "rasterizer returned no PNG", "a silent nil PNG is still an error")
    end)

    with_terminal({ chafa = true }, serve("/tmp/page.png"), function(terminal, state)
      terminal.render({}, {})
      H.eq(#state.commands, 0, "no path renders nothing")
      H.match(state.errors[1], "no path provided", "and says so")
    end)

    -- The dpi and size ratio a caller (or config) supplies have to reach the
    -- rasterizer and the display command respectively.
    local seen_dpi, seen_page
    with_terminal({ chafa = true }, function(_, page, opts, cb)
      seen_dpi, seen_page = opts.dpi, page
      cb("/tmp/page.png", nil)
    end, function(terminal, state)
      terminal.render({}, {
        path = "/docs/a.pdf",
        terminal_dpi = 300,
        terminal_size_ratio = { width = 0.5, height = 0.25 },
      })
      H.eq(seen_dpi, 300, "terminal_dpi reaches the rasterizer")
      H.eq(seen_page, 1, "and with no page list, page 1 is rendered")
      local w, h = state.commands[1]:match("%-%-size=(%d+)x(%d+)")
      H.eq(
        tonumber(w),
        math.floor(vim.o.columns * 0.5),
        "chafa's width is terminal_size_ratio.width of the editor's columns"
      )
      H.eq(
        tonumber(h),
        math.floor(vim.o.lines * 0.25),
        "and its height the same fraction of the editor's lines"
      )
    end)
  end
end
