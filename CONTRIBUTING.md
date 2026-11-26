# Contributing to CrossLint

## The documents are the specification

The README, [the glossary](docs/glossary.md), and [`crosslint.usage.kdl`](crosslint.usage.kdl) say what CrossLint does. When code and documents disagree, change the code, or change both in one commit and say why. Use the glossary's words, in code as in prose; a new idea gets a glossary entry before it gets a name.

The command reference, [`docs/reference/cli.md`](docs/reference/cli.md), is generated from `crosslint.usage.kdl`. After changing the spec, check it and regenerate the reference in the same commit:

```console
$ usage lint crosslint.usage.kdl
$ usage generate markdown --file crosslint.usage.kdl --out-file docs/reference/cli.md
```

What each part of CrossLint must guarantee is in [`docs/design/`](docs/design/README.md), and each requirement there becomes a test that fails when the requirement is broken. Architecture decisions are in [`docs/decisions/`](docs/decisions/). To change one, write a new record with the next number and delete the old one.

## Checks

After `bundle install`, run `bundle exec rake fixtures` once: it installs the packages the Angular plugin's test fixtures lock, with `npm ci`, using the Node that `mise.toml` pins. No test task runs it, and a test whose fixture lacks them fails saying to run it. Then `bundle exec rake check` runs every check CI runs, and CI runs it after every push to `trunk`:

- the test suite, covering every line and branch of `lib/` and of each built-in plugin's Ruby, but the other system's process tree (`job_object.rb` off Windows, `process_group.rb` on it), with each built-in plugin's tests in its folder under `plugins/`;
- the same suite under RBS's runtime type checker, which compares every call into CrossLint with `sig/`;
- mutation testing with mutant, of `lib/` and each built-in plugin's Ruby, `JobObject` aside, which a test must catch every change of; CI runs it in four parts at once, each as `MUTANT_SHARD=N/4 bundle exec rake mutant`, and `rake check:without_mutant` runs the rest;
- Steep, checking `lib/` against `sig/`, `rbs validate`, and the check that every public declaration in `sig/` has a comment;
- Standard, for style, set to Ruby 3.3's syntax, which mutant reads;
- every Ruby example in the documentation, run and checked against the results it shows;
- `usage lint`, the check that `docs/reference/cli.md` matches the spec, and `reuse lint`.

Before a push, run `bundle exec rake gate`, which takes about a minute. It runs every check in that list but full mutation testing, cheapest first, and then mutation testing of only part of the code:

- the subjects the change touches since `origin/trunk`, which the clone needs to have, or since the commit in `GATE_BASE`;
- the subjects each changed test file covers, by its path (`test/cross_lint/core/load_project_test.rb` covers `CrossLint::Core::LoadProject`, and a plugin's tests cover that plugin's Ruby);
- every subject, when a changed test file covers none by its path, so a change to such a test is never left unchecked.

It prints the base and how many subjects it chose, warns of a Ruby file Git doesn't track yet (the diff leaves it out), and refuses a base that is `HEAD` itself. Mutant forks a process for each mutation, so the gate refuses to run on Windows, where nothing forks, rather than skip its mutation testing.

Every public class, module, method, and constant is documented in its RBS signature under `sig/`, in Markdown. A `.rb` file has a comment only where the code needs a reason: why it's written this way, or what makes it tricky. How the code divides, and why, is in [Architecture](docs/design/architecture.md).

## Landing a change

Commit straight to `trunk`, one change at a time, each one complete and releasable. A spike, an experiment written to answer a question, is throwaway code and stays off `trunk`; its answer goes in the issue it serves. Run `rake gate` before you push, and rebase and run it again when a push is refused because `trunk` moved.

When CI on `trunk` fails, revert the commit that broke it at once, whoever wrote it, and tell its author in the issue the commit names; the fix lands again afterwards, with a test. Nobody fixes forward on a red `trunk`.

### Known flaky tests

A test that fails without a change to what it tests is a fault in the test, fixed or set aside with its reason recorded here, never rerun until it passes. Running it again never closes it.

## Licensing

CrossLint is MIT-licensed, copyright setdef. [`REUSE.toml`](REUSE.toml) declares the copyright and license of every file, following the [REUSE specification](https://reuse.software/spec/), and `reuse lint` must pass.

A file under a permissive license carries no SPDX header; `REUSE.toml` covers it. A file under a copyleft or share-alike license carries an SPDX header naming its license, and the license's text goes in `LICENSES/`.

Code or prose taken from [ng-nudge](https://github.com/OverTheTopMarketing/ng-nudge) (MIT, Copyright 2026 Over The Top Marketing) keeps its notice: wrap each passage in `SPDX-SnippetBegin` and `SPDX-SnippetEnd`, with `SPDX-SnippetCopyrightText` and `SPDX-License-Identifier` naming its copyright holder and license, the way [setdef/Tokra](https://github.com/setdef/Tokra) credits Tauri.

## Releases

Releases are tags and GitHub releases, cut whenever `trunk` is ready. To cut one, tag a commit CI passed as `v` and the version in `crosslint.usage.kdl`, such as `v0.1.0`, and push the tag: the Release workflow builds each platform's archive from a clean checkout, runs each with no Ruby to fall back on (on Linux in a container with no Ruby, and on macOS and Windows with an empty `PATH`), and publishes the archives with a `SHA256SUMS` file. It refuses a tag that doesn't match the spec's version, and a tag whose commit has no passing CI run from a push to `trunk`. A tag pushed before that run passes fails its Release run; rerun the Release run once CI has passed. Every version is `0.X.Y`, three plain integers, with no prerelease form such as `-rc.1` and no build metadata, and the version stays below 1.0.0. Nothing is published to a registry outside GitHub.
