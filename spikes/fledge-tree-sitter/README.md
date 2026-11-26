# Fledge app with ruby_tree_sitter

This spike is throwaway evidence for step 3 of [#1](https://github.com/setdef/CrossLint/issues/1) ("Building it"). It is not CrossLint's design.

**Question.** Can a Ruby program that uses the [`ruby_tree_sitter`](https://rubygems.org/gems/ruby_tree_sitter) gem and the TypeScript and TSX grammars be built into a [Fledge](https://github.com/setdef/Fledge) console app, installed through [mise](https://mise.jdx.dev/) on a computer with no Ruby, and run on each platform? Can the app load a Ruby rule file from the project it runs in?

Results below come from commit [`a59fe42`](https://github.com/setdef/CrossLint/tree/a59fe429f9b4a919f577191614651930d4909207/spikes/fledge-tree-sitter) with Fledge v0.17.0, `ruby_tree_sitter` 2.1.1 and tree-sitter-typescript v0.23.2.

## Result

| Platform | Built | Installed through mise, no Ruby | Runs |
| --- | --- | --- | --- |
| `arm64-darwin` | yes | yes | yes |
| `x86_64-linux` (glibc) | yes | yes | yes |
| `x64-mingw-ucrt` | only after four changes to the gem's build | yes | **no**: the process stops with Ruby's `[BUG] object allocation during garbage collection phase` |

No Linux `aarch64`, Windows ARM64 or musl computer was available, so those platforms are untried.

A project-local Ruby rule file loads and runs on every platform. It can use Ruby's standard library, the gems the app carries, and files in the project's folder. A rule file that requires any other gem raises `LoadError`. [Project-local rules](#project-local-ruby-rules) lists what works around that.

## What the app does

`app/main.rb` takes `.ts` and `.tsx` files and prints each class with its decorators, and each member that carries a decorator:

```console
$ tsspike sample/Widget.ts
sample/Widget.ts
  class WidgetComponent @Component({ selector: "app-widget", templateUrl: "./widget.component.html" })
    @Input() label (public_field_definition)
    @Input({ required: true }) id (public_field_definition)
    @Output() picked (public_field_definition)
    @HostListener("window:resize") onResize (method_definition)
  class Base
    @Input() inherited (public_field_definition)
```

With `--rules DIR` it then loads every `*.rb` in `DIR` and runs the rules they register (`TsSpike.rule(name) { |facts| ... }`). `sample/project/.crosslint/rules/` holds seven rule files, each testing one thing about loading (see below).

In tree-sitter-typescript's tree, the decorators of an exported class are children of its `export_statement`, and a member's decorators are siblings that come before it in the `class_body`.

## Rerun

On a computer with [mise](https://mise.jdx.dev/) and a C compiler (and `git`, which Bundler uses to fetch Fledge):

```console
$ bash scripts/build.sh                # writes dist/tsspike-PLATFORM.tar.gz (.zip on Windows)
$ bash scripts/install-check.sh dist/tsspike-PLATFORM.tar.gz
```

`build.sh` installs Ruby 4.1.0-preview1 from `mise.toml`, compiles the grammars (`scripts/grammars.rb`), installs the `fledge` gem from its git tag, and runs `fledge build`. `install-check.sh` installs the archive through mise into an empty data folder, removes every Ruby from `PATH` (a stock Mac keeps `/usr/bin/ruby`, Ruby 2.6), and times and runs the program. Both take environment variables documented in their headers (`RULES_ONLY`, `MISE_OPTS`).

## How the pieces fit

**Fledge.** `fledge build ../app` runs from a folder whose `Gemfile` lists Fledge (`build/Gemfile`). It downloads Fledge's runtime (a Ruby 4.1.0-preview1 build; 26 MB on macOS, 35 MB on Linux) and compiles the gems from source against that Ruby. The archive holds the program (`tsspike`, or `tsspike.exe`), `app/` with the project, the runtime, and `fledge.cfg`. The program starts `app/main.rb` under `bundler/setup` (Ruby loads it through `RUBYOPT`).

**The gem.** `ruby_tree_sitter` 2.1.1 ships precompiled gems for Ruby 3.1 to 4.0 on macOS and Linux and none for 4.1, so Bundler installs its source gem. The gem's `extconf.rb` downloads the tree-sitter 0.26.5 sources (with `git`, or `curl` and `tar`) and compiles `libtree-sitter.a` into the extension. That needs a network, a C compiler and `make` on the computer that runs `fledge build`, and nothing on the user's computer. The lockfile carries the `ruby` platform plus each platform Fledge builds on (`bundle lock --add-platform`, `--add-checksums`).

**The grammars.** The gem contains no grammar. `TreeSitter::Language.load(name, path)` calls `dlopen` on a shared library that exports `tree_sitter_<name>`, and `TreeSitter.language(name)` searches `parsers/`, `vendor/parsers/`, `/usr/lib` and similar folders relative to the current directory, so it finds nothing once a user runs the app from a project. `scripts/grammars.rb` downloads tree-sitter-typescript v0.23.2 (SHA-256 checked), compiles `typescript/src/parser.c` and `tsx/src/parser.c` with their scanners into `app/parsers/libtree-sitter-{typescript,tsx}.{dylib,so,dll}` (1.4 MB each on macOS), and `main.rb` loads them by absolute path from `__dir__`. Fledge copies `app/parsers/` into the archive although `.gitignore` lists it, because it ships every file of the project except a short list of folders. Each platform needs a separate compile, so a grammar plugin means a C compiler at build time for every platform, or a prebuilt library per platform.

## Results per platform

Archive size, installed size and times come from one run each (the first-run time from two to three). Each install used mise 2026.11.7 and a `file://` URL for the archive, with `strip_components = 1` and `bin_path = "."` as in [setdef/Fledge#123](https://github.com/setdef/Fledge/issues/123).

| | `arm64-darwin` (macOS 27) | `x86_64-linux` (Ubuntu 24.04, glibc 2.39) | `x64-mingw-ucrt` (Windows 11) |
| --- | --- | --- | --- |
| Archive | 28.3 MB `.tar.gz` | 37.6 MB `.tar.gz` | 27.2 MB `.zip` |
| Installed | 96,324 KiB | 117,952 KiB | 79,424 KiB |
| `mise install` | 1.4 s | 0.8 s | 5.7 to 15 s |
| First run after install | 0.9 s, 4.2 s | 0.08 s | 0.3 s |
| Later runs, mean of 10 | 0.11 s | 0.08 s | 0.24 to 0.27 s |
| `fledge build`, new workspace | 88 s | 32 s | 560 s (mise's installs took 81 s of it) |
| Ruby on `PATH` | none reachable, except macOS's `/usr/bin/ruby` | none | none |

Each run printed the same classes and members as the macOS example above, and the same rule results, except Windows, below.

Two things the table does not say. On macOS the first run after install took 0.9 s once and 4.2 s once, as [setdef/Fledge#125](https://github.com/setdef/Fledge/issues/125) describes. And mise installed from a `file://` URL: no release of this app exists on GitHub, so an install from `https://github.com/.../releases/download/...` (mise's `http` backend over the network, or its `github` backend) is untried.

## Project-local Ruby rules

Each file in `sample/project/.crosslint/rules/` was loaded by the installed app, from the project's folder, on macOS and Linux (and on Windows for the files that need no network):

| File | What it does | Result |
| --- | --- | --- |
| `01_trivial.rb` | `load`ed from the project's folder; registers a rule that flags a class with `@Input()` members and no decorator | works |
| `02_sibling_file.rb` | `require_relative "helpers/names"`, a file of the project beside it | works |
| `03_unbundled_gem.rb` | `require "rainbow"`, a gem the app does not carry | `LoadError: cannot load such file -- rainbow` |
| `04_bundled_gem_not_locked.rb` | `require "csv"`, a bundled gem of Ruby 4.x that the app's lockfile lacks | `LoadError`, with Ruby's note that csv is no longer a default gem |
| `05_bundler_inline.rb` | `bundler/inline` asks for `rainbow` 3.1.1 | loads; Bundler installed the gem **into the app's install folder** (`lib/ruby/gems/4.1.0+5/`) |
| `06_vendored_pure_ruby.rb` | adds a `vendor/` folder of the project to `$LOAD_PATH` and requires a pure-Ruby file | works |
| `07_own_gemfile.rb` | writes a Gemfile with `rainbow`, runs the app's `bundle install` and `bundle exec` in a subprocess | loads and prints the gem's output; needs `BUNDLE*`, `RUBY*`, `GEM_*` and `BUNDLER_*` variables removed (`unsetenv_others: true`), because the app starts under `bundler/setup` and a subprocess inherits it |

The runs that loaded rules 05 and 07 took 349 s on Linux and 822 s on macOS, and a few seconds on a third computer (a Mac). The Linux run used 3.9 s of CPU in all; the cause was not investigated.

So in a Fledge app, a project-local rule file can load and run, and it can use Ruby's standard library, the gems in the app's lockfile, and Ruby files the project carries. It stops at gems the app was not built with. Two routes past that exist, `bundler/inline` and a subprocess with a Gemfile of the project; both need a network and a writable folder at run time, and neither was tried with a gem that needs a compiler (a user's computer may have none).

A plugin published as a gem is therefore either built into the app (every plugin the app can use must be in the lockfile at build time) or installed at run time by one of the two routes. The first route means one app build per plugin set.

## Where it broke, and what fixed it

| Where | What happened | Fix |
| --- | --- | --- |
| Windows, `scripts/grammars.rb` | `LoadError: 126: The specified module could not be found ... zlib.so`: RubyInstaller's head build of Ruby imports `libz-1.dll` and `libgcc_s_seh-1.dll` and does not ship them | `RUBY_DLL_PATH`, `MSYS2_PATH` and `RI_DEVKIT` in `mise.toml`, copied from Fledge's `mise.toml` (`[env]`), with the MSYS2 packages it installs |
| Windows, gem `extconf.rb` | `The syntax of the command is incorrect`: `repo.rb` runs `mkdir A && cd A && git init ...` through `cmd.exe`, so no copy of tree-sitter is fetched and the build stops | `scripts/tree_sitter_core_windows.rb` builds `libtree-sitter.a` from the tagged release; `BUNDLE_BUILD__RUBY_TREE_SITTER` (a `bundle config build.NAME` option that Fledge reads) points the gem at it with `--enable-sys-libs` and `--with-tree-sitter-include/-lib` |
| Windows, `language.c` | `dlfcn.h` does not exist on MinGW (`dlopen` is how the gem loads a grammar) | `scripts/windows/dlfcn.h`, four functions over `LoadLibraryA`, placed in the include folder the gem is pointed at |
| Windows, `logger.c` | `error: expected declaration specifiers`: the file calls a local variable `stderr`, which Windows' C library defines as a macro | rename it (`scripts/windows_app.rb` patches a path copy of the gem) |
| Windows, `tree.c` | the file keeps a pointer in an `unsigned long` (`ULONG2NUM`, `NUM2ULONG`), 32 bits on Windows, and the compiler warns of a cast from integer to pointer | `ULL2NUM`, `NUM2ULL` (same patch) |
| Linux, `install-check.sh` | the run's `PATH` held a Ruby, so "no Ruby on `PATH`" was false | the script drops every `PATH` folder that holds a Ruby |
| `07_own_gemfile.rb` | the subprocess's `bundle install` died inside `bundler/setup` because `BUNDLER_VERSION` and `BUNDLER_SETUP` leaked in | `unsetenv_others: true` and a filtered environment |

## Still broken

- **Windows runs stop with a Ruby `[BUG]`.** `ruby_tree_sitter` 2.1.1's `tree_free` function calls Ruby (`rb_cv_get`, `rb_hash_lookup`, `rb_hash_delete`, `ULONG2NUM`) while Ruby frees objects. On the Windows runtime's Ruby (RubyInstaller's `4.1.0dev`, master 0e25874222) any collection that frees a tree stops the process: `[BUG] object allocation during garbage collection phase`. It happens at exit (the program printed all its output first, then exited with status 3) and in the middle of a run, as soon as the garbage collector runs (rules 05 and 07 both hit it, inside `rubygems` and `openssl` code that allocates). Setting `TSSPIKE_EXIT_BANG=1` makes `main.rb` end with `exit!(0)`, which skips the exit-time free: the program then exits 0 with the right output when it makes no network calls, and still stops when a collection runs during one. The same code does not stop on macOS or Linux. Whether the cause is the gem, the Windows Ruby build, or the changes made here is not established; the gem calling Ruby from a free function is the part Ruby's extension rules forbid. A Windows plugin story for tree-sitter needs a fixed gem, or a different binding.
- **The gem does not support Windows.** Its README lists no Windows platform, which fits the four build failures above. The Windows build needs a patched copy of the gem as a path gem (`build/app-windows/`), not the gem from rubygems.org.
- **Not tried:** Linux `aarch64`, Linux with musl, Windows ARM64; installing from a GitHub release over the network; a plugin gem that needs a compiler; the app signed or notarized; `ruby_tree_sitter` through a Fledge phone build.

## Fledge findings

For the Fledge maintainers. Each was seen in the runs above.

- **[#123](https://github.com/setdef/Fledge/issues/123) holds on every platform tried.** With mise's default options, `mise which tsspike` fails and the app's `ruby` is the one mise finds, on macOS (`http:tsspike@0.0.1 does not provide tsspike (it provides: bundle, bundler, erb, gem, irb, ... ruby, ...)`) and on Windows (the archive has `ruby/bin/`, which mise puts on `PATH`, and `tsspike.exe` is not found). The executables of the app's gems (`rbts`, `print_matches` from `ruby_tree_sitter`) land on `PATH` as well. With `strip_components = 1` and `bin_path = "."`, `tsspike` runs and no Ruby is on `PATH`, on all three platforms. The Linux default was not run.
- **The Windows build computer needs more than the README says.** The README says a Windows app runs on RubyInstaller's development build, and `fledge build` needs that Ruby installed first; how to install it, and the MSYS2 compiler and the two DLLs it lacks, is in Fledge's `mise.toml` only. The spike copies those tables.
- **Windows runtime and a gem with a free function that calls Ruby.** See above.
- **Fledge ships every file of the project except a short list of folders (`.git`, `.bundle`, `vendor/bundle`, `vendor/cache`, its output folders),** git-ignored files included (`app/parsers/` arrived in the archive).
- **First-run time on macOS** (4.2 s once, 0.9 s once, 0.11 s after) matches #125.

## LintLedger

[setdef/LintLedger](https://github.com/setdef/LintLedger) is a public repository with two commits, `docs/plan.md` and issues, and no code, no release, no gem and no `mise` entry. Its [issue #2](https://github.com/setdef/LintLedger/issues/2) plans to build with Fledge and install through mise, and says that until #123 changes the mise entry needs `strip_components = 1` and `bin_path = "."`. So it shows the plan to use this route and nothing about whether a real tool builds and installs that way. This spike is the only evidence so far, and it covers a console app with one native gem and loose shared libraries on three platforms, with the Windows exception above. LintLedger's plan also says a ledger is evaluated as Ruby, which makes it a project-local Ruby file in the sense of the section above.
