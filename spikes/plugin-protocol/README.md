# Plugins as separate programs

A spike for [issue #4](https://github.com/setdef/CrossLint/issues/4). It is evidence, not CrossLint's design, and it makes none of #4's decisions.

## Question

The prior art on #4 (protoc plugins, go-plugin, Danger's `--process`, LSP, pre-commit) suggests an option #4 lacks. CrossLint is a Ruby host. A plugin is a separate program, in any language, that talks to the host over stdin and stdout in JSON. The host tells the plugin which files match its artifacts and passes the facts it already has (paths, which companion files exist). The plugin replies with violations. A Rubyist writes a plugin in Ruby and a JavaScript developer in JavaScript. Does that work?

## Result

Policies fit in a manifest as data: ng-nudge's five built-in policies run from 14 lines of JSON that the host applies, and the host sends rules to plugins in two languages from one policy. The parts that stay code are the rules that read inside files. See [Policies as data](#policies-as-data).

Debt tracking's other work (excusing other plugins' violations, stale entries, `--update-debt`) works as design (a), the host doing it, and as design (b), a plugin with a new `post_check` step doing it. Both read and write ng-nudge's `debt.tsv` as it is, and gave the same output and the same file on all 16 cases. They differ in who writes the debt code, in how much protocol a third party must keep stable, and in what a plugin can do to other plugins' violations. See [Debt tracking](#debt-tracking).

It works for path-relation rules and for a rule that reads TypeScript, with three plugins in three languages (Ruby, JavaScript, shell with `jq`) against one fixture project. The same results came out on macOS (arm64), Linux (x86_64) and Windows 11 (x64), as plain Ruby and inside a Fledge console app installed through mise with no Ruby on `PATH`, where the Ruby plugins ran on the Ruby the app carries (`{host_ruby}`). The host reports a missing runtime by plugin and runtime name, exits 2, and still runs the other plugins. On a timeout it ends the plugin's whole process group (a job object on Windows), and `run.sh` checks that the plugin's child is gone. Provisioning a plugin's runtime with `mise` worked; a cold install of Node took 47 s here. See [Inside a Fledge app](#inside-a-fledge-app) and [Windows](#windows) for what broke on the way.

## Rerun

```console
$ bash run.sh
```

Needs Ruby 3.2 or later, Node 20 or later, `jq`, and network access on the first run (it installs `typescript` 6.0.3 into `fixture/`). It prints `ok` or `FAIL` per check and exits 0 when every result matches `expected/violations.txt` and every error path gives its expected message. `TIMING=1 bash run.sh` also prints per-plugin timings. To build the host as a Fledge app, install it through mise and run the same checks against it, run `bash fledge/scripts/check.sh` (needs mise and network access). Run the host by hand:

```console
$ ruby host/crosslint.rb --root fixture --timing plugins/spec-per-component-rb plugins/template-per-component-sh plugins/component-io-js
```

Options: `--config FILE` (a JSON file for policy conditions), `--provision` (install a missing runtime with mise, see below), `--timing`, `--repeat N` (send the same check N times to one process), `--lifetime per-check|per-run`, `--core-debt` (design (a) of [Debt tracking](#debt-tracking)), and the flags that a plugin's `hooks.post_check.flags` lists (`--update-debt` for `plugins/debt-rb`). `run.sh` ends with `debt/check.sh`, which runs each debt case under both designs; `BLESS=1 bash debt/check.sh CASE...` writes design (a)'s results as the expected files, and you read them before you commit them.

## Protocol, version 1

Every plugin is a folder with a `plugin.json` manifest and its program. The host reads the manifest without starting anything. The program reads one JSON object per line on stdin, writes one JSON object per line on stdout, and exits when stdin closes. Stderr is free text, and the host shows it only when the plugin fails. The request and response shapes follow JSON-RPC (`id`, `method`, `params`, `result`, `error`) without claiming to be it.

### Manifest

```json
{
  "name": "component-io",
  "protocol": 1,
  "runtime": {
    "command": "node",
    "args": ["{plugin_dir}/plugin.mjs"],
    "min_version": "20",
    "also": ["jq"],
    "provision": { "mise": "node@22" }
  },
  "lifetime": "per-check",
  "timeout": 60,
  "artifacts": [
    { "name": "component", "match": "src/**/*.component.ts",
      "companions": { "interface": "{dir}/{base}.component.i.d.ts" } }
  ]
}
```

- `protocol`: the version the plugin speaks. When the number differs, the host stops before it starts anything.
- `runtime.command` and `args`: what the host starts, with the project root as the working directory. `{plugin_dir}` is the manifest's folder. `{host_ruby}` stands for the Ruby that runs the host (for a Ruby plugin in an app that carries a Ruby).
- `runtime.min_version` (optional): the host runs `command --version` and compares the first version number it finds.
- `runtime.also` (optional): other executables the plugin needs on `PATH`, such as `jq`.
- `runtime.provision` (optional): how the host can install the runtime when it is missing. Only `mise` is implemented.
- `lifetime`: `per-check` starts a fresh process for each artifact; `per-run` keeps one process for the whole run. The messages are the same either way.
- `artifacts`: each has a `name`, a glob `match` relative to the project root, `companions` (a map from a name to a path template; `{dir}` is the matched file's folder and `{base}` its file name up to the first dot), and optionally `expects`, a list of companion names that this kind of artifact is expected to have.
- `rules` (optional): the rules the plugin implements, each `{ "name": "..." }`. A policy may list only declared rules. Without the key, any name is accepted.
- `policies` (optional): each has a `name`, `artifacts` (names from this manifest), `when` (a condition, below) and `rules`. A rule is `name` for one of this plugin's, or `plugin/name` for another plugin's, which must be on the command line. The host evaluates `when` for each matched file and sends the plugin only the rules whose policies apply. Without the key, the host makes one policy per artifact that always applies and lists no rules, so the plugin runs everything. `"policies": []` makes none.
- `hooks` (optional): `{"post_check": {"flags": ["update-debt"]}}` makes the plugin a post-check plugin. The host reads the manifest before it parses the command line and accepts each listed flag. See [Debt tracking](#debt-tracking).

A condition is a JSON object:

| Condition | True when |
| --- | --- |
| `{"companion": "interface", "exists": true}` | the companion file exists (`exists` defaults to `true`) |
| `{"expects": "spec"}` | the artifact's `expects` lists it |
| `{"config": "rules.has-debt.withComment", "present": true}` | the key is in the JSON file given with `--config` (`present` defaults to `true`) |
| `{"lines": {"gt": 1}}` | the file has more than 1 line (`gt`, `gte` or `eq`) |
| `{"all": [...]}`, `{"any": [...]}`, `{"not": {...}}` | the combination holds |

Without `when`, a policy always applies. `--config` takes a JSON file in the shape of ng-nudge's `rc.json`; `rules.NAME.enabled: false` removes that rule from every item, and the policy still applies, as in ng-nudge. A condition the host does not know fails with `bad-manifest`, and a rule that no given plugin declares fails with `rule-unknown`.

### Messages

Handshake, always first:

```json
{"id":1,"method":"handshake","params":{"protocol":1,"host":"crosslint-spike"}}
{"id":1,"result":{"protocol":1,"name":"component-io"}}
```

Check, once per artifact. The host expands the glob and the companion templates, and tests which companions exist, so the plugin starts with those facts. When policies chose the rules, each item carries them in `rules`, and the plugin runs only those on that item (a plugin that ignores `rules` runs all of its rules, so the field is an addition to protocol 1, not a new version):

```json
{"id":2,"method":"check","params":{"root":"/abs/project","artifact":"component","items":[
  {"path":"src/app/card/card.component.ts",
   "rules":["interface-matches-api"],
   "companions":{"interface":{"path":"src/app/card/card.component.i.d.ts","exists":true}}}]}}
{"id":2,"result":{"violations":[
  {"rule":"interface-matches-api","path":"src/app/card/card.component.ts","message":"src/app/card/card.component.i.d.ts lacks \"expanded\""}]}}
```

### Errors

A plugin that cannot answer replies with `{"id":N,"error":{"code":"...","message":"..."}}`. The host prints `crosslint: plugin NAME: CODE: MESSAGE` for it, and for each fault it finds itself. It then goes on to the next plugin, and exits 2 after the last one (1 when only violations were found, 0 when there are none). The codes the host raises:

| Code | Cause |
| --- | --- |
| `runtime-missing` | `command` or an `also` executable is not on `PATH` (and provisioning is off or unavailable), or the process could not start |
| `runtime-too-old` | `min_version` is higher than what `--version` printed |
| `provision-failed` | `mise install` failed |
| `protocol-mismatch` | the manifest or the handshake says a version other than the host's |
| `exited` | the process ended before it answered; the message carries the exit status and the first 300 bytes of stderr |
| `bad-json` | a stdout line was not JSON |
| `bad-response` | wrong `id`, neither `result` nor `error`, or a violation without a `rule` and a `path` that are strings |
| `timeout` | no answer within `timeout` seconds (default 60); the host kills the process and its children |
| `bad-manifest` | a policy lists an artifact the manifest lacks, a companion it does not declare, or a condition the host does not know |
| `rule-unknown` | a policy lists a rule of a plugin that was not given, or a rule that plugin does not declare |

Any other code comes from the plugin. The JavaScript plugin uses `dependency-missing` when the project has no installed `typescript`, and the host passes it through.

## What was built

| Part | Lines of code |
| --- | --- |
| `host/crosslint.rb`, the host | 254 (161 before policies and process groups; about 25 of the added lines are conditions, 35 apply the policies, 20 end process groups) |
| `plugins/spec-per-component-rb/plugin.rb`, every component has a spec | 15 |
| `plugins/template-per-component-sh/plugin.sh`, every component has an HTML template | 13 |
| `plugins/component-io-js/plugin.mjs`, a component's inputs and outputs, inherited ones included, appear in its interface file | 77 |
| `plugins/ng-nudge-paths-rb/plugin.rb`, five of ng-nudge's rules that read paths or one TSV file | 26 |
| three manifests | 13, 13, 18 |
| `plugins/ng-nudge-paths-rb/plugin.json`, with ng-nudge's five policies in 14 lines | 50 |
| `plugins/ng-nudge-ts-js/plugin.json`, a second manifest for the JavaScript plugin | 14 |
| `run.sh`, the checks | 99 before debt tracking, 104 now |
| Debt tracking, see [its table](#lines-of-code-for-debt-tracking) | `host/debt.rb` 143, `plugins/debt-rb/plugin.rb` 15, host changes 69 |

Lines of code exclude blank lines and comment lines, except for the manifests and `run.sh`, which are line counts. The three plugins check one `component` artifact each, so a plugin could carry several rules. The fixture (`fixture/`) has four Angular-style components, written to trigger a violation from each plugin: `card` and `footer` lack a spec, `footer` and `list` lack a template, `card` lacks `expanded` in its interface, `list` lacks the input `inheritedSignal` that it inherits through an import, and `footer` has no interface file.

The JavaScript plugin is the reading of one component from [`spikes/ts-from-ruby/approach_b/helper.mjs`](../ts-from-ruby/approach_b/helper.mjs): the compiler's `getBaseTypes` finds the base class, and `input()`, `output()`, `@Input` and `@Output` members with initializers count, as in ng-nudge. It loads the `typescript` that the project has installed with `createRequire` from the project root. It rebuilds the TypeScript program on every check.

The Ruby plugin has no TypeScript parser and no file system access. The host's facts are enough for a path-relation rule. The shell plugin parses JSON with `jq`, which is the practical way to write one.

## Policies as data

The cases are the five built-in policies of ng-nudge, as the [ng-nudge study](../ng-nudge-study/README.md#policies-and-rules) lists them. `plugins/ng-nudge-paths-rb/plugin.json` holds them as data and a 26-line Ruby plugin holds the rules that read only paths and one TSV file. The `interface-matches-component` rule needs a TypeScript reader, so the policy lists it as `ng-nudge-ts/interface-matches-api`, the JavaScript plugin from above under a second manifest (`plugins/ng-nudge-ts-js/`, which reuses `component-io-js/plugin.mjs`). The host evaluates the conditions and sends each plugin the rules for each file. The fixture gained a service without a spec, two stub files, two SCSS files (one beside a CSS file) and a `debt.tsv` with two entries.

| ng-nudge policy | In the manifest | Data or code |
| --- | --- | --- |
| `HasSpec` | `component` and `service` artifacts, `{"expects": "spec"}`, rule `spec-exists` | Data. The rule is a path test written in Ruby. |
| `HasInterface` | `component`, `{"companion": "interface", "exists": true}`, rules `stub-exists` and `ng-nudge-ts/interface-matches-api` | The policy is data. The second rule is code, in another plugin and another language. |
| `HasStub` | `component`, `{"companion": "stub", "exists": true}`, rule `interface-exists` | The policy is data. `stub-matches-component` was not built; it is the interface check aimed at the stub file. |
| `HasStyles` | `component`, no condition, rule `prefer-css-over-scss` | Data. The rule (SCSS exists and CSS does not) could be data too, and is Ruby here. |
| `HasDebt` | `debt-file`, `all` of `{"config": "rules.has-debt.withComment"}` and `{"lines": {"gt": 1}}`, rule `has-debt` | The condition is data, with two conditions the others do not need. The rule is code. Excusing other rules' violations, stale entries and `--update-debt` are not a policy; see [Debt tracking](#debt-tracking). |

Results (`run.sh` on macOS):

- With a config that has `rules.has-debt.withComment`, the run gives 11 violations, which match what ng-nudge's policy table says for this fixture: `spec-exists` on `card`, `footer` and the service; `stub-exists` on `card` and `list` (they have an interface and no stub, and `button` has both); `interface-exists` on `footer` (a stub and no interface); `prefer-css-over-scss` on `card` only; two `has-debt` entries; and two `interface-matches-api` violations from the JavaScript plugin.
- With no `withComment` in the config, `has-debt` does not apply, and the other nine violations are unchanged.
- With `spec-exists` disabled in the config, its three violations disappear and the rest stay.
- When a policy lists a rule of a plugin that was not given, or uses a condition the host does not know, the host reports a named error and exits 2.

What the cases show:

- **The conditions of all five built-in policies fit as data.** `instanceof Component` in ng-nudge is a kind of artifact, `component`, in the manifest. Four policies need only `companion` and `expects`; `HasDebt` also needs a config key and a line count, which the host reads from the `--config` file and the matched file. The five policies take 14 lines of JSON, where the study measures ng-nudge's at 23 to 27 lines of JavaScript each.
- **One policy can list rules of plugins in different languages,** which is the case where one project mixes Ruby and JavaScript. The host groups the rules by plugin, and each plugin gets the file's facts from the manifest that owns the artifact. The plugins must agree on companion names (the JavaScript plugin reads `interface`); nothing checks that.
- **Code is still needed for the rules that read inside files,** and for any `applies` that tests something other than a file's path, its companions, its line count or the config. ng-nudge's built-in policies have none, but its project policies are classes with an arbitrary `applies(artifact)`, and the spike has no way to express or call that. A plugin could answer an `applies` request over the protocol; nobody tried it.
- **Debt is more than a policy.** ng-nudge excuses the violations that match a debt-file entry, finds stale entries, rewrites the file with `--update-debt` and changes the exit code (study, "Where the engine, Angular and debt are tangled"). The `has-debt` rule here only reports each row. Filtering another plugin's violations needs a step after the rules run, and protocol 1 had no message for one. [Debt tracking](#debt-tracking) builds it two ways.
- **Not modeled in these cases:** severity of `prefer-css-over-scss`, which is a warning in ng-nudge, the rest of ng-nudge's per-rule configuration, and which policy is listed for an artifact in a printed report. `withComment`, severity for `has-debt` and d3-dsv quoting are in [Debt tracking](#debt-tracking), whose designs replace this section's `has-debt` rule and policy.
- **Host changes:** a plugin with no files for an artifact is no longer started (before, it got an empty check), and `run.sh`'s check for a project with no `typescript` now uses a project that has a component.

## Debt tracking

The question from [#4](https://github.com/setdef/CrossLint/issues/4): policies are data in a manifest, but ng-nudge's debt tracking also excuses other rules' violations that `debt.tsv` lists, reports stale entries (debt paid off) and rewrites the file with `--update-debt`. The protocol had no step for that. Two designs were built over the same cases:

- **(a) The host does debt tracking.** `--core-debt` makes the host call `Debt.evaluate` (`host/debt.rb`) on every plugin's violations after the checks.
- **(b) A debt plugin with a post-check step.** `plugins/debt-rb` declares `hooks.post_check`. After the checks the host sends it every violation and some facts, and the plugin replies with the excused violations, the stale entries, its violations, report lines and the files to write. The host applies the reply and writes the files, but only the ones the plugin returns, and the plugin returns the debt file only when the command line has `--update-debt`.

Both call the same `Debt.evaluate`: (a) as a function call, (b) from a 15-line Ruby plugin that requires the same file. So the two designs behave the same by construction, and the cases below do not choose between them. What differs is where the code sits, what the protocol must keep stable, and what a plugin can do to other plugins' violations. A debt plugin written in another language under (b) would need a copy of that 143-line library in that language.

### The step

```json
{"id":3,"method":"post_check","params":{"root":"/abs/project","config":{"rules":{"has-debt":{"withComment":true}}},"flags":["update-debt"],
  "violations":[{"id":0,"plugin":"ng-nudge-rules","rule":"spec-exists","path":"src/app/card/card.component.ts",
                 "message":"spec file missing","artifact":"component","key":"app/card/card"}],
  "ran":[["ng-nudge-rules","spec-exists","component","app/card/card"]],
  "known":[["component","app/card/card"]],
  "rules":[["ng-nudge-rules","spec-exists"]]}}
{"id":3,"result":{"excused":[0],"violations":[],"stale":[],"report":["..."],"failing":false,"writes":[]}}
```

- **Violation identity.** The host gives each violation an `id`, the `artifact` it was found on and a `key`: the artifact's path below `srcDir` (default `src`) with the role suffix dropped, so `src/app/foo/foo.service.ts` is `app/foo/foo`, as in ng-nudge. A plugin may add `detail` to a violation, such as the member name. The host rejects a violation with no string `rule` and `path` (ng-nudge bug 27).
- **`ran`** lists each rule that ran on each item: a rule that a policy chose and that is not disabled in the config, or all of a plugin's declared rules when no policy chose. **`known`** lists every item found, whether or not a policy applies. **`rules`** lists the rules of plugins that finished without a failure, plus the rules of the violations.
- **Reply.** `excused` lists violation ids that the host removes. `violations` are added (the `has-debt` ones). `report` lines go to stdout after the violations. The host exits 1 when `failing` is true, even if no violation fails. `writes` are files below the project root.
- **The step is not specific to debt.** `plugins/summary-sh` (12 lines of shell with `jq`) is a second post-check plugin that counts what is left. It runs after debt tracking under both designs and sees the list after excusing (case `two-hooks`: 10 violations left in 5 files).
- **Severity** is new in the host: a violation may carry `"severity": "warning"`, which prints `(warning)` and does not fail the run. Only `has-debt` sets it.

### Cases

`debt/check.sh` runs each case under both designs against a copy of `fixture/` plus `debt/overlay/` (a service that shares `app/card/card` with the card component, and a component that lacks three interface members). A case passes when both designs give the same output, exit status and, after `--update-debt`, the same debt file as `debt/expected/`. All 16 pass on macOS arm64.

| Case | What it shows |
| --- | --- |
| `mixed` | A debt file as ng-nudge writes it: quoted comments with a quote, a newline and a tab, a row with `\` in its key, rows excusing violations of the Ruby plugin and of the JavaScript plugin, a stale row for an artifact that has the spec, and one for a deleted artifact. Output: the excused violations are gone, two entries are reported as paid off, exit 1. |
| `mixed-update` | The same file with `--update-debt`. Kept rows stay byte for byte, the `\` row is rewritten with `/`, the two stale rows go, new rows are appended in sorted order, exit 0. |
| `snapshot`, `idempotent` | `--update-debt` with no debt file writes one; a run with that file passes with no output. |
| `more`, `detail`, `detail-update` | ng-nudge bug 7: two plain rows excuse two of the three missing members and the host reports the third; rows with a `Detail` column excuse exactly their members. |
| `shared`, `shared-update` | ng-nudge bug 5: one plain row for a key that a component and a service share excuses neither, and the host reports it as ambiguous; `--update-debt` writes one row for each artifact with the comment on both. |
| `disabled` | ng-nudge bug 11: `spec-exists` is disabled in the config, its rows are reported as not checked, not paid off, exit 0. |
| `plugin-failed-no-node` | The TypeScript plugin has no `node`: its rows are reported as not checked and the run exits 2. ng-nudge has no plugins, so it has no case for this. |
| `has-debt-true`, `has-debt-none`, `has-debt-matching` | `withComment` as `true`, as `"none"` and as `{maxSeverity: "none", matching}` with `severity: "warning"`. |
| `bad-row` | A row with no rule: exit 2 and the row number in the message. |
| `two-hooks` | Two post-check plugins in order. |

### What each design keeps of ng-nudge's debt behavior

The study's "Debt tracking" list, row by row. The behavior is the same under (a) and (b) because both call one library. Under (b), a debt plugin that does not use that library has to build every row again.

| ng-nudge behavior | Kept | Where it differs or was not tried |
| --- | --- | --- |
| A missing file means no debt | Yes (`snapshot`) | |
| Tab-separated, header `Rule`, `Artifact`, `Comment`, d3-dsv quoting, final newline | Yes | The parser gives the same fields as d3-dsv 3.0.1 on every case file and on a CRLF file, and the file written by `mixed-update` is byte for byte what d3-dsv's `tsvFormatRows` gives for its rows. The check ran once, by hand, outside `run.sh`. |
| A row's comment kept across updates, rows kept in place | Yes, and a kept row is copied as it was read, including its quoting | A row that is kept is not re-quoted; a row with `\` in its key is rewritten. |
| Empty `Rule` or `Artifact` stops the run, naming the row | Mostly (`bad-row`) | The message gives the row number as ng-nudge's does; the run still prints the violations and exits 2, where ng-nudge prints only the error. |
| A violation that matches an entry is not printed and does not fail | Yes (`mixed`) | Matching differs: see the next table. Excusing a warning was not tried, since no plugin here reports one. |
| A stale entry prints `★  Debt paid off:`, `   <artifact> no longer owes <rule>` and the instruction line, and exits 1 | Yes (`mixed`) | The instruction line is `Run --update-debt to update .config/ng-nudge/debt.tsv` (ng-nudge's line gives `npx ng-nudge --update-debt`). |
| `--update-debt` keeps matching rows, drops stale ones, appends one row per unexcused violation with an empty comment, never writes `has-debt` violations, prints `Updated <path> (N entries)` | Yes (`mixed-update`) | The path has `.tsv`. New rows are sorted. A row for a violation with a detail has a `Detail` column, which ng-nudge ignores when reading and drops when it writes. The line adds `X added, Y removed`. |
| `has-debt` with `withComment` (`true`, `"warning"`, `"none"`, `"error"`, `false`, `{maxSeverity, matching}`), base severity from `rules.has-debt.severity`, silent unless `withComment` is present, off when `enabled` is `false`, off with no entries | Yes for `true`, `"none"` and the object | `"warning"`, `"error"` and `false` run the same code path as ng-nudge's but no case uses them. `matching` is a Ruby regular expression where ng-nudge's is JavaScript's. |
| Every violation counts, whatever `--warnings` or the verbosity hides | Not tried | `--warnings`, `-q`, `-s` and `-d` are not modeled. |

### What each design does about ng-nudge's debt bugs

| Bug | How both designs handle it | Case |
| --- | --- | --- |
| 5 and 7, coarse matching: an entry excuses every violation with its rule and base path | The host excuses one violation per row. It matches a row with a `Detail` to that detail, and a plain row, as every existing ng-nudge row is, to the first violation left with its rule and key, so a violation added later is reported. When a plain row could mean violations of two artifacts, the host excuses neither and reports the row as ambiguous. Keys written for a rule that ran on two artifacts with that key carry the artifact (`app/card/card.service`), and ng-nudge reads those rows as stale. | `more`, `detail`, `shared`, `shared-update` |
| 7, one identical row per violation | A violation with a `detail` gets one row for each detail. One without gets a row for each violation, because the format has no count. | `snapshot` |
| 11, a disabled rule's entries count as paid off | An entry is stale only when its rule ran on its artifact and found nothing, or its artifact is gone. A rule that did not run, or whose plugin failed, leaves the entry alone. | `disabled`, `plugin-failed-no-node` |
| 22, a debt file does not carry between Windows and other systems | A key is read with `\` as `/`, and the host builds keys from Ruby's globbing, which uses `/`. Ran on macOS only, with a row written by hand. | `mixed` |
| 9, a `--update-debt` run reports the state before the update | The report and the exit status follow the state after: every violation is recorded, so the run exits 0 unless a `has-debt` violation fails. | `mixed-update` |
| 10, an empty file loses its header | The header is always written. Built, not run. | |
| 8, `--update-debt` with no folder prints only an error | The host creates the folder. Built, not run: every case has the folder. | |
| 27, a violation without a rule breaks every run | The host rejects it from any plugin. | `run.sh`, `plugins-broken/no-rule` |
| Unsorted order | New rows are sorted by rule, key and detail. | `snapshot` |
| 25, 29 and the rest of the study's list | Not relevant to the debt code. | |
| 30, "Updated" prints the path without `.tsv` | The line has the whole path. | `mixed-update` |

One difference from ng-nudge that no bug covers: an entry whose rule did not run because its policy no longer applies (the stub rule, after the interface file is deleted) is reported as not checked. ng-nudge reports it as paid off.

### What the designs cost and mean

| | (a) The host does it | (b) A plugin does it, through `post_check` |
| --- | --- | --- |
| Who writes the debt code | CrossLint's maintainers, once, in Ruby. | Whoever writes the debt plugin, in that plugin's language. Here, the same Ruby, with 25 more lines (15 for the plugin and 10 for the manifest). |
| Protocol that must stay stable | None for debt. `id`, `artifact`, `key`, `detail` and `severity` on violations, which a third party may use. | All of (a)'s, plus the `post_check` request (`root`, `config`, `flags`, `violations`, `ran`, `known`, `rules`), its reply, and `hooks` in the manifest. |
| What a plugin author does for debt | Nothing. Give each violation a `rule` and a `path`. For stale detection, list the rules in the manifest. For per-member debt, set `detail`. | The same. A plugin that is itself a debt plugin writes `post_check`. |
| A third-party plugin's violations | Always pass through debt, and cannot opt out. | Pass through debt when the project lists the debt plugin. |
| What else a plugin can do to violations | Nothing; only the host's code sees them. | Any post-check plugin sees every violation, in every plugin, and can excuse, add or write files. It is code that runs with the user's rights, like any plugin, so listing one is a trust decision. |
| On by default (#5, question 2) | A host feature, always there. A project with no debt file pays nothing. | The host would list the debt plugin by default, or the project lists it. A project that forgets has no debt tracking and no error. |
| Other uses of the step | None. | `summary-sh` is one; a report format, a severity override or inline suppressions are others, none built. |
| Cost at run time | None measured beyond the code. | One more process: 72 ms to start and handshake and 1 ms for the step on macOS arm64. A whole run took 0.75 s with no debt, 0.76 s under (a) and 0.74 s under (b), one run each. |
| What a command-line flag needs | The host has `--update-debt` built in. | The manifest lists it, and the host reads manifests before it parses the command line (2 lines). |

**(c) A hook in the protocol, and the debt code in the host as the default hook.** The host has both parts: `apply` takes a reply from either, and `two-hooks` runs (a)'s in-process debt tracking and a post-check plugin one after the other. What was not built is the choice between the two for debt, so a project could replace the built-in one with a plugin. That would cost (b)'s protocol surface and (a)'s code, with one place for debt's matching rules.

### Lines of code for debt tracking

Lines of code exclude blank lines and comment lines.

| Part | Lines |
| --- | --- |
| `host/debt.rb`: the TSV, matching, stale entries, update, `has-debt` | 143 |
| `host/crosslint.rb`: 291 before and 360 now | +69: about 45 for both designs (key, `ran`, `known`, `rules`, ids, `apply`, severity and the exit status, the check on a violation's shape), 10 for (a) only, 14 for (b) only |
| `plugins/debt-rb/plugin.rb` and `plugin.json`, design (b) | 15 and 10 |
| `plugins/summary-sh/plugin.sh` and `plugin.json` | 12 and 9 |
| `plugins/ng-nudge-rules-rb/plugin.json`: the four policies without `has-debt` | 45 |
| `debt/check.sh` | 41 |
| 16 cases | 16 expected outputs and 4 expected debt files; 16 case files (6 debt files, 4 flag files, 5 configs, 1 hooks file) |

### What broke

- **Qualifying every key.** An early version wrote `app/card/card.component` for every row of the card whenever a component and a service shared the base path, including `prefer-css-over-scss`, which only components have. A written key now carries the artifact only when one rule ran on two artifacts with that key.
- **The format has no room for a member name.** Bug 7 cannot be fixed inside the three columns. A fourth, optional column `Detail` carries it, which ng-nudge ignores and then drops. Without it, only a count remains (the duplicate rows).
- **The Fledge build.** `fledge/scripts/build.sh` now copies `host/debt.rb` into the app next to `main.rb`, and `fledge/app/.gitignore` lists it. Whether Fledge packs a second file of the app was not run.

### What is unproven about debt

- **A Fledge app with debt tracking.** The build change above was not run, so `--core-debt` inside an app is unverified. Design (b) in an app needs `host/debt.rb` on disk beside the plugin, which it has here only because the plugin runs from this repository.
- **Windows.** No debt case ran there. The `\` row ran only as data on macOS; `ln -s` in `debt/check.sh`, for `node_modules`, may not work under MSYS2.
- **A debt plugin in another language.** Under (b) the cost of a second implementation (143 lines of Ruby here) was not measured.
- **Rules with the same name in two plugins.** The `plugin/rule` form for a rule name that two plugins both provide is written and no case uses it.
- **A plugin with no `rules` in its manifest.** It gets excusing but no stale detection, and its entries are reported as not checked.
- **`srcDir` other than `src`,** several packages with one debt file, and keys from artifacts outside `srcDir`.
- **JavaScript regular expressions** in `withComment.matching`, which differ from Ruby's.
- **Large files:** a debt file of thousands of rows, and `known` and `ran` for a project of thousands of artifacts. The request is one line of JSON and its size was not measured.
- **Excusing a warning, `--warnings`, `-q`, `-s`,** and the short `-d`.

## Inside a Fledge app

`fledge/` builds the host (`host/crosslint.rb`, copied to `app/main.rb`) into a Fledge v0.17.0 console app, `crosslint-spike`, the way [fledge-tree-sitter](../fledge-tree-sitter/README.md) does, with no gems beyond Fledge and no Tree-sitter. `fledge/scripts/check.sh` builds it for the computer it runs on, installs the archive through mise into an empty data folder (a `file://` URL, `strip_components = 1`, `bin_path = "."`, as in [setdef/Fledge#123](https://github.com/setdef/Fledge/issues/123)), with Node 22 and `jq` 1.7 from mise beside it and every Ruby dropped from `PATH`, and then runs the whole of `run.sh` with `CROSSLINT=crosslint-spike`, so every check goes through the installed app. The Ruby plugins' manifests say `"command": "{host_ruby}"`, so they run on the Ruby the app carries.

| | macOS 27, arm64 | Linux x86_64 (Ubuntu 24.04) |
| --- | --- | --- |
| Built | yes | yes |
| Archive, installed | 26 MB `.tar.gz`, 85,464 KiB | 35 MB `.tar.gz`, 105,688 KiB |
| Ruby on `PATH` under `mise x`, outside the app | `/usr/bin/ruby` (the system's) | none |
| `{host_ruby}` | `.../bin/ruby` inside the install | `.../bin/ruby` inside the install |
| Start, first run then mean of 10 | 1.32 s, 0.12 s | 0.08 s, 0.07 s |
| `run.sh` against the app | every check passes | every check passes |

On Windows 11 x64 the app built and installed the same way (74,842 KiB installed, 0.31 s for the first run and 0.23 s for later ones, Ruby on `PATH`: none), and `run.sh` passes against it, after one change: Ruby 4.1 no longer loads `fiddle` from the standard library, so the host's job object code (see [Windows](#windows)) raised a `LoadError`, fell back to `taskkill`, and the hung plugin's child survived. Adding `gem "fiddle", platforms: [:windows]` to the app's `Gemfile` fixed it, and the gem installed without a compiler error.

What this shows:

- **All three plugins run, and the Ruby plugins run on the app's Ruby.** The Ruby plugin got no Ruby from `PATH` on Linux, and on macOS the system's `/usr/bin/ruby` is on `PATH` and was not used. The two policy plugins, the process-group check and the error paths behave as they do with plain Ruby.
- **Inside the app, `PATH` already has the app's `bin/` first,** so `ruby` there is the app's Ruby too (`--info` prints it). The host's environment (`RUBYOPT`, `BUNDLE_GEMFILE`) is passed on to plugins; the Ruby plugins use only the standard library and ran with it. A Ruby plugin that needs a gem the app lacks has the problem the [fledge-tree-sitter](../fledge-tree-sitter/README.md#project-local-ruby-rules) spike measured.
- **Node, `jq` and `typescript` still come from outside the app.** The check installs them; the app does not carry them.
- **Install time:** `mise install` of the app, Node and `jq` together took 54 s on both, almost all of it Node.
- **Fledge:** nothing new broke on these two. `fledge build` took 7 to 9 s in a workspace that already had Fledge's runtime; a build from nothing was not timed. The first attempt of `check.sh` failed because its `ls` of a `.zip` found nothing on these systems and stopped the script (fixed).

## Windows

Run on Windows 11 x64, as plain Ruby: Ruby 4.0.10 (RubyInstaller, `x64-mingw-ucrt`), Node 22.23.5 and `jq` 1.7 installed through mise, and `run.sh` run from MSYS2's `bash`. Every check passes, including the TypeScript plugin, the policies, the error paths and the check that a hung plugin's child is gone. Three plugin runtimes were involved: Ruby (`{host_ruby}`), Node, and `sh` with `jq` (MSYS2's `sh` and mise's `jq.exe`). Windows with no `sh` was not run; the PowerShell plugin is the equivalent there.

| What broke | Fix |
| --- | --- |
| The host stopped at the first plugin: `wrong exec option symbol: pgroup`. Ruby on Windows has no `pgroup:` for `spawn`. | The option is `new_pgroup: true` on Windows. |
| Every comparison with `expected/*.txt` failed. Ruby writes `\r\n` for each `\n` of `puts` on Windows. | `$stdout.binmode` in the host, so the output is the same on every system. |
| `npm --prefix DIR install` in `run.sh` ignored `DIR` and looked for `package.json` in the working directory, under MSYS2's `bash`. | `run.sh` runs `npm install` from inside `fixture/`. |
| A plugin that died made the host crash with `Errno::EPIPE` from `IO#close`. On Windows, closing the pipe to a dead process flushes into it and fails. | The host ignores `EPIPE` when it closes a plugin's stdin. |
| `taskkill /T /F /PID` ended the `sh` that the host started and left its `sleep` child running. The `sleep` is an MSYS2 process, and the process tree that `taskkill` follows did not link it to the `sh`. | A job object: the host makes one for each plugin with `Fiddle` calls to `CreateJobObjectW`, `SetInformationJobObject` (kill on close), `OpenProcess` and `AssignProcessToJobObject`, and ends it with `TerminateJobObject` on timeout, after the plugin exits, and (through kill on close) when the host exits. With the job, `run.sh`'s check passes. `taskkill` is the fallback when Fiddle cannot load. About 20 lines. |
| `Spike.which` found no `node` or `sh`: Windows executables have an extension. | The host tries each `PATHEXT` extension. |

- **As a Fledge app on Windows,** every check passes too: see [Inside a Fledge app](#inside-a-fledge-app). The app needs the `fiddle` gem for the job object.
- **A shell plugin on Windows needs `sh` and `jq`.** MSYS2's `sh` was on `PATH` for these runs. For a Windows with neither, `plugins/template-per-component-ps1/` does the shell plugin's job in PowerShell with `ConvertFrom-Json` (about 20 lines, the `powershell` command), and `run.sh` checks that it gives the shell plugin's two violations when `powershell` is on `PATH`. It passed on Windows. It is skipped on the other systems here.
- **Starting Node:** `node.exe` started without trouble. A `.cmd` shim (some mise setups on Windows put one on `PATH`) was not met; `npm` is one, and only `run.sh` calls it.
- **Not run:** Windows ARM64; a Windows with no MSYS2 (where the shell plugin is skipped, PowerShell stands in); paths with spaces or non-ASCII characters; the host running with `--provision` on Windows.

## Cost per plugin call

Measured on macOS 27 (arm64) with Ruby 4.0.10, Node 26.12.1 and `jq` through mise's shims, by `--timing`. "Start" is spawn plus handshake, and includes the `--version` call that `min_version` triggers for the Ruby and Node plugins. Ranges are two to four runs.

| Plugin | Start | First check | Later checks in the same process |
| --- | --- | --- | --- |
| Ruby | 55 to 60 ms | under 1 ms | under 1 ms |
| shell with `jq` | 69 ms (250 ms once, with a cold shim) | 38 to 42 ms | 37 to 42 ms |
| JavaScript | 52 to 60 ms (163 ms once) | 321 to 372 ms | 99 to 129 ms |

All three plugins in one host run took 0.58 s of wall time. Reusing a process (`lifetime: per-run`) saves the start cost for each later artifact, and for the JavaScript plugin it also saves most of the Node warm-up (the checks get faster because the JIT is warm, not because the plugin caches anything). The shell plugin starts `jq` per line, so its check time does not fall.

## When a runtime is missing

With `PATH` holding Ruby and the system tools but no `node`:

```console
$ ruby host/crosslint.rb --root fixture plugins/component-io-js plugins/spec-per-component-rb
crosslint: plugin component-io: runtime-missing: needs node on PATH (rerun with --provision to install node@22 with mise)
src/app/card/card.component.ts: [spec-per-component/component-has-spec] no spec at ...
$ echo $?
2
```

The host reports the plugin and the runtime by name, fails with a status that differs from "violations found", and still runs the other plugins. `run.sh` checks this, and the other errors in the table: a missing helper from `also`, a Node older than `min_version`, a plugin that crashes (status and stderr shown), prints garbage, speaks another protocol, replies with an error, or hangs. It also checks the JavaScript plugin in a project with no `typescript`. The "no node" check is skipped when `node` is in `/usr/bin` or `/bin`.

## A runtime the host provisions

`--provision` runs `mise install node@22` and then starts the plugin as `mise x node@22 -- node plugin.mjs`, when `node` is not on `PATH` and the manifest has `provision.mise`. mise's data folder was set to an empty folder for the cold run.

| Step | Time |
| --- | --- |
| Cold: `mise install node@22` (Node 22.23.5, download, checksum, extract) | 46.6 s; 187 MB of mise data and 48 MB of cache afterward |
| Warm: `mise install node@22`, already installed | 29 ms |
| Start and handshake through `mise x` | 52 to 58 ms |

The check results were the same as with Node on `PATH`. The Linux x86_64 run also installed Ruby, `jq` and Node through mise before `run.sh` started, in 47 s; that was setup for the run, not the host's provisioning.

Two things changed in the host because of the first attempt:

- The first version ran `mise x node@22 -- node ...` and let the handshake timeout (60 s) cover the install. It timed out. The host now installs in a separate step that has no timeout, then starts the plugin.
- `mise x` read the mise configuration of the user's account and tried to install the other tools it lists, as well as Node. The host now sets `MISE_NO_CONFIG=1` for provisioning. That also means a project's `mise.toml` pins do not apply to the plugin's runtime. Whether they should is open.

The project's `typescript` is still read from the project's `node_modules`, so provisioning Node does not provision the compiler.

## Where it ran

| Platform | Result |
| --- | --- |
| macOS 27.2.1, arm64 | `run.sh` passes. Provisioning run here. |
| Linux x86_64 (Ruby 4.0.10, Node 22.23.5, `jq` 1.7 from mise) | `run.sh` passes, including the no-Node check. |
| Windows 11 x64 (Ruby 4.0.10, Node 22.23.5, `jq` 1.7 from mise; MSYS2's `bash` and `sh`) | `run.sh` passes, including the PowerShell plugin and the no-Node check. |
| macOS arm64, Linux x86_64 and Windows x64, in a Fledge app | `fledge/scripts/check.sh` passes on each: built, installed through mise, `run.sh` against the app. This was before debt tracking; the debt cases and the check on a violation's shape ran on macOS arm64 only. |

## What broke

- **The provisioning timeout and the user's mise configuration,** above.
- **The host killed only the process it started.** The `hang` plugin is `sh` running `sleep 30`; after the host's `KILL` on timeout, the `sleep` kept running (on Linux until the run's end; on macOS the rerun found it alive after the host exited). The host now starts each plugin in a separate process group (`pgroup: true`) and, on a timeout, sends `KILL` to the whole group (`Process.kill("KILL", -pid)`). It also sweeps the group after every plugin exit and at host exit, so a plugin that exits and leaves a child behind is covered too. `run.sh` has the `hang` plugin write its child's pid to a file and checks that the child is gone after the timeout. On Windows the host puts each plugin in a job object instead, see [Windows](#windows).
- **A test for "no node" on this Mac passed for the wrong reason at first,** because Homebrew's directory was on the `PATH` I built, and it holds a `node`. `run.sh` now builds the `PATH` from Ruby's folder plus `/usr/bin:/bin` and skips the check when those hold a `node`.
- **Shell and JSON.** The shell plugin needs `jq`, which the manifest lists in `also`. Without a JSON tool, a shell plugin would have to parse the host's line by hand.

## Unproven

- **Policies that need code,** as above: an `applies` that tests more than paths, companions, line counts and config.
- **Debt tracking:** what is left is listed under [Debt tracking](#what-is-unproven-about-debt).
- **Severity,** and the rest of ng-nudge's per-rule configuration, as above.
- **Rules that need facts about other artifacts or other files.** The plugin gets paths and which companions exist. A plugin that needs more reads the files itself, as the JavaScript plugin does; whether the host should pass file contents, or answer queries during a check, was not tried.
- **A Ruby plugin that needs a gem the app lacks,** in an app. The plugins here use only the standard library; the [fledge-tree-sitter](../fledge-tree-sitter/README.md#project-local-ruby-rules) spike has the measurements for loading gems.
- **Windows beyond what ran:** a machine with no MSYS2 (the PowerShell plugin stands in for the shell plugin there, and it ran only from MSYS2's `bash`), `.cmd` shims for Node, paths with spaces, and ARM64.
- **Fledge apps on other platforms:** Linux `aarch64` and musl, Windows ARM64, and an app installed from a GitHub release over the network (mise installed from a `file://` URL).
- **Plugin distribution and trust.** The spike runs plugin folders passed on the command line. How plugins reach a project (a gem, an npm package, a folder in the repository, a download) is not part of it, and a plugin is arbitrary code that runs with the user's rights.
- **A long-running plugin that keeps state.** `per-run` reuses a process, but no plugin caches its TypeScript program between checks, so the saving a persistent JavaScript plugin could give beyond Node's warm-up is unmeasured.
- **Runs in parallel, output size and streaming.** Plugins run one after another. Each request and response is one line; the largest here is a few hundred bytes. A plugin that writes to stdout outside the protocol breaks the line reading.
- **Other TypeScript versions.** The JavaScript plugin ran against `typescript` 6.0.3 only.
- **Provisioning other runtimes** (Ruby, Python, a downloaded binary). Only `node@22` through mise ran, and mise's `MISE_NO_CONFIG` behavior comes from one version (2026.11).
- **Rules that a project writes.** The plan says project owners can always write artifacts, policies and rules. Whether a project-local rule is a plugin folder in the repository, or Ruby loaded into the host as in the [fledge-tree-sitter](../fledge-tree-sitter/README.md) spike, is not decided by this spike.
