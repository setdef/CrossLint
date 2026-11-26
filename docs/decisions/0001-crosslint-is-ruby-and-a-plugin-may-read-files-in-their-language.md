---
status: proposed
date: 2026-11-26
deciders: setdef's maintainer chose the option, in #4
---

# CrossLint is one program, in Ruby, and a plugin may read a language's files with a helper in that language

## Context and Problem Statement

CrossLint checks relations between files that linters such as ESLint and RuboCop can't, because they look at one file at a time. Its predecessor, ng-nudge, is JavaScript and serves only Angular projects. Most of the checks wanted so far read only paths, Markdown or YAML, and can run in a project of any language. A few read inside source files, such as an Angular component's inputs and outputs, and each language has a reader its community builds and keeps current: the TypeScript compiler for TypeScript, Prism for Ruby. Can one CrossLint serve projects in every language, and if it can, what code may its plugins carry?

## Decision Drivers

* A project in any language can use CrossLint, including one with no Ruby and no Node.
* An Angular project that uses ng-nudge can replace it in 30 minutes or less, losing none of its value.
* Checks that read inside a language's files give the same answers that language's tools give.
* A plugin shared between projects runs in every project that lists it, whatever language the plugin was written in.

## Considered Options

1. **One CrossLint, in Ruby; a plugin carries data and Ruby, and may also carry a helper in the language of the files it reads.**
2. One CrossLint, in Ruby; a plugin carries data and Ruby only, and reads inside files with Tree-sitter.
3. A CrossLint in TypeScript, for TypeScript and JavaScript projects only.
4. One CrossLint, in Ruby; a plugin is a separate program in any language, talking to CrossLint over JSON on standard input and output.

CrossLint installing a plugin's runtime itself, as pre-commit does for Node, Go and Rust, was weighed as an addition to option 1 or 4, not as an option alone.

## Decision Outcome

Chosen: option 1. CrossLint ships as one self-contained app, built with Fledge, so a project needs no Ruby to run it. Checks of paths, Markdown and YAML run in a project of any language. The Angular plugin reads TypeScript with a JavaScript helper of about 90 lines that calls the project's TypeScript compiler, which an Angular project already has.

Option 2 lost because syntax alone can't answer what the compiler answers. A Ruby reader built on Tree-sitter had to reimplement module resolution, and still missed a base class built by a mixin; `ruby_tree_sitter` 2.1.1 also crashes on Windows. Option 3 lost because a Ruby project, or a repository of Markdown alone, would need Node to use it. Option 4 lost because a plugin brings its author's runtime with it, so shared plugins would split by language, and because each new thing a plugin needs from CrossLint becomes a change to the protocol that has to stay compatible.

A helper is allowed only for reading the files of the language it is written in, so the runtime it needs is one that a project with those files already has.

Confidence: a Ruby program built with Fledge, installed through mise, ran with no Ruby on `PATH` on macOS on ARM, Linux on x64 and Windows on x64. The JavaScript helper collected inputs and outputs the way ng-nudge does on 17 of 17 test components, against 16 of 17 for Tree-sitter. Unproven: the helper on Windows, and with TypeScript 7.

### Consequences

* Good, because a project of any language installs one app and needs no runtime for checks of paths, Markdown and YAML.
* Good, because the Angular plugin's answers come from the TypeScript compiler, as ng-nudge's do.
* Good, because the Angular checks don't use Tree-sitter, so its Windows crash can't reach them.
* Bad, because the Angular plugin is written in two languages, and its maintainers keep a JavaScript helper working across TypeScript releases.
* Bad, because a plugin with a helper fails in a project without that language's runtime, and has to report the missing runtime by name.
* Bad, because a Ruby plugin that needs a gem CrossLint wasn't built with can load it only with a network and a writable folder.
* Bad, because every release needs a Fledge build on each platform CrossLint supports.

### Confirmation

Nothing checks it yet.

## More Information

The options, the evidence for each, and what each means for people who write artifacts, policies and rules are in #4. Revisit this decision if a check that reads inside files is wanted for a language whose projects don't carry that language's runtime.
