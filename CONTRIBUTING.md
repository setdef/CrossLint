# Contributing to CrossLint

## Writing things down

Record each thing where the next contributor will find it, in its one home, and nowhere else. What lives only in a chat, or on one machine, is lost.

| What | As it is | As it will be |
| --- | --- | --- |
| Requirements: what CrossLint does for its users | The README and the pages of `docs/` outside `docs/design/` | Issues |
| Contract: what a caller can rely on | Doc comments, in the RBS signatures under `sig/` | Issues |
| Architecture: the few decisions the structure rests on | Accepted ADRs in [`docs/decisions/`](docs/decisions/) | Proposed ADRs there |
| Design: how each part works, and why | The design documents in [`docs/design/`](docs/design/README.md) | Nowhere |
| Behavior: what the code does | Tests, under `test/` and each built-in plugin's `test/` | Nowhere |
| Facts that constrain the design | The design document or ADR they constrain; until that exists, the issue whose work they constrain | Nowhere |

- **Decide a design at the last responsible moment,** while building it, with the facts in hand, then record it as it is. Never write a design, or a behavior, ahead of the code, in an issue or anywhere else.
- **A design document explains a part to the people who change it:** its concepts, how its pieces fit, why it is shaped this way, its traps, and what it deliberately doesn't do. It doesn't restate the code: no fields, option lists, step-by-step restatements, exact messages, or private call graphs.
- **Change a design document when a design decision changes,** never because behavior did. The two change independently.
- **A doc comment describes the contract from the caller's side,** never how the code does the work inside.
- **Check a fact at its source before anything rests on it,** on the system it's about. A decision that rests on an unchecked fact waits.
- **Record a fact found before its design exists as a fact, not a decision:** what was tried or checked, how, on which system and version, and the result. It waits in the issue whose work it constrains, and moves to the design document or ADR once that is decided.
- **An issue may hold a proposed or an accepted requirement or contract,** and one that doesn't say which is neither accepted nor refused.
- **The README was written ahead of the code, as CrossLint's requirements.** The rest of the user documentation describes only what CrossLint does today.

Use [the glossary](docs/glossary.md)'s words, in code as in prose; a new idea gets a glossary entry before it gets a name. To change an architecture decision, write a new record with the next number and delete the old one.

The command reference, [`docs/reference/cli.md`](docs/reference/cli.md), is generated from [`crosslint.usage.kdl`](crosslint.usage.kdl). After changing the spec, check it and regenerate the reference in the same commit:

```console
$ usage lint crosslint.usage.kdl
$ usage generate markdown --file crosslint.usage.kdl --out-file docs/reference/cli.md
```

Every public class, module, method, and constant has a doc comment in its RBS signature under `sig/`, in Markdown. A `.rb` file has a comment only where the code needs a reason: why it's written this way, or what makes it tricky.

## Checks

After `bundle install`, run `bundle exec rake fixtures` once: it installs the packages the Angular plugin's test fixtures lock, with `npm ci`, using the Node that `mise.toml` pins. No test task runs it, and a test whose fixture lacks them fails saying to run it. `bundle exec rake check` runs every check; the Rakefile says which. Before a push, run `bundle exec rake gate`, which runs `rake check`, in about a minute, on any system. CI runs it again after the push, in two tiers: `fast.yml` judges each push on Linux, and `ci.yml` runs in batches, one run at a time on `trunk`, with the tests on macOS and Windows.

The tests cover every line and branch of `lib/` and of each built-in plugin's Ruby, but the other system's process tree. Mutation testing is off until Stryker (for Ruby) can run it (#23). Write each test as if it still ran: see each new test fail on the code without the change before it passes; give each branch and each boundary a test that fails when the branch is removed or the boundary moves by one; and assert the exact value, message, or exit status, not only that something happened.

## Landing a change

Commit straight to `trunk`, one change at a time, each one complete and releasable. A spike, an experiment written to answer a question, is throwaway code and stays off `trunk`; its answer goes in the issue it serves. Run `rake gate` before you push, and rebase and run it again when a push is refused because `trunk` moved.

When a run of `fast.yml` or `ci.yml` on `trunk` fails, `trunk` is red: revert the commit that broke it at once, whoever wrote it, and tell its author in the issue the commit names; the fix lands again afterwards, with a test. Nobody fixes forward on a red `trunk`.

### Known flaky tests

A test that fails without a change to what it tests is a fault in the test, fixed or set aside with its reason recorded here, never rerun until it passes. Running it again never closes it.

## Licensing

CrossLint is MIT-licensed, copyright setdef. [`REUSE.toml`](REUSE.toml) declares the copyright and license of every file, following the [REUSE specification](https://reuse.software/spec/), and `reuse lint` must pass.

A file under a permissive license carries no SPDX header; `REUSE.toml` covers it. A file under a copyleft or share-alike license carries an SPDX header naming its license, and the license's text goes in `LICENSES/`.

Code or prose taken from [ng-nudge](https://github.com/OverTheTopMarketing/ng-nudge) (MIT, Copyright 2026 Over The Top Marketing) keeps its notice: wrap each passage in `SPDX-SnippetBegin` and `SPDX-SnippetEnd`, with `SPDX-SnippetCopyrightText` and `SPDX-License-Identifier` naming its copyright holder and license, the way [setdef/Tokra](https://github.com/setdef/Tokra) credits Tauri.

## Releases

Releases are tags and GitHub releases, cut whenever `trunk` is ready. To cut one, tag a commit at the head of a passing run of `ci.yml` as `v` and the version in `crosslint.usage.kdl`, such as `v0.1.0`, and push the tag: the Release workflow builds each platform's archive from a clean checkout, runs each with no Ruby to fall back on (on Linux in a container with no Ruby, and on macOS and Windows with an empty `PATH`), and publishes the archives with a `SHA256SUMS` file. It refuses a tag that doesn't match the spec's version, and a tag whose commit isn't the head of a passing run of `ci.yml` from a push to `trunk`. A tag pushed before that run passes fails its Release run; rerun the Release run once it has passed. Every version is `0.X.Y`, three plain integers, with no prerelease form such as `-rc.1` and no build metadata, and the version stays below 1.0.0. Nothing is published to a registry outside GitHub.
