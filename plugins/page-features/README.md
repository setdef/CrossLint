# page-features

A shared plugin for CrossLint that checks that every page component of an app has a Gherkin feature file, at a path that follows from the page's path, so that each page has scenarios that describe it.

## Listing it

List it in `.config/crosslint/config.kdl` from its folder of the CrossLint repository, with the path patterns of the project's pages and their feature files:

```kdl
plugin "https://github.com/setdef/CrossLint" ref="TAG" path="plugins/page-features" {
  page "web/src/screens/{path}Screen.tsx"
  feature "specs/screens/{path}Screen.feature"
}
```

`TAG` is a tag of CrossLint that has this folder.

| Setting | Meaning | Default |
| --- | --- | --- |
| `page` | The path pattern that finds the page components, relative to the project's root. | `src/pages/{path}.tsx` |
| `feature` | The path pattern of each page's feature file, with only placeholders `page` has. | `features/{path}.feature` |

A path pattern is CrossLint's: `{path}` matches a file name and the folders before it, and `{name}` matches one folder or file name. With the settings above, `web/src/screens/cart/CartScreen.tsx` is a page, and its feature file is `specs/screens/cart/CartScreen.feature`. A file beside it, such as `useCart.ts`, isn't a page, since `page` doesn't match it.

Whatever `page` matches, a file is a page unless the text `{path}` matched has a dot in its last segment. With `{path}.tsx`, `Home.tsx` is a page, and `Home.test.tsx`, `Home.stories.tsx`, and `Home.spec.tsx` aren't. With `{path}.page.tsx`, `Home.page.tsx` is a page and `Home.test.page.tsx` isn't. A folder's name doesn't count, so `v1.2/About.tsx` is a page. A `page` pattern without `{path}` takes every file it matches.

## What it checks

The policy `page-features/feature-exists` reports a page with no feature file at the path `feature` gives, by its exact name. It doesn't read the feature file: the test runner that runs the scenarios reports one it can't parse.

A project whose files `page` doesn't match gets CrossLint's warning that no file matches the artifact `page`, which usually means `page` needs the project's layout.

## How a page is found

A page component is found by its path, with one pattern, because a path is what every framework's pages have in common. Frameworks find their pages in different ways: a folder of pages, a file named `page.tsx` in each route's folder, or a router's table in code. Reading a router's table would take a reader for each framework and language. A path pattern reaches each layout that keeps pages apart from other components, by folder or by name.
