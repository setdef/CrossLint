# Design documents

These documents specify CrossLint: what it replaces, how its plugins are shaped, and how its command line behaves. Each is a requirement that later designs are checked against. What waits on the choice of language, [#4](https://github.com/setdef/CrossLint/issues/4), is marked "waits on #4" in the document it affects. Report a mistake in any of them as an issue in this repository.

## Reading order

The documents build on one another, so read them in this order:

1. [plugins.md](plugins.md) specifies artifacts, policies and rules, what a plugin supplies, how a project writes them for itself, which plugins run, and how rules are named and configured. It defines the terms the other two use.
2. [ng-nudge-compatibility.md](ng-nudge-compatibility.md) specifies what CrossLint keeps from ng-nudge, the bugs it doesn't keep, and the steps a project takes to migrate. It uses plugins.md's terms.
3. [command-line.md](command-line.md) specifies flags, output, streams, exit codes, configuration and environment, and how each conflict between a command-line guideline and ng-nudge's behavior is settled. It cites the requirements in ng-nudge-compatibility.md.

## Where to start

- To write a plugin, read plugins.md.
- To migrate a project from ng-nudge, read ng-nudge-compatibility.md, then the conflicts table in command-line.md.
- To write a script that runs CrossLint, read command-line.md.
