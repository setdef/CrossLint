# Glossary for plugin authors

The words for writing a plugin, with the meaning each has in a `plugin.kdl` and in a plugin's Ruby. The words every user of CrossLint shares, such as artifact, piece, role, policy, and rule, are in [the glossary](../glossary.md); everything a `plugin.kdl` can hold is in [the plugin reference](plugin.md).

## Declaring

| Word | Meaning | Avoid |
| --- | --- | --- |
| **manifest** | A plugin's `plugin.kdl`, which declares its roles, policies, rules, helpers, settings, commands, and steps. CrossLint stops at any line it doesn't know. | plugin config, descriptor |
| **artifact declaration** | What a manifest says about one role: the path pattern that finds each artifact's primary piece, the pattern of each artifact's name, and the path pattern of each of its other pieces. Written `artifact ROLE { ... }`, or made by the helper on the `artifacts` line. | |
| **path pattern** | A path with placeholders in braces, such as `lib/{path}.rb`, matched case-sensitively with `/` on every system. CrossLint finds primary pieces with the pattern in `primary`; in another piece's pattern, each placeholder stands for what it matched there. | glob (a path pattern is not a glob) |
| **placeholder** | `{path}`, which matches a file name and the folders before it, or `{name}`, which matches one segment of a path. | variable, wildcard |
| **regex** | A regular expression on a piece, in Ruby's dialect, written `regex=`: the piece is a part of its file, and exists when the regex has a match there. A placeholder in it stands for what it matched in `primary`, as literal text. | regexp, pattern (a regex is not a path pattern) |
| **condition** | What a policy's `when` says must hold before its rules run on an artifact: that a piece exists, or `not`, `all`, or `any` of other conditions. | filter, predicate |
| **built-in rule** | A rule CrossLint has, which it runs wherever a policy's `rule` line gives its name, with no code: `piece-exists` and `piece-absent`. | core rule |
| **setting** | A value a plugin takes in its block in the project's configuration, such as the Angular plugin's `src-dir`, declared in the manifest with `setting NAME`. | option |

## Ruby and helpers

| Word | Meaning | Avoid |
| --- | --- | --- |
| **Ruby rule** | A rule whose helper runs on the Ruby CrossLint carries: a class that inherits from `CrossLint::Rule`, in the helper's file. Its `check` gets one artifact and returns its violations. | custom rule |
| **project files** | The files a Ruby rule sees through `project_files`: those Git tracks, and the untracked ones it doesn't ignore. | |
| **detail** | What tells apart the violations one rule finds on one artifact, such as a missing input's name, so the debt plugin can excuse each alone. | |
| **helper** | A command and a file a plugin carries, which run its rules or declare its artifacts: on the Ruby CrossLint carries, written `command=(crosslint)"ruby"`, so that every project can run it, or on a program on the project's `PATH`, such as the Angular plugin's, which runs on Node and reads TypeScript with ts-morph. | adapter, sidecar |
| **fault** | What stops a plugin: an exception its Ruby raises, a gem it requires that CrossLint wasn't built with, or a helper that fails. The plugin reports nothing else, and `crosslint check` exits with 2. | crash |
| **mistake** | A line of a manifest or a configuration that CrossLint can't use, CrossLint stops at it with exit status 2, before it checks anything, and says which file and line. | invalid config |
| **notice** | A warning CrossLint gives about a plugin rather than an artifact, such as an artifact declaration whose `primary` pattern matches nothing. | |

## Steps and commands

| Word | Meaning | Avoid |
| --- | --- | --- |
| **step** | Work CrossLint does once, after every rule of every plugin has run, requested in a manifest with `step NAME`. It sees every violation, and can excuse some, add others, and report entries that no violation matches. CrossLint has one step, `track-debt`. | hook |
| **plugin command** | A command declared in a manifest, under the plugin's name, run as `crosslint PLUGIN COMMAND`, such as `crosslint debt update`. It runs the check, and the plugin's step does the command's work. | subcommand |
| **command flag** | A flag of one plugin command, declared in the command's block. No plugin can add a flag to CrossLint's commands. | plugin flag |

## Sharing

| Word | Meaning | Avoid |
| --- | --- | --- |
| **local plugin** | A plugin in the project's repository, listed by its path. | custom rules |
| **shared plugin** | A plugin in a separate Git repository, listed by its URL, a ref, and, for a plugin in one of the repository's folders, `path=`. CrossLint fetches it into the user's cache on first use. | remote plugin, package |
| **built-in plugin** | A plugin that ships inside CrossLint: `angular` or `debt`. CrossLint runs it only when the configuration lists it. | default plugin |
| **ref** | The tag or full commit SHA at which a project lists a shared plugin. Never a branch. | version, pin |
