# Getting started

In this tutorial, we add CrossLint to an app translated into French and German, and write a rule for it: every screen's English messages have a French and a German translation. The app's code could be in any language, since the rule is about its translation files alone. By the end, you'll have run a check that fails, fixed a violation, and accepted the rest as debt, so the check passes in CI today and fails on any new violation. It takes about 15 minutes.

If you get stuck, [post on the forum](https://forum.setdef.com/c/crosslint) with the command you ran and everything it printed. Words in bold are defined in the [glossary](glossary.md), the [glossary for plugin authors](reference/plugin-glossary.md), or the [debt plugin's glossary](../plugins/debt/glossary.md).

## What you need

- **Git, and a shell such as bash or zsh.** On Windows, use Git Bash, which comes with Git for Windows.
- **CrossLint on your `PATH`,** from [the README's installation steps](../README.md#installation). Check that the shell finds it:

  <!--
  SPDX-SnippetBegin
  SPDX-License-Identifier: MIT-0
  SPDX-SnippetCopyrightText: 2026 setdef
  -->
  ```console
  $ crosslint --version
  crosslint 0.2.0
  ```
  <!-- SPDX-SnippetEnd -->

You don't need Node, Python, Ruby, or any other runtime installed; CrossLint carries the one it runs on.

## Make the project

The app's text is in message catalogs, one JSON file per screen, in a folder for each language under `locales/`. Make it in an empty folder:

<!--
SPDX-SnippetBegin
SPDX-License-Identifier: MIT-0
SPDX-SnippetCopyrightText: 2026 setdef
-->
```console
$ mkdir shop
$ cd shop
$ git init --quiet
$ mkdir -p locales/en locales/fr locales/de
$ touch locales/en/{account,cart,checkout,orders,search}.json
$ touch locales/fr/{account,cart,orders,search}.json
$ touch locales/de/{account,cart,orders}.json
```
<!-- SPDX-SnippetEnd -->

English has five screens, French four, and German three. A real catalog holds its screen's messages, such as `{"title": "Your cart"}`, but empty files will do here, since the rule we'll write is only about which files exist. CrossLint lists a project's files with Git, so the project has to be a Git repository, though its files needn't be committed.

## Write a configuration

From the project's root, ask CrossLint for a configuration:

<!--
SPDX-SnippetBegin
SPDX-License-Identifier: MIT-0
SPDX-SnippetCopyrightText: 2026 setdef
-->
```console
$ crosslint init
crosslint: wrote .config/crosslint/config.kdl, with the recommended plugins: debt
```
<!-- SPDX-SnippetEnd -->

`.config/crosslint/config.kdl` is the project's configuration. It lists the **plugins** CrossLint runs, and no plugin runs until it's listed there. So far it lists one, `debt`, which we'll use at the end.

## Declare the rule

A project's rule goes in a **local plugin**: a folder in your repository with a `plugin.kdl`. Create the folder `.config/crosslint/translations`, and in it this `plugin.kdl`:

<!--
SPDX-SnippetBegin
SPDX-License-Identifier: MIT-0
SPDX-SnippetCopyrightText: 2026 setdef
-->
```kdl
// .config/crosslint/translations/plugin.kdl
artifact "catalog" {
  primary "locales/en/{path}.json"
  name "{path}"
  piece "fr" "locales/fr/{path}.json"
  piece "de" "locales/de/{path}.json"
}

policy "has-french" {
  applies-to "catalog"
  rule "piece-exists" piece="fr"
}

policy "has-german" {
  applies-to "catalog"
  rule "piece-exists" piece="de"
}
```
<!-- SPDX-SnippetEnd -->

This declares all three kinds of thing CrossLint works with:

- Each **artifact** of the **role** `catalog` is one screen's messages, in every language. Its primary **piece** is the English file, which CrossLint finds with the **path pattern** `locales/en/{path}.json`. For `locales/en/checkout.json`, `{path}` matches `checkout`, so the artifact's name, from `name "{path}"`, is `checkout`, and its pieces `fr` and `de` are `locales/fr/checkout.json` and `locales/de/checkout.json`.
- The **policies** `has-french` and `has-german` say when to check: every `catalog`. With a policy for each language, you can [turn one off, or make it a warning](reference/configuration.md#policy), in the project's configuration while that language is new.
- The **rule** `piece-exists` does the checking: it reports a `catalog` whose piece doesn't exist.

So the artifact `checkout` isn't any one of its files. It is all three, and any piece but the primary may be missing, which is what the rules check. The rule is built into CrossLint, so the plugin needs no code. Now list the plugin in `.config/crosslint/config.kdl`, below `debt`:

<!--
SPDX-SnippetBegin
SPDX-License-Identifier: MIT-0
SPDX-SnippetCopyrightText: 2026 setdef
-->
```kdl
// .config/crosslint/config.kdl
plugin "debt"
plugin ".config/crosslint/translations"
```
<!-- SPDX-SnippetEnd -->

## Run the check

Before you run it, which catalogs do you expect to fail, and for which languages? Then run:

<!--
SPDX-SnippetBegin
SPDX-License-Identifier: MIT-0
SPDX-SnippetCopyrightText: 2026 setdef
-->
```console
$ crosslint check
locales/en/checkout.json: checkout: no fr file at locales/fr/checkout.json (translations/has-french)
locales/en/checkout.json: checkout: no de file at locales/de/checkout.json (translations/has-german)
locales/en/search.json: search: no de file at locales/de/search.json (translations/has-german)
crosslint: checked 5 catalog artifacts: 3 errors
```
<!-- SPDX-SnippetEnd -->

Each **violation** is one line on standard output: the artifact's primary piece, its name, what's wrong, and the plugin and policy it comes from. `checkout` fails both policies, once for each missing piece. The last line is CrossLint's summary, on standard error. What did the shell get?

<!--
SPDX-SnippetBegin
SPDX-License-Identifier: MIT-0
SPDX-SnippetCopyrightText: 2026 setdef
-->
```console
$ echo $?
1
```
<!-- SPDX-SnippetEnd -->

`crosslint check` exits with 1 when a violation fails the check, so CI fails the way it does for a failing test.

If instead you see `crosslint: .config/crosslint/translations/plugin.kdl:3: unknown node "primay", did you mean "primary"?`, CrossLint stopped before checking anything, with exit status 2. CrossLint never skips a line it doesn't understand: a typo in a rule would otherwise leave a check that never runs. Fix the line the message gives, and run the check again.

## Fix one violation

Translate the search screen into German, at the path the violation gives. An empty file stands in for the translation here. Then check again:

<!--
SPDX-SnippetBegin
SPDX-License-Identifier: MIT-0
SPDX-SnippetCopyrightText: 2026 setdef
-->
```console
$ touch locales/de/search.json
$ crosslint check
locales/en/checkout.json: checkout: no fr file at locales/fr/checkout.json (translations/has-french)
locales/en/checkout.json: checkout: no de file at locales/de/checkout.json (translations/has-german)
crosslint: checked 5 catalog artifacts: 2 errors
```
<!-- SPDX-SnippetEnd -->

## Accept the rest as debt

The checkout screen's English is being rewritten, so its translations will wait. Rather than leave the check failing until then, record its violations as **debt** with the debt plugin's command:

<!--
SPDX-SnippetBegin
SPDX-License-Identifier: MIT-0
SPDX-SnippetCopyrightText: 2026 setdef
-->
```console
$ crosslint debt update
crosslint: wrote .config/crosslint/debt.tsv: 2 entries added, 0 removed
crosslint: checked 5 catalog artifacts: 2 accepted as debt
$ cat .config/crosslint/debt.tsv
Rule	Artifact	Comment
translations/has-french	checkout	
translations/has-german	checkout	
```
<!-- SPDX-SnippetEnd -->

The debt file's columns are separated by tabs. Each line after the header is an **entry**: the plugin and policy, the artifact by its name, and an empty comment at the end. Open the file and write in each comment why the violation is still there, such as `Checkout's English is being rewritten`, so whoever reads the file later knows. Then check again:

<!--
SPDX-SnippetBegin
SPDX-License-Identifier: MIT-0
SPDX-SnippetCopyrightText: 2026 setdef
-->
```console
$ crosslint check
crosslint: checked 5 catalog artifacts: 2 accepted as debt
$ echo $?
0
```
<!-- SPDX-SnippetEnd -->

Commit `.config/crosslint/config.kdl`, the plugin, and the debt file.

Now the check passes while no violation is new. Add an English catalog with no translations, and it fails again. Translate checkout into French, and it fails too: the entry for `has-french` has become a **paid-off entry**, because translating checkout paid off its debt. The check fails until `crosslint debt update` removes the entry, so the debt file only ever shrinks as the work gets done.

## Check your work

You've finished when all of these are true:

- `crosslint check` exits with 0 in `shop`.
- `.config/crosslint/debt.tsv` has a comment on every entry.
- After `touch locales/en/wishlist.json`, `crosslint check` exits with 1 and reports the wishlist once for each language. Delete the file again afterwards.

You should now be comfortable declaring an artifact and its pieces, writing policies that run a rule on it, and keeping a check passing with debt. To check what files contain, such as whether a French catalog has every key its English one has, read [Helpers](reference/plugin.md#helpers) in the plugin reference, which run a rule you write in your project's language, and [Regexes](reference/plugin.md#regexes), with which CrossLint finds text in a file, with no code.
