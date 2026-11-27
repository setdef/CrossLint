---
status: proposed
date: 2026-11-27
deciders: setdef's maintainer chose that a plugin adds commands under the plugin's name, in #20; the agent acting as CrossLint's architect chose the rest of the surface, within ADR 0005
---

# A plugin reaches the engine only through what its manifest declares, and adds commands under the plugin's name

## Context and Problem Statement

ADR 0005 gives CrossLint an engine with no role, language, or policy built in: Angular and debt tracking are plugins, and a project that lists neither runs without them. Each needs more of the engine than artifacts, policies, and rules. Debt tracking sees every violation after the rules have run, keeps settings, and rewrites its file when asked. The Angular plugin finds its artifacts where its settings say, and gives each the key ng-nudge's debt files use. Shared plugins, which anyone can publish, need the same reach. How does a plugin get that reach, so the engine and its command line stay free of any one plugin, and so a plugin can't change what CrossLint's own commands mean?

## Decision Drivers

* The engine has no role, language, or policy built in (ADR 0005).
* CrossLint's command line is the same in every project: its commands and flags, and what `--help` lists for them, don't depend on which plugins a project lists.
* A plugin's additions can't collide with CrossLint's commands and flags, with another plugin's, or with ones CrossLint adds later.
* The debt plugin and the Angular plugin use only what any plugin, a shared one included, can use.

## Considered Options

1. **A manifest declares every way a plugin reaches the engine:** a step built into CrossLint, by name; the settings the plugin takes; artifacts that one of the plugin's helpers declares from those settings, each with an optional key for debt entries; and commands under the plugin's own name, such as `crosslint debt update`.
2. As option 1, but a plugin adds flags to `crosslint check` in place of commands, such as `crosslint check --update-debt`.
3. As option 1, but the engine owns `--update-debt` and passes it to whichever step asks.
4. Debt tracking is part of the engine, and only the Angular plugin is a plugin.

## Decision Outcome

Chosen: option 1. A plugin declares each thing it adds in its `plugin.kdl`, and the engine refuses anything not declared there: a setting the plugin doesn't name, a command it doesn't name, a step CrossLint doesn't have. A plugin's commands run as `crosslint PLUGIN COMMAND`, so a plugin's name keeps them apart from CrossLint's commands and from other plugins'. `crosslint check` keeps the flags `crosslint.usage.kdl` gives it, in every project.

Option 2 lost because `check`'s flags would change with the configuration, a shared plugin could take any flag name, including one CrossLint adds later, and a fixed `--help` couldn't list them. Option 3 lost because the engine would know about debt, which ADR 0005 rules out, and every project's `--help` would show a debt flag. Option 4 lost for the same reason, and because a project that tracks no debt would carry it.

How a plugin declares each of these, and what CrossLint prints for plugin commands, is in `docs/design/plugins.md` and `docs/reference/plugin.md`.

Confidence: the debt plugin is built on a step, settings, and `crosslint debt update`, a command under its name, and the Angular plugin on settings, artifacts its helper declares from them, and keys; their tests pass, and the built app runs `crosslint debt update` in `rake build:check`. No comparison of the options was recorded beyond the reasons here.

### Consequences

* Good, because a project's `crosslint check` takes the same flags everywhere, and a script that runs it doesn't break when the project lists another plugin.
* Good, because a plugin can't take a name CrossLint later needs for a flag, and two plugins can't take the same command name.
* Good, because debt tracking and the Angular checks are written with what any shared plugin can use, so the surface is exercised before strangers rely on it.
* Bad, because a plugin that needs something new from the engine needs a new kind of declaration, a change to CrossLint, where a hook into the engine's code would have needed none.
* Bad, because `crosslint --help` has to read the project's configuration to list its plugins' commands, so it can show different commands in different projects, and has to stay useful outside a project or with a configuration it can't read.
* Bad, because the only steps are the ones built into CrossLint, so a shared plugin can't bring a step written for it yet.

### Confirmation

Tests fail when the code departs from it: `test/cross_lint/cli_test.rb` shows a plugin's command runs as `crosslint PLUGIN COMMAND` and takes only the global flags and the command flags its manifest declares (`test_a_plugins_command_runs_the_check_and_tells_the_plugins_step_its_name`, `test_a_plugins_command_takes_no_other_flags`, `test_a_plugins_command_takes_the_flags_it_declares_and_tells_its_step`), and that `check` refuses a flag the usage spec doesn't give it (`test_check_takes_only_the_flags_the_usage_spec_gives_it`); `test/cross_lint/adapters/kdl_plugin_manifests_test.rb` shows a `flag` line outside a command's block is a mistake (`test_refuses_a_flag_as_a_mistake_that_says_what_to_write_instead`); and `test/cross_lint/core/load_project_test.rb` shows CrossLint stops at a command flag named as a global flag, as `--help`, or as another flag of its command (`test_stops_at_a_flag_of_a_command_named_for_a_global_flag_for_help_or_for_another_flag_of_the_command`), at a plugin with commands named for a command of CrossLint's or a reserved name, and at a local or shared plugin with a built-in plugin's name. The manifest tests show CrossLint stops at any line and any setting a plugin doesn't declare, and an architecture test shows nothing outside `plugins/angular/` refers to anything inside it.

## More Information

Revisit when a shared plugin needs a step CrossLint doesn't have; a step written in Ruby, declared in the manifest, was weighed and left for then.
