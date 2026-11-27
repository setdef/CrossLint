# Configuration reference

A project's configuration is `.config/crosslint/config.kdl` in its root, in [KDL](https://kdl.dev/). It lists the plugins CrossLint runs, and settings for their policies. `crosslint init` writes one with the recommended plugins; this page lists everything it can hold.

An Angular project that tracks debt and keeps one local plugin might have:

<!--
SPDX-SnippetBegin
SPDX-License-Identifier: MIT-0
SPDX-SnippetCopyrightText: 2026 setdef
-->
```kdl
plugin "angular" {
  src-dir "src"
}
plugin "debt" {
  report-entries commented="warning"
}
plugin ".config/crosslint/signatures"

policy "angular/prefer-css-over-scss" severity="error"
policy "signatures/has-test" enabled=#false

warnings "all"
```
<!-- SPDX-SnippetEnd -->

CrossLint finds the configuration by looking in the current folder and then in each folder above it, or from `-C`'s folder. A project with no configuration, or one that lists no plugin, stops CrossLint with exit status 2, since no check would run. Any node or property this page doesn't list stops CrossLint the same way, with the nearest valid spelling where one is close.

## `plugin`

`plugin NAME { ... }` runs a plugin. List each plugin once. No plugin runs unless the configuration lists it, the built-in ones included.

- A name that starts with `.` or `/` is a local plugin: the folder at that path, relative to the project's root, with a `plugin.kdl` in it ([plugin reference](plugin.md)).
- A name that starts with `https://` is a shared plugin: a Git repository, at the tag or full commit SHA its `ref` property gives, such as `plugin "https://github.com/OWNER/REPO" ref="v1.2.0"`. A branch is refused, so a plugin's version changes only when the configuration does. The plugin's name is the repository's name, the URL's last segment without `.git`, and its `plugin.kdl` is at the repository's root. A `path` property lists the plugin from a folder of the repository instead, such as `plugin "https://github.com/OWNER/REPO" ref="v1.2.0" path="plugins/links"`: its `plugin.kdl` is in that folder, and its name is the folder's last part. `path` is relative to the repository's root, with `/` between folders, and an absolute path, a `..`, a `\`, a drive letter, an empty path, and a folder with no `plugin.kdl` at that commit are mistakes, with exit status 2. Folders of one repository at one ref are fetched once, and `crosslint update` moves the `ref` and keeps `path`. The first time `crosslint check` needs a shared plugin, it prints a line on standard error, fetches that commit into the user's cache (`$XDG_CACHE_HOME/crosslint/plugins`, or `~/.cache/crosslint/plugins`, or `%LOCALAPPDATA%\crosslint\cache\plugins` on Windows), and uses that copy from then on. `crosslint update` moves each shared plugin whose `ref` is a plain version tag to the newest version tag that is compatible with it, and lists on standard error the newer versions that aren't; `crosslint update --latest` moves to the highest version tag, whatever its major version. It leaves other refs alone. A URL with a user name or password is refused; give Git the credentials with a Git credential helper.

  > **Warning:** a shared plugin's Ruby and helpers run with your rights, and CrossLint doesn't sandbox them. List only a plugin you would run as a script, at a ref you have read.
- Any other name is a built-in plugin: `angular` or `debt`.

The block holds the settings the plugin's `plugin.kdl` declares, and can be left out when there are none. A setting the plugin doesn't declare stops CrossLint with exit status 2, naming it.

### `angular`

ng-nudge's checks for Angular projects: a spec for every component, directive, pipe, service, guard, resolver, and interceptor; a stub and an interface for a component that has either, with the same inputs and outputs as the component; and a warning for a `.scss` stylesheet with no `.css`. It reads TypeScript with a helper that runs on [Node](https://nodejs.org/), with the ts-morph the plugin carries, which reads TypeScript 6.0. Its six policies have the names of ng-nudge's rules: `spec-exists`, `stub-exists`, `interface-exists`, `stub-matches-component`, `interface-matches-component`, and `prefer-css-over-scss`. It compares a component's inputs and outputs with its stub's and its interface's by their public names, aliases included, and reads TypeScript only for a component that has a stub or an interface. Its words, such as stub and base path, are in [its glossary](../../plugins/angular/glossary.md).

