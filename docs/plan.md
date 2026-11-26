# Plan

This file is a seed, and it is meant to disappear. It holds what was settled before the first commit. The work itself is in this repository's issues. As each line below gets its lasting home, delete it here. When nothing is left, delete the file: #3 tracks that.

CrossLint catches what a linter should be able to catch but can't, because ESLint, RuboCop and others like them look at one file at a time. For example: every file has a corresponding test or spec file; every Angular component has an HTML template beside it; every Ruby file has an RBS declaration at the matching path under `sig/`.

## Settled

- **Whether one CrossLint can serve every language is open,** and the maintainer decides it: see #1. If it can, CrossLint is written in Ruby.
- **The name implies no language.** Its predecessor, [ng-nudge](https://github.com/OverTheTopMarketing/ng-nudge), is JavaScript, and that is not a reason for CrossLint to be. The command and package names are chosen once the language is.
- **Everything derived from ng-nudge (MIT, Copyright 2026 Over The Top Marketing) keeps its notice,** credited by the REUSE specification with SPDX headers and snippets, the way [setdef/Tokra](https://github.com/setdef/Tokra) credits Tauri.
- **Its first user** is [Kerrick/opinionated-databricks-appkit-template](https://github.com/Kerrick/opinionated-databricks-appkit-template), which is not an Angular project.
- **Releases happen on GitHub, freely:** tags and GitHub releases are cut whenever the trunk is ready. Versions are `0.X.Y` only, three plain integers: no prerelease form (no `-rc.1`, no `.pre.`), and no `1.0.0` or higher until the maintainer says so. Nothing goes to a registry outside GitHub (npm, RubyGems, mise's registry, or any other) until the maintainer approves it.

Nothing else is settled.
