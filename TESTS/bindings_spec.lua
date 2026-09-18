-- TESTS/bindings_spec.lua — the three binding surfaces: the `:PdfPort` verb,
-- the five file-tree actions, and the FileType/BufReadCmd autocmds.
--
-- `smoke_spec.lua` only checks that the command exists. What it does is here:
-- every route, the path resolution in front of them (argument, then <cfile>,
-- then the current buffer), and the `pages=` key that exists so
-- `:PdfPort float` is usable from a script rather than only from a prompt.
--
-- The verb is re-registered against a fake `pdfport` API for the duration, so
-- running a route records a call instead of opening anything. `ui.kit` is
-- faked too: it is a soft dependency this checkout does not have, and the
-- interactive page prompt requires it unconditionally.

return function(H)
  -- --------------------------------------------------------- :PdfPort verb

  do
    ---Register the verb against a recording stand-in for the public API.
    ---@param fn fun(state: table)
    ---@return table state
    local function with_verb(fn)
      local state = {
        opened = {},
        picked = {},
        created = {},
        merged = {},
        errors = {},
        warnings = {},
        infos = {},
        scratches = {},
        page_answer = "2-4",
      }
      H.with_modules({
        ["lib.nvim.notify"] = {
          create = function()
            return {
              info = function(msg)
                state.infos[#state.infos + 1] = msg
              end,
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
        ["ui.kit"] = {
          input = function(opts)
            opts.on_submit(state.page_answer)
          end,
        },
        ["lib.nvim.window.make_scratch"] = function(opts)
          state.scratches[#state.scratches + 1] = opts
        end,
        ["pdfport.util.notify"] = H.UNLOAD,
        ["pdfport.util.page_range"] = H.UNLOAD,
        ["pdfport.bindings.usrcmds"] = H.UNLOAD,
      }, function()
        require("pdfport.bindings.usrcmds").register({
          open = function(opts, on_error)
            state.opened[#state.opened + 1] = { opts = opts, on_error = on_error }
          end,
          pick_open = function(path, opts)
            state.picked[#state.picked + 1] = { path = path, opts = opts }
          end,
          create = function(opts)
            state.created[#state.created + 1] = opts
          end,
          merge = function(opts)
            state.merged[#state.merged + 1] = opts
          end,
        })
        fn(state)
      end)
      return state
    end

    ---Run `:PdfPort <args...>`. nvim_cmd rather than vim.cmd so a spec that
    ---intercepts vim.cmd can still invoke the command itself.
    ---@param ... string
    local function run(...)
      vim.api.nvim_cmd({ cmd = "PdfPort", args = { ... } }, {})
    end

    local pdf = H.tempfile("-bindings-spec.pdf", { "%PDF-1.4 fake" })

    -- Bare `:PdfPort [path]` is the verb's root route: it matches with no
    -- literal subcommand at all, and opens the shared mode picker rather
    -- than keeping a second, hand-maintained choice list of its own.
    local state = with_verb(function()
      run(pdf)
    end)
    H.eq(#state.picked, 1, "bare :PdfPort opens the mode picker")
    H.eq(state.picked[1].path, pdf, "for the path it was given")
    H.match(state.picked[1].opts.title, "pdfport", "under a pdfport-owned title")
    H.eq(#state.opened, 0, "and does not open anything directly")

    state = with_verb(function()
      run("text", pdf)
    end)
    H.eq(state.opened[1].opts.mode, "buffer", ":PdfPort text extracts into a buffer")
    H.eq(state.opened[1].opts.path, pdf, "for the given path")
    H.eq(state.opened[1].opts.focus, true, "focusing the result")
    H.eq(
      type(state.opened[1].on_error),
      "function",
      "with the command's own notifier as the error handler, not the library default"
    )

    state = with_verb(function()
      run("system", pdf)
    end)
    H.eq(state.opened[1].opts.mode, "system", ":PdfPort system hands it to the OS viewer")

    -- float/terminal prompt for a page range when `pages=` is absent...
    state = with_verb(function()
      run("float", pdf)
    end)
    H.eq(state.opened[1].opts.mode, "float", ":PdfPort float opens a float")
    H.eq_list(state.opened[1].opts.pages, { 2, 3, 4 }, "with the range the prompt returned")

    state = with_verb(function()
      run("terminal", pdf)
    end)
    H.eq(state.opened[1].opts.mode, "terminal", ":PdfPort terminal renders in the terminal")
    H.eq_list(state.opened[1].opts.pages, { 2, 3, 4 }, "prompting for pages there too")

    -- ...and skip the prompt entirely when it is supplied, which is the only
    -- way to drive these two routes from a script or a mapping.
    state = with_verb(function(s)
      s.page_answer = "9"
      run("float", pdf, "pages=1-2,7")
    end)
    H.eq_list(
      state.opened[1].opts.pages,
      { 1, 2, 7 },
      "an explicit pages= is used as-is, without prompting"
    )

    -- A pages= that parses to nothing is reported rather than silently
    -- falling through to "the whole document", which is the kind of thing
    -- that goes unnoticed in a script.
    state = with_verb(function()
      run("float", pdf, "pages=abc")
    end)
    H.eq(#state.opened, 0, "a pages= that parses to nothing opens nothing")
    H.eq(#state.warnings, 1, "and warns")
    H.match(state.warnings[1], "did not parse", "saying why")

    state = with_verb(function()
      run("create", pdf)
    end)
    H.eq(#state.created, 1, ":PdfPort create goes to the creation API")
    H.eq_list(state.created[1].inputs, { pdf }, "with the resolved path as its input")

    state = with_verb(function()
      run("merge", "out.pdf", "a.pdf", "b.pdf")
    end)
    H.eq(#state.merged, 1, ":PdfPort merge goes to the merge API")
    H.eq_list(state.merged[1].inputs, { "a.pdf", "b.pdf" }, "with every extra argument an input")
    H.match(state.merged[1].output, "out%.pdf$", "and the first argument as the output")

    state = with_verb(function()
      run("merge", "out.pdf", "only.pdf")
    end)
    H.eq(#state.merged, 0, "merging fewer than two inputs does nothing")
    H.match(state.errors[1], "at least 2 input PDFs", "and says what it needed")

    -- Both diagnostics routes show the same registry dump; they differ only
    -- in the title, since the registry reports backends and producers together.
    state = with_verb(function()
      run("backends")
      run("producers")
    end)
    H.eq(#state.scratches, 2, "backends and producers each open a scratch window")
    H.match(state.scratches[1].title, "backends", "titled for the half the user asked about")
    H.match(state.scratches[2].title, "producers", "and likewise for producers")
    H.ok(#state.scratches[1].lines > 0, "with the registry diagnostics as content")
    H.ok(state.scratches[1].nice_quit, "and q/<Esc> bound to close it")

    -- Without lib.nvim's scratch helper the same text is notified instead:
    -- diagnostics that cannot be shown in a window are still worth having.
    do
      local saved = package.preload["lib.nvim.window.make_scratch"]
      package.preload["lib.nvim.window.make_scratch"] = function()
        error("module 'lib.nvim.window.make_scratch' not found")
      end
      local plain = with_verb(function()
        H.with_modules({ ["lib.nvim.window.make_scratch"] = H.UNLOAD }, function()
          run("backends")
        end)
      end)
      H.eq(#plain.infos, 1, "with no scratch helper the diagnostics are notified")
      H.match(plain.infos[1], "pdfport registry diagnostics", "as the same text, in one message")
      package.preload["lib.nvim.window.make_scratch"] = saved
    end

    -- ------------------------------------------------- path resolution

    -- No argument: <cfile>, then the current buffer's own name.
    local buf = vim.api.nvim_create_buf(false, true)
    local win = vim.api.nvim_get_current_win()
    local saved_buf = vim.api.nvim_win_get_buf(win)
    vim.api.nvim_win_set_buf(win, buf)

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { pdf })
    vim.api.nvim_win_set_cursor(win, { 1, 0 })
    state = with_verb(function()
      run("text")
    end)
    H.eq(state.opened[1].opts.path, pdf, "with no argument the path under the cursor is used")

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
    -- Canonical, because that is what comes back: Neovim resolves a buffer
    -- name through the OS, so on macOS `nvim_buf_get_name()` answers
    -- `/private/var/...` for the `/var/...` that `tempname()` reported. The
    -- fallback under test is "the path came from this buffer", not which of
    -- the two spellings of one directory the runner's kernel prefers.
    local named = H.tempfile("-named-buffer.pdf")
    vim.api.nvim_buf_set_name(buf, named)
    state = with_verb(function()
      run("text")
    end)
    H.eq(state.opened[1].opts.path, named, "falling back to the current buffer's own name")

    local anon = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(anon, 0, -1, false, { "" })
    vim.api.nvim_win_set_buf(win, anon)
    state = with_verb(function()
      run("text")
    end)
    H.eq(#state.opened, 0, "an unnamed buffer with nothing under the cursor resolves to nothing")
    H.match(state.errors[1], "no file path", "and the command says so")
    H.match(state.errors[1], "PdfPort text", "naming the route that could not run")

    vim.api.nvim_win_set_buf(win, saved_buf)
    vim.api.nvim_buf_delete(buf, { force = true })
    vim.api.nvim_buf_delete(anon, { force = true })

    -- ---------------------------------------------------- completion

    -- A dedicated PDF_PATH argument type rather than composer's built-in
    -- PATH: this one puts .pdf files first, which is the whole reason it
    -- exists as its own type.
    do
      local dir = vim.fn.stdpath("cache") .. "/pdfport_spec_complete"
      pcall(vim.fn.delete, dir, "rf")
      vim.fn.mkdir(dir, "p")
      for _, name in ipairs({ "zzz.pdf", "aaa.txt" }) do
        vim.fn.writefile({ "x" }, dir .. "/" .. name)
      end

      with_verb(function()
        local items = vim.fn.getcompletion("PdfPort text " .. dir .. "/", "cmdline")
        H.ok(#items >= 2, "completing a directory offers its entries")
        H.match(items[1], "zzz%.pdf$", "with PDFs first, even when they sort last alphabetically")
        H.match(items[2], "aaa%.txt$", "and everything else after them")
      end)

      pcall(vim.fn.delete, dir, "rf")
    end

    pcall(vim.fn.delete, pdf)
    pcall(vim.fn.delete, named)
  end

  -- Re-register the real verb, so the remaining specs (and anything after the
  -- suite) see the plugin's own routes rather than this spec's recorder.
  require("pdfport").setup({})

  -- -------------------------------------------------------------- keymaps

  do
    local keymaps = require("pdfport.bindings.keymaps")

    -- The declaration tables have to agree: ORDER is what the docs and
    -- :checkhealth read top to bottom, and a key present in one table and
    -- missing from another is a silently undocumented or unbindable action.
    H.eq(#keymaps.ORDER, 5, "five actions are declared")
    for _, action in ipairs(keymaps.ORDER) do
      H.ok(keymaps.DEFAULTS[action], ("%s has a default key"):format(action))
      H.ok(keymaps.DESCRIPTIONS[action], ("%s has a description"):format(action))
      H.match(keymaps.DEFAULTS[action], "^<leader>p", ("%s lives under <leader>p"):format(action))
    end
    local declared = 0
    for _ in pairs(keymaps.DEFAULTS) do
      declared = declared + 1
    end
    H.eq(declared, #keymaps.ORDER, "and ORDER covers every declared default, with none left over")
    H.ok(keymaps.VISUAL_ACTIONS.open_batch, "batch-open is the visual-mode action")
    H.falsy(keymaps.VISUAL_ACTIONS.open, "while the rest are normal-mode")

    -- resolve() is neo-tree's path: it installs mappings itself from a table
    -- keyed by lhs, so what it needs is the resolved keys, not the binding.
    local resolved = keymaps.resolve()
    H.eq(resolved.open, keymaps.DEFAULTS.open, "resolve() falls back to the defaults")
    H.eq(keymaps.resolve({ open = "<leader>x" }).open, "<leader>x", "an override replaces one key")
    H.eq(keymaps.resolve({ open = false }).open, false, "false disables one action")
    H.eq(
      keymaps.resolve({ open = { "<leader>x", "<leader>y" } }).open,
      "<leader>x",
      "a list override collapses to its first key -- neo-tree's table is keyed by lhs"
    )
    H.eq(
      keymaps.resolve({ open = "<leader>x" }).open_text,
      keymaps.DEFAULTS.open_text,
      "and overriding one action leaves the others at their defaults"
    )

    -- The five actions themselves, over a path getter the spec controls.
    do
      local path, opened, picked, batched, warnings = nil, {}, {}, {}, {}
      local notify = {
        warn = function(msg)
          warnings[#warnings + 1] = msg
        end,
        error = function() end,
        info = function() end,
      }

      H.with_modules({
        ["pdfport"] = {
          open = function(opts)
            opened[#opened + 1] = opts
          end,
        },
        ["pdfport.util.picker"] = {
          pick_and_open = function(p)
            picked[#picked + 1] = p
          end,
        },
        ["pdfport.util.batch"] = {
          open_selected = function(resolver)
            batched[#batched + 1] = resolver()
          end,
        },
      }, function()
        local actions = keymaps.actions(function()
          return path
        end, notify)

        path = "/docs/a.pdf"
        actions.open.rhs()
        H.eq_list(picked, { "/docs/a.pdf" }, "the `open` action goes through the shared picker")

        actions.open_text.rhs()
        H.eq(opened[1].mode, "buffer", "`open_text` skips the picker and extracts to a buffer")
        H.eq(opened[1].split, "vsplit", "as a vertical split")
        H.eq(opened[1].focus, true, "with focus")

        actions.open_system.rhs()
        H.eq(opened[2].mode, "system", "`open_system` hands it to the OS viewer")
        H.eq(opened[2].split, nil, "with no split, which would mean nothing there")
        H.eq(opened[2].focus, nil, "and no focus flag either")

        actions.open_terminal.rhs()
        H.eq(opened[3].mode, "terminal", "`open_terminal` renders it in the terminal")

        actions.open_batch.rhs()
        H.eq_list(batched, { "/docs/a.pdf" }, "`open_batch` hands the resolver to util.batch")
        H.eq(actions.open_batch.mode, "v", "and is declared as a visual-mode mapping")

        -- Only `open` says why nothing happened: it is the key a user presses
        -- on purpose, while the others are reached from the picker it opens.
        path = "/docs/notes.txt"
        actions.open.rhs()
        H.eq(#picked, 1, "a non-PDF is not opened by the picker action")
        H.eq_list(warnings, { "not a PDF file" }, "which says so")

        local before = #opened
        actions.open_text.rhs()
        actions.open_system.rhs()
        actions.open_terminal.rhs()
        H.eq(#opened, before, "the direct actions decline a non-PDF too")
        H.eq(#warnings, 1, "but silently -- a notification per tree entry would be noise")

        path = nil
        actions.open.rhs()
        H.eq(#warnings, 2, "a resolver that finds no path at all warns as well")

        -- Case-insensitively, because a file tree shows whatever the
        -- filesystem has and .PDF is common on Windows.
        path = "/docs/REPORT.PDF"
        actions.open.rhs()
        H.eq(#picked, 2, "an uppercase .PDF is recognised")
      end)
    end

    -- bind() goes through lib.nvim's keymap registry rather than
    -- vim.keymap.set, which is what makes a wrong action name in a user's
    -- table say so instead of silently binding nothing.
    do
      local buf = vim.api.nvim_create_buf(false, true)
      local registered = keymaps.bind(buf, "spec_surface", function()
        return "/docs/a.pdf"
      end, { warn = function() end, error = function() end, info = function() end })
      H.eq(#registered, 5, "bind() reports all five registrations")

      local by_name = {}
      for _, entry in ipairs(registered) do
        by_name[entry.name] = entry
        H.ok(entry.bound, ("%s was actually bound"):format(entry.name))
        H.eq(entry.buffer, buf, ("%s is buffer-local, not global"):format(entry.name))
        H.match(
          entry.desc,
          "^pdfport: ",
          ("%s is described under the plugin's name"):format(entry.name)
        )
      end
      H.eq(by_name.open.lhs, keymaps.DEFAULTS.open, "the picker key uses its declared default")
      H.eq(by_name.open.mode, "n", "in normal mode")
      H.eq(by_name.open_batch.mode, "v", "while batch-open is bound in visual mode instead")

      -- The registry's own bookkeeping is one thing; whether Neovim really
      -- has the mappings is another, so both are checked.
      H.eq(#vim.api.nvim_buf_get_keymap(buf, "n"), 4, "four normal-mode maps exist on the buffer")
      H.eq(#vim.api.nvim_buf_get_keymap(buf, "v"), 1, "and one visual-mode map")

      -- `false` disables exactly one action and leaves the rest alone.
      local buf2 = vim.api.nvim_create_buf(false, true)
      local partial = keymaps.bind(buf2, "spec_surface_2", function()
        return nil
      end, { warn = function() end, error = function() end, info = function() end }, {
        open_system = false,
      })
      local names = {}
      for _, entry in ipairs(partial) do
        if entry.bound then names[entry.name] = true end
      end
      H.falsy(names.open_system, "a disabled action is not bound")
      H.ok(names.open, "while its siblings still are")
      H.eq(#vim.api.nvim_buf_get_keymap(buf2, "n"), 3, "leaving three normal-mode maps")

      vim.api.nvim_buf_delete(buf, { force = true })
      vim.api.nvim_buf_delete(buf2, { force = true })
    end

    do
      local groups = {}
      H.with_modules({
        ["lib.nvim.bindings.keymap.which_key"] = {
          add_group = function(opts)
            groups[#groups + 1] = opts
          end,
        },
      }, function()
        keymaps.register_which_key()
      end)
      H.eq(#groups, 1, "which-key gets one group registered")
      H.eq(groups[1].prefix, "<leader>p", "for the plugin's own prefix")
      H.eq(groups[1].group, "pdfport", "labelled pdfport")
      -- Per-key descriptions are deliberately not sent: which-key reads the
      -- mappings' own `desc`, so repeating them here would only give one
      -- string a second place to drift from.
      H.eq(groups[1].keys, nil, "and nothing else -- the descriptions live on the mappings")
    end
  end

  -- ------------------------------------------------------------- autocmds

  do
    local autocmds = require("pdfport.bindings.autocmds")

    local seen = {}
    autocmds.on_filetype("spec_tree_ft", "pdfport_spec_group", function(buf)
      seen[#seen + 1] = buf
    end)
    local registered = vim.api.nvim_get_autocmds({ group = "pdfport_spec_group" })
    H.eq(#registered, 1, "on_filetype registers exactly one FileType autocmd")
    H.eq(registered[1].event, "FileType", "on the FileType event")
    H.eq(registered[1].pattern, "spec_tree_ft", "for the filetype it was given")

    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].filetype = "spec_tree_ft"
    H.eq(#seen, 1, "entering a matching buffer invokes the callback")
    H.eq(seen[1], buf, "with that buffer's number")
    vim.api.nvim_buf_delete(buf, { force = true })

    -- BUG: this module's own docs say each registration is idempotent --
    -- "re-running setup() clears and re-creates its own augroup instead of
    -- accumulating duplicate autocmds/keymaps". It does not. `autocmd.create`
    -- resolves a string `group` through `autocmd.group(name)` WITHOUT the
    -- `clear` argument, so the augroup is created once and every later call
    -- adds another autocmd to it. Clearing needs the caller to resolve the
    -- group itself first (`autocmd.group(name, true)`) and pass the id.
    -- Pinned rather than fixed: see register_bufreadcmd below for what it
    -- actually costs, and the fix changes observable behaviour.
    autocmds.on_filetype("spec_tree_ft", "pdfport_spec_group", function(buf_nr)
      seen[#seen + 1] = buf_nr
    end)
    H.eq(
      #vim.api.nvim_get_autocmds({ group = "pdfport_spec_group" }),
      2,
      "BUG: registering again ADDS a second autocmd instead of clearing the group"
    )

    local twice = vim.api.nvim_create_buf(false, true)
    vim.bo[twice].filetype = "spec_tree_ft"
    H.eq(#seen, 3, "BUG: so one FileType event now runs the same callback twice")
    vim.api.nvim_buf_delete(twice, { force = true })
    pcall(vim.api.nvim_del_augroup_by_name, "pdfport_spec_group")

    -- The opt-in BufReadCmd: `:e file.pdf` must invoke the picker instead of
    -- loading the raw PDF bytes into a buffer.
    autocmds.register_bufreadcmd()
    local read_cmds = vim.api.nvim_get_autocmds({ group = "pdfport_bufreadcmd" })
    H.eq(#read_cmds, 1, "register_bufreadcmd registers one autocmd")
    H.eq(read_cmds[1].event, "BufReadCmd", "on BufReadCmd")
    H.eq(read_cmds[1].pattern, "*.pdf", "for *.pdf")
    H.match(read_cmds[1].desc, "picker", "described by what it does")

    -- BUG (the same one, and this is where it is visible to a user): the
    -- doc comment promises "idempotent like M.on_filetype (own augroup,
    -- cleared on each call)". A second `require("pdfport").setup()` -- which
    -- costs nothing else, and which lazy.nvim reconfiguration or a plugin
    -- embedding pdfport can easily trigger -- leaves TWO BufReadCmd autocmds
    -- on `*.pdf`. Both fire for one `:e file.pdf`, so the mode picker opens
    -- twice, stacked, for a single open.
    autocmds.register_bufreadcmd()
    H.eq(
      #vim.api.nvim_get_autocmds({ group = "pdfport_bufreadcmd" }),
      2,
      "BUG: registering the BufReadCmd again adds a second rather than replacing it"
    )

    do
      local picked = {}
      local pdf = H.tempfile("-autocmd-spec.pdf", { "%PDF-1.4 fake" })
      H.with_modules({
        ["pdfport.util.picker"] = {
          pick_and_open = function(path)
            picked[#picked + 1] = path
          end,
        },
      }, function()
        vim.cmd("edit " .. vim.fn.fnameescape(pdf))
        local buf_nr = vim.api.nvim_get_current_buf()
        H.eq(vim.bo[buf_nr].buftype, "nofile", "the PDF buffer is marked as a scratch buffer")
        H.falsy(vim.bo[buf_nr].modifiable, "and read-only, so nobody edits PDF bytes by accident")
        H.eq(vim.bo[buf_nr].bufhidden, "wipe", "and wiped once it is left")
        vim.wait(500, function()
          return #picked > 0
        end)
        H.match(picked[1], "autocmd%-spec%.pdf$", "and the mode picker is invoked on that file")
        -- The consequence of the duplicate registration above, made concrete:
        -- one `:e file.pdf`, two pickers.
        H.eq(#picked, 2, "BUG: both registrations fire, so the picker opens twice for one :e")
        vim.cmd("enew")
      end)
      pcall(vim.fn.delete, pdf)
    end

    pcall(vim.api.nvim_del_augroup_by_name, "pdfport_bufreadcmd")
  end
end
