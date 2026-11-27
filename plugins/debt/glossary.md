# Glossary of the debt plugin

The words of debt tracking, with the meaning each has in the debt plugin. The words every user of CrossLint shares, such as artifact and violation, are in [the glossary](../../docs/glossary.md).

| Word | Meaning | Avoid |
| --- | --- | --- |
| technical **debt** | Violations accepted for now, each with the reason, so that the check passes until a new one appears. | baseline, suppressions, ignores |
| **debt file** | `.config/crosslint/debt.tsv`, which lists a project's debt, one entry per line, and is committed with the project. | baseline file |
| **entry** | One line of the debt file: the plugin and policy, the artifact, the detail where its rule gives one, and the comment. A violation that matches an entry doesn't fail the check. | record, row |
| **comment** | An entry's reason, which people write, such as `PDF export is being rewritten`. An update never changes it. | note |
| **paid-off entry** | An entry no violation matches any more, because the violation was fixed and its debt paid off. CrossLint fails the check while it is in the file, until `crosslint debt update` removes it, so the debt file only ever shrinks as the work gets done. | stale entry |