| Setting | Meaning | Default |
| --- | --- | --- |
| `src-dir PATH` | The folder the plugin's artifacts are found in, relative to the project's root. A file or folder below it whose name starts with `.` is skipped, as ng-nudge skips them. | `src` |
| `tsconfig PATH` | The `tsconfig.json` the helper reads, relative to the project's root, once a component has a stub or an interface. | `tsconfig.json` |
| `role NAME files=PATTERN { expects PIECE ... }` | Find a role's files by this [path pattern](plugin.md#artifact), which ends in `.ts`, relative to `src-dir`, in place of `{path}.NAME.ts`; for a role the plugin doesn't have, add it. Each piece is at the primary piece's path with `.ts` replaced, such as `.spec.ts`. `expects` takes only `spec`; without a block, the role expects a spec. | |

### `debt`

Debt tracking: violations listed in the debt file don't fail the check, and an entry no violation matches does, because its debt is paid off. Its words, such as entry and paid-off entry, are in [its glossary](../../plugins/debt/glossary.md).

| Setting | Meaning | Default |
| --- | --- | --- |
| `file PATH` | The debt file, relative to the project's root. | `.config/crosslint/debt.tsv` |
| `report-entries commented=SEVERITY matching=REGEX` | Also report each entry as a finding on the debt file, `line N lists PLUGIN/POLICY on ARTIFACT as debt: COMMENT`, from the policy `debt/has-debt`: an entry with a comment at `commented` (`error`, `warning`, or `none`; without it, the policy's severity), and one without at the policy's severity. With `matching`, only a comment the regular expression matches counts as one. | entries aren't reported |

The debt file is tab-separated, in ng-nudge's format, so a file moved from ng-nudge reads unchanged: a header row `Rule`, `Artifact`, `Comment`, and an optional fourth column `Detail`, then one entry per line. `Rule` is `PLUGIN/POLICY`, or a bare policy name, which stands for the policy of that name when exactly one listed plugin has one. `Artifact` is the artifact's name, which is its primary path unless its declaration has a [`name`](plugin.md#artifact), or its [key](plugin-glossary.md#declaring), such as ng-nudge's base path `app/card/card`, alone or as `NAME.ROLE`. A field holding a tab, a newline, or `"` is wrapped in `"`, with each `"` doubled. Paths are written with `/` on every system, a path read with `\` is read as `/`, and the file keeps the line endings it had. An entry with no rule or no artifact stops CrossLint with exit status 2, naming the file and the line.

An entry for a plugin the configuration doesn't list, for a disabled policy, or for a plugin that stopped at a fault is kept as it is. The check doesn't count it as paid off, which would fail the check, and `report-entries` doesn't report it. `crosslint debt update` keeps it with its comment.

The debt plugin adds one command:

| Command | What it does |
| --- | --- |
| `crosslint debt update` | Runs the check, then rewrites the debt file to list exactly the current violations: keeps each entry that still matches, with its comment, drops paid-off entries, and adds one entry with an empty comment for each new violation, warnings included. Then reports the state the update left, and exits with 0. It takes the global flags, such as `-C`, and `-n`/`--dry-run`, which lists each entry it would add, remove, or replace, and the summary, writes nothing, and exits with 0. |

## `policy`

`policy PLUGIN/POLICY ...` changes one listed plugin's policy, with these properties:

| Property | Meaning |
| --- | --- |
| `enabled=#false` | Don't run the policy. Its entries in the debt file are kept. They aren't paid-off entries, which would fail the check, and `report-entries` doesn't report them. |
| `severity="error"` or `severity="warning"` | Report the policy's violations at this severity, in place of what its plugin declares. |

A policy that no listed plugin has stops CrossLint with exit status 2.

## `warnings` and `verbosity`

`warnings MODE` sets the default for `crosslint check --warnings`: `all`, `none`, or `error`. `verbosity MODE` sets the default output: `normal`, `quiet` as for `--quiet`, or `silent` as for `--silent`. A flag on the command line wins over either.
