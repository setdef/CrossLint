# Plugins

This document specifies what is settled about CrossLint's plugins and the three kinds of thing they supply: artifacts, policies and rules. Every later design of plugins is checked against it. What waits on the language question, [#4](https://github.com/setdef/CrossLint/issues/4), is listed under [Waits on #4](#waits-on-4).

## Artifacts, policies and rules

CrossLint has three kinds of thing, and they always come together:

- **An artifact** is a set of files that belong together, such as a component with its template, its test and its stub. Its definition holds the path where each of those files belongs.
- **A policy** determines when rules apply: to which artifacts, and under what condition.
- **A rule** is one check.

These are [ng-nudge](https://github.com/OverTheTopMarketing/ng-nudge)'s terms, and they keep ng-nudge's meanings. A rule runs on an artifact only when a policy applies it there.

An artifact whose files are related only by their paths is declared as data: a name, a pattern that finds its primary files, the path of each companion file relative to the primary file, and which companions it expects. Declaring one takes no code. Every check that compares paths, such as "every file has a test", "every component has a template beside it" or "every Ruby file has a signature file at the matching path under `sig/`", needs only such an artifact, a policy and a rule that reads whether each companion exists. Code is needed where an artifact or a rule reads inside files, and where a policy's condition can't be stated as data.

## Plugins

A plugin supplies any number of artifacts, policies and rules, in any mix.

CrossLint's engine, its Angular checks and its debt tracking are separate. The Angular checks are a plugin, and so is debt tracking. A project that uses neither Angular nor debt tracking uses CrossLint without either plugin.

The engine does what every plugin needs, and nothing that only one needs. ng-nudge 0.3.0 lacks this split. Its engine builds a TypeScript project from `tsconfig.json` on every run and has the four Angular policies built in ([`lib/codebase.js:1-30`](https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/codebase.js#L1-L30)), its configuration loader starts with the seven Angular roles ([`lib/config/registry/artifact.registry.js:16-18`](https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/config/registry/artifact.registry.js#L16-L18)), and its run loop holds the debt file, filters violations with it, finds stale entries, sets the exit code with it and writes it ([`lib/verification-task.js`](https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/lib/verification-task.js)). In CrossLint:

- **The engine** loads configuration and plugins; finds each artifact's files from its pattern and companion paths; takes whether a file exists from the filesystem; applies policies and runs rules; applies each rule's configuration and severity; prints the report; and sets the exit code. It has no roles, languages or policies built in.
- **Every violation has an identity** the engine gives it: its rule, its artifact with the artifact's role, and a detail such as a member's name. Debt tracking matches on that identity without knowing what an artifact is ([ng-nudge-compatibility.md](ng-nudge-compatibility.md#debt-tracking)).
- **A plugin can do what debt tracking needs:** remove violations from the report before it is printed, add violations after the other rules have run, count toward the exit code, add a flag (`--update-debt`), read configuration keys under its rules, and print lines in the report.
- **A plugin that reads inside files** loads what it reads them with only when one of its checks reads a file. The Angular plugin loads a TypeScript reader for its member checks, and its path checks run without one.

## Artifacts, policies and rules a project writes

The people who own a project can always write artifacts, policies and rules for it.

The artifacts, policies and rules a project writes for itself are a local plugin: a plugin with a manifest, kept in the project's repository. A local plugin and a shared one are the same thing, with the same manifest, read by the same loader. Sharing a local plugin takes no rewriting, only a way for other projects to get it. The cost is a few lines of manifest for even the smallest project rule. The decision is [#5](https://github.com/setdef/CrossLint/issues/5), question 1.

A project lists its local plugin in its configuration as it lists any other plugin.

## Nothing on until it is listed

No plugin runs until the project lists it in its configuration, and that includes the debt plugin and the Angular plugin. The decision is [#5](https://github.com/setdef/CrossLint/issues/5), questions 2 and 3.

- CrossLint's documented configuration shows a recommended list of plugins. If CrossLint writes a configuration file for a project, it writes the recommended list into it.
- A plugin on the recommended list does nothing in a project that lacks what it reads. The debt plugin reports nothing and fails nothing without a debt file, as ng-nudge's debt tracking does.
- The Angular plugin is not on by default. An Angular project lists it.
- A configuration that lists no plugin is an error, because no check would run, and the message points to the recommended list.
- A project lists its plugins under a `plugins` key in `.config/ng-nudge/rc.json`. CrossLint defines that key, so it is a known key. The form of CrossLint's configuration for a project without an `rc.json` waits on [#4](https://github.com/setdef/CrossLint/issues/4).

A project migrating from ng-nudge adds a `plugins` key to its `rc.json` that lists the Angular plugin and the debt plugin ([ng-nudge-compatibility.md](ng-nudge-compatibility.md#migrating-in-30-minutes-or-less)).

## Configuring rules

- Every rule is configured the same way, whichever plugin supplies it, the project's local plugin included: it can be turned off, and its severity can be set. ng-nudge ignores both settings for the rules of the policies a project writes. A rule with no severity in the configuration has the default severity its plugin declares, where ng-nudge gives every such rule `error`. Both are in [ng-nudge-compatibility.md, Bugs not kept](ng-nudge-compatibility.md#bugs-not-kept).
- ng-nudge's rule names, such as `spec-exists` and `has-debt`, keep working in a project's configuration and debt file, because both hold them ([ng-nudge-compatibility.md](ng-nudge-compatibility.md#policies-and-rules)).
- A rule's full name is `plugin/rule`, as in ESLint, so rules of the same name from different plugins stay apart. A bare name is accepted for the rule of any listed plugin when exactly one listed plugin has a rule of that name, so ng-nudge's names keep working. When more than one listed plugin has a rule of that name, a bare name is an error that lists the full names.

## A rule no policy runs

A rule that no policy applies never runs, and CrossLint says so instead of loading it and ignoring it, as ng-nudge does with the rules in `.config/ng-nudge/rules/` ([ng-nudge-compatibility.md, Bugs not kept](ng-nudge-compatibility.md#bugs-not-kept)).

CrossLint reports such a rule as unused. It creates no implicit policy for it, because a rule runs on an artifact only when a policy applies it there.

## Waits on #4

Each of these is settled with [#4](https://github.com/setdef/CrossLint/issues/4):

- **What code a plugin may carry, and in which language,** and so how a project writes policies and rules for itself.
- **The form of the manifest,** and whether policies are data in it, code, or either.
- **Where the Angular plugin lives:** in this repository, in a separate one, or shipped with CrossLint ([#5](https://github.com/setdef/CrossLint/issues/5), question 3).
- **How shared plugins are published and installed** ([#5](https://github.com/setdef/CrossLint/issues/5), question 4).
- **How the debt plugin's hooks work.**
