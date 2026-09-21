-- TESTS/picker_batch_spec.lua — the shared "open PDF as…" picker and the
-- visual-mode batch opener.
--
-- `util.picker` is the one choice list every file-tree integration, the
-- `:PdfPort` command and `pdfport.pick_open()` share, and its documented
-- guarantee is that "System application" is ALWAYS one of the options: it is
-- the only entry that needs no external CLI, no backend and no configuration,
-- so a picker that can leave the user with no working option is worse than no
-- picker. That guarantee is a property of `M.choices()`, which is why it is
-- public and why it is asserted here from several directions.
--
-- `util.batch` is the other half: it resolves a visual selection to PDF paths
-- and counts settled outcomes rather than attempted opens.
--
-- `pdfport` itself and `ui.kit` are replaced in `package.loaded`, so nothing
-- is extracted, rendered or handed to the OS.

return function(H)
  local picker = require("pdfport.util.picker")

  -- ------------------------------------------------------------- choices()

  do
    local default = picker.choices()
    H.ok(#default > 1, "the default list offers several ways to open a PDF")

    local has_system, modes = false, {}
    for _, c in ipairs(default) do
      if c.mode == "system" then has_system = true end
      modes[c.mode] = true
      H.eq(type(c.label), "string", "every choice has a label")
      H.ok(c.label ~= "", "which is not empty")
    end
    H.ok(has_system, "the default list includes the system application")
    H.ok(modes.buffer, "as well as the buffer renderer")
    H.ok(modes.float, "the float renderer")
    H.ok(modes.terminal, "and the terminal renderer")

    -- Filtering cannot remove the system entry: it is re-appended here rather
    -- than trusted to every call site.
    local filtered = picker.choices({ choices = { { label = "only", mode = "buffer" } } })
    H.eq(#filtered, 2, "a caller-supplied list without it gets it back")
    H.eq(filtered[1].label, "only", "the caller's own entry comes first")
    H.eq(filtered[2].mode, "system", "and the system entry is appended")

    -- ...but it is not duplicated when the caller kept it.
    local kept = picker.choices({
      choices = { { label = "sys", mode = "system" }, { label = "buf", mode = "buffer" } },
    })
    H.eq(#kept, 2, "a list that already has it is left at its own length")
    H.eq(kept[1].label, "sys", "in the caller's own order")

    H.eq(#picker.choices({ choices = {} }), 1, "even an empty list still offers the system entry")
  end

  -- ------------------------------------------------------- open_via_picker()

  do
    ---Drive the picker with `ui.kit` and `pdfport` replaced.
    ---@param opts table|nil        picker opts
    ---@param choose fun(items: string[]): integer|nil  which entry to select
    ---@param fn fun(state: table)
    local function pick(opts, choose, fn)
      local state = { opened = {}, inputs = {}, select_opts = nil }
      H.with_modules({
        ["ui.kit"] = {
          select = function(select_opts)
            state.select_opts = select_opts
            local idx = choose(select_opts.items)
            if idx then
              select_opts.on_select(select_opts.items[idx], idx)
            elseif select_opts.on_cancel then
              select_opts.on_cancel()
            end
          end,
          input = function(input_opts)
            state.inputs[#state.inputs + 1] = input_opts
            input_opts.on_submit("2-3")
          end,
        },
        ["pdfport"] = {
          open = function(open_opts)
            state.opened[#state.opened + 1] = open_opts
          end,
        },
        ["pdfport.util.page_range"] = H.UNLOAD,
      }, function()
        fn(state)
      end)
      return state
    end

    -- A plain buffer-mode choice opens straight away, with no page prompt.
    local state = pick(nil, function()
      return 1
    end, function(s)
      picker.open_via_picker("/docs/a.pdf", { title = "spec" })
      H.eq(s.select_opts.title, "spec", "the caller's title is used")
    end)
    H.eq(#state.opened, 1, "choosing an entry opens the PDF once")
    H.eq(state.opened[1].path, "/docs/a.pdf", "for the path that was picked")
    H.eq(state.opened[1].mode, "buffer", "in the chosen mode")
    H.eq(state.opened[1].focus, true, "focusing the result, since the user asked for it")
    H.eq(#state.inputs, 0, "and no page range is asked for in buffer mode")

    -- float/terminal prompt for a page range first: rasterizing or floating a
    -- 400-page document is not a useful default.
    local float_state = pick(nil, function(items)
      for i, label in ipairs(items) do
        if label:match("Float") then return i end
      end
      return nil
    end, function()
      picker.open_via_picker("/docs/a.pdf")
    end)
    H.eq(#float_state.inputs, 1, "float mode prompts for a page range")
    H.match(float_state.inputs[1].title, "pdfport pages", "with a prompt that says what it wants")
    H.eq(float_state.opened[1].mode, "float", "then opens in float mode")
    H.eq_list(float_state.opened[1].pages, { 2, 3 }, "carrying the parsed page range")

    -- `system_first` is for embedders whose previous behaviour was "always
    -- the system viewer": the old one-keystroke path stays under the cursor.
    local first_state = pick(nil, function()
      return 1
    end, function()
      picker.open_via_picker("/docs/a.pdf", { system_first = true })
    end)
    H.match(first_state.select_opts.items[1], "System", "system_first puts the system entry first")
    H.eq(first_state.opened[1].mode, "system", "so entry 1 is now the system one")
    H.eq(#first_state.select_opts.items, #picker.choices(), "without dropping any other entry")

    -- `system_open` hands that one entry to the caller's own OS-opener (WSL
    -- path translation, open.nvim delegation) instead of pdfport's renderer.
    local routed = {}
    local routed_state = pick(nil, function()
      return 1
    end, function()
      picker.open_via_picker("/docs/a.pdf", {
        system_first = true,
        system_open = function(path)
          routed[#routed + 1] = path
        end,
      })
    end)
    H.eq_list(routed, { "/docs/a.pdf" }, "system_open receives the path")
    H.eq(#routed_state.opened, 0, "and pdfport's own system renderer is not used")

    -- Cancelling means "never mind", not "open it in some default mode".
    local cancelled = 0
    local cancel_state = pick(nil, function()
      return nil
    end, function()
      picker.open_via_picker("/docs/a.pdf", {
        on_cancel = function()
          cancelled = cancelled + 1
        end,
      })
    end)
    H.eq(cancelled, 1, "dismissing the picker calls on_cancel")
    H.eq(#cancel_state.opened, 0, "and opens nothing")
  end

  -- Without ui.nvim the picker still works, through vim.ui.select. That
  -- fallback is what keeps ui.nvim a soft dependency.
  do
    local opened = {}
    local saved_select = vim.ui.select
    local saved_preload = package.preload["ui.kit"]
    package.preload["ui.kit"] = function()
      error("module 'ui.kit' not found")
    end

    local seen_prompt, seen_items
    vim.ui.select = function(items, select_opts, on_choice)
      seen_items, seen_prompt = items, select_opts.prompt
      on_choice(items[1], 1)
    end

    H.with_modules({
      ["ui.kit"] = H.UNLOAD,
      ["pdfport"] = {
        open = function(open_opts)
          opened[#opened + 1] = open_opts
        end,
      },
    }, function()
      picker.open_via_picker("/docs/a.pdf", { title = "Fallback" })
    end)

    H.ok(seen_items, "vim.ui.select is used when ui.kit is absent")
    H.eq(#seen_items, #picker.choices(), "offering the same list")
    H.match(seen_prompt, "^Fallback", "with the caller's title as the prompt")
    H.eq(#opened, 1, "and a choice still opens the PDF")

    -- Cancelling through the fallback has to reach on_cancel too.
    local cancels = 0
    vim.ui.select = function(items, _, on_choice)
      on_choice(nil, nil)
    end
    H.with_modules({
      ["ui.kit"] = H.UNLOAD,
      ["pdfport"] = {
        open = function(open_opts)
          opened[#opened + 1] = open_opts
        end,
      },
    }, function()
      picker.open_via_picker("/docs/a.pdf", {
        on_cancel = function()
          cancels = cancels + 1
        end,
      })
    end)
    H.eq(cancels, 1, "cancelling the fallback calls on_cancel as well")
    H.eq(#opened, 1, "and opens nothing further")

    package.preload["ui.kit"] = saved_preload
    vim.ui.select = saved_select
  end

  -- ------------------------------------------------------------- page_range

  -- `prompt()` is the interactive half of the parser that page_range_spec
  -- already covers: what matters here is that a dismissed or blank prompt
  -- reaches the caller as nil rather than as an empty page list.
  do
    local answers = { "1-3,5", "", "nonsense" }
    local idx = 0
    H.with_modules({
      ["ui.kit"] = {
        input = function(opts)
          idx = idx + 1
          opts.on_submit(answers[idx])
        end,
      },
      ["pdfport.util.page_range"] = H.UNLOAD,
    }, function()
      local page_range = require("pdfport.util.page_range")
      local got
      page_range.prompt(function(pages)
        got = pages
      end)
      H.eq_list(got, { 1, 2, 3, 5 }, "a range is parsed into an explicit page list")

      page_range.prompt(function(pages)
        got = pages
      end)
      H.eq(got, nil, "a blank answer is nil, meaning the caller's own default")

      page_range.prompt(function(pages)
        got = pages
      end)
      H.eq(got, nil, "as is an answer with no page number in it at all")
    end)
  end

  -- Without ui.nvim, prompt() still works through vim.ui.input -- the
  -- fallback docs/requirements.md promises for this prompt too.
  do
    local saved_input = vim.ui.input
    local saved_preload = package.preload["ui.kit"]
    package.preload["ui.kit"] = function()
      error("module 'ui.kit' not found")
    end

    local seen_prompt
    vim.ui.input = function(input_opts, on_confirm)
      seen_prompt = input_opts.prompt
      on_confirm("1-3,5")
    end

    H.with_modules({
      ["ui.kit"] = H.UNLOAD,
      ["pdfport.util.page_range"] = H.UNLOAD,
    }, function()
      local page_range = require("pdfport.util.page_range")
      local got
      page_range.prompt(function(pages)
        got = pages
      end)
      H.eq_list(got, { 1, 2, 3, 5 }, "vim.ui.input is used when ui.kit is absent")
      H.match(seen_prompt, "pdfport pages", "with the same prompt text")
    end)

    package.preload["ui.kit"] = saved_preload
    vim.ui.input = saved_input
  end

  -- ----------------------------------------------------------------- batch

  do
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "a.pdf",
      "notes.txt",
      "b.PDF",
      "a.pdf",
      "c.pdf",
    })
    local win = vim.api.nvim_get_current_win()
    local saved_buf = vim.api.nvim_win_get_buf(win)
    vim.api.nvim_win_set_buf(win, buf)

    ---The cursor-based resolver each integration supplies, faked over the
    ---buffer's own lines -- the same shape as netrw/oil/nvim-tree's.
    local function resolve_path()
      local line = vim.api.nvim_win_get_cursor(win)[1]
      return vim.api.nvim_buf_get_lines(buf, line - 1, line, false)[1]
    end

    ---Run open_selected with `pdfport` and the notifier replaced.
    ---@param settle fun(path: string): boolean  what each open reports back
    ---@param fn fun()
    ---@return table opened, table notes
    local function with_batch(settle, fn)
      local opened, notes = {}, {}
      H.with_modules({
        ["lib.nvim.notify"] = {
          create = function()
            return {
              info = function(msg)
                notes[#notes + 1] = { level = "info", msg = msg }
              end,
              warn = function(msg)
                notes[#notes + 1] = { level = "warn", msg = msg }
              end,
              error = function(msg)
                notes[#notes + 1] = { level = "error", msg = msg }
              end,
              debug = function() end,
            }
          end,
        },
        ["pdfport.util.notify"] = H.UNLOAD,
        ["pdfport"] = {
          open = function(open_opts, on_error, on_done)
            opened[#opened + 1] = open_opts
            local ok = settle(open_opts.path)
            if not ok then on_error("could not open " .. open_opts.path) end
            on_done(ok)
          end,
        },
      }, fn)
      return opened, notes
    end

    -- Lines 1..4: one .txt (skipped), one duplicate (deduped), and a .PDF in
    -- capitals (matched case-insensitively).
    vim.api.nvim_buf_set_mark(buf, "<", 1, 0, {})
    vim.api.nvim_buf_set_mark(buf, ">", 4, 0, {})
    vim.api.nvim_win_set_cursor(win, { 2, 0 })

    local opened, notes = with_batch(function()
      return true
    end, function()
      require("pdfport.util.batch").open_selected(resolve_path)
    end)

    H.eq(#opened, 2, "non-PDF lines are skipped and duplicates are opened only once")
    H.eq(opened[1].path, "a.pdf", "in selection order")
    H.eq(opened[2].path, "b.PDF", "matching the .pdf suffix case-insensitively")
    H.eq(opened[1].mode, "buffer", "each one opens into a buffer")
    H.eq(opened[1].split, "vsplit", "as a vertical split")
    H.eq(opened[1].focus, false, "without stealing focus, since several are opening at once")
    H.eq(vim.api.nvim_win_get_cursor(win)[1], 2, "and the cursor is put back where it started")
    H.eq(notes[#notes].level, "info", "a fully successful batch reports at info level")
    H.match(notes[#notes].msg, "opened 2 PDF", "with the count of files that actually opened")

    -- Counting settled outcomes, not attempts: opening is asynchronous and
    -- reports failures through its own error callback, so a selection where
    -- some failed must not still claim they all opened.
    local _, mixed_notes = with_batch(function(path)
      return path ~= "b.PDF"
    end, function()
      require("pdfport.util.batch").open_selected(resolve_path)
    end)
    local summary = mixed_notes[#mixed_notes]
    H.eq(summary.level, "warn", "a partly failed batch warns instead")
    H.match(summary.msg, "opened 1 of 2", "naming how many of how many succeeded")
    H.match(summary.msg, "1 failed", "and how many did not")
    H.eq(mixed_notes[1].level, "error", "while each failure is still reported individually")

    -- A selection with no PDF in it says so rather than opening nothing
    -- silently.
    vim.api.nvim_buf_set_mark(buf, "<", 2, 0, {})
    vim.api.nvim_buf_set_mark(buf, ">", 2, 0, {})
    local none, none_notes = with_batch(function()
      return true
    end, function()
      require("pdfport.util.batch").open_selected(resolve_path)
    end)
    H.eq(#none, 0, "a selection of non-PDFs opens nothing")
    H.eq(none_notes[1].level, "warn", "and warns")
    H.match(none_notes[1].msg, "no PDF files", "saying there was nothing to open")

    -- A reversed selection (cursor dragged upwards) covers the same lines.
    vim.api.nvim_buf_set_mark(buf, "<", 5, 0, {})
    vim.api.nvim_buf_set_mark(buf, ">", 3, 0, {})
    local reversed = with_batch(function()
      return true
    end, function()
      require("pdfport.util.batch").open_selected(resolve_path)
    end)
    H.eq(#reversed, 3, "a reversed selection still covers its whole range")
    H.eq(reversed[1].path, "b.PDF", "walked from the lower line number upwards")
    H.eq(reversed[3].path, "c.pdf", "to the higher one")

    -- A resolver that raises on some lines must not take the whole batch
    -- down with it: file trees do return nodes with no path.
    vim.api.nvim_buf_set_mark(buf, "<", 1, 0, {})
    vim.api.nvim_buf_set_mark(buf, ">", 5, 0, {})
    local resilient = with_batch(function()
      return true
    end, function()
      require("pdfport.util.batch").open_selected(function()
        local line = vim.api.nvim_win_get_cursor(win)[1]
        if line == 3 then error("no node here") end
        return resolve_path()
      end)
    end)
    H.eq(#resilient, 2, "a resolver that raises on one line skips only that line")
    H.eq(resilient[2].path, "c.pdf", "and the rest of the selection still opens")

    vim.api.nvim_win_set_buf(win, saved_buf)
    vim.api.nvim_buf_delete(buf, { force = true })
  end
end
