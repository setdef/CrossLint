# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `crosslint update --latest` moves each shared plugin to the highest version tag of its repository, even when that version isn't compatible with the plugin's ref.
- A `primary` line in `plugin.kdl` takes `regex=REGEX`: each match in a file the pattern finds is an artifact, on the line where the match starts. The regex's named captures are placeholders for the artifact's name, its pieces' paths, and its pieces' regexes.
- A `piece` line takes `regex=REGEX`: the piece is a part of its file, such as a `<style>` block, and exists when the regex has a match there. CrossLint refuses a regex that Ruby reads differently from PCRE or JavaScript, and says what to write instead.
- An `artifact` block takes `name PATTERN`, which gives each artifact of the role a name, such as `GET /cart`, in place of its primary piece's path. A violation and a debt entry use the name. Two artifacts of one role with one name are a fault.
- `rule NAME helper=HELPER` and `artifacts helper=HELPER` let a helper in any language run a rule and declare a plugin's artifacts.
- A helper's block takes `command "PROGRAM" "WORD" ...` for a program that needs words before its file, such as `bundle exec ruby`.
- `crosslint check` prints the line of an artifact found inside a file, and the artifact's name when it isn't its primary piece's path, before the message. `--json` adds a `line` key to each finding, which is a number or `null`.
- The artifact a Ruby rule gets has `primary`, its primary piece, a piece like the others, with `name`, `path`, `exist?`, and `read`, and `artifact.piece("primary")` gives the same piece. `artifact.path` and `artifact.read` stay. `primary` is the name of the primary piece, so CrossLint stops with exit status 2 at a piece named `primary`, in a manifest or in the artifacts a helper declares.
- A configuration can start with the oldest CrossLint that reads it, written `crosslint min="1.2"`. An older CrossLint stops at that line with exit status 2, before it reads any other, names both versions, and says to upgrade.
- `crosslint check --json` prints the version of the CrossLint that wrote the object as its first key, `crosslint_version`, such as `"crosslint_version": "1.0.0"`.
- A program helper's request has `name` and `line` in its `artifact` object: the name CrossLint calls the artifact by, and the line its primary piece's regex matched at (`null` for a whole file).
- Each release file has a build provenance attestation, so `gh attestation verify` can check an archive or `SHA256SUMS` against this repository.

### Changed

