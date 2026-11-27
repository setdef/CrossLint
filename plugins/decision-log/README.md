# decision-log

A shared plugin for CrossLint that keeps a decision log, such as a folder of architecture decision records, true to itself: the log's index links to exactly the records in its folder, no two records have the same number, and no Markdown file cites a record by a number no record has.

## Listing it

List it in `.config/crosslint/config.kdl` from its folder of the CrossLint repository:

```kdl
plugin "https://github.com/setdef/CrossLint" ref="TAG" path="plugins/decision-log" {
  folder "doc/adr"
  index "doc/adr/README.md"
}
```

`TAG` is a tag of CrossLint that has this folder. Both settings are optional:

| Setting | Meaning | Default |
| --- | --- | --- |
| `folder` | The folder of the records, relative to the project's root. | `docs/decisions` |
| `index` | The index's path, relative to the project's root. | `README.md` in `folder` |

## What it checks

A record is a Markdown file directly in `folder` whose name starts with its number, such as `0001-use-postgres.md`, or `20240131-use-postgres.md` in a log numbered by date. Other files there, such as a template, are not records, and neither is a file in a folder inside `folder`.

| Policy | Reports |
| --- | --- |
| `decision-log/index-lists-records` | A record the index has no link to, and a link in the index to a record-named file of `folder` that doesn't exist, such as a deleted record's. A link counts in any form: a table's row, a list's item, a reference definition, or `href` in HTML, resolved from the index's folder. |
| `decision-log/numbers-unique` | Two or more records with the same number, such as `0004-a.md` and `4-b.md`. Its violations are on the index. |
| `decision-log/citations-resolve` | In any Markdown file of the project, `ADR` and a number, as in `ADR 7`, `ADR 0007`, or `ADR-0007`, where no record has that number. `former ADR 7`, the way a dated document mentions a deleted record, isn't checked, nor is a number in a code span or a fenced block. |

A log with no index gets CrossLint's warning that no file matches the artifact `index`. A link to a record from another file isn't this plugin's to check: [markdown-links](../markdown-links/README.md) checks every relative link.
