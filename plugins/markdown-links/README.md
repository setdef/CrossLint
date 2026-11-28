# markdown-links

A shared plugin for CrossLint that checks that every relative link in a project's Markdown files resolves: its path points to a file or folder of the project, and its anchor, when it has one, to a heading or an HTML `id` or `name` in the Markdown file it points to. It reads Markdown in any project, whatever its language, and runs on the Ruby CrossLint carries, so it needs nothing installed beside CrossLint.

## Listing it

List it in `.config/crosslint/config.kdl` from its folder of the CrossLint repository:

<!--
SPDX-SnippetBegin
SPDX-License-Identifier: MIT-0
SPDX-SnippetCopyrightText: 2026 setdef
-->
```kdl
plugin "https://github.com/setdef/CrossLint" ref="TAG" path="plugins/markdown-links"
```
<!-- SPDX-SnippetEnd -->

`TAG` is a tag of CrossLint that has this folder. The plugin takes no settings.

## What it checks

Each file whose name ends in `.md` is the primary piece, and the only piece, of a `markdown-file` artifact, and the policy `markdown-links/links-resolve` checks its links. A violation's message gives the link as written and the lines it is on, and its detail is the link as written, so a debt entry excuses that link wherever it is in the file.

A link resolves as GitHub resolves it in a repository's Markdown:

- A path is relative to the Markdown file's folder, or to the project's root when it starts with `/`. A `..` that would leave the project is reported.
- The path leads to a file or a folder among the project's files, which are the files Git tracks and the untracked files it doesn't ignore. A file Git ignores isn't there in a clone, so a link to one is reported. The name is matched exactly, so `Guide.md` doesn't resolve to `guide.md`.
- `%20` and the other percent escapes are decoded, and a query such as `?plain=1` is dropped.
- An anchor into a Markdown file matches a heading, with the anchor GitHub makes for it (`## The files setting` is `#the-files-setting`, and a second `## Usage` is `#usage-1`), or an `id` or `name` in its HTML. An anchor into any other file, such as `tool.rb#L3`, isn't checked.

The plugin reads inline links and images, reference definitions such as `[guide]: docs/guide.md`, and `href` and `src` in HTML tags. It skips links with a scheme, such as `https:` or `mailto:`, links that start with `//`, and empty ones. It skips what GitHub doesn't render as a link: fenced code blocks, code spans, HTML comments, front matter, and brackets escaped with a backslash. An indented code block is read as text, so a link in one is checked.

The text of a link, or of an image's alt text, may hold brackets, as in `[the [draft] guide](docs/guide.md)`. A link with `?plain=1`, which shows a file's source on GitHub, has no anchor checked, since its anchor is a line there.

What it doesn't read:

- A heading inside a block quote or a list item. A link to its anchor is reported as having no heading, though GitHub renders one.
- An HTML attribute whose value has no quotes, as in `<a href=docs/guide.md>`. The link isn't checked.
- A character reference in a destination. `&amp;` is read as the five characters it is written with, not as `&`, so a destination that holds one resolves to a file named with them, or to none.

Files Git ignores are never checked, and neither is any file not named `.md`.