- A violation of the built-in rules `piece-exists` and `piece-absent` has the name of the piece it checks as its detail, such as `test`, so `crosslint check --json` prints it as `"detail"`, and `crosslint debt update` writes one debt entry for each failing piece, where it wrote one entry for all of an artifact's. A debt entry written before has no detail, and still matches every such violation of its policy on its artifact, with a warning, until `crosslint debt update` rewrites it.
- **Breaking:** `crosslint check --json` prints `paid_off` in place of `stale`, both as the top-level key and inside `summary`. A script that reads either key has to read `paid_off`.
- The debt plugin calls an entry that no violation matches a paid-off entry, not a stale one. The text summary says "1 entry paid off", and the entry's message is "the debt entry at FILE:LINE is paid off, since no violation matches it; crosslint debt update removes it". The check still fails on such an entry, with exit status 1, until `crosslint debt update` removes it.
- **Breaking:** `crosslint update` moves a shared plugin only to the highest tag that is compatible with its ref, by the rule Cargo and npm use for Semantic Versioning: from X.Y.Z on, the same X; from 0.Y.Z on, the same 0.Y; and at 0.0.Z, no move. To move across an incompatible version, pass `--latest`. The line `crosslint update` writes for a plugin lists the tag of each newer incompatible version, lowest first, and the tag `--latest` moves to.
- **Breaking:** `plugin.kdl` uses the glossary's words for the parts of an artifact. Rename `files` to `primary` and `companion` to `piece`, the rules `companion-exists` and `companion-absent` to `piece-exists` and `piece-absent` with `piece=NAME`, and the condition `companion-exists` to `piece-exists`. A Ruby rule calls `artifact.piece(NAME)`, `CrossLint::Artifacts#artifact` takes `primary:` and `pieces:`, and a helper sends and receives `primary` and `pieces`.
- **Breaking:** `rule NAME ruby=FILE` and `artifacts ruby=FILE` are gone, and CrossLint stops with exit status 2 at either. Declare the file as `helper NAME command=(crosslint)"ruby" file=FILE`, and write `rule NAME helper=NAME` or `artifacts helper=NAME`. A helper on `(crosslint)"ruby"` runs on the Ruby CrossLint carries, and `command="ruby"` without the annotation is the project's Ruby.
- The warning that no file matches a role's `primary` pattern says `the primary pattern of role "doc"`, where it said `the files of artifact "doc"`. The warning that no file matches the pattern of any of a plugin's roles says `the primary pattern of any role of plugin NAME`, where it said `the files of any artifact of plugin NAME`.
- The Angular plugin reads TypeScript 6.0 with the ts-morph the plugin carries, so a project needs no `typescript` package. The plugin still needs [Node](https://nodejs.org/) on the `PATH`.

## [0.2.0] - 2026-11-26

### Added

- Four shared plugins in this repository's `plugins/` folder, each listed by the repository's URL, a tag, and its `path=`:
  - `markdown-links` checks that every relative link in a Markdown file resolves, anchors included.
  - `decision-log` checks that a decision log's index links to exactly the records in its folder, that no two records have one number, and that no Markdown file cites a record number that no record has.
  - `agents-md` checks that every `AGENTS.md` has a `CLAUDE.md` beside it whose first line is `@AGENTS.md`.
  - `page-features` checks that every page component of an app has a Gherkin feature file.
- A rule written in Ruby can call `project_files`, which lists every file Git lists for the project, tracked or not, except those Git ignores, and `read(PATH)`, which returns a file's text. `read` raises `Errno::ENOENT` for an absolute path, a path that leaves the project, and a file that links to somewhere outside the project.

## [0.1.0] - 2026-11-26

### Added

- `crosslint check` runs the plugins a project lists, prints each violation on a line of standard output, and exits with 0 when every check passes, 1 when a check fails, and 2 when CrossLint can't run. It takes `--warnings=all|none|error`, `--all`, and `--json`. `--quiet`, `--silent`, `--no-color`, `--debug`, and `-C DIR` work with every command.
- `crosslint init` writes `.config/crosslint/config.kdl` with the recommended plugins, and takes `--force` and `--dry-run`.
- `crosslint init --from-ng-nudge` moves a project from ng-nudge 0.3.0: it writes the configuration from `.config/ng-nudge/rc.json`, moves the debt file to `.config/crosslint/debt.tsv`, and lists every change before it makes any.
- `crosslint update` moves each shared plugin to the highest version tag of its repository, and takes `--dry-run`.
- `crosslint help` explains one command or lists every command.
- Plugins declared in `plugin.kdl` as data: artifacts with `files` and `companion` lines, policies with `applies-to`, `when`, and `rule` lines, and the built-in rules `companion-exists` and `companion-absent`. A plugin can also carry rules written in Ruby, and helpers that run in another language.
- A project lists plugins in its configuration: local plugins by folder, shared plugins by a Git URL and a tag or commit, and the built-in `angular` and `debt` plugins.
- The Angular plugin carries ng-nudge's checks: a spec for each component, directive, pipe, service, guard, resolver, and interceptor, a stub and an interface that match their component's inputs and outputs, and a warning for a `.scss` stylesheet with no `.css`.
- The debt plugin excuses the violations that a project's debt file lists, and fails the check on an entry that no violation matches. `crosslint debt update` rewrites the debt file to match the current violations.
- Release archives of CrossLint for macOS on Apple silicon, Linux on x86-64, and Windows on x86-64, each with everything it needs, and a `SHA256SUMS` file.

[Unreleased]: https://github.com/setdef/CrossLint/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/setdef/CrossLint/releases/tag/v0.2.0
[0.1.0]: https://github.com/setdef/CrossLint/releases/tag/v0.1.0
