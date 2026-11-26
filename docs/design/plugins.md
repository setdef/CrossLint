# Plugins

What loading and running a plugin must guarantee, and the traps known so far. The decision these rest on is [ADR 0001](../decisions/0001-crosslint-is-ruby-and-a-plugin-may-read-files-in-their-language.md). What a plugin can declare is in [the plugin reference](../reference/plugin.md); how to meet each requirement is the implementer's choice.

## The engine and its plugins

- **The engine has no role, language, or policy built in.** It loads the configuration and the plugins, finds each artifact's files, applies policies, runs rules, applies each policy's severity and the configuration's settings, prints the report, and sets the exit status. Angular and debt tracking are plugins like any other, and a project that lists neither runs without them.
- **What debt tracking needs, any plugin can have:** a step after every rule has run that sees every violation and can excuse some, add others, and report stale entries; a flag (`--update-debt`); and settings under its name in the configuration. What the Angular plugin needs, any plugin can have too: Ruby that declares its artifacts from its settings, and a key for each artifact that debt entries can name. No plugin reaches the engine any other way.
- **A local plugin, a shared plugin, and a built-in one are loaded the same way,** from a folder with a `plugin.kdl`. A built-in plugin's folder ships inside CrossLint. The Angular plugin lives in this repository in one folder, and nothing outside that folder depends on its contents, so it can move to a separate repository later.

## Ruby rules

- A rule written in Ruby runs on the Ruby CrossLint carries, so a project needs no Ruby. It can require Ruby's standard library and files in its plugin's folder.
- **A gem CrossLint wasn't built with can't be loaded,** and requiring one stops the plugin with a message naming the gem, not a Ruby `LoadError`. `bundler/inline` would install a gem into CrossLint's install folder at run time, so CrossLint must not offer it.
- A rule that raises an exception is reported as a fault in its plugin, naming the plugin, the rule, and the artifact, with the trace under `--debug`. The other plugins still run, and the check exits with 2.
- **A rule that runs for 60 seconds on one artifact is a fault,** and so is one that recurses until Ruby raises `SystemStackError`; neither may hang the check or end it for the other plugins.
- **Files a rule requires load into one Ruby,** so two plugins whose required files define the same top-level constant collide. A rule keeps its constants inside its class.

## Helpers

- A helper runs on the project's runtime for its language, found on the `PATH`, and its plugin declares which command it needs. A command not on the `PATH` stops CrossLint with exit status 2 before any check starts, naming the plugin and the command.
- **On Windows, find the command with each extension in `PATHEXT`,** since `node` is `node.exe` or `node.cmd` there.
- Requests and responses are JSON on the helper's standard input and output, one per line. Its standard error goes to CrossLint's standard error under `--debug`, and to its message when it fails.
- **A helper that gives no answer for 60 seconds is ended, with everything it started.** Ending only the helper's process leaves its children running: on macOS and Linux, start it in a new process group and end the group; on Windows, put it in a job object. On Windows, `taskkill /T` alone leaves an MSYS2 child running.
- **At the end of a check, end every helper at once.** Close each helper's input, give each 2 seconds to exit, then end its process tree; helpers are ended in parallel, so one slow helper doesn't hold up the rest. On Ctrl-C, end every helper's tree without waiting.
- **A helper CrossLint can't put in its process group or job object is ended at once, and is a fault,** never left running. On Windows, check every call that creates the job object and assigns the helper to it.
- **A helper runs with the environment CrossLint was started with,** not the one the app sets up for the Ruby it carries, so `RUBYOPT`, `BUNDLE_*`, and the app's folders on `PATH` never reach it; a helper that runs `ruby` gets the project's Ruby, not CrossLint's.
- **On Windows, write to a helper in binary mode,** or Ruby turns each `\n` into `\r\n`; and a helper that has already exited makes closing its input raise `EPIPE`, which is not an error of the check.
- The Angular plugin's helper asks the project's `typescript` package, from its `node_modules`, so its answers match the project's compiler version.

## Shared plugins

- **A shared plugin is fetched at its ref,** a tag or a full 40-character commit SHA, never a branch, and only that commit is fetched. A ref that names a branch and no tag, or a SHA the repository doesn't have, stops CrossLint with exit status 2, naming the plugin and the URL. Git does the fetching, and reads `HTTPS_PROXY`, `HTTP_PROXY`, and `NO_PROXY` itself. CrossLint runs Git with `protocol.allow=never`, `protocol.https.allow=always`, and `protocol.file.allow=always`, so a Git setting such as `url.*.insteadOf` can't turn a fetch into `ssh`, `git`, `http`, or `ext`.
- **A shared plugin's URL with a user name or password,** such as `https://user:token@host/...`, is a mistake, with exit status 2: the secret would sit in the configuration and on standard error. The message says to give Git the credentials with a Git credential helper.
- **The copy goes in the user's cache, outside the project,** in `$XDG_CACHE_HOME/crosslint/plugins`, or `~/.cache/crosslint/plugins` when `XDG_CACHE_HOME` isn't an absolute path, or `%LOCALAPPDATA%\crosslint\cache\plugins` on Windows. It is fetched into a folder of its own and renamed into place, so an interrupted fetch leaves no partial copy. Each fetch removes the cache's `.fetching-*` folders that are an hour old or more, which a fetch ended outright left behind. Later checks use the copy and make no request, even after the tag moves upstream, until `crosslint update` changes the configuration.
- **Print a line on standard error before every network request,** `crosslint: fetching URL at REF` or `crosslint: listing the tags of URL`, and make none during a check otherwise.
- **A fetch or a listing of tags that takes more than 60 seconds is ended,** with everything it started, and stops CrossLint with exit status 2.
- A plugin that can't be fetched stops CrossLint with exit status 2, naming the plugin and the URL; it never runs the check without it.

## Known limits

- **A plugin is trusted code.** CrossLint refuses a gem it wasn't built with when a rule requires it, but it doesn't sandbox a plugin: a plugin written to get around the refusal can load code another way, and can do anything the user running CrossLint can. List only plugins you would run as a script.
- **A process can escape being ended.** On Windows, a helper joins its job object just after it starts, so a process it starts in that instant isn't in the job. On macOS and Linux, a process that leaves the helper's process group, such as one that calls `setsid`, isn't in the group CrossLint ends. CrossLint stops waiting for such a process, and it keeps running.
- **The user's Git configuration still applies to a fetch,** so a `url.*.insteadOf` setting can send it to another https address, or to a folder on the computer, than the one CrossLint prints.
- **A shared plugin's submodules aren't fetched,** so a plugin that keeps files in a submodule can't use them.
