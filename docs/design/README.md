# Design

What each part of CrossLint must guarantee, and the traps known so far. These pages say what must hold and why, not how to build it. The behavior people see is in [the README](../../README.md) and the [references](../reference/); the decisions these pages rest on are in [the decision log](../decisions/).

- [Architecture](architecture.md): the core, its ports and adapters, the command line, the composition root, and what each may depend on.
- [Checking](checking.md): finding the project and its files, running plugins, and output and exit status.
- [Plugins](plugins.md): the engine and its plugins, rules in Ruby, helpers in other languages, and shared plugins.
- [Debt](debt.md): the debt file's format, matching violations to entries, and updating.
- [Replacing ng-nudge](ng-nudge.md): what must carry over from ng-nudge, and its defects CrossLint doesn't copy.

To report a mistake in any of these pages, [open an issue](https://github.com/setdef/CrossLint/issues).
