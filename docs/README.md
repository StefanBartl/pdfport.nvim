# pdfport.nvim documentation

What is here, and which question each page answers. [The README](../README.md)
is the short version of all of it.

## Getting it running

| Page | Answers |
| --- | --- |
| [installation.md](installation.md) | What has to be there first — this plugin's job is to drive external tools, so the requirements are the interesting part — and a spec per plugin manager |
| [configuration.md](configuration.md) | Every option `setup()` takes |

## Using it

| Page | Answers |
| --- | --- |
| [commands.md](commands.md) | Every command and its arguments |
| [BINDINGS.md](BINDINGS.md) | Every keymap, user command and autocommand this plugin registers |
| [integrations.md](integrations.md) | Which other plugins reach this one and how — starting with the file trees |
| [WORKFLOW.md](WORKFLOW.md) | The different question: not what each command does, but how they combine once several backends and producers are available at once |

## Why it is the way it is

| Page | Answers |
| --- | --- |
| [FEATURES/](FEATURES/README.md) | One page per area — the core, rendering, the backends it can run on, the producers it can write, and the integrations |

## Here, but not prose

**`install.json`** declares the external tools this plugin can use,
machine-readably, for `:Lib deps show pdfport.nvim`. What each tool is *for*
is in [installation.md](installation.md) and
[FEATURES/BACKENDS.md](FEATURES/BACKENDS.md).
