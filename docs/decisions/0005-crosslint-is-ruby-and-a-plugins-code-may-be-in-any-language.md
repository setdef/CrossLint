---
status: proposed
date: 2026-11-27
deciders: setdef's maintainer chose one CrossLint, in Ruby, whose plugins may carry helpers, in #4, then chose that a plugin's code may be in any language, on the project's runtime, and that the Angular plugin be ng-nudge's classes in JavaScript with ts-morph; the agent acting as CrossLint's architect chose how a helper runs rules and declares artifacts, and that a plugin's Ruby on the Ruby CrossLint carries is a helper like any other, which runs in CrossLint's process
---

# CrossLint is one program, in Ruby, and a plugin's code may be in any language

## Context and Problem Statement

CrossLint checks relations between files that linters such as ESLint and RuboCop can't, because they look at one file at a time. Its predecessor, ng-nudge, is JavaScript and serves only Angular projects. Most of the checks wanted so far read only paths, Markdown or YAML, and can run in a project of any language. A few read inside source files, such as an Angular component's inputs and outputs, and each language has a reader its community builds and keeps current: the TypeScript compiler for TypeScript, Prism for Ruby. A plugin that reads such files has rules and artifacts to declare as well, and the people who write a project's plugins work in the project's language, with its runtime and packages, which need not be Ruby's. Can one CrossLint serve projects in every language, and if it can, in which languages may a plugin's code be written, and on which runtime does it run?

## Decision Drivers

* A project in any language can use CrossLint, including one with no Ruby and no Node.
* An Angular project that uses ng-nudge can replace it in 30 minutes or less, losing none of its value.
* Checks that read inside a language's files give the same answers that language's tools give.
* An author can write a shared plugin that runs in every project that lists it, whatever the project's language.
* A plugin can be written as data, or as code in any language.
* A project's developers write a plugin's code for the runtime they already use, with their Ruby or their Node and their packages, not CrossLint's.
* The Angular plugin's code reads as clearly as ng-nudge's.

## Considered Options

1. **One CrossLint, in Ruby; a plugin carries data, and code in any language as helpers: each helper is a command and a file, and runs rules and declares artifacts. A helper on the Ruby CrossLint carries runs in CrossLint's process; any other runs on the project's runtime and speaks a line protocol.**
2. One CrossLint, in Ruby; a plugin carries data and Ruby, and may carry a helper only to read the files of the helper's language, for a rule in Ruby to call.
3. One CrossLint, in Ruby; a plugin carries data and Ruby only, and reads inside files with Tree-sitter.
4. A CrossLint in TypeScript, for TypeScript and JavaScript projects only.
5. One CrossLint, in Ruby; a plugin is a program in any language, which CrossLint sends each artifact's facts as JSON on standard input, and which answers on standard output.

CrossLint installing a plugin's runtime itself, as pre-commit does for Node, Go and Rust, was weighed in #4 as an addition to options 2 and 5, not as an option alone.

## Decision Outcome

Chosen: option 1. CrossLint ships as one self-contained app, built with Fledge, so a project needs no Ruby to run it, and checks of paths, Markdown and YAML run in a project of any language. Whatever is specific to one language or framework is in a plugin, as the Angular checks are, and so is debt tracking, so the engine has no role, language, or policy built in. A plugin's code may be in any language, because a plugin should be writable as data or as code in any language, and because a project's developers expect that code to run on the runtime and packages they already have, not on CrossLint's. A helper whose command is a program runs on the project's runtime, found on the `PATH`. A helper on the Ruby CrossLint carries stays, so that a plugin can run in a project with no runtime that fits it; authors of shared plugins write such plugins too.

A helper runs a rule that a plugin declares as `rule NAME helper=HELPER`, and declares a plugin's artifacts from its settings with `artifacts helper=HELPER`. The architect chose this as the smallest change that lets a helper do both. Artifacts as data that read settings lost because they would be a larger change to the format of `plugin.kdl`. Artifacts declared when the check runs, instead of when the plugin loads, lost because CrossLint checks policies against the artifacts while it loads.

A plugin author writes every helper one way, a command and a file, and names the runtime in the command, with the Ruby CrossLint carries written `command=(crosslint)"ruby"`. Such a helper runs in CrossLint's process, so its rules keep the guarantees CrossLint gives about files (exact names, ignored files left out, links out of the project refused), a trace for each fault, and a time limit for each artifact. A separate Ruby process speaking the line protocol lost because the protocol would have to rebuild those guarantees, and a reserved command name in place of the annotation lost because some `PATH` could hold a program of that name.

The Angular plugin is ng-nudge's classes, in JavaScript, run by its helper: the helper declares the plugin's artifacts and runs its two rules that read TypeScript, with ts-morph, a dependency the plugin carries, so a project installs nothing for it. The maintainer chose this because ng-nudge's code reads more clearly than a dense helper whose answers Ruby rules and a Ruby artifacts file pass along, and accepted that the plugin reads TypeScript with the TypeScript that ts-morph carries, not the project's.

