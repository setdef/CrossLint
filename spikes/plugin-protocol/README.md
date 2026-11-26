<!--
  SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->
# Plugins as separate programs

A spike for [issue #4](https://github.com/setdef/CrossLint/issues/4). It is evidence, not CrossLint's design, and it makes none of #4's decisions.

## Question

The prior art on #4 (protoc plugins, go-plugin, Danger's `--process`, LSP, pre-commit) suggests an option #4 lacks. CrossLint is a Ruby host. A plugin is a separate program, in any language, that talks to the host over stdin and stdout in JSON. The host tells the plugin which files match its artifacts and passes the facts it already has (paths, which companion files exist). The plugin replies with violations. A Rubyist writes a plugin in Ruby and a JavaScript developer in JavaScript. Does that work?

## Result

It works for path-relation rules and for a rule that reads TypeScript, with three plugins in three languages (Ruby, JavaScript, shell with `jq`) against one fixture project. The same results came out on macOS (arm64) and Linux (x86_64). The host reports a missing runtime by plugin and runtime name, exits 2, and still runs the other plugins. Provisioning a plugin's runtime with `mise` worked; a cold install of Node took 47 s here. A Fledge-built app and Windows were not run.

## Rerun

```console
$ bash run.sh
```

Needs Ruby 3.2 or later, Node 20 or later, `jq`, and network access on the first run (it installs `typescript` 6.0.3 into `fixture/`). It prints `ok` or `FAIL` per check and exits 0 when every result matches `expected/violations.txt` and every error path gives its expected message. `TIMING=1 bash run.sh` also prints per-plugin timings. Run the host by hand:

```console
$ ruby host/crosslint.rb --root fixture --timing plugins/spec-per-component-rb plugins/template-per-component-sh plugins/component-io-js
```

Options: `--provision` (install a missing runtime with mise, see below), `--timing`, `--repeat N` (send the same check N times to one process), `--lifetime per-check|per-run`.

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
- `artifacts`: each has a `name`, a glob `match` relative to the project root, and `companions`, a map from a name to a path template. `{dir}` is the matched file's folder and `{base}` its file name up to the first dot.

### Messages

Handshake, always first:

```json
{"id":1,"method":"handshake","params":{"protocol":1,"host":"crosslint-spike"}}
{"id":1,"result":{"protocol":1,"name":"component-io"}}
```

Check, once per artifact. The host expands the glob and the companion templates, and tests which companions exist, so the plugin starts with those facts:

```json
{"id":2,"method":"check","params":{"root":"/abs/project","artifact":"component","items":[
  {"path":"src/app/card/card.component.ts",
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
| `bad-response` | wrong `id`, or neither `result` nor `error` |
| `timeout` | no answer within `timeout` seconds (default 60); the host kills the process |

Any other code comes from the plugin. The JavaScript plugin uses `dependency-missing` when the project has no installed `typescript`, and the host passes it through.

## What was built

| Part | Lines of code |
| --- | --- |
| `host/crosslint.rb`, the host | 161 |
| `plugins/spec-per-component-rb/plugin.rb`, every component has a spec | 15 |
| `plugins/template-per-component-sh/plugin.sh`, every component has an HTML template | 13 |
| `plugins/component-io-js/plugin.mjs`, a component's inputs and outputs, inherited ones included, appear in its interface file | 75 |
| three manifests | 13, 13, 18 |
| `run.sh`, the checks | 54 |

Lines of code exclude blank lines and comment lines, except for the manifests and `run.sh`, which are line counts. The three plugins check one `component` artifact each, so a plugin could carry several rules. The fixture (`fixture/`) has four Angular-style components, written to trigger a violation from each plugin: `card` and `footer` lack a spec, `footer` and `list` lack a template, `card` lacks `expanded` in its interface, `list` lacks the input `inheritedSignal` that it inherits through an import, and `footer` has no interface file.

The JavaScript plugin is the reading of one component from [`spikes/ts-from-ruby/approach_b/helper.mjs`](../ts-from-ruby/approach_b/helper.mjs): the compiler's `getBaseTypes` finds the base class, and `input()`, `output()`, `@Input` and `@Output` members with initializers count, as in ng-nudge. It loads the `typescript` that the project has installed with `createRequire` from the project root. It rebuilds the TypeScript program on every check.

The Ruby plugin has no TypeScript parser and no file system access. The host's facts are enough for a path-relation rule. The shell plugin parses JSON with `jq`, which is the practical way to write one.

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

The check results were the same as with Node on `PATH`. The cold install also happened in the Linux run, where the build machine installed Ruby, `jq` and Node through mise in 47 s before `run.sh` started; that was setup for the run, not the host's provisioning.

Two things changed in the host because of the first attempt:

- The first version ran `mise x node@22 -- node ...` and let the handshake timeout (60 s) cover the install. It timed out. The host now installs in a separate step that has no timeout, then starts the plugin.
- `mise x` read the mise configuration of the user's account and tried to install the other tools it lists, as well as Node. The host now sets `MISE_NO_CONFIG=1` for provisioning. That also means a project's `mise.toml` pins do not apply to the plugin's runtime. Whether they should is open.

The project's `typescript` is still read from the project's `node_modules`, so provisioning Node does not provision the compiler.

## Where it ran

| Platform | Result |
| --- | --- |
| macOS 27.2.1, arm64 | `run.sh` passes. Provisioning run here. |
| Linux x86_64 (a build machine; Ruby 4.0.10, Node 22.23.5, `jq` 1.7 from mise) | `run.sh` passes, including the no-Node check. |
| In a Fledge-built app | Not run. It needs a Fledge build of the host (the [fledge-tree-sitter](../fledge-tree-sitter/README.md) spike's script is the starting point). |
| Windows | Not run. |

## What broke

- **The provisioning timeout and the user's mise configuration,** above.
- **The host kills only the process it started.** The `hang` plugin is `sh` running `sleep 30`; after the host's `KILL`, the `sleep` kept running until the build machine's run ended it ("ended 1 process the command left running"). A plugin that starts children needs the host to kill the process group, which the spike does not do.
- **A test for "no node" on this Mac passed for the wrong reason at first,** because Homebrew's directory was on the `PATH` I built, and it holds a `node`. `run.sh` now builds the `PATH` from Ruby's folder plus `/usr/bin:/bin` and skips the check when those hold a `node`.
- **Shell and JSON.** The shell plugin needs `jq`, which the manifest lists in `also`. Without a JSON tool, a shell plugin would have to parse the host's line by hand.

## Unproven

- **Policies.** The protocol carries artifacts (a glob and companions) and rules (the `check` result). Nothing in it says when a rule applies, so a policy has no place yet.
- **Rules that need facts about other artifacts or other files.** The plugin gets paths and which companions exist. A plugin that needs more reads the files itself, as the JavaScript plugin does; whether the host should pass file contents, or answer queries during a check, was not tried.
- **Whether a Fledge app carries the Ruby that `{host_ruby}` points to, and what a Ruby plugin's `ruby` finds there.** In a Fledge app no Ruby is on `PATH`, so a manifest with `"command": "ruby"` would find a project's Ruby or none. `{host_ruby}` is implemented but never run inside an app.
- **Windows.** Starting `sh`, `.cmd` shims for Node and path separators in the manifests were not tried.
- **Plugin distribution and trust.** The spike runs plugin folders passed on the command line. How plugins reach a project (a gem, an npm package, a folder in the repository, a download) is not part of it, and a plugin is arbitrary code that runs with the user's rights.
- **A long-running plugin that keeps state.** `per-run` reuses a process, but no plugin caches its TypeScript program between checks, so the saving a persistent JavaScript plugin could give beyond Node's warm-up is unmeasured.
- **Runs in parallel, output size and streaming.** Plugins run one after another. Each request and response is one line; the largest here is a few hundred bytes. A plugin that writes to stdout outside the protocol breaks the line reading.
- **Other TypeScript versions.** The JavaScript plugin ran against `typescript` 6.0.3 only.
- **Provisioning other runtimes** (Ruby, Python, a downloaded binary). Only `node@22` through mise ran, and mise's `MISE_NO_CONFIG` behavior comes from one version (2026.11).
- **Rules that a project writes.** The plan says project owners can always write artifacts, policies and rules. Whether a project-local rule is a plugin folder in the repository, or Ruby loaded into the host as in the [fledge-tree-sitter](../fledge-tree-sitter/README.md) spike, is not decided by this spike.
