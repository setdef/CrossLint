# Plugin sharing

Question, from the "Also to find out" list in issue #1:

1. Can shared plugins (each a set of artifacts, policies and rules) be published and installed the way ESLint's are? Should a default set be on from the start (debt tracking, for a drop-in replacement of ng-nudge)? Does an Angular plugin belong in this repository or its own?
2. Do a project's own artifacts, policies and rules need to be a plugin, or can they live in its repository?

Nothing here is a design. Decisions are the maintainer's; each section ends with the options and the evidence.

Rerun the one experiment with `bash try-mise.sh WORKDIR` (needs `mise` and network; it writes only under `WORKDIR` and gives mise its own data, cache and config directories). Output of the run is quoted in [Experiment](#experiment-installing-a-plugin-through-mise).

## Short answers

- **Publishing and installing like ESLint.** ESLint's mechanism is npm: a registry, a name convention (`eslint-plugin-*`), keywords for discovery, `peerDependencies` for compatibility, and a lockfile for pinning. RuboCop does the same with RubyGems and Bundler, Stylelint with npm. A CrossLint that carries its own runtime has none of those in the project, and publishing to a registry is not approved. What remains is sharing by URL: a Git tag or GitHub release archive, pinned by checksum. mise can install such an archive today with no Ruby or Node (tested below). CrossLint itself would have to supply the name, the compatibility check and the version listing that npm supplies for ESLint.
- **Local rules without a plugin.** Every tool surveyed lets a project keep its own rules in its repository with no packaging step, except golangci-lint, whose custom linters need a rebuilt binary. ng-nudge already works this way: project artifacts, rules and policies are files in `.config/ng-nudge/`.
- **Default set.** Tools split evenly. ESLint and Stylelint turn nothing on until the project asks. RuboCop, Biome and golangci-lint turn a default set on. ng-nudge's own debt policy is a no-op until a debt file has entries and the rule's `withComment` option is set, so "on by default" costs a project without debt nothing.
- **Angular plugin location.** The ecosystems surveyed mostly keep framework plugins in their own repositories (`angular-eslint`, `rubocop-rails`, `rubocop-rspec`), versioned separately from the engine. Biome and golangci-lint keep everything in one repository because they ship one binary. Options and their effect on a 30-minute migration are in [Where the Angular plugin lives](#where-the-angular-plugin-lives).

## How other tools share plugins

Versions are the ones whose documentation I read. Where a page states no version, the version is the latest published when I read it.

| Tool (docs read) | Where plugins are published | Install and enable | Pinning | Project-local rule, no plugin |
|---|---|---|---|---|
| ESLint flat config, v10.15.0 ([plugins](https://eslint.org/docs/latest/use/configure/plugins), [creating plugins](https://eslint.org/docs/latest/extend/plugins), [shareable configs](https://eslint.org/docs/latest/extend/shareable-configs)) | npm. Names are `eslint-plugin-*` or `@scope/eslint-plugin`; keywords `eslint`, `eslintplugin`, `eslint-plugin`; `eslint` is a `peerDependency`. | `npm install`, then `import` in `eslint.config.js`, then `plugins: { name }` and `rules: { "name/rule": "error" }`. A plugin's `configs` are opted into with `extends: ["name/recommended"]`; the page says plugins cannot force a config on a project. | npm: ranges in `package.json`, exact tree in the lockfile ([npm docs](https://docs.npmjs.com/cli/v11/configuring-npm/package-lock-json)). | A "virtual plugin" in the config file: `plugins: { local: { rules: { "my-rule": myRule } } }`, then `"local/my-rule": "error"`. A rule does not run unless its severity is `warn` or `error` ([custom rules](https://eslint.org/docs/latest/extend/custom-rules)). The plugins page also says plugins need not be on npm and shows `import local from "./my-local-plugin.js"`. |
| RuboCop 1.93 ([plugins](https://docs.rubocop.org/rubocop/latest/plugins.html), [inheritance](https://docs.rubocop.org/rubocop/latest/configuration/inheritance.html)) | RubyGems. Plugins are built on the `lint_roller` gem (plugin system since RuboCop 1.72). | Add the gem to the `Gemfile`; list it under `plugins:` in `.rubocop.yml`. Shared configuration comes from `inherit_gem`, from `inherit_from` with a local path, or from `inherit_from` with an `http` URL (cached for 24 hours; the page documents no checksum or pin for a URL). | Bundler: `Gemfile` and `Gemfile.lock`. | `require: ./path/custom_cop.rb` loads a Ruby file from the repository, and the cop is configured like any other. A plugin not published as a gem is loaded with `plugins: - name: { require_path: ..., plugin_class_name: ... }`. The page says `require` stays for internal custom cops. |
| Stylelint 18.1.0 ([configure](https://stylelint.io/user-guide/configure), [plugins](https://stylelint.io/developer-guide/plugins)) | npm. Keywords `stylelint-plugin` and `stylelint-config`; Stylelint is a `peerDependency`. | `npm install`; `plugins: ["name"]` and `extends: ["stylelint-config-standard"]`. Both accept a module name, an absolute path or a path relative to the config file. "No rules are turned on by default." | npm lockfile. | Put a path in `plugins`, such as `"../special-rule.js"`, and enable `namespace/rule` under `rules`. Rule names must carry a namespace. |
| Biome 2.6.9 ([linter plugins](https://biomejs.dev/linter/plugins/)) | No registry in the documentation. A plugin is a file: GritQL (`.grit`, a pattern DSL) or JavaScript. | `"plugins": ["./path.grit"]` in `biome.json`; an entry can be `{ "path", "includes": [globs] }` to limit it to some files. A shared config can ship a plugin file: `"resolutionKind": "config"` resolves the path from the shared config's directory. | The shared config's own version (it is also a file or package; the page does not say more). | The same `.grit` file, anywhere in the project. The page notes GritQL plugins match patterns in one file and have no access to the semantic model, and JavaScript plugins are about ten times longer for the same rule. |
| golangci-lint v2 ([module plugins](https://golangci-lint.run/docs/plugins/module-plugins/), [Go plugins](https://golangci-lint.run/docs/plugins/go-plugins)) | Go modules, fetched from a Go proxy or a local path. | `.custom-gcl.yml` lists plugin modules and versions; `golangci-lint custom` builds a new binary (needs Go and Git); `.golangci.yml` enables it under `linters.settings.custom`. The older Go-plugin route needs `CGO_ENABLED=1` and an exact version match with the host's libraries. | `version:` per plugin in `.custom-gcl.yml`. | A local-path plugin in the same `.custom-gcl.yml`. It needs a rebuild, so a project with no Go toolchain cannot add one. |
| Semgrep ([run rules](https://semgrep.dev/docs/running-rules), [CLI reference](https://semgrep.dev/docs/cli-reference)) | A registry of rulesets (data, not code), and any URL. | `--config` takes a YAML file, a directory of `.yml` files, a URL of a config file, or a registry entry; several `--config` flags combine. | A URL or a copied file; the registry names are not versioned in what I read. | A YAML file in the repository, passed to `--config`. Rules are data, with patterns written in the target language. |
| Danger ([Danger JS plugins](https://danger.systems/js/usage/extending-danger.html), [Danger Ruby getting started](https://danger.systems/guides/getting_started.html)) | npm packages tagged `danger-plugin` (JS); gems (Ruby). | Add the package or gem to the project; call it from the `Dangerfile`. | npm lockfile or `Gemfile.lock`; the Ruby guide recommends Bundler for exactly this reason. | The `Dangerfile` is the project's own rules. The JS plugin page describes a plugin as the code you move out of a `Dangerfile` once you want to reuse it across projects. |

Patterns in the table:

- Each tool that has a registry uses its language's package manager for four jobs: naming, discovery, compatibility (`peerDependencies`) and pinning (lockfile). A tool with no registry (Biome, Semgrep) shares files or URLs and leaves pinning to the project.
- Every tool has a path to a project-local rule that needs no packaging. A shared plugin is the same code as a local one, plus a name, a version and a place to download it.
- Rules written as data (Semgrep YAML, Biome GritQL) travel by file. Rules written as code (ESLint, RuboCop, Stylelint, Danger) travel with the language's package manager and need that language's runtime in the project.
- Defaults differ. ESLint (rules run only when configured or extended) and Stylelint (stated on the page) start empty. RuboCop starts from its default configuration, which every project inherits ([inheritance](https://docs.rubocop.org/rubocop/latest/configuration/inheritance.html)). Biome enables "recommended" rules when the project has no configuration ([linter](https://biomejs.dev/linter/)). golangci-lint's `linters.default` is `standard` unless set ([configuration file](https://golangci-lint.run/docs/configuration/file/)).

### What ng-nudge does today

Read from the public repository at commit `10a7224` (`@overthetopmarketing/ng-nudge` 0.3.0, [README](https://github.com/OverTheTopMarketing/ng-nudge/blob/10a722456daacca08f6425c5b74e5586183c654b/README.md), [`lib/config/`](https://github.com/OverTheTopMarketing/ng-nudge/tree/10a722456daacca08f6425c5b74e5586183c654b/lib/config)):

- It is installed by a Git URL in `devDependencies` (README), and its `package.json` has a `publishConfig` pointing at GitHub Packages. It has no plugin concept: there is one package with built-in artifacts, rules and policies.
- A project extends it with files in `.config/ng-nudge/`: `artifacts/*.artifact.js`, `rules/*.rule.js`, `policies/*.policy.js`, loaded by `ExtensionDirectory` with a dynamic `import()`. The project can also declare artifacts as data in `rc.json` (a `pattern` and an `expects` list; see `rc.schema.json`).
- The debt policy (`HasDebt`) returns "does not apply" when the debt file is empty or when the `has-debt` rule has no `withComment` option. So a project that has no debt file sees no debt behavior.

## Which sharing mechanisms still work with no Ruby and no Node

Assumption, from issue #1: CrossLint is a self-contained app that carries its own runtime and is installed through mise, so the project may have no Ruby, no Node, and possibly no Git. [Fledge#123](https://github.com/setdef/Fledge/issues/123) describes installing such an app through mise's `http:` backend.

"Author" is whoever writes the plugin. "Project" is whoever uses it.

| Mechanism | Author does | Project does | What breaks or is left open |
|---|---|---|---|
| **Files in the project's repository** (vendored copy, or the project's own directory) | Nothing, or publishes a repository to copy from. | Copies the files, commits them, points CrossLint at the directory. | No update path: the copy drifts. Nothing else breaks; works with any runtime. |
| **Fetch by Git URL, by CrossLint** (`url` plus tag or commit) | Pushes a tag. | Lists the URL and tag in the CrossLint config. CrossLint clones or downloads an archive and caches it. | A clone needs the `git` binary; an HTTPS archive (`.../archive/refs/tags/<tag>.tar.gz`) needs only an HTTP client in CrossLint's runtime. A tag can be moved, so pinning needs a recorded checksum or commit SHA. CrossLint has to build the lockfile, the cache and the update command that npm and Bundler give other tools. |
| **mise `http:` backend** (archive URL, tag archive or release asset) | Pushes a tag or attaches an archive to a GitHub release. | Adds one line to `mise.toml`; `mise install`; commits `mise.lock`. CrossLint reads the plugin from the install directory (`mise where`). | Tested below. The pin is mise's checksum, not CrossLint's, so the project needs mise (already assumed). mise has no knowledge of CrossLint's compatibility range. The archive's top folder was kept in one test and stripped in the other; the plugin author should set `strip_components` explicitly so the layout is the same everywhere. |
| **mise `github:` backend** (GitHub release assets) | Attaches an archive to a GitHub release (releases on GitHub are allowed by the plan). | `"github:org/plugin" = "0.3.1"` in `mise.toml`. mise picks the asset by platform, checks the digest GitHub reports or a published checksum file and, on public GitHub, artifact attestations ([github backend](https://mise.jdx.dev/dev-tools/backends/github.html)). It can resolve a version range such as `0.3`, which `http:` cannot. | Documented here, not run (it needs a real release). A plugin archive is the same for every platform, so mise's platform-asset scoring is unneeded; `asset_pattern` selects it by name. |
| **Plugin as a data or DSL file** (YAML, or a DSL) | Writes data. | Any mechanism above carries it. | Nothing about the runtime. Only artifacts that read inside files, and rules with real logic, need code (see the sibling spikes on reading TypeScript from Ruby). |
| **Plugin as code in CrossLint's own language** | Writes Ruby (if CrossLint is Ruby). | Needs the code to load into CrossLint's embedded runtime. | Open: whether a Fledge-built app can `require` Ruby files from outside the app, and whether gems with native parts can be added to its runtime. The sibling spike on building into Fledge covers the build; I did not test loading. A Ruby plugin's author would not need Ruby on the project's machine. |
| **Plugin as code in another language** (a JavaScript helper that reads TypeScript) | Writes JavaScript. | Needs Node on the machine, or CrossLint carries Node. | Breaks the "neither Ruby nor Node" case unless CrossLint bundles a JavaScript runtime. A project with Node has it; one without does not. |
| **Registry package** (RubyGems, npm) | Publishes to a registry. | `gem install` or `npm install`. mise has `gem:` and `npm:` backends. | Not approved ([plan](../../docs/plan.md)). Needs Ruby or Node on the machine, so it fails the no-runtime case for any language the project lacks. |
| **A new binary with the plugin built in** (golangci-lint's route) | Publishes a module; the project (or CI) builds a custom binary. | Installs a toolchain, builds. | Needs the toolchain the project is trying to avoid. Shows what plugin-by-rebuild costs a single-binary tool. |
| **Inside an Agent Skill folder** | Puts the plugin's data files in the skill's `assets/` or `references/` directory ([Agent Skills specification](https://agentskills.io/specification): optional `scripts/`, `references/`, `assets/`). | Installs the skill the way it installs any skill; points the CrossLint config at `<skills dir>/<skill>/...`. | The path depends on where the project keeps skills and how they get there. mise can fetch skills a tool's release declares and link them with `mise skills sync` ([Packslip resources](https://mise.jdx.dev/dev-tools/packslip-resources.html)), but the page says those links are symlinks into mise's install directory and should not be committed, so a fresh clone or CI job has no plugin until someone runs `mise skills sync`. A missing plugin file must be an error, or the check silently stops running. The plugin version moves with the skill's, not with CrossLint's. I read the documentation; I did not run `mise skills sync`, and I did not check how other skill installers handle non-Markdown files. |

### Experiment: installing a plugin through mise

`try-mise.sh` ran with mise 2026.11.12, the version in Fledge#123, on one platform (no Linux or Windows run). It built a tarball holding a data-only plugin (two YAML files), then:

1. Installed it with `"http:crosslint-plugin-adr-index" = { version = "0.1.0", url = "file://.../adr-index-0.1.0.tar.gz", checksum = "sha256:..." }`. It installed in 52 ms. `mise where` printed the install directory, which held `adr-index/crosslint-plugin.yml` and `adr-index/rules/...` (the top folder was kept). With an empty `mise.lock` present, `mise lock` recorded the URL and checksum for seven platforms.
2. Changed the archive and installed again into a fresh data directory. mise refused it with `Expected: sha256:f211...` and `Actual: sha256:c706...`.
3. Pointed the same backend at a GitHub tag archive of a public repository (`https://github.com/rubocop/rubocop-rake/archive/refs/tags/v0.7.1.tar.gz`, a tag with no release attached). It installed, the top folder was stripped, and `mise lock` recorded the archive's checksum.

What the run shows: a plugin can be fetched from a tag or a release URL, pinned and verified by checksum, with no Ruby, Node or Git, and with no registry. What it does not show: how CrossLint finds the install directory (it would call `mise where` or read `mise.lock`, or the project would set a path), a Linux or Windows run, or the `github:` backend.

Two details to know: `mise.lock` is written only when the file already exists (I created it empty), and the `file://` form takes an absolute path, so a lock that records one works only where the file is.

## Do a project's own artifacts, policies and rules need to be a plugin?

Evidence for "no":

- All seven tools allow project-local rules with no packaging (table above), with golangci-lint as the exception because it rebuilds a binary.
- ng-nudge's project-local extension points already work without a plugin concept: three directories of files, plus artifacts as data in `rc.json`.
- A project-local rule and a shared rule are the same thing in ESLint (`local/my-rule` is a virtual plugin) and RuboCop (`require:`): the only difference is that the shared one has a package around it.

Options for the maintainer:

| Option | What the project writes | Effect |
|---|---|---|
| A. Project directory only, loaded by the same loader as plugins | Files in a directory (for example `.crosslint/`), no manifest, no name or version | One code path in CrossLint. A rule moves from a project to a shared plugin by copying files and adding a manifest. A project can keep rules and one or more plugins side by side. |
| B. Everything is a plugin; a project's own rules are a local plugin | A small manifest plus the files, as ESLint's virtual plugin requires a plugin object | Uniform, one concept. Costs a few lines of boilerplate for the smallest project rule, and ng-nudge users have none of it today. |
| C. Two mechanisms: plugins for sharing, a lighter "project rules" file for local | Different shapes for the same thing | Two things to document and to keep equivalent. No tool surveyed does this on purpose. |

## Whether a default set is on from the start

What bears on the choice:

- ESLint and Stylelint start empty, and a plugin cannot force its configuration on a project. Their users opt in with `extends`. RuboCop, Biome and golangci-lint start with a default set that a project can switch off.
- The ng-nudge behavior CrossLint has to match is: no debt file means no debt behavior, and a debt file with entries means debt checks run (the policy conditions above). That reads the same under both choices, so "on by default" and "opt in" both preserve it for a project with no debt.
- The settled rule is that a project using neither Angular nor debt tracking can still use CrossLint (plan.md). That excludes a default set that fails or warns on such a project. A default set that is silent unless its inputs exist meets it.

Options:

| Option | For a project replacing ng-nudge | For a project that is not Angular |
|---|---|---|
| A. Nothing on until the project lists a plugin (ESLint, Stylelint) | The migration includes naming the Angular plugin and the debt plugin in the config. One more step, and a step that fails loudly if forgotten (no rules run). | Nothing to switch off. |
| B. A core set on by default, including debt tracking, silent when there is no debt file (RuboCop, Biome) | Debt tracking works the moment the debt file is in place. The Angular plugin is still opted in. | Debt tracking is present but inactive; the project can disable it. |
| C. Core set on, plus a named preset (`recommended`) that bundles the Angular plugin | One config line enables everything ng-nudge did. | The preset is not selected, so it costs nothing. |

Unknown that changes the choice: whether the debt file's format must stay compatible with `debt.tsv` (three columns: `Rule`, `Artifact`, `Comment`; README). If it does, a debt plugin has to read ng-nudge's file and `withComment` option on day one, whichever option is chosen.

## Where the Angular plugin lives

Precedent: `angular-eslint` ([github.com/angular-eslint/angular-eslint](https://github.com/angular-eslint/angular-eslint)) and `typescript-eslint` are separate repositories from `eslint/eslint`; `rubocop-rails` and `rubocop-rspec` are separate repositories from `rubocop/rubocop`; Stylelint's standard config is its own repository. Biome and golangci-lint keep their language and framework checks in one repository because they ship one binary.

| Option | Release and versioning | Replacing ng-nudge in 30 minutes |
|---|---|---|
| A. In this repository, as a separate directory with a manifest and a version of its own | One tag cycle can version core and Angular together; the plugin can be tested against the core in one commit. Compatibility is a non-issue while they are released together. | One source to pin. If shipped as a separate archive, one more line in the config. If bundled in the core release, no extra step. |
| B. Its own repository (`setdef/<something>`) | Two version lines. Core must say which plugin API versions it accepts, and the plugin which core versions it needs (npm's `peerDependencies`, RuboCop's plugin system). The plugin can release without a core release. | Two things to install and pin, and a compatibility error is possible when they disagree. Needs the sharing mechanism from the previous section to work before the first migration, since the Angular plugin is the first shared plugin. |
| C. Bundled into the CrossLint distribution as its default plugin | One download, one version. | Fewest steps, but a non-Angular project carries Angular files, and moving the plugin out later changes every user's config. |

Observations that bear on the choice:

- The plugin's inputs include code that reads TypeScript (the component artifact). Whatever it needs from the runtime (a Tree-sitter grammar, a JavaScript helper) determines whether it can be a pure data plugin. If it needs compiled code, it cannot be carried by the lighter mechanisms in the previous table, and B's separate releases carry compiled-code risk that A keeps in one build.
- Option B depends on a working install-by-URL mechanism for the first Angular user. Option A does not, because the plugin ships in the same archive as the core.
- Whichever location is chosen, the plugin's interface to the core is the same one any third-party plugin would use. Option A makes it easiest to cheat on that interface, since core and plugin change in one commit.

## Decisions this work needs from the maintainer

1. Whether a project's own artifacts, policies and rules need a manifest (options A to C above).
2. Which sharing mechanism CrossLint supports first, given the registry is not approved: fetch by URL by CrossLint, mise `http:` or `github:`, vendoring, or skill folders. The experiment shows mise works for data-only plugins.
3. Default set (options A to C above).
4. Angular plugin location (options A to C above).
5. Whether plugins may contain code in a language other than CrossLint's, because it determines whether a "neither Ruby nor Node" project can ever use one.

## Not verified

- Linux and Windows runs of the mise experiment, and mise's `github:` backend against a real release (needs a release; releases are out of scope here).
- Whether a Fledge-built app can load Ruby files and gems from outside itself.
- `mise skills sync` and other skill installers with a plugin folder in a skill.
- RuboCop's remote `inherit_from` has no documented checksum; I did not test it.
- Some table cells (names, keywords, `peerDependencies`) rest on page summaries I could not re-read in full: ESLint's plugin pages and Stylelint's plugin page. Check them before quoting.
