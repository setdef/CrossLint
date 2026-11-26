# Glossary

The word CrossLint uses for each idea, in its documentation, its messages, and its code, with what other tools call the same idea and the words to avoid. A page that needs a word this list lacks adds it here first.

## Artifacts, policies, and rules

CrossLint has three kinds of thing, and they come together: an artifact says which files belong together, a policy says when to check them, and a rule does the checking.

| Word | Meaning | Avoid |
| --- | --- | --- |
| **artifact** | A set of files that belong together, such as a component with its template, its test, and its stub. An artifact's declaration gives the pattern that finds its primary files, and the path of each companion. | group, unit, module |
| **primary file** | The file an artifact is found by, such as `card.component.ts` for a component. | main file, source |
| **companion** | A file that belongs with an artifact's primary file, at a path the artifact gives, such as its test or its signature file. A companion may or may not exist; checking that is a rule's work. | sibling, related file, partner |
| **path pattern** | A path with a placeholder in braces, such as `lib/{path}.rb`. In an artifact's `files`, `{path}` matches one or more folders and a file name; in a companion's path, it stands for what it matched. | glob (a path pattern is not a glob), template |
| **policy** | A declaration of when rules apply: to which artifacts, and under what condition, such as "every component whose stub exists". | check, linter config |
| **rule** | One check of one artifact, such as "the companion exists" or "the stub declares every input the component has". A rule runs only where a policy applies it. | lint, assertion, test |
| **violation** | What a rule reports when an artifact fails it: the rule, the artifact, a message, and a severity. | error (an error is one severity), offense, problem |
| **severity** | `error`, which fails the check, or `warning`, which is reported and fails the check only with `--warnings=error`. | level |

## Plugins

| Word | Meaning | Avoid |
| --- | --- | --- |
| **plugin** | A folder of artifacts, policies, and rules, with a `plugin.kdl` that declares them. A project uses a plugin by listing it in its configuration. | extension, package, preset |
| **local plugin** | A plugin kept in the project's repository, for that project's rules. It is a plugin in every way; only where it lives differs. | custom rules, project rules |
| **shared plugin** | A plugin kept in a Git repository of its own, which projects list by its URL and a tag or commit. CrossLint fetches it into the user's cache. | remote plugin, package |
| **built-in plugin** | A plugin that ships inside CrossLint, such as `angular` and `debt`. It runs only when the configuration lists it, like any other. | core plugin, default plugin |
| **configuration** | `.config/crosslint.kdl` in a project's root. It lists the plugins CrossLint runs, and settings for their rules. | config file, rc file, settings |
| **helper** | A program in another language that a plugin carries to read files of that language, such as the Angular plugin's JavaScript that asks the project's TypeScript compiler for a component's inputs. It runs on the runtime for that language that the project already has. | adapter, bridge, sidecar |

## Debt

| Word | Meaning | Avoid |
| --- | --- | --- |
| **debt** | Violations a project accepts for now, so the check passes until a new one appears. | baseline, suppressions, ignores, allowlist |
| **debt file** | `.config/crosslint/debt.tsv`, the file that lists a project's debt, one entry per line, committed with the project. | baseline file |
| **entry** | One line of the debt file: the rule, the artifact, a detail where the rule gives one, and a comment saying why the violation is accepted. | record, row |
| **stale entry** | An entry that no current violation matches, because someone fixed it. A stale entry fails the check until `crosslint check --update-debt` removes it. | paid-off debt, resolved debt |
