# Design of decision-log

Why the plugin reads a decision log the way its [README](README.md) says.

- **A record is a file whose name starts with a number.** adr-tools numbers each new record (`adr new` writes `0001-title.md`), and MADR's documentation gives a record the form `NNNN-title-with-dashes.md`. The records in log4brains's repository start with a date, `20240131-title.md`, but its README says it requires no numbering, and it keeps `index.md` and `template.md` beside its records, so a log4brains record whose name doesn't start with a digit isn't seen. A log keeps other files beside its records, such as a template and the index. A log whose records have no number has no number to cite either, so the plugin has nothing to check in it.
- **The index is the artifact, not each record.** "The index lists exactly the records" is a claim about the index, and every violation of it is on the index, so a debt entry for a missing link holds the index's path and the record's name. CrossLint's warning that no file matches the index stands for a log with no index.
- **Only the text "ADR" and a number is a citation.** A record is cited by number in prose, and a number alone is too common to read as one. "former ADR N" is how a dated document mentions a record that a later one replaced, so it stays as written and isn't checked.
- **Only Markdown is read for citations.** Code cites records too, but no plugin can tell a comment from a string in every language, and this plugin reads every project the same way.
- **The plugin keeps a Markdown reader in its folder,** `markdown.rb`, as markdown-links does, so that it can be listed and moved without markdown-links. The two readers skip the same places, and this one reads links but not headings.
