# Getting started

In this tutorial, we add CrossLint to a Ruby project and write a rule for it: every Ruby file under `lib/` has a test under `test/`. By the end, you'll have run a check that fails, fixed a violation, and accepted the rest as debt, so the check passes in CI today and fails on any new violation. It takes about 15 minutes.

If you get stuck, [open an issue](https://github.com/setdef/CrossLint/issues) with the command you ran and everything it printed. Words in bold are defined in the [glossary](glossary.md).

## What you need

- **A project in a Git repository,** with Ruby files under `lib/` and tests under `test/`. The examples use a Ruby project called `invoices`, whose test for `lib/invoices/total.rb` is `test/invoices/total_test.rb`; where your project keeps its files elsewhere, change the paths to match.
- **CrossLint on your `PATH`,** from [the README's installation steps](../README.md#installation). Check that the shell finds it:

  ```console
  $ crosslint --version
  crosslint 0.1.0
  ```

You don't need Ruby installed; CrossLint carries the Ruby it runs on.

<!-- Placeholder: replace the output of crosslint init with that of a real run once init works (#11). -->

## Write a configuration

From the project's root, ask CrossLint for a configuration:

```console
$ crosslint init
crosslint: wrote .config/crosslint/config.kdl, with the recommended plugins: debt
```

`.config/crosslint/config.kdl` is the project's **configuration**. It lists the **plugins** CrossLint runs, and no plugin runs until it's listed there. So far it lists one, `debt`, which we'll use at the end.

## Declare the rule

A project's rule goes in a **local plugin**: a folder in your repository with a `plugin.kdl`. Create `.config/crosslint/tests/plugin.kdl`:

```kdl
artifact "ruby-file" {
  files "lib/{path}.rb"
  companion "test" "test/{path}_test.rb"
}

policy "has-test" {
  applies-to "ruby-file"
  rule "companion-exists" companion="test"
}
```

This declares all three kinds of thing CrossLint works with:

- The **artifact** `ruby-file` is each Ruby file under `lib/`, found by the **path pattern** `lib/{path}.rb`. For `lib/invoices/total.rb`, `{path}` matches `invoices/total`, so its `test` **companion** is `test/invoices/total_test.rb`.
- The **policy** `has-test` says when to check: every `ruby-file`.
- The **rule** `companion-exists` does the checking: it reports a `ruby-file` whose `test` doesn't exist.

The rule is built into CrossLint, so the plugin needs no code. Now list the plugin in `.config/crosslint/config.kdl`, below `debt`:

```kdl
plugin "debt"
plugin ".config/crosslint/tests"
```

## Run the check

Before you run it, which files do you expect it to report? Then run:

```console
$ crosslint check
lib/invoices/currency.rb: no test file at test/invoices/currency_test.rb (tests/has-test)
lib/invoices/pdf.rb: no test file at test/invoices/pdf_test.rb (tests/has-test)
lib/invoices/tax.rb: no test file at test/invoices/tax_test.rb (tests/has-test)
crosslint: checked 9 ruby-file artifacts: 3 errors
```

Each **violation** is one line on standard output: the file, what's wrong, and the plugin and policy it comes from. The last line is CrossLint's summary, on standard error. What did the shell get?

```console
$ echo $?
1
```

`crosslint check` exits with 1 when a violation fails the check, so CI fails the way it does for a failing test.

If instead you see `crosslint: .config/crosslint/tests/plugin.kdl:2: unknown node "file", did you mean "files"?`, CrossLint stopped before checking anything, with exit status 2. CrossLint never skips a line it doesn't understand: a typo in a rule would otherwise leave a check that never runs. Fix the line the message gives, and run the check again.

## Fix one violation

Write the missing test for `tax.rb`, at the path the violation gives, and check again:

```console
$ crosslint check
lib/invoices/currency.rb: no test file at test/invoices/currency_test.rb (tests/has-test)
lib/invoices/pdf.rb: no test file at test/invoices/pdf_test.rb (tests/has-test)
crosslint: checked 9 ruby-file artifacts: 2 errors
```

## Accept the rest as debt

The other two will take longer. Rather than leave the check failing until they're done, record them as **debt**:

```console
$ crosslint check --update-debt
crosslint: wrote .config/crosslint/debt.tsv: 2 entries added, 0 removed
crosslint: checked 9 ruby-file artifacts: 2 accepted as debt
```

Open `.config/crosslint/debt.tsv`. Each line after the header is an **entry**: the plugin and policy, the artifact, and an empty comment at the end. Write in each comment why the violation is still there, such as `PDF export is being rewritten`, so whoever reads the file later knows. Then check again:

```console
$ crosslint check
crosslint: checked 9 ruby-file artifacts: 2 accepted as debt
$ echo $?
0
```

Commit `.config/crosslint/config.kdl`, the plugin, and the debt file.

Now the check passes while no violation is new. Add a Ruby file under `lib/` with no test, and it fails again. Write the test for `currency.rb`, and it fails too: its entry has become a **stale entry**, and `crosslint check --update-debt` removes it, so the debt file only ever shrinks as the work gets done.

## Check your work

You've finished when all of these are true:

- `crosslint check` exits with 0 in your project.
- `.config/crosslint/debt.tsv` has a comment on every entry.
- A Ruby file you add under `lib/` with no test makes `crosslint check` exit with 1.

You should now be comfortable declaring an artifact, a policy and a rule, and keeping a check passing with debt. To check something a path can't show, such as what a file contains, read [the plugin reference](reference/plugin.md#rules-in-ruby).
