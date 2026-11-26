# Glossary

The word CrossLint uses for each idea, in its documentation, its messages, and its code, with what other tools call the same idea and the words to avoid. A page that needs a word this list lacks adds it here first.

## Artifacts, policies, and rules

CrossLint has three kinds of thing, and they come together: an artifact says which files belong together, a policy says when to check them, and a rule does the checking.

| Word | Meaning | Avoid |
| --- | --- | --- |
| **artifact** | A set of files that belong together, such as a component with its template, its test, and its stub. An artifact's declaration gives the pattern that finds its primary files, and the path of each companion. | group, unit, module |
| **primary file** | The file an artifact is found by, such as `card.component.ts` for a component. | main file, source |
| **companion** | A file that belongs with an artifact's primary file, at a path the artifact gives, such as its test or its signature file. A companion may or may not exist; checking that is a rule's work. | sibling, related file, partner |
| **path pattern** | A path with a placeholder in braces, such as `lib/{path}.rb`. In an artifact's `files`, `{path}` matches a file name and the folders before it, if any; in a companion's path, it stands for what it matched. | glob (a path pattern is not a glob), template |
| **placeholder** | A name in braces in a path pattern, `{path}` or `{name}`, which stands for part of a path. | variable, wildcard |
| **policy** | A declaration of when rules apply: to which artifacts, and under what condition, such as "every component whose stub exists". | check, linter config |
| **condition** | What a policy's `when` says must hold for an artifact before the policy applies to it, such as `companion-exists "stub"`. | filter, predicate |
| **rule** | One check of one artifact, such as "the companion exists" or "the stub declares every input the component has". A rule runs only where a policy applies it. | lint, assertion, test |
| **violation** | What a rule reports when an artifact fails it: the plugin and policy that ran the rule, the artifact with its role, a message, a severity, and a detail where one artifact can fail the rule in several ways, such as a missing member's name. | error (an error is one severity), offense, problem |
| **fault** | What stops a plugin: an exception its Ruby raises, a gem it requires that CrossLint wasn't built with, or a helper that fails. The plugin reports nothing else, and `crosslint check` exits with 2. | crash, plugin error |
| **notice** | A warning CrossLint gives about a plugin rather than an artifact, such as an artifact whose `files` pattern matches no file. A notice has no policy, and debt can't record it. | violation (a violation is about an artifact) |
| **built-in rule** | A rule that ships inside CrossLint, such as `companion-exists`, which any plugin's policy can run without code. | core rule, standard rule |
| **severity** | `error`, which fails the check, or `warning`, which is reported and fails the check only with `--warnings=error`. | level |

## Plugins

| Word | Meaning | Avoid |
| --- | --- | --- |
| **plugin** | A folder of artifacts, policies, and rules, with a `plugin.kdl` that declares them. A project uses a plugin by listing it in its configuration. | extension, package, preset |
| **local plugin** | A plugin kept in the project's repository, for that project's rules. It is a plugin in every way; only where it lives differs. | custom rules, project rules |
| **shared plugin** | A plugin kept in a separate Git repository, which projects list by its URL and a tag or commit. CrossLint fetches it into the user's cache. | remote plugin, package |
| **ref** | The tag or full commit SHA at which a project lists a shared plugin, as `ref="v1.2.0"`. Never a branch. | version, pin |
| **step** | Code a plugin runs once, after every rule of every plugin has run. It sees every violation and can excuse some, add others, and report stale entries, as the debt plugin's `track-debt` does. | hook, post-processor |
| **built-in plugin** | A plugin that ships inside CrossLint, such as `angular` and `debt`. It runs only when the configuration lists it, like any other. | core plugin, default plugin |
| **manifest** | A plugin's `plugin.kdl`, which declares the plugin's artifacts, policies, rules, and helpers. | plugin config, descriptor |
| **project root** | The folder that holds a project's `.config/crosslint/config.kdl`. Every path in a plugin, a configuration, and the report is relative to it. | base dir, workspace |
| **configuration** | `.config/crosslint/config.kdl` in a project's root, beside the debt file and any local plugins the project keeps in `.config/crosslint/`. It lists the plugins CrossLint runs, and settings for their rules. | config file, rc file, settings (a setting is one value in it) |
| **setting** | One value in the configuration, such as a plugin's `src-dir` or a policy's `severity`. | option (an option is on the command line), preference |
| **mistake** | Something in the configuration or a manifest that CrossLint can't use, such as a node it doesn't know. A mistake stops CrossLint with exit status 2 before it checks anything, naming the file and the line. | error (an error is a severity), invalid config |
| **helper** | A program in another language that a plugin carries to read files of that language, such as the Angular plugin's JavaScript that asks the project's TypeScript compiler for a component's inputs. It runs on the runtime for that language that the project already has. | adapter, bridge, sidecar |

## Debt

| Word | Meaning | Avoid |
| --- | --- | --- |
| **debt** | Violations a project accepts for now, so the check passes until a new one appears. | baseline, suppressions, ignores, allowlist |
| **debt file** | `.config/crosslint/debt.tsv`, the file that lists a project's debt, one entry per line, committed with the project. | baseline file |
| **entry** | One line of the debt file: the plugin and policy that found the violation, the artifact, a detail where the rule gives one, and a comment saying why the violation is accepted. | record, row |
| **stale entry** | An entry that no current violation matches, because someone fixed it. A stale entry fails the check until `crosslint check --update-debt` removes it. | paid-off debt, resolved debt |
