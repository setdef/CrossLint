---
status: proposed
date: 2026-11-26
deciders: the agent acting as CrossLint's architect chose the structure, within ADR 0005
---

# The engine is a core of plain Ruby objects, and everything it reaches is an adapter behind a port

## Context and Problem Statement

CrossLint reads a configuration and plugin manifests in KDL and a debt file in TSV, asks Git which files the working tree has, runs Ruby rules and helpers in other languages, and reports to a terminal or as JSON, as `check`, `init`, and `update`. Its rules about artifacts, policies, violations, and debt stay the same whichever format, filesystem, or output they meet, and ADR 0005 makes the Angular checks and debt tracking plugins of an engine with no role, language, or policy built in. How should the code be divided, so the rules can be tested and changed apart from the formats and systems around them?

## Decision Drivers

* The engine has no role, language, or policy built in (ADR 0005).
* Each requirement in `docs/design/` becomes a test, and a test touches a file, a process, or the network only when its requirement is about one.
* A format can change, such as CrossLint's debt format beside ng-nudge's, without touching the rules.

## Considered Options

1. A core of value objects and use cases in plain Ruby, reaching everything outside through ports declared as RBS interfaces, with adapters behind them and one composition root.
2. One layer of command classes, each reading files and printing as it goes.
3. A dependency-injection framework, such as dry-system, holding every part.

## Decision Outcome

Chosen: option 1.

- **The core** holds the domain as immutable value objects, each `class X < Data.define(...)`, and one use case per command. It requires Ruby's core and standard library and nothing else.
- **Ports** are RBS interfaces in `sig/`, named for what the core needs, such as `_ProjectFiles` or `_DebtFiles`. Ruby checks nothing about them; Steep checks each adapter's methods against them, and RBS's runtime checker checks every call during the tests.
- **Adapters** implement the ports: KDL, TSV, Git and the filesystem, subprocesses, text and JSON. An in-memory adapter of each port ships with CrossLint, and every adapter of a port, the in-memory one included, passes the same contract tests.
- **The command line is an adapter too,** and **one composition root** builds the adapters and hands them to the use case the command line chose.

Option 2 lost because a command class that reads files and prints can only be tested through files and output, and each command that needs the debt rules would hold another copy of them. Option 3 lost because a framework that holds every part becomes one more thing the core depends on, for a program whose parts fit in one composition root.

How the parts fit is in `docs/design/architecture.md`.

Confidence: the deciding agent's judgment alone; no comparison was recorded. The structure works as described: the use cases' tests run against the in-memory adapters, and each port's adapters pass the same contract tests, in `lib/cross_lint/testing.rb`. Nothing yet shows it pays off against options 2 and 3.

### Consequences

* Good, because the use cases can be tested against the in-memory adapters, without files or processes.
* Good, because a new adapter for a port, such as another debt format, is correct when it passes the port's contract tests.
* Good, because the Angular plugin and the debt plugin reach the engine through the same ports any plugin uses.
* Bad, because each new thing the engine reaches needs an RBS interface, an adapter, an in-memory adapter, and contract tests, four places to change where one class would do.
* Bad, because a contributor has to know which part a change belongs in before making it.

### Confirmation

Steep checks every adapter against its port. A test loads the core with nothing outside Ruby's standard library and fails when the core requires an adapter or a gem.

## More Information

Revisit a port that has had one adapter besides the in-memory one for a year, since it may not be earning its place.
