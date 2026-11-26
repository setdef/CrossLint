# Reading TypeScript from Ruby

A spike for [issue #1](https://github.com/setdef/CrossLint/issues/1), step 3, first bullet. It is evidence, not CrossLint's design.

## Question

[ng-nudge](https://github.com/OverTheTopMarketing/ng-nudge) reads inside files in one place: its component artifact collects the inputs and outputs of a component class, including those inherited from base classes in other files, and compares their names with the component's stub and interface. Can Ruby do that, with a Tree-sitter gem (approach A) or with a JavaScript helper that an Angular plugin could carry (approach B)?

## Rerun it

```sh
./run.sh
```

Needs Ruby with Bundler, Node with npm, a C compiler and network access. It installs the packages, compiles the TypeScript grammar, and runs both approaches over the fixture in every mode. It exits 0 when every mode gives the result recorded below. With `NG_NUDGE_CLONE=/path/to/ng-nudge` (a checkout with `npm ci` run in it) it also reruns ng-nudge's code on the fixture and checks that `expected/ng-nudge.json` is unchanged.

## What ng-nudge collects

From `lib/artifact/api.js` in ng-nudge 0.3.0, which uses ts-morph:

- The class is the first top-level class in the file that has a `@Component` decorator. A file with no such class gives no result, and the rule is skipped.
- Properties of the class are read in order, then of its base class (`getBaseClass()`), and so on up. A name already seen is skipped, so a subclass wins.
- A property counts only if it has an initializer. Then:
  - `input(...)` or `input.<anything>(...)` makes it an input;
  - `output(...)` makes it an output;
  - otherwise a `@Input` or `@Output` decorator makes it an input or output.
- Names starting with `#` are skipped.
- The stub is read the same way. The interface is the property names of its one interface.
- Rules compare names only. ng-nudge also collects types, and compares none.

So ng-nudge does not handle these, and the fixture includes each:

| Form | ng-nudge |
| --- | --- |
| `@Input() x!: string;` and `@Input({ required: true }) x!: number;` (no initializer) | skipped |
| `@Input() set x(v) {}` (accessor) | skipped |
| `model()` and `model.required()` | skipped |
| `outputFromObservable()` | skipped |
| base class from a package under `node_modules` | class found, no members read (a `.d.ts` has no initializers) |
| `extends mixin(Base)` | finds `Base` and its members, not the mixin's members |

## Fixture

`fixture/` is an Angular-style project with no Angular installed: 17 components (`fixture/src/app/c01-…` to `c17-…`), each with a stub and an interface, some complete and some missing members. It covers:

- decorator inputs and outputs in every form above, and signal `input()`, `input.required()`, `input()` with `alias`, `output()`, `model()`, `model.required()`, `computed()` and `signal()` as non-inputs;
- a base class imported by a relative path, by a `tsconfig` path alias with a wildcard (`@app/*`), by an exact alias to a barrel (`@shared`), through `export *` and `export { A as B } from`, by a renamed import (`import { A as B }`), by a default import, by a directory import (`'../bases'`), by a namespace import (`bases.NsBase`), and from a library folder alias (`@lib/ui`);
- a base class in the same file, a two-level chain with an override, a generic base, a mixin, an abstract `@Directive` base, an `export default` component, and a file with a non-component class before the component;
- a base class from a package under `node_modules` (`fixture/packages/acme-ui-base`, copied into `fixture/node_modules` by `run.sh`), written as a published Angular library is: a `.d.ts` whose inputs and outputs appear only in the type arguments of `static ɵcmp`;
- `tsconfig.json` that extends `tsconfig.base.json`, which holds the paths and has comments and trailing commas.

Two expectations, both committed:

- `expected/ng-nudge.json` is what ng-nudge's `ComponentApi` and `InterfaceApi` return on the fixture (`truth/dump.mjs`), with the stub and interface violations its rules would report.
- `expected/angular.json` is what Angular treats as the inputs and outputs, written by hand from the fixture's source. It differs from the first in the forms ng-nudge skips. In it a `model()` is an input plus an output named `<name>Change`. The mixin's member is left out of it: I did not check what Angular does with one.

Each approach runs in two modes. The default mode copies ng-nudge's rules, quirks included. `--strict` also reads the forms ng-nudge skips (the table above, with a library class's `ɵcmp` types for the package base).

## Results

| Mode | A, Tree-sitter | B, TypeScript API |
| --- | --- | --- |
| ng-nudge's forms, against `expected/ng-nudge.json` | 16 of 17 | 17 of 17 |
| ng-nudge's forms, A with `--mixin-heuristic` | 17 of 17 | |
| every Angular form, against `expected/angular.json` | 16 of 17 | 17 of 17 |
| every Angular form, A with `--mixin-heuristic` | 17 of 17 | |

Each count is components whose inputs, outputs, stub, interface and violations all match. A's one miss is `c15-mixin-base`, in both modes.

## Approach A: Ruby with Tree-sitter

`approach_a/ts_reader.rb`, 287 lines of code, with `ruby_tree_sitter` 2.1.1 and the `tree-sitter-typescript` 0.23.2 grammar. It parses every fixture file without a parse error, and it also parses `accessor`, `satisfies`, `using`, `const` type parameters and import attributes.

What the gem gives: a syntax tree per file. What I wrote that ts-morph gives ng-nudge for free:

- **Finding the class and its members** (about 120 lines with the strict forms): the top-level classes, their decorators, the field initializers, the call shapes `input`, `input.x` and `output`.
- **Reading `tsconfig.json`** (about 20 lines): strip comments and trailing commas from the JSON, follow `extends`, and take `baseUrl` and `paths` from the file that defines them.
- **Resolving a module specifier to a file** (about 45 lines): relative paths, with `.ts`, `.tsx`, `.d.ts`, `index.ts` and `./x.js` to `x.ts`; `paths` patterns with and without `*`; `baseUrl`; a walk up through `node_modules` that reads `package.json` (`types`, `typings`, `exports["."].types`, `main`) and falls back to `@types`.
- **Finding what a module exports under a name** (together with the import lookup and the extends expression, about 100 lines): `export class`, `export default class`, `export default X`, `export { A as B }`, `export { A as B } from`, `export * from`, a re-exported import, and cycles. Imports are the reverse: default, named with `as`, namespace.
- **Walking the chain** with a guard against cycles.

Where syntax was not enough:

- **A mixin base.** `extends withMixIn(BaseA)` is a call. What it returns needs the type checker. Without a guess A reads no base members (`c15` fails). `--mixin-heuristic` takes the first argument as the base class, which passes here and fails for `extends mix(Other, BaseA)`. ts-morph finds `BaseA` through the types, and `expected/ng-nudge.json` shows that it also skips the mixin's members.
- **A package's inputs and outputs.** The `.d.ts` has no initializers or decorators. Reading `ɵcmp`'s type arguments is syntax, but it is a convention of Angular's compiled output, and it is the only way a syntax reader can see a library's inputs.

Grammar details that cost time, each a fact about `tree-sitter-typescript`'s trees:

- `abstract class` is the node `abstract_class_declaration`, not `class_declaration`.
- `export declare class` wraps the class in an `ambient_declaration`.
- The decorators of an exported class hang on the `export_statement`, not on the class.
- A field's decorators are children of the field, but a method's or accessor's decorators are siblings that come before it in the class body.
- A quoted property name is a `string` node, not an identifier.

What it depends on at run time: the gem and its three Ruby dependencies (`oppen`, `sorbet-runtime`, `zeitwerk`; 2.7 MB installed in all), and a compiled grammar. The gem ships no grammars. Compiling the grammar's `parser.c` (8.7 MB) and `scanner.c` takes under one second with `cc`. RubyGems lists `ruby_tree_sitter` 2.1.1 precompiled for macOS (arm64, x86_64) and Linux (x86_64, aarch64, arm; glibc and musl), and lists no Windows build.

Another gem: `tree_sitter_language_pack` 1.27.3 has the same kind of tree API, with no grammar to compile. It downloads each grammar on first use into a cache folder in the user's home (about 15 seconds for TypeScript here), so it needs network access at run time unless the folder is filled in advance. I ran it to parse one snippet and did not run the approach on it. I did not try `tree_stump` or `tree_haver`.

## Approach B: Ruby calling a JavaScript helper

`approach_b/helper.mjs` (89 lines of code) and `approach_b/ts_helper.rb` (28 lines). Ruby starts Node once, sends the tsconfig path and the list of files as JSON on stdin, and reads the inputs, outputs and interface names back as JSON. The helper uses the TypeScript compiler API: it builds a program from the tsconfig, and finds a base class with the checker's `getBaseTypes`, which follows every import form in the fixture, path aliases, re-exports, packages, and mixins. It is the same resolution ts-morph does, which is a wrapper around that API. It loads the `typescript` that the project has installed, not a bundled copy.

It needs Node, and `typescript` in the project's `node_modules`. An Angular project has both: Angular 22.3's `@angular/compiler-cli` declares a peer dependency on `typescript` `>=6.0 <6.1`, and this spike ran with 6.0.3. The helper needs nothing else installed. TypeScript 7.0.2 is the `latest` tag on npm; I did not run the helper against it and do not know whether its JavaScript API is the same.

It reads a base class from a package no better than A does: the checker finds the class, and the helper then reads `ɵcmp` as A does. For a project that is not Angular, the helper is a second program in a second language that the plugin must carry and that the project must be able to run.

## Costs, side by side

| | A | B |
| --- | --- | --- |
| Code | 287 lines of Ruby | 89 lines of JavaScript, 28 of Ruby |
| Run time here, 17 components | 0.6 s | 0.9 s |
| Packages | one gem, its grammar built with `cc` | none beyond the project's `typescript` |
| Import, alias and package resolution | written by hand | the compiler's |
| Mixins and other types | a guess | the compiler's |
| Works with no Node on the machine | yes | no |
| Language of the plugin author's code | Ruby | Ruby and JavaScript |

Run times include process start. They are one run on one machine, not benchmarks.

## Not tried

A resolves modules by rules I wrote, so each feature it lacks is a case where it can disagree with the compiler. I did not implement or test: `extends` of a tsconfig from a package, `typesVersions`, `exports` conditions other than `.` and `types`, `rootDirs`, symlinked workspace packages, Yarn Plug'n'Play, `export =`, declaration merging, a renamed `Input` import (`import { Input as In }`), and a base class named through a type alias or `typeof`. ng-nudge's collection, as read above, does not handle the renamed decorator import either.
