# pdfport.nvim documentation

What is here, and which question each page answers. [The README](../README.md)
is the short version of all of it.

## Getting it running

| Page | Answers |
| --- | --- |
| [requirements.md](requirements.md) | This plugin's job is to drive external tools, so this is the interesting part — required and optional, one row per tool |
| [installation.md](installation.md) | A spec per plugin manager |
| [quickstart.md](quickstart.md) | The first thing to run after installing |
| [what-you-get.md](what-you-get.md) | The full command/API surface at a glance |
| [configuration.md](configuration.md) | Every option `setup()` takes |
| [health.md](health.md) | The ten `:checkhealth pdfport` sections, and which findings are actually problems |

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

## Working on it

| Page | Answers |
| --- | --- |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Ground rules, project layout, and how to add a backend, a producer or a file-tree adapter |

## Here, but not prose

**`install.json`** declares the external tools this plugin can use,
machine-readably, for `:Lib deps show pdfport.nvim`. What each tool is *for*
is in [installation.md](installation.md) and
[FEATURES/BACKENDS.md](FEATURES/BACKENDS.md).
