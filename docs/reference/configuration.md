# Configuration reference

A project's configuration is `.config/crosslint.kdl` in its root, in [KDL](https://kdl.dev/). It lists the plugins CrossLint runs, and settings for their policies. `crosslint init` writes one with the recommended plugins; this page lists everything it can hold.

An Angular project that tracks debt and keeps one local plugin might have:

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

CrossLint finds the configuration by looking in the current folder and then in each folder above it, or from `-C`'s folder. A project with no configuration, or one that lists no plugin, stops CrossLint with exit status 2, since no check would run. Any node or property this page doesn't list stops CrossLint the same way, with the nearest valid spelling where one is close.

## `plugin`

`plugin NAME { ... }` runs a plugin. List each plugin once. No plugin runs unless the configuration lists it, the built-in ones included.

- A name that starts with `.` or `/` is a local plugin: the folder at that path, relative to the project's root, with a `plugin.kdl` in it ([plugin reference](plugin.md)).
- A name that starts with `https://` is a shared plugin: a Git repository, at the tag or full commit SHA its `ref` property gives, such as `plugin "https://github.com/OWNER/REPO" ref="v1.2.0"`. A branch is refused, so a plugin's version changes only when the configuration does. The first time `crosslint check` needs a shared plugin, it prints a line on standard error, fetches it into the user's cache, and uses that copy from then on. `crosslint update` moves each shared plugin's `ref` to its newest tag.
- Any other name is a built-in plugin: `angular` or `debt`.

The block holds the plugin's settings, and can be left out when there are none.

### `angular`

ng-nudge's checks for Angular projects: a spec for every component, directive, pipe, service, guard, resolver, and interceptor; a stub and an interface for a component that has either, with the same inputs and outputs as the component; and a warning for a `.scss` stylesheet with no `.css`. It reads TypeScript with a helper that runs on [Node](https://nodejs.org/) and the project's `typescript` package. Its policies have the names of ng-nudge's rules: `spec-exists`, `stub-exists`, `interface-exists`, `stub-matches-component`, `interface-matches-component`, and `prefer-css-over-scss`.

| Setting | Meaning | Default |
| --- | --- | --- |
| `src-dir PATH` | The folder the plugin's artifacts are found in, relative to the project's root. | `src` |
| `tsconfig PATH` | The `tsconfig.json` its TypeScript checks read. | `tsconfig.json` |
| `role NAME files=PATTERN { expects COMPANION ... }` | Find a role's files by this [path pattern](plugin.md#artifact), relative to `src-dir`, in place of `{path}.NAME.ts`; for a role the plugin doesn't have, add it. `expects` lists the companions the role must have, such as `spec`. | |

### `debt`

Debt tracking: violations listed in the debt file don't fail the check, and an entry no violation matches does.

| Setting | Meaning | Default |
| --- | --- | --- |
| `file PATH` | The debt file, relative to the project's root. | `.config/crosslint/debt.tsv` |
| `report-entries commented=SEVERITY matching=REGEX` | Also report each entry as a violation of `debt/has-debt`: an entry with a comment at `commented` (`error`, `warning`, or `none`), and one without at the policy's severity. With `matching`, only a comment the regular expression matches counts as one. | entries aren't reported |

## `policy`

`policy PLUGIN/POLICY ...` changes one listed plugin's policy, with these properties:

| Property | Meaning |
| --- | --- |
| `enabled=#false` | Don't run the policy. Its entries in the debt file are kept, and are neither stale nor reported. |
| `severity="error"` or `severity="warning"` | Report the policy's violations at this severity, in place of what its plugin declares. |

A policy that no listed plugin has stops CrossLint with exit status 2.

## `warnings` and `verbosity`

`warnings MODE` sets the default for `crosslint check --warnings`: `all`, `none`, or `error`. `verbosity MODE` sets the default output: `normal`, `quiet` as for `--quiet`, or `silent` as for `--silent`. A flag on the command line wins over either.
