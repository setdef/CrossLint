# ruby_tree_sitter on Windows: the garbage collection crash

This spike is throwaway evidence for [#4](https://github.com/setdef/CrossLint/issues/4). It is not CrossLint's design.

**Question.** On Windows x64, a program that uses [`ruby_tree_sitter`](https://github.com/Faveod/ruby-tree-sitter) 2.1.1 stops with `[BUG] object allocation during garbage collection phase` at exit and whenever a garbage collection frees a tree ([the earlier spike](../fledge-tree-sitter/README.md#still-broken)). macOS and Linux don't. Is the cause the gem, the Windows Ruby, or the earlier spike's patches?

## Answer

**The gem causes it, and a 12-line patch fixes it.** `tree_free` and `node_free` allocate a Ruby object while Ruby is freeing objects, and the gem marks both types `RUBY_TYPED_FREE_IMMEDIATELY`, which makes Ruby call them inside the sweep, where allocation is forbidden. The allocation is `ULL2NUM(pointer)` (`ULONG2NUM` in the gem as published). On Windows x64, Ruby's largest fixnum is 2^30 - 1, because a C `long` has 32 bits there, so almost every pointer becomes a Bignum, and building a Bignum allocates. On macOS and Linux the largest fixnum is 2^62 - 1, every pointer is a fixnum, and nothing allocates, so the same code passes by luck.

Neither of the other two suspects is involved:

- **The Windows Ruby.** RubyInstaller's released 4.0.10 crashes the same way as the 4.1.0dev head build that Fledge ships.
- **The spike's patches.** The crash happens with and without the `ULL2NUM` change. Without it (`ulong` below) the gem also keeps a pointer in 32 bits, which adds a second, different crash (a segmentation fault in the gem's exit-time finalizer).

## Evidence

### The program

`repro.rb` parses `{"a": [1, 2]}` with the JSON grammar and exits. `build.rb` builds the gem's source (version 2.1.1, from rubygems.org), tree-sitter 0.26.5 and the grammar with the Ruby that runs it, and `run.sh` runs the program in four modes. `exit` drops the tree and exits normally. `gc` drops the tree, calls `GC.start` and leaves with `exit!`, so no exit-time free runs. `keep` keeps the tree and leaves with `exit!`. `many` parses 3,000 trees while the program runs, collects, and exits normally.

```console
$ MISE_ENV=head bash run.sh spike ulong fix     # Windows
$ MISE_ENV=ruby40 bash run.sh spike fix         # Windows
$ MISE_ENV=head bash run.sh stock fix           # macOS, Linux
```

`MISE_ENV` picks the Ruby (`mise.head.toml`, `mise.ruby40.toml`). The variants:

| Variant | The gem |
| --- | --- |
| `stock` | As published. Only macOS and Linux can build it. |
| `ulong` | Windows: only the changes the gem needs to compile (a `dlfcn.h` over `LoadLibrary`, and `logger.c`'s local variable `stderr`, which is a macro there). `tree.c` keeps `ULONG2NUM` and `NUM2ULONG`. |
| `spike` | `ulong` plus the earlier spike's `ULL2NUM` and `NUM2ULL`. |
| `fix` | The same as `stock` on macOS and Linux, `spike` on Windows, plus `patches/free-deferred.patch`. |

### Results

Exit status of `repro.rb` per mode. 0 means the program finished and printed everything; 3 is Ruby's `[BUG]`.

| Platform and Ruby | Variant | `exit` | `gc` | `keep` | `many` |
| --- | --- | --- | --- | --- | --- |
| Windows 11 x64, RubyInstaller head, 4.1.0dev (master 0e25874222) | `spike` | 3 | 3 | 0 | 3 |
| | `ulong` | 3 (segmentation fault) | 3 | 0 | 3 |
| | `fix` | 0 | 0 | 0 | 0 |
| Windows 11 x64, RubyInstaller 4.0.10 | `spike` | 3 | 3 | 0 | 3 |
| | `fix` | 0 | 0 | 0 | 0 |
| macOS (arm64), 4.1.0-preview1 | `stock` | 0 | 0 | 0 | 0 |
| | `fix` | 0 | 0 | 0 | 0 |
| Linux x86_64 (glibc), 4.1.0-preview1 | `stock` | 0 | 0 | 0 | 0 |
| | `fix` | 0 | 0 | 0 | 0 |

`keep` passes everywhere because nothing frees a tree. The crash needs a tree or node to be freed.

### Where the allocation is

Ruby's C backtrace for `spike` on the Windows head Ruby (frames trimmed to the symbol names):

```text
rb_bug
rb_memerror
rb_ec_newobj_of
rb_ull2inum
(tree_sitter.so, no symbol)
rb_objspace_call_finalizer
```

`ulong` fails the same way through `rb_uint2big` in place of `rb_ull2inum`, so the 32-bit value is also a Bignum: `repro.rb` prints which `1 << bits` are fixnums. On Windows (both Rubies) the answer is `[20]`: `1 << 30` already is not one. On macOS and Linux it is `[20, 30, 31, 32, 40, 48, 61]`.

### What the gem does

`ext/tree_sitter/tree.c` keeps a reference count for each tree in a Hash that is a class variable, `Tree::@@rc`, keyed by the tree's address. `tree_free` and `node_free` both call `tree_rc_free`, which runs `ULONG2NUM`, `rb_cv_get`, `rb_hash_lookup`, `rb_hash_delete` and `rb_hash_aset` on it. Every type in the gem has `.flags = RUBY_TYPED_FREE_IMMEDIATELY` (`macros.h`, `DATA_DECLARE_DATA_TYPE`). Ruby's header for the flag says structs with it "are deallocated during the sweep phase" and that using it "needs deep understanding of both GC and threads". Without the flag, Ruby calls `dfree` after the collection, where allocating and calling Ruby are allowed. `tree_cursor`, `query_cursor`, `parser` and the rest free only C memory, so they are fine.

The Hash design came in with [pull request 10](https://github.com/Faveod/ruby-tree-sitter/pull/10) in 2022, whose description calls it "theoretically dangerous" and says the proper way is a C-only structure. `tree.c` on the default branch is identical to 2.1.1's (same blob, `75d4a69`).

### The public tracker

The repository has 11 issues and 91 pull requests, all closed or merged, as of 2026-11-25. None mentions Windows, `mingw`, garbage collection, `RUBY_TYPED_FREE_IMMEDIATELY` or this message. The latest commit is the 2.1.1 release (2026-04-30). The gem's README lists no Windows platform, and its build needs three changes to compile there (below), so it probably has not been run on Windows. That is an inference.

## The patch

`patches/free-deferred.patch` (a patch for the gem's `ext/tree_sitter/`) adds `DATA_DECLARE_DATA_TYPE_DEFERRED_FREE`, a variant of the macro without `RUBY_TYPED_FREE_IMMEDIATELY`, and uses it for `tree` and `node`, the two types whose free function calls Ruby. It changes 3 files and about 12 lines. With it, all four modes pass on both Windows Rubies, and on macOS and Linux. `build.rb --fix` applies it.

What the patch does not do:

- It does not remove the Bignum allocation on Windows when a tree or node is created (`tree_rc_new`), which is allowed there and slightly slower than a fixnum key.
- It does not fix the gem's other Windows problems, which the earlier spike patched by hand: `extconf.rb` shells out to Unix commands, `language.c` includes `dlfcn.h`, `logger.c` has a local variable called `stderr`, and `tree.c` keeps a pointer in an `unsigned long`. The last one is a real bug on Windows (pointers cut to 32 bits), which the Windows variants here replace with `ULL2NUM` and `NUM2ULL`.
- A C-only reference count, which the 2022 pull request calls the proper design, would need no deferred free. It is a larger change and was not tried.

## Draft issue for the gem

Not filed. The maintainers of `Faveod/ruby-tree-sitter` decide whether to file it, so this is a draft for the project's maintainer to approve.

> **`tree_free` and `node_free` allocate during GC; crashes on Windows with `[BUG] object allocation during garbage collection phase`**
>
> `Tree` and `Node` are declared with `RUBY_TYPED_FREE_IMMEDIATELY`, so Ruby calls `tree_free` and `node_free` during the sweep. Both call `tree_rc_free`, which converts the tree's address with `ULONG2NUM` and then calls `rb_cv_get`, `rb_hash_lookup`, `rb_hash_delete` and `rb_hash_aset`. Ruby forbids allocating there.
>
> On Linux and macOS this goes unnoticed, because the address fits in a fixnum (2^62 - 1), so `ULONG2NUM` allocates nothing. On Windows x64 a fixnum tops out at 2^30 - 1 (C `long` has 32 bits), so nearly every address becomes a Bignum and `rb_ull2inum` calls `rb_ec_newobj_of` inside the sweep. Any program that frees a tree stops with `[BUG] object allocation during garbage collection phase`, at exit or whenever a collection runs. The same would likely happen on any platform with a 32-bit fixnum, which I did not test.
>
> Reproduced with `ruby_tree_sitter` 2.1.1, RubyInstaller's Ruby 4.0.10 and 4.1.0dev on Windows 11 x64, after the gem was made to compile there (see below). Backtrace: `rb_bug`, `rb_memerror`, `rb_ec_newobj_of`, `rb_ull2inum`, `tree_rc_free`.
>
> A minimal fix is to leave `RUBY_TYPED_FREE_IMMEDIATELY` off the `tree` and `node` types, so that Ruby calls their free functions after the collection. With it, a program that parses 3,000 trees, collects and exits normally passes on Windows (both Rubies), macOS and Linux. The patch is below. A C-only reference count in place of `Tree::@@rc`, as [#10](https://github.com/Faveod/ruby-tree-sitter/pull/10) suggests, would remove the Hash and the need for the flag.
>
> Separately, the gem does not compile on Windows as published: `extconf.rb`'s `repo.rb` shells out to `mkdir A && cd A && git init`, `language.c` needs `dlfcn.h`, `logger.c` has a local variable called `stderr` (a macro in the Windows C library), and `tree.c` stores a pointer in an `unsigned long` (`ULONG2NUM` and `NUM2ULONG` cut it to 32 bits). I can open issues for those if Windows is of interest.
>
> (the patch, `patches/free-deferred.patch`)

## Files

- `repro.rb`: the program.
- `build.rb`: builds the variants (`--ulong`, `--fix`).
- `run.sh`: builds and runs every variant in four modes and prints a summary.
- `mise.toml`, `mise.head.toml`, `mise.ruby40.toml`: the tools. The Windows tables follow Fledge's `mise.toml`, as in the earlier spike.
- `dlfcn.h`: the earlier spike's `dlfcn.h`, with its functions marked `inline`.
- `patches/free-deferred.patch`: the fix.

## Not done

- A Windows ARM64, Linux `aarch64` or 32-bit computer.
- The patch inside a Fledge app. The reproduction compiles the gem with mkmf and loads it with `-I`; it does not use Bundler or Fledge. The earlier spike's Fledge app still carries the unpatched gem.
- A C-only reference count.
- Running the gem's test suite with the patch.
- The released 4.0.10 Ruby on macOS and Linux (the runs there used 4.1.0-preview1).