Option 2 lost because a plugin whose checks read another language would carry Ruby only to pass JSON between CrossLint and its helper, written by developers who may not work in Ruby. Option 3 lost because syntax alone can't answer what the compiler answers: a Ruby reader built on Tree-sitter had to reimplement module resolution, and still missed a base class built by a mixin; `ruby_tree_sitter` 2.1.1 also crashes on Windows; and a plugin's authors could write only Ruby. Option 4 lost because a Ruby project, or a repository of Markdown alone, would need Node to use it. Option 5 lost because it is a larger change than option 1, and would replace the manifest and the steps through which a plugin reaches the engine (ADR 0006).

How plugins load and run is in `docs/design/plugins.md`, and what a plugin declares is in `docs/reference/plugin.md`.

Confidence: a Ruby program built with Fledge, installed through mise, ran with no Ruby on `PATH` on Linux on x64 and Windows on x64, and on macOS on ARM with only the system's Ruby on `PATH`, which it didn't use (#4). In #4, a helper that called the TypeScript compiler collected inputs and outputs the way ng-nudge does on 17 of 17 test components, against 16 of 17 for Tree-sitter. The Angular plugin's tests run its helper on Node and check its report on a fixture against what ng-nudge reports there, less ng-nudge's defects, and they pass on macOS, Linux, and Windows in CI. The four shared plugins in `plugins/` run their rules with helpers on the Ruby CrossLint carries, three of them declare their artifacts with one too, and their tests pass. No comparison was recorded that option 1 is better than options 2 and 5 beyond the reasons above. Unproven: whether the TypeScript 6.0 that ts-morph carries answers as a project's compiler of another version does (#45), TypeScript 7, and a shared plugin whose helper a program runs.

### Consequences

* Good, because a project of any language installs one app and needs no runtime for checks of paths, Markdown and YAML.
* Good, because a plugin's author writes its rules and artifacts in the language they know, for the runtime and packages the project has.
* Good, because the Angular plugin is ng-nudge's classes, and reads TypeScript through ts-morph, as ng-nudge does.
* Good, because the Angular checks don't use Tree-sitter, so its Windows crash can't reach them.
* Bad, because a plugin with a helper a program runs fails in a project without the helper's runtime, and has to report the missing runtime by name, so a shared plugin written for Node serves only projects that have Node, and an author who wants it to run everywhere writes it for the Ruby CrossLint carries.
* Bad, because the Angular plugin reads TypeScript with the TypeScript 6.0 that ts-morph carries, so a project on another version of TypeScript can get answers its compiler wouldn't give, and the plugin's maintainers keep ts-morph current.
* Bad, because the app carries the Angular plugin's npm packages, so every release build installs Node and the plugin's packages on each platform, beside the Fledge build CrossLint needs there.
* Bad, because shared plugins can depend on the helpers' line protocol for rules and artifacts, so each change to its requests and answers has to stay compatible.
* Bad, because a helper on the Ruby CrossLint carries can use only the gems CrossLint was built with, and runs in CrossLint's process, so it shares one Ruby with every other plugin's.

### Confirmation

Tests fail when the code departs from it: `test/cross_lint/core/helper_rule_test.rb` shows a helper runs a rule and its answer becomes the rule's violations; `test/cross_lint/core/load_project_test.rb` shows a helper declares a plugin's artifacts from its settings (`test_adds_the_artifacts_a_plugins_helper_declares_from_its_settings_and_stops_the_helper`); `test/cross_lint/adapters/kdl_plugin_manifests_test.rb` shows a helper on `command=(crosslint)"ruby"` is read as Ruby that CrossLint runs, for rules and for artifacts (`test_reads_a_rule_whose_helper_is_on_crosslints_ruby_as_that_helpers_ruby`, `test_reads_the_file_whose_ruby_declares_artifacts_from_a_helper_on_crosslints_ruby`); `test/cross_lint/core/ruby_rule_test.rb` shows such a rule reads no file outside the project and stops at its time limit (`test_reads_no_file_outside_the_project`, `test_stops_a_rule_that_runs_past_its_time_limit_even_one_that_rescues_every_error`); `test/cross_lint/adapters/helpers_test.rb` shows a helper starts with the environment CrossLint was started with, not the one the app sets up for the Ruby it carries (`test_starts_a_helper_with_the_environment_the_launcher_saved_not_the_one_it_set`); and `plugins/angular/test/fixture_test.rb` runs the Angular plugin through its helper, and shows a project without Node stops with exit status 2, naming the plugin and `node`. The release workflow runs `crosslint --version` and `crosslint --help` from each platform's archive with an empty `PATH`. `rake build:check` runs the built app's Angular plugin with only Git and Node on the `PATH`, when someone runs it; no workflow does.

## More Information

The options, the evidence for each, and what each means for people who write artifacts, policies and rules are in #4. Revisit this decision if a check that reads inside files is wanted for a language whose projects don't carry that language's runtime.
