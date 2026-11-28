# Plugins

How CrossLint loads and runs plugins, and why each is done the way it is. The decisions these rest on are [ADR 0005](../decisions/0005-crosslint-is-ruby-and-a-plugins-code-may-be-in-any-language.md) and [ADR 0006](../decisions/0006-a-plugin-reaches-the-engine-only-through-what-its-manifest-declares.md). What a plugin can declare is in [the plugin reference](../reference/plugin.md), and how a project lists one is in [the configuration reference](../reference/configuration.md#plugin).

## The engine and its plugins

- **The engine has no role, language, or policy built in.** It loads the configuration and the plugins, finds each artifact and its pieces, applies policies, runs rules, applies severities and settings, prints the report, and sets the exit status. Angular and debt tracking are plugins like any other, and a project that lists neither runs without them.
- **The built-in plugins use only what any plugin can.** Debt tracking needs a step that sees every violation after the rules have run, a command under its name, and settings; the Angular plugin needs a helper that declares its artifacts from its settings and runs its rules, and a key for each artifact that a debt entry can hold. Each is a kind of line in `plugin.kdl`, so a shared plugin can have the same reach, and the surface is used before strangers rely on it.
- **A local plugin, a shared plugin, and a built-in one load the same way,** from a folder with a `plugin.kdl`. A built-in plugin's folder ships inside CrossLint. Nothing outside `plugins/angular/` depends on what's inside it, so it can move to a repository of its own.

## Plugin commands

- **A plugin's commands are under its name,** as `crosslint debt update`, so the plugin's name keeps them apart from CrossLint's commands and from other plugins', and no plugin adds a flag to CrossLint's commands: `crosslint check` takes the same flags in every project, and a script that runs it doesn't break when a project lists another plugin.
- **A command runs the check and then tells the plugin's step its name and its command flags,** and the step does the work. A command is therefore a way to ask a step for something, not code the plugin brings; a shared plugin can't bring a step CrossLint doesn't have (ADR 0006).
- **CrossLint keeps names for commands it may add,** and refuses a plugin that has commands and one of those names, so a command CrossLint adds later never takes over a plugin's. A built-in plugin's name is refused for any other plugin, so `debt` always means CrossLint's debt plugin.
- **The first word on the line is settled before any plugin is loaded or fetched,** from CrossLint's commands and the names the configuration lists; a shared plugin's name comes from its URL. Only a word that names a shared plugin not fetched yet fetches it, so a typo never reaches the network.
- **Help never fails.** Asking for help reads only what is on disk, never fetches, and shows what it can when the configuration can't be read, because help is what someone reaches for when something is wrong.

## Helpers a program runs

- **A helper whose command is a program reads files of its language with that language's tools,** on the project's runtime, found on the `PATH`, so it runs with the versions the project has. The Angular plugin's helper runs on the project's Node and reads TypeScript with the ts-morph the plugin carries, which carries TypeScript 6.0, so a project installs no package for it. On Windows, the command is found with each extension in `PATHEXT`, since `node` is `node.exe` or `node.cmd` there.
- **A helper gets the environment CrossLint was started with,** not the one the app sets up for the Ruby it carries, so `RUBYOPT`, `BUNDLE_*`, and the app's folders on `PATH` never reach it, and a helper that runs `ruby` gets the project's Ruby.
- **Ending a helper ends everything it started.** Ending only its process leaves its children running, so on macOS and Linux it starts in a process group of its own, and on Windows in a job object; `taskkill /T` alone leaves an MSYS2 child running. A helper CrossLint can't contain is ended at once, never left running, which is why every call that sets up the job object is checked.
- **Helpers end in parallel** at the end of a check, so one slow helper doesn't hold up the rest.
- **On Windows, a helper is written to in binary mode,** or Ruby turns each `\n` into `\r\n`, and a helper that has already exited makes closing its input raise `EPIPE`, which isn't an error of the check.

## Helpers on CrossLint's Ruby

- **A helper on `command=(crosslint)"ruby"` runs inside CrossLint's process,** on the Ruby CrossLint carries, so a project needs no Ruby, and its rules keep what CrossLint guarantees about files (exact names, ignored files left out, links out of the project refused), a trace for each fault, and a time limit for each artifact. `(crosslint)` marks the runtime in the same notation as any other command, so a plugin author writes every helper one way, but CrossLint starts no program for it.
- **A gem CrossLint wasn't built with can't be loaded,** and `bundler/inline` is refused: it would install gems into CrossLint's install folder at run time, which may not be writable and is shared by every project.
- **One plugin's fault never stops the others.** A rule that raises, runs too long on one artifact, or recurses until Ruby raises `SystemStackError` is a fault in its plugin; the other plugins still run, and the check exits with 2.
- **Files a rule requires load into one Ruby,** so two plugins whose files define the same top-level constant collide. A rule keeps its constants inside its class.

## Shared plugins

- **A shared plugin is fetched at a tag or a full commit SHA, never a branch,** so its version changes only when the configuration does. Git does the fetching, so proxies and credential helpers work as they do for the user's Git.
- **Git may use only `https` and `file`.** A Git setting such as `url.*.insteadOf` could otherwise turn a fetch into `ssh`, `git`, `http`, or `ext`, which runs a command.
- **A URL with a user name or password is refused,** since the secret would sit in the configuration and on standard error.
- **One commit is fetched once,** for each URL and ref, whichever of its folders the configuration lists with `path=`, so listing several plugins of one repository costs one fetch.
- **The copy goes in the user's cache, outside the project,** fetched into a folder of its own and renamed into place, so an interrupted fetch leaves no partial copy; a later fetch removes what an interrupted one left. Git lists tags from a folder of the cache too, so the project's own Git configuration never applies to a fetch.
- **`crosslint update` reads a tag's `crosslint min=` line by fetching the tag,** the highest it would move to first, and stops at the first one this CrossLint reads. A plugin that doesn't move costs no fetch, a plugin that moves costs the fetch of each tag it tries, two requests each (the tag's lookup and the fetch), and the tag it moves to is then in the cache, so the check that follows makes no request for it: in the usual case, where the newest tag reads, update and the check make the requests they made before, in another order. The line that lists the newer incompatible tags says that `--latest` moves to the highest one, or to the newest tag below it that this CrossLint reads, and doesn't fetch the tag to learn which: that would cost two requests for each plugin that has such a tag, even one that doesn't move. Fetching only `plugin.kdl`, with a partial clone, lost because the check fetches the whole tag right after, and fetching the file would be one more request. A search that halves the tags lost because a later tag may need an older CrossLint than an earlier one, and a halving search could then pass over the newest tag this CrossLint reads. A minimum in each tag's name lost because it would add a rule to how authors tag.
- **Later checks use the copy and make no request,** even after a tag moves upstream, until `crosslint update` changes the configuration. CrossLint says so on standard error before every network request, so a check is never silent while it waits on the network, and a fetch that takes too long is ended rather than waited on.

## Known limits

- **A plugin is trusted code.** CrossLint refuses a gem it wasn't built with when a rule requires it, but it doesn't sandbox a plugin: a plugin written to get around the refusal can load code another way, and can do anything the user running CrossLint can. List only plugins you would run as a script.
- **A process can escape being ended.** On Windows, a helper joins its job object just after it starts, so a process it starts in that instant isn't in the job. On macOS and Linux, a process that leaves the helper's process group, such as one that calls `setsid`, isn't in the group CrossLint ends. CrossLint stops waiting for such a process, and it keeps running. On Windows, a helper that exits before it joins the job counts as finished; its process ID can then pass to another process, so CrossLint leaves alone a process created after it started the helper.
- **The user's Git configuration still applies to a fetch,** so a `url.*.insteadOf` setting can send it to another https address, or to a folder on the computer, than the one CrossLint prints.
- **A shared plugin's submodules aren't fetched,** so a plugin that keeps files in a submodule can't use them.
