# AGENTS.md

These rules are for everyone who works on this repository, people and their agents alike.

## What CrossLint is

CrossLint catches what a linter should be able to catch but can't, because ESLint, RuboCop and others like them look at one file at a time. For example: every file has a corresponding test or spec file, or every Ruby file has an RBS declaration at the matching path under `sig/`. The work, and the questions still open, are in this repository's issues.

## How work lands

CrossLint uses trunk-based development. The trunk is `trunk`.

- Commit straight to `trunk`. Open no long-lived branches and no pull requests.
- Make each commit one change that is complete and releasable. Hide a change that needs several commits behind a flag, or build it by branch by abstraction, so each push is safe to release.
- Before you push, run the checks that apply to your change. `reuse lint` must pass.
- Fetch and rebase onto `origin/trunk` before you push. When the push is refused because the trunk moved, rebase, run the checks again, and push again, every time.
- After you push, wait for nothing: start the next change.
- When a commit turns the trunk red, revert it at once, whoever wrote it, and tell its author. Land the fix again when it is ready.

## Licensing

CrossLint is MIT-licensed, copyright setdef. `LICENSE` has the text, and `REUSE.toml` gives every file its copyright and license, following the [REUSE specification](https://reuse.software/spec/).

Code and prose derived from ng-nudge (MIT, Copyright 2026 Over The Top Marketing) keep its notice. Credit them with SPDX headers and snippets, the way [setdef/Tokra](https://github.com/setdef/Tokra) credits Tauri: wrap each derived passage in `SPDX-SnippetBegin` and `SPDX-SnippetEnd`, and give it the original copyright holder and license in `SPDX-SnippetCopyrightText` and `SPDX-License-Identifier`. Add the text of each new license to `LICENSES/` with `reuse download`.

## Releases

Releases happen on GitHub, freely: cut tags and GitHub releases whenever the trunk is ready. Every version is `0.X.Y`, three plain integers. Use no prerelease form (no `-rc.1`, no `.pre.`), and no `1.0.0` or higher until the maintainer says so.

Publish nothing to a registry outside GitHub (npm, RubyGems, mise's registry, or any other) until the maintainer approves it.
