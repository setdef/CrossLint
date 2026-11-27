# CrossLint's documentation

Where to start depends on what you're doing:

- **New to CrossLint?** Work through [Getting started](getting-started.md). In about 15 minutes, it adds CrossLint to a project, writes one rule, and keeps the check passing with debt.
- **Adding a check to a project?** The [cookbook](cookbook/README.md) has one recipe per check, each with a plugin to copy and what it reports, such as [every Rails route has its action](cookbook/rails-routes.md) and [Vue components scope their styles](cookbook/scoped-vue-styles.md).
- **Moving from ng-nudge?** Read [Moving from ng-nudge](../README.md#moving-from-ng-nudge) in the README.
- **Looking something up?** The references list everything:
  - [Command reference](reference/cli.md): every command, flag, and exit status, generated from [`crosslint.usage.kdl`](../crosslint.usage.kdl).
  - [Configuration reference](reference/configuration.md): everything `.config/crosslint/config.kdl` can hold, including the built-in plugins' settings.
  - [Plugin reference](reference/plugin.md): everything a `plugin.kdl` can declare, including rules in Ruby and helpers.
  - [Glossary](glossary.md): the words CrossLint's checking is made of, and the words it avoids.
  - [Glossary for plugin authors](reference/plugin-glossary.md): the words for writing a plugin.
  - The [debt plugin's](../plugins/debt/glossary.md) and the [Angular plugin's](../plugins/angular/glossary.md) glossaries: the words only those plugins use.
- **Working on CrossLint itself?** Read [CONTRIBUTING.md](../CONTRIBUTING.md), then the [design pages](design/README.md), which say how each part works and why, and the [decision log](decisions/), which says why it's built the way it is.

To report a mistake in any page, [post on the forum](https://forum.setdef.com/c/crosslint) naming the page.
