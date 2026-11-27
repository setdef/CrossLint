# CrossLint's documentation

Where to start depends on what you're doing:

- **New to CrossLint?** Work through [Getting started](getting-started.md). In about 15 minutes, it adds CrossLint to a project, writes one rule, and keeps the check passing with debt.
- **Moving from ng-nudge?** Read [Moving from ng-nudge](../README.md#moving-from-ng-nudge) in the README.
- **Looking something up?** The references list everything:
  - [Command reference](reference/cli.md): every command, flag, and exit status, generated from [`crosslint.usage.kdl`](../crosslint.usage.kdl).
  - [Configuration reference](reference/configuration.md): everything `.config/crosslint/config.kdl` can hold, including the built-in plugins' settings.
  - [Plugin reference](reference/plugin.md): everything a `plugin.kdl` can declare, including rules in Ruby and helpers.
  - [Glossary](glossary.md): the word CrossLint uses for each idea, and the words it avoids.
- **Working on CrossLint itself?** Read [CONTRIBUTING.md](../CONTRIBUTING.md), then the [design pages](design/README.md), which say how each part works and why, and the [decision log](decisions/), which says why it's built the way it is.

To report a mistake in any page, [open an issue](https://github.com/setdef/CrossLint/issues) naming the page.
