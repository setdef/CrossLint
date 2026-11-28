# agents-md

A shared plugin for CrossLint that checks that every `AGENTS.md` in a project has a `CLAUDE.md` beside it whose first line is `@AGENTS.md`. Claude Code reads `CLAUDE.md`, and reads that line as an import of the `AGENTS.md` in the same folder, so Claude Code follows the same instructions as the agents that read `AGENTS.md`.

## Listing it

List it in `.config/crosslint/config.kdl` from its folder of the CrossLint repository:

<!--
SPDX-SnippetBegin
SPDX-License-Identifier: MIT-0
SPDX-SnippetCopyrightText: 2026 setdef
-->
```kdl
plugin "https://github.com/setdef/CrossLint" ref="TAG" path="plugins/agents-md"
```
<!-- SPDX-SnippetEnd -->

`TAG` is a tag of CrossLint that has this folder. The plugin takes no settings. It runs on the Ruby CrossLint carries, so it needs nothing installed beside CrossLint, whatever the project's language.

## What it checks

Each `AGENTS.md` is the primary piece of an artifact whose piece `claude` is the `CLAUDE.md` in its folder: the `AGENTS.md` at the project's root of an `agents-md` artifact, and each `AGENTS.md` in a folder of a `nested-agents-md` artifact. The plugin's policies apply to both:

| Policy | Reports |
| --- | --- |
| `agents-md/claude-md-exists` | An `AGENTS.md` with no `CLAUDE.md` in its folder. The name is matched exactly, so a `claude.md` doesn't count. |
| `agents-md/claude-md-imports-agents-md` | A `CLAUDE.md` whose first line isn't `@AGENTS.md`. A byte order mark before the line, and spaces, tabs, or a CRLF line ending after it, are ignored. |

A `CLAUDE.md` that is a symbolic link to its `AGENTS.md` is read as that `AGENTS.md`, so its first line is the `AGENTS.md`'s first line, and `claude-md-imports-agents-md` reports it. Files Git ignores are never checked. A project with no `AGENTS.md` anywhere gets CrossLint's warning that no file matches the plugin's artifacts.
