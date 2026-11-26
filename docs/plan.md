# Plan

This file is a seed, and it is meant to disappear. It holds what was settled before the first commit. The work itself is in this repository's issues. As each line below gets its lasting home, delete it here. When nothing is left, delete the file: #3 tracks that.

CrossLint catches what a linter should be able to catch but can't, because ESLint, RuboCop and others like them look at one file at a time. For example: every file has a corresponding test or spec file; every Angular component has an HTML template beside it; every Ruby file has an RBS declaration at the matching path under `sig/`.

Its one predecessor is [ng-nudge](https://github.com/OverTheTopMarketing/ng-nudge) (MIT, Copyright 2026 Over The Top Marketing), which does this for Angular only. ng-nudge bundles three things that should be separable: its engine, its Angular part, and its technical-debt tracking.

## Settled

- **None of ng-nudge's value is lost,** and none of its bugs are kept. How its output looks is free to change.
- **A project that uses ng-nudge can replace it with CrossLint in 30 minutes or less,** as a drop-in or close to one.
- **The engine, the Angular part and the debt tracking are separable.** A project that uses neither Angular nor debt tracking can still use CrossLint.
- **Three kinds of thing, always together: artifacts, policies and rules.** An artifact is a set of files that belong together, such as a component with its template, its test and its stub, and it knows where each of those files should be. A policy decides when rules apply. A rule performs one check. These are ng-nudge's terms and they keep their meaning.
- **A plugin supplies any number of artifacts, policies and rules.**
- **The people who own a project can always write their own artifacts, policies and rules for it.**
- **Whether one CrossLint can serve every language is open,** and the maintainer decides it: see #1. If it can, CrossLint is written in Ruby.
- **The name implies no language.** Its predecessor is JavaScript, and that is not a reason for CrossLint to be. The command and package names are chosen once the language is.
- **Everything derived from ng-nudge keeps its notice,** credited by the REUSE specification with SPDX headers and snippets, the way [setdef/Tokra](https://github.com/setdef/Tokra) credits Tauri.
- **Its first user** is [Kerrick/opinionated-databricks-appkit-template](https://github.com/Kerrick/opinionated-databricks-appkit-template), which is not an Angular project.
- **Releases happen on GitHub, freely:** tags and GitHub releases are cut whenever the trunk is ready. Versions are `0.X.Y` only, three plain integers: no prerelease form (no `-rc.1`, no `.pre.`), and no `1.0.0` or higher until the maintainer says so. Nothing goes to a registry outside GitHub (npm, RubyGems, mise's registry, or any other) until the maintainer approves it.

Nothing else is settled.
