-- TESTS/config_util_spec.lua — configuration merge, and the three small
-- utility modules every other module is built on (notify, spawn_env,
-- platform).
--
-- These are the pieces nothing else can be tested around: a wrong merge makes
-- every backend read the wrong timeout, a wrong `platform.has` makes every
-- `available()` lie, and `spawn_env` decides whether a libuv child can find
-- pandoc at all. All three delegate to lib.nvim, so what is asserted here is
-- the delegation and the plugin-specific logic on top of it -- never lib.nvim's
-- own behaviour, which has its own suite.

return function(H)
  -- ------------------------------------------------------------- DEFAULTS

  do
    local defaults = require("pdfport.config.DEFAULTS")
    H.eq(type(defaults), "function", "DEFAULTS is a factory, not a shared table")

    local a, b = defaults(), defaults()
    H.falsy(rawequal(a, b), "each call returns a fresh table")
    a.fallback_chain[1] = "mutated"
    H.eq(b.fallback_chain[1], "pdftotext", "so one caller's mutation cannot leak into the next")

    local d = defaults()
    H.eq(d.default_backend, "auto", "the default backend is auto")
    -- Order is the contract here, not membership: resolver.lua appends every
    -- registered id after this list, so a backend missing from it is still
    -- reachable -- the list decides what is tried first.
    H.eq(d.fallback_chain[1], "pdftotext", "the cheapest local backend is tried first")
    H.eq(
      d.fallback_chain[#d.fallback_chain],
      "gemini",
      "and the remote model backends come last, never reached while a local one works"
    )
    H.ok(
      H.index_of(d.fallback_chain, "claude") < H.index_of(d.fallback_chain, "gemini"),
      "claude before gemini"
    )
    H.eq(d.extract_opts.timeout_ms, 30000, "extraction gets 30 s by default")
    H.ok(d.extract_opts.cache, "and is cached by default")
    H.eq(d.render_opts.mode, "buffer", "opening renders into a buffer by default")
    H.eq(d.create_opts.timeout_ms, 60000, "creation gets 60 s by default")

    H.eq_list(d.create_chain.image, { "img2pdf", "magick" }, "images: lossless img2pdf first")
    H.eq_list(d.create_chain.markdown, { "pandoc" }, "markdown goes through pandoc")
    H.eq_list(d.create_chain.text, { "pandoc" }, "as does plain text")
    H.eq_list(d.create_chain.html, { "weasyprint", "chromium" }, "html: weasyprint, then a browser")
    H.eq_list(d.create_chain.office, { "soffice" }, "office documents: LibreOffice")
    H.eq_list(
      d.create_chain.pdf,
      { "qpdf", "pdftk", "ghostscript" },
      "merging: exact first, re-encoding last"
    )

    H.eq(d.pdf_engine, "auto", "the TeX engine is auto-detected by default")
    H.eq(d.ollama_host, "http://localhost:11434", "ollama defaults to the local daemon")
    H.falsy(d.auto_open_on_read, "intercepting :e file.pdf is opt-in")
    H.ok(d.deps_popup, "the one-time install popup is on by default")
    H.falsy(d.debug, "debug logging is off by default")
  end

  -- --------------------------------------------------------------- config

  do
    local config = require("pdfport.config")

    config.setup({ extract_opts = { max_pages = 7 } })
    local cfg = config.get()
    H.eq(cfg.extract_opts.max_pages, 7, "a user value is applied")
    H.eq(cfg.extract_opts.timeout_ms, 30000, "and its siblings survive the deep merge")
    H.eq(cfg.default_backend, "auto", "as do untouched top-level keys")

    -- setup() rebuilds from the defaults rather than accumulating: a second
    -- call with a different spec must not leave the first one's values behind.
    config.setup({ default_backend = "marker" })
    H.eq(config.get().default_backend, "marker", "a later setup() applies its own values")
    H.eq(
      config.get().extract_opts.max_pages,
      nil,
      "and drops the previous call's -- setup() resets rather than accumulating"
    )

    -- A configured chain replaces the default outright. Merging them would
    -- mean a user who removed a backend still got it, in a position they
    -- never chose.
    config.setup({ fallback_chain = { "docling" } })
    H.eq_list(config.get().fallback_chain, { "docling" }, "a user chain replaces, not extends")

    config.setup(nil)
    H.eq(config.get().default_backend, "auto", "setup(nil) is the defaults")
    H.eq(#config.get().fallback_chain, 8, "with the full built-in chain back")

    -- ERR-50: validation runs before the merge, not after -- a typo must not
    -- silently vanish into the default with no trace anywhere.
    config.setup({ defalt_backend = "marker", extract_opts = { max_page = 3, timeout_ms = 5 } })
    local issues = config.issues()
    H.eq(#issues, 2, "one issue per rejected key")
    H.ok(
      H.index_of(issues, "unknown option 'defalt_backend' (did you mean 'default_backend'?)") ~= nil,
      "an unknown top-level key names the nearby real one"
    )
    H.ok(
      H.index_of(
        issues,
        "unknown option 'extract_opts.max_page' (did you mean 'extract_opts.max_pages'?)"
      ) ~= nil,
      "an unknown nested key is reported with its dotted path"
    )
    H.eq(
      config.get().default_backend,
      "auto",
      "the rejected top-level key falls back to the default"
    )
    H.eq(
      config.get().extract_opts.max_pages,
      nil,
      "the rejected nested key falls back to its default"
    )
    H.eq(
      config.get().extract_opts.timeout_ms,
      5,
      "its valid sibling in the same table is still applied"
    )

    -- A value that must be a table but is not degrades to the default too,
    -- rather than being merged in and corrupting every reader of it.
    config.setup({ fallback_chain = "pdftotext" })
    H.eq(#config.issues(), 1, "a wrong-typed table option is one issue")
    H.match(config.issues()[1], "must be a table", "naming what was expected")
    H.eq_list(
      config.get().fallback_chain,
      require("pdfport.config.DEFAULTS")().fallback_chain,
      "and the default chain is kept rather than the string"
    )

    config.setup({ default_backend = "marker" })
    H.eq(#config.issues(), 0, "a clean setup() reports no issues")

    -- ERR-50: the unknown-key check recurses to whatever depth KNOWN
    -- declares, not just one level -- a typo two levels down must be
    -- caught with its full dotted path, exactly like a top-level one.
    config.setup({ render_opts = { terminal_size_ratio = { wdith = 0.4, height = 0.5 } } })
    local nested_issues = config.issues()
    H.eq(#nested_issues, 1, "one issue for the misspelled nested-of-nested key")
    H.ok(
      H.index_of(
        nested_issues,
        "unknown option 'render_opts.terminal_size_ratio.wdith' "
          .. "(did you mean 'render_opts.terminal_size_ratio.width'?)"
      ) ~= nil,
      "the dotted path names exactly where the typo is, two levels deep"
    )
    H.eq(
      config.get().render_opts.terminal_size_ratio.width,
      0.9,
      "the rejected leaf falls back to its default"
    )
    H.eq(
      config.get().render_opts.terminal_size_ratio.height,
      0.5,
      "its valid sibling two levels down is still applied"
    )

    -- ERR-22: a value of the right type but out of range degrades to the
    -- default rather than reaching renderers/terminal.lua, where it would
    -- otherwise crash `vim.o.columns * size_ratio.width` asynchronously,
    -- outside any pcall.
    config.setup({
      render_opts = {
        terminal_dpi = -5,
        terminal_size_ratio = { width = "bad", height = 0.8 },
      },
    })
    local value_issues = config.issues()
    H.eq(#value_issues, 2, "one issue per invalid value")
    H.ok(
      H.index_of(
        value_issues,
        "option 'render_opts.terminal_dpi' must be a positive number -- using the default"
      ) ~= nil,
      "a negative terminal_dpi is rejected, not just a wrong type"
    )
    H.ok(
      H.index_of(
        value_issues,
        "option 'render_opts.terminal_size_ratio.width' must be a number in (0, 1] "
          .. "-- using the default"
      ) ~= nil,
      "a wrong-typed terminal_size_ratio.width is rejected"
    )
    H.eq(config.get().render_opts.terminal_dpi, 216, "terminal_dpi falls back to its default")
    H.eq(
      config.get().render_opts.terminal_size_ratio.width,
      0.9,
      "terminal_size_ratio.width falls back to its default"
    )
    H.eq(
      config.get().render_opts.terminal_size_ratio.height,
      0.8,
      "its valid sibling is still applied"
    )

    config.setup({ default_backend = "marker" })
    H.eq(#config.issues(), 0, "a clean setup() reports no issues again")
  end

  -- --------------------------------------------------------------- notify

  do
    local emitted
    H.with_modules({
      ["lib.nvim.notify"] = {
        create = function(prefix)
          return {
            info = function(msg)
              emitted = { level = "info", prefix = prefix, msg = msg }
            end,
            warn = function(msg)
              emitted = { level = "warn", prefix = prefix, msg = msg }
            end,
            error = function(msg)
              emitted = { level = "error", prefix = prefix, msg = msg }
            end,
            debug = function(msg)
              emitted = { level = "debug", prefix = prefix, msg = msg }
            end,
          }
        end,
      },
      ["pdfport.util.notify"] = H.UNLOAD,
    }, function()
      local notifier = require("pdfport.util.notify").create("[pdfport.spec]")

      notifier.info("hello")
      H.eq(emitted.level, "info", "info delegates to lib.nvim.notify")
      H.eq(emitted.prefix, "[pdfport.spec]", "carrying the prefix it was created with")
      H.eq(emitted.msg, "hello", "and the message unchanged")

      notifier.warn("careful")
      H.eq(emitted.level, "warn", "warn delegates too")
      notifier.error("broken")
      H.eq(emitted.level, "error", "as does error")

      -- debug is the one method that is NOT a straight delegation: lib.nvim's
      -- own debug() always emits, and this one is gated on the plugin's own
      -- config flag so a default install stays silent.
      emitted = nil
      notifier.debug("quiet", { debug = false })
      H.eq(emitted, nil, "debug is silent when cfg.debug is false")
      notifier.debug("quiet", nil)
      H.eq(emitted, nil, "and when there is no config at all")
      notifier.debug("loud", { debug = true })
      H.eq(emitted.level, "debug", "but emits once cfg.debug is set")
      H.eq(emitted.msg, "loud", "with the message")
    end)
  end

  -- ----------------------------------------------------------- spawn_env

  do
    local applied
    H.with_modules({
      ["lib.nvim.cross.run.env"] = {
        array = function()
          return { "PATH=/usr/bin", "HOME=/home/x" }
        end,
        apply = function(opts)
          applied = opts
          return { text = opts and opts.text, env = { PATH = "/usr/bin" } }
        end,
      },
      ["pdfport.util.spawn_env"] = H.UNLOAD,
    }, function()
      local spawn_env = require("pdfport.util.spawn_env")

      -- The two shapes exist because the two runners want different ones:
      -- libuv's spawn takes an array of "KEY=VALUE", vim.system takes a dict.
      local array = spawn_env.array()
      H.eq_list(array, { "PATH=/usr/bin", "HOME=/home/x" }, "array() is libuv's KEY=VALUE shape")

      local opts = spawn_env.opts({ text = true })
      H.eq(opts.text, true, "opts() keeps the caller's own spawn options")
      H.eq(type(opts.env), "table", "and folds a completed env in")
      H.eq(applied.text, true, "the caller's options are what gets handed to lib.nvim")

      H.eq(type(spawn_env.opts()), "table", "opts() works with no arguments at all")
      H.eq(applied, nil, "passing nil through unchanged rather than inventing a table")
    end)
  end

  -- ------------------------------------------------------------ platform

  do
    ---Load `pdfport.platform` against a chosen OS and executable set.
    ---@param os_flags table<string, boolean>  is_windows/is_macos/is_linux/is_wsl
    ---@param present table<string, boolean>
    ---@param fn fun(platform: table)
    local function with_platform(os_flags, present, fn)
      H.with_modules({
        ["lib.nvim.cross.platform.is_windows"] = function()
          return os_flags.windows == true
        end,
        ["lib.nvim.cross.platform.is_macos"] = function()
          return os_flags.macos == true
        end,
        ["lib.nvim.cross.platform.is_linux"] = function()
          return os_flags.linux == true
        end,
        ["lib.nvim.cross.platform.is_wsl"] = function()
          return os_flags.wsl == true
        end,
        ["lib.nvim.core"] = {
          has_exec = function(exe)
            return present[exe] == true
          end,
          first_available = function(list)
            for _, exe in ipairs(list) do
              if present[exe] == true then return exe end
            end
            return nil
          end,
        },
        ["pdfport.platform"] = H.UNLOAD,
      }, function()
        fn(require("pdfport.platform"))
      end)
    end

    with_platform({ windows = true }, { ["explorer.exe"] = true }, function(platform)
      H.eq(platform.os(), "windows", "Windows is detected")
      H.falsy(platform.is_wsl(), "and is not WSL")
      -- Never a bare `start`: that is a cmd.exe built-in, not something
      -- libuv or jobstart can spawn without a shell.
      H.eq(platform.open_cmd(), "explorer.exe", "the OS opener on Windows is explorer.exe")
    end)

    with_platform({ macos = true }, {}, function(platform)
      H.eq(platform.os(), "macos", "macOS is detected")
      H.eq(platform.open_cmd(), "open", "whose OS opener is `open`")
    end)

    with_platform({ linux = true }, { ["xdg-open"] = true }, function(platform)
      H.eq(platform.os(), "linux", "Linux is detected")
      H.eq(platform.open_cmd(), "xdg-open", "with xdg-open as the opener")
    end)

    -- WSL reports as Linux for tool purposes but must still answer is_wsl(),
    -- which is what picks wsl-open over xdg-open.
    with_platform({ wsl = true }, { ["wsl-open"] = true }, function(platform)
      H.eq(platform.os(), "linux", "WSL counts as linux for tool detection")
      H.ok(platform.is_wsl(), "while still reporting itself as WSL")
      H.eq(platform.open_cmd(), "wsl-open", "and falls through to wsl-open")
    end)

    with_platform({}, {}, function(platform)
      H.eq(platform.os(), "unknown", "an OS none of the probes recognise is `unknown`")
      H.eq(platform.open_cmd(), nil, "with no opener to name")
    end)

    with_platform({ linux = true }, { pdftotext = true, python3 = true }, function(platform)
      H.ok(platform.has("pdftotext"), "has() delegates to lib.nvim.core's memoized probe")
      H.falsy(platform.has("definitely-not-installed"), "and reports a missing binary as false")
      H.eq(
        platform.first_available({ "nope", "python3", "pdftotext" }),
        "python3",
        "first_available returns the earliest match in the caller's own order"
      )
      H.eq(platform.first_available({ "nope" }), nil, "and nil when none of them is there")

      H.eq(platform.python(), "python3", "python() resolves an interpreter")
      H.eq(platform.python(), "python3", "and is stable across calls (it memoizes)")
    end)

    with_platform({ linux = true }, {}, function(platform)
      H.eq(platform.python(), nil, "python() is nil when no interpreter is installed")
      H.falsy(platform.has_python_module("pdfplumber"), "and every python module is then absent")
      H.falsy(platform.has_python_module("pdfplumber"), "cached, so the second call is free")
      platform.reset_cache()
      H.falsy(platform.has_python_module("docling"), "reset_cache() clears the module cache")
    end)

    -- The terminal-image tool: kitty only when the terminal really is kitty
    -- (its `icat` protocol is not something another terminal understands),
    -- then imgcat, then chafa as the universal fallback.
    do
      local saved_term, saved_prog = vim.env.TERM, vim.env.TERM_PROGRAM
      vim.env.TERM = "xterm-kitty"
      vim.env.TERM_PROGRAM = nil
      with_platform({ linux = true }, { kitten = true, chafa = true }, function(platform)
        H.eq(platform.best_terminal_renderer(), "kitty", "inside kitty, kitty's own icat wins")
      end)
      with_platform({ linux = true }, { chafa = true, imgcat = true }, function(platform)
        H.eq(
          platform.best_terminal_renderer(),
          "imgcat",
          "inside kitty but without the kitten binary, imgcat is preferred over chafa"
        )
      end)
      vim.env.TERM = "xterm-256color"
      with_platform({ linux = true }, { kitten = true, chafa = true }, function(platform)
        H.eq(
          platform.best_terminal_renderer(),
          "chafa",
          "outside kitty the kitten binary is not used, even when installed"
        )
      end)
      with_platform({ linux = true }, {}, function(platform)
        H.eq(platform.best_terminal_renderer(), nil, "and with no tool at all there is no renderer")
      end)
      vim.env.TERM, vim.env.TERM_PROGRAM = saved_term, saved_prog
    end
  end

  -- Leave the plugin in the state the remaining specs expect: setup() again
  -- so resolver/dispatcher/composer hold the real default config rather than
  -- whatever the config section above left in place.
  require("pdfport").setup({})
end
