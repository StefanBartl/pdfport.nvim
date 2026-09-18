-- TESTS/integrations_spec.lua — the file-tree integrations.
--
-- Four trees, one job: turn "what is under the cursor" into a path. That is
-- the only thing that differs between them (bindings/keymaps.lua owns what the
-- keys then do), and it is also the only part that can be wrong in a way no
-- other spec would catch -- most visibly in netrw's, which is the one that
-- builds a path by string concatenation rather than reading one off an API.
--
-- neo-tree, nvim-tree and oil are replaced in `package.loaded` with stand-ins
-- shaped like the one function this plugin calls on each of them, so the specs
-- run without any of the four plugins installed.

return function(H)
  -- ------------------------------------------------ unified path resolution

  do
    local buf = vim.api.nvim_create_buf(false, true)
    local win = vim.api.nvim_get_current_win()
    local saved_buf = vim.api.nvim_win_get_buf(win)
    vim.api.nvim_win_set_buf(win, buf)

    ---Run `fn` with the current buffer's filetype set and the named tree
    ---plugin faked.
    ---@param ft string
    ---@param modules table<string, any>
    ---@param fn fun(integrations: table, state: table)
    local function as_tree(ft, modules, fn)
      local state = { opened = {}, warnings = {} }
      vim.bo[buf].filetype = ft
      local replacements = {
        ["lib.nvim.notify"] = {
          create = function()
            return {
              info = function() end,
              warn = function(msg)
                state.warnings[#state.warnings + 1] = msg
              end,
              error = function() end,
              debug = function() end,
            }
          end,
        },
        ["pdfport.util.notify"] = H.UNLOAD,
        ["pdfport.integrations"] = H.UNLOAD,
        ["pdfport"] = {
          open = function(opts)
            state.opened[#state.opened + 1] = opts
          end,
        },
      }
      for k, v in pairs(modules) do
        replacements[k] = v
      end
      H.with_modules(replacements, function()
        fn(require("pdfport.integrations"), state)
      end)
    end

    local function neotree_module(id)
      return {
        ["neo-tree.sources.manager"] = {
          get_state_for_window = function()
            return {
              tree = {
                get_node = function()
                  return id
                      and {
                        get_id = function()
                          return id
                        end,
                      }
                    or nil
                end,
              },
            }
          end,
        },
      }
    end

    as_tree("neo-tree", neotree_module("/docs/from-neotree.pdf"), function(integrations)
      H.eq(
        integrations.current_pdf_path(),
        "/docs/from-neotree.pdf",
        "neo-tree's node id is the path"
      )
    end)

    as_tree("neo-tree", neotree_module(nil), function(integrations)
      H.eq(integrations.current_pdf_path(), nil, "a neo-tree window with no node under the cursor")
    end)

    as_tree("NvimTree", {
      ["nvim-tree.api"] = {
        tree = {
          get_node_under_cursor = function()
            return { absolute_path = "/docs/from-nvimtree.pdf" }
          end,
        },
      },
    }, function(integrations)
      H.eq(
        integrations.current_pdf_path(),
        "/docs/from-nvimtree.pdf",
        "nvim-tree's node carries an absolute path"
      )
    end)

    as_tree("oil", {
      ["oil"] = {
        get_current_dir = function()
          return "/docs/"
        end,
        get_cursor_entry = function()
          return { name = "from-oil.pdf" }
        end,
      },
    }, function(integrations)
      H.eq(
        integrations.current_pdf_path(),
        "/docs/from-oil.pdf",
        "oil's directory already ends in a separator, so the name is appended directly"
      )
    end)

    -- netrw has no Lua API at all: the path is built from `b:netrw_curdir`
    -- and the word under the cursor, which makes the separator this plugin's
    -- problem rather than the tree's.
    do
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "report.pdf" })
      vim.api.nvim_win_set_cursor(win, { 1, 0 })

      vim.b[buf].netrw_curdir = "/docs"
      as_tree("netrw", {}, function(integrations)
        H.eq(
          integrations.current_pdf_path(),
          "/docs/report.pdf",
          "a directory without a trailing separator gets one inserted"
        )
      end)

      vim.b[buf].netrw_curdir = "/docs/"
      as_tree("netrw", {}, function(integrations)
        H.eq(
          integrations.current_pdf_path(),
          "/docs/report.pdf",
          "and one that already ends in / does not get a second"
        )
      end)

      -- The Windows half of the same check: netrw reports a backslash path
      -- there, and doubling the separator produces a path nothing can open.
      vim.b[buf].netrw_curdir = "C:\\docs\\"
      as_tree("netrw", {}, function(integrations)
        H.eq(
          integrations.current_pdf_path(),
          "C:\\docs\\report.pdf",
          "a trailing backslash counts as a separator too"
        )
      end)

      vim.b[buf].netrw_curdir = nil
      as_tree("netrw", {}, function(integrations)
        H.eq(integrations.current_pdf_path(), nil, "without b:netrw_curdir there is no path")
      end)
    end

    as_tree("lua", {}, function(integrations)
      H.eq(integrations.current_pdf_path(), nil, "a buffer that is not a file tree resolves to nil")
    end)

    -- Each tree's plugin missing entirely must miss, not raise: the
    -- integration module is loadable with none of them installed.
    do
      local saved = {}
      for _, mod in ipairs({ "neo-tree.sources.manager", "nvim-tree.api", "oil" }) do
        saved[mod] = package.preload[mod]
        package.preload[mod] = function()
          error("module '" .. mod .. "' not found")
        end
      end
      for _, ft in ipairs({ "neo-tree", "NvimTree", "oil" }) do
        as_tree(ft, {
          ["neo-tree.sources.manager"] = H.UNLOAD,
          ["nvim-tree.api"] = H.UNLOAD,
          ["oil"] = H.UNLOAD,
        }, function(integrations)
          H.eq(
            integrations.current_pdf_path(),
            nil,
            ("%s without its plugin installed resolves to nil"):format(ft)
          )
        end)
      end
      for mod, value in pairs(saved) do
        package.preload[mod] = value
      end
    end

    -- --------------------------------------------------------- open_current

    as_tree("oil", {
      ["oil"] = {
        get_current_dir = function()
          return "/docs/"
        end,
        get_cursor_entry = function()
          return { name = "paper.pdf" }
        end,
      },
    }, function(integrations, state)
      integrations.open_current()
      H.eq(#state.opened, 1, "open_current opens what is under the cursor")
      H.eq(state.opened[1].path, "/docs/paper.pdf", "at the resolved path")
      H.eq(state.opened[1].mode, "buffer", "into a buffer by default")
      H.eq(state.opened[1].split, "vsplit", "as a vertical split")
      H.eq(state.opened[1].focus, true, "with focus")

      integrations.open_current({ mode = "system", split = false })
      H.eq(state.opened[2].mode, "system", "caller options override the defaults")
      H.eq(state.opened[2].path, "/docs/paper.pdf", "while the resolved path survives the merge")
    end)

    as_tree("oil", {
      ["oil"] = {
        get_current_dir = function()
          return "/docs/"
        end,
        get_cursor_entry = function()
          return { name = "notes.txt" }
        end,
      },
    }, function(integrations, state)
      integrations.open_current()
      H.eq(#state.opened, 0, "a non-PDF under the cursor is not opened")
      H.match(state.warnings[1], "not a PDF", "and is named in the warning")
      H.match(state.warnings[1], "notes%.txt", "so the user can see what was under the cursor")
    end)

    as_tree("lua", {}, function(integrations, state)
      integrations.open_current()
      H.eq(#state.opened, 0, "and neither is a buffer that is not a file tree")
      H.match(state.warnings[1], "unsupported file%-tree", "which says what went wrong")
    end)

    vim.api.nvim_win_set_buf(win, saved_buf)
    vim.api.nvim_buf_delete(buf, { force = true })
  end

  -- ---------------------------------------------- per-tree setup() wiring

  -- netrw, oil and nvim-tree all bind the same five actions through the same
  -- FileType autocmd; what each one's setup() owns is the filetype, the
  -- augroup name and its own path resolver.
  do
    local function autocmd_group(name)
      local ok, list = pcall(vim.api.nvim_get_autocmds, { group = name })
      return ok and list or {}
    end

    require("pdfport.integrations.netrw").setup()
    local netrw_cmds = autocmd_group("pdfport_netrw")
    H.eq(#netrw_cmds, 1, "netrw's setup registers one autocmd")
    H.eq(netrw_cmds[1].pattern, "netrw", "on the netrw filetype")

    require("pdfport.integrations.oil").setup()
    local oil_cmds = autocmd_group("pdfport_oil")
    H.eq(#oil_cmds, 1, "oil's setup registers one autocmd")
    H.eq(oil_cmds[1].pattern, "oil", "on the oil filetype")

    -- nvim-tree's setup is the one that gates on its plugin being installed,
    -- because its path resolver is useless without the API module.
    require("pdfport.integrations.nvim_tree").setup()
    H.eq(
      #autocmd_group("pdfport_tree"),
      0,
      "nvim-tree's setup is a no-op when nvim-tree itself is not installed"
    )

    H.with_modules({
      ["nvim-tree.api"] = {
        tree = {
          get_node_under_cursor = function()
            return { absolute_path = "/docs/a.pdf" }
          end,
        },
      },
    }, function()
      require("pdfport.integrations.nvim_tree").setup()
      local tree_cmds = autocmd_group("pdfport_tree")
      H.eq(#tree_cmds, 1, "with nvim-tree present it registers its autocmd")
      H.eq(tree_cmds[1].pattern, "NvimTree", "on the NvimTree filetype")
    end)

    -- Entering a matching buffer binds the five keys buffer-locally.
    do
      local buf = vim.api.nvim_create_buf(false, true)
      vim.bo[buf].filetype = "netrw"
      H.eq(#vim.api.nvim_buf_get_keymap(buf, "n"), 4, "entering a netrw buffer binds four keys")
      H.eq(#vim.api.nvim_buf_get_keymap(buf, "v"), 1, "plus the visual-mode batch key")
      vim.api.nvim_buf_delete(buf, { force = true })
    end

    for _, group in ipairs({ "pdfport_netrw", "pdfport_oil", "pdfport_tree" }) do
      pcall(vim.api.nvim_del_augroup_by_name, group)
    end

    -- nvim-tree also exports the five actions as plain functions, so its own
    -- `on_attach` can map them directly instead of going through setup().
    do
      local nvim_tree = require("pdfport.integrations.nvim_tree")
      for _, name in ipairs({
        "cmd_open",
        "cmd_open_text",
        "cmd_open_system",
        "cmd_open_terminal",
        "cmd_open_batch",
      }) do
        H.eq(type(nvim_tree[name]), "function", ("nvim_tree exports %s"):format(name))
      end

      local opened = {}
      H.with_modules({
        ["nvim-tree.api"] = {
          tree = {
            get_node_under_cursor = function()
              return { absolute_path = "/docs/a.pdf" }
            end,
          },
        },
        ["pdfport"] = {
          open = function(opts)
            opened[#opened + 1] = opts
          end,
        },
      }, function()
        nvim_tree.cmd_open_text()
      end)
      H.eq(#opened, 1, "and calling one of them opens the node under the cursor")
      H.eq(opened[1].path, "/docs/a.pdf", "at nvim-tree's own absolute path")
    end
  end

  -- ------------------------------------------------------------- neo-tree

  -- neo-tree is the exception: it does not take mappings via vim.keymap.set
  -- at all, but as a table of lhs to command name that it installs itself.
  do
    local neotree = require("pdfport.integrations.neotree")

    local commands = neotree.commands()
    for _, name in ipairs({
      "pdfport_open",
      "pdfport_text",
      "pdfport_system",
      "pdfport_terminal",
      "pdfport_batch",
    }) do
      H.eq(type(commands[name]), "function", ("neo-tree gets a %s command"):format(name))
    end

    local function state_for(path)
      return {
        tree = {
          get_node = function()
            return {
              get_id = function()
                return path
              end,
            }
          end,
        },
      }
    end

    local opened, picked, batched, warnings = {}, {}, {}, {}
    H.with_modules({
      ["lib.nvim.notify"] = {
        create = function()
          return {
            info = function() end,
            warn = function(msg)
              warnings[#warnings + 1] = msg
            end,
            error = function() end,
            debug = function() end,
          }
        end,
      },
      ["pdfport.util.notify"] = H.UNLOAD,
      ["pdfport.util.picker"] = {
        pick_and_open = function(path)
          picked[#picked + 1] = path
        end,
      },
      ["pdfport.util.batch"] = {
        open_selected = function(resolver)
          batched[#batched + 1] = resolver()
        end,
      },
      ["pdfport"] = {
        open = function(opts)
          opened[#opened + 1] = opts
        end,
      },
      ["pdfport.integrations.neotree"] = H.UNLOAD,
    }, function()
      local cmds = require("pdfport.integrations.neotree").commands()

      cmds.pdfport_open(state_for("/docs/a.pdf"))
      H.eq_list(picked, { "/docs/a.pdf" }, "pdfport_open goes through the shared picker")

      cmds.pdfport_text(state_for("/docs/a.pdf"))
      H.eq(opened[1].mode, "buffer", "pdfport_text extracts into a buffer")
      H.eq(opened[1].split, "vsplit", "as a vertical split")

      cmds.pdfport_system(state_for("/docs/a.pdf"))
      H.eq(opened[2].mode, "system", "pdfport_system hands it to the OS viewer")

      cmds.pdfport_terminal(state_for("/docs/a.pdf"))
      H.eq(opened[3].mode, "terminal", "pdfport_terminal renders it in the terminal")

      cmds.pdfport_batch(state_for("/docs/a.pdf"))
      H.eq_list(batched, { "/docs/a.pdf" }, "pdfport_batch hands a resolver to util.batch")

      cmds.pdfport_open(state_for("/docs/notes.txt"))
      H.eq(#picked, 1, "a non-PDF is not picked")
      H.eq_list(warnings, { "not a PDF file" }, "and the deliberate key says why")

      local before = #opened
      cmds.pdfport_text(state_for("/docs/notes.txt"))
      cmds.pdfport_system({})
      H.eq(#opened, before, "while the direct commands decline silently")
      H.eq(#warnings, 1, "adding no further noise")
    end)

    -- The mappings table neo-tree installs: normal-mode entries at the top
    -- level, visual-mode ones under a "v" sub-table, which is neo-tree's own
    -- documented per-mode window.mappings shape.
    do
      local groups = {}
      local map
      H.with_modules({
        ["lib.nvim.bindings.keymap.which_key"] = {
          add_group = function(opts)
            groups[#groups + 1] = opts
          end,
        },
      }, function()
        map = neotree.keymaps()
      end)

      local keymaps = require("pdfport.bindings.keymaps")
      H.eq(map[keymaps.DEFAULTS.open], "pdfport_open", "the picker key maps to the open command")
      H.eq(map[keymaps.DEFAULTS.open_text], "pdfport_text", "and the extract key to its command")
      H.eq(type(map.v), "table", "visual-mode entries live under a `v` sub-table")
      H.eq(
        map.v[keymaps.DEFAULTS.open_batch],
        "pdfport_batch",
        "which is where the batch key ends up"
      )
      H.eq(map[keymaps.DEFAULTS.open_batch], nil, "and not at the top level as a normal-mode key")
      H.eq(#groups, 1, "which-key is given the group label at the same time")

      local partial = neotree.keymaps({ open_system = false, open_batch = false })
      H.eq(partial[keymaps.DEFAULTS.open_system], nil, "a disabled action gets no entry")
      H.eq(partial.v, nil, "and disabling the batch action drops the visual sub-table entirely")

      local renamed = neotree.keymaps({ open = "gp" })
      H.eq(renamed.gp, "pdfport_open", "an override moves the command to the requested key")
      H.eq(renamed[keymaps.DEFAULTS.open], nil, "and leaves nothing on the default one")
    end
  end

  -- --------------------------------------------- picker previewer adapters

  -- telescope.nvim and fzf-lua are not in this checkout, so only the half
  -- that does not touch their APIs is exercised: the filetype gate, and the
  -- extraction request behind it.
  do
    local requests = {}
    local telescope = require("pdfport.integrations.telescope")

    H.with_modules({
      ["pdfport"] = {
        extract = function(opts)
          requests[#requests + 1] = opts
          opts.__callback({
            status = "ok",
            text = "# Extracted\n\nbody",
            format = "markdown",
            backend = "marker",
          })
        end,
      },
    }, function()
      local buf = vim.api.nvim_create_buf(false, true)

      H.falsy(telescope.filetype_hook("/docs/a.txt", buf, {}), "a non-PDF is left to the default")
      H.eq(#requests, 0, "and nothing is extracted for it")

      H.ok(telescope.filetype_hook("/docs/a.pdf", buf, {}), "a PDF is handled by the hook")
      H.eq(#requests, 1, "which asks for one extraction")
      H.eq(requests[1].path, "/docs/a.pdf", "of that file")
      -- A preview is a glance, not a read: extracting a 400-page scan to
      -- show the first screen would hold the picker for minutes.
      H.eq(requests[1].max_pages, 5, "capped at a few pages, since this is only a preview")

      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      H.eq(lines[1], "# Extracted", "the extracted text lands in the preview buffer")
      H.eq(vim.bo[buf].filetype, "markdown", "with a filetype so it is highlighted")
      H.falsy(vim.bo[buf].modifiable, "and read-only again afterwards")

      -- The preview is memoized per path, so scrolling back to a file the
      -- picker has already shown does not extract it a second time.
      telescope.filetype_hook("/docs/a.pdf", buf, {})
      H.eq(#requests, 2, "the hook itself re-extracts (its cache lives on the previewer object)")

      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    -- `M.previewer()` itself: previously untested at all. `telescope.previewers`
    -- is faked so the previewer object's own `define_preview` -- path
    -- resolution, the extraction request, and the cache-then-check-status
    -- bug fzf's `preview_fn` is pinned for below -- runs without the real
    -- telescope.nvim installed. Only telescope's own `new_buffer_previewer`
    -- internals (buffer wiring, highlighting inside telescope itself) stay
    -- out of reach here, same as before.
    do
      local previewer_requests = {}
      local captured_opts

      H.with_modules({
        ["telescope.previewers"] = {
          new_buffer_previewer = function(bp_opts)
            captured_opts = bp_opts
            return bp_opts
          end,
        },
        ["pdfport"] = {
          extract = function(opts)
            previewer_requests[#previewer_requests + 1] = opts
            opts.__callback({
              status = "error",
              text = nil,
              error = "no backend available",
              format = "plain",
              backend = "none",
            })
          end,
        },
      }, function()
        local previewer = telescope.previewer({ max_pages = 4 })
        H.eq(captured_opts.title, "PDF (pdfport)", "the previewer is titled for pdfport")
        H.ok(type(previewer.define_preview) == "function", "and carries a define_preview closure")

        local buf = vim.api.nvim_create_buf(false, true)
        local self_stub = { state = { bufnr = buf } }

        previewer.define_preview(self_stub, { path = "/docs/a.txt" }, {})
        H.eq(#previewer_requests, 0, "a non-PDF entry is ignored, same gate as filetype_hook")

        previewer.define_preview(self_stub, { filename = "/docs/b.pdf" }, {})
        H.eq(#previewer_requests, 1, "entry.filename is used when .path is absent")
        H.eq(previewer_requests[1].path, "/docs/b.pdf", "with that resolved path")
        H.eq(previewer_requests[1].max_pages, 4, "honouring the caller-supplied page cap")
        H.match(
          vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1],
          "no backend available",
          "a failed extraction is written into the preview buffer"
        )

        -- BUG: the same one fzf.lua's `_cache` is pinned for above --
        -- `cache[path] = text` runs before anything looks at `result.status`,
        -- so this failed preview is memoized exactly like a successful one.
        -- TESTS/README.md already named this as "duplicated in
        -- integrations/telescope.lua"; until now nothing here actually
        -- exercised that copy of it.
        previewer.define_preview(self_stub, { filename = "/docs/b.pdf" }, {})
        H.eq(#previewer_requests, 1, "BUG: a failed preview is cached, so it is never retried")
        H.match(
          vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1],
          "no backend available",
          "BUG: and the stale error is replayed from the memo"
        )

        vim.api.nvim_buf_delete(buf, { force = true })
      end)
    end

    local fzf_requests = {}
    H.with_modules({
      ["pdfport"] = {
        extract = function(opts)
          fzf_requests[#fzf_requests + 1] = opts
          opts.__callback({
            status = "error",
            text = nil,
            error = "no backend available",
            format = "plain",
            backend = "none",
          })
        end,
      },
      ["pdfport.integrations.fzf"] = H.UNLOAD,
    }, function()
      local preview = require("pdfport.integrations.fzf").preview_fn({ max_pages = 2 })
      local buf = vim.api.nvim_create_buf(false, true)

      preview("/docs/a.txt", buf, {})
      H.eq(#fzf_requests, 0, "fzf-lua's previewer ignores non-PDFs too")

      preview("/docs/a.pdf", buf, {})
      H.eq(#fzf_requests, 1, "and extracts for a PDF")
      H.eq(fzf_requests[1].max_pages, 2, "honouring a caller-supplied page cap")

      -- A failed extraction is shown in the preview rather than leaving the
      -- "extracting..." placeholder up forever.
      H.match(
        vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1],
        "no backend available",
        "an extraction error is written into the preview buffer"
      )

      -- BUG: the previewer's own per-path memo stores whatever text it ended
      -- up showing, INCLUDING an error message -- `_cache[filepath] = text`
      -- runs before anything looks at `result.status`. `util/cache.lua`, the
      -- extraction cache proper, deliberately refuses exactly this ("if not
      -- result or result.status ~= 'ok' ... then return end") because a
      -- transient failure -- ollama not started yet, poppler not installed
      -- yet -- would otherwise be pinned. Here it is: once a PDF has failed
      -- to preview, every later preview of it in this Neovim session replays
      -- the stale error without retrying, and `_cache` is module-level, so
      -- not even opening a fresh picker clears it. Pinned rather than fixed:
      -- the same line is duplicated in integrations/telescope.lua and the fix
      -- changes what a user sees.
      preview("/docs/a.pdf", buf, {})
      H.eq(#fzf_requests, 1, "BUG: a failed preview is cached, so it is never retried")
      H.match(
        vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1],
        "no backend available",
        "BUG: and the stale error is replayed from the memo"
      )

      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end
end
