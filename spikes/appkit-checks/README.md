# AppKit checks

Spike for issue #1, step 3. Two checks were suggested for [Databricks AppKit](https://github.com/databricks/appkit) apps and could not be verified. This spike checks each against Databricks' documentation and AppKit's source, then tries to run each from Ruby. It is evidence, not CrossLint's design.

AppKit is cited at commit [`34d8cf7`](https://github.com/databricks/appkit/tree/34d8cf7aff829b2cb6104e2564d2024b31d51424).

## Check 1: every `config/queries/*.sql` key reaches a hook or chart

Verdict: holds, in a corrected form.

- **The key.** It is the file name minus `.sql`, and minus `.obo.sql` for an on-behalf-of file. [`getAppQuery`](https://github.com/databricks/appkit/blob/34d8cf7aff829b2cb6104e2564d2024b31d51424/packages/appkit/src/app/index.ts) requires `^[a-zA-Z0-9_-]+$` and reads `config/queries` without recursing. A dotted name or a file in a subfolder can never be served. If `x.sql` and `x.obo.sql` both exist, `x.obo.sql` wins and AppKit logs a warning. The [analytics plugin page](https://github.com/databricks/appkit/blob/34d8cf7aff829b2cb6104e2564d2024b31d51424/docs/docs/plugins/analytics.md) says "filename without `.sql`", which is loose for `.obo.sql`.
- **Where a key is passed.** More than the two named places:
  - `useAnalyticsQuery(key, parameters, options)`;
  - `useChartData({ queryKey })`, in [`use-chart-data.ts`](https://github.com/databricks/appkit/blob/34d8cf7aff829b2cb6104e2564d2024b31d51424/packages/appkit-ui/src/react/hooks/use-chart-data.ts);
  - the `queryKey` prop of the chart components, in [`charts/wrapper.tsx`](https://github.com/databricks/appkit/blob/34d8cf7aff829b2cb6104e2564d2024b31d51424/packages/appkit-ui/src/react/charts/wrapper.tsx);
  - the `queryKey` prop of `DataTable`, in the [`DataTable` reference](https://github.com/databricks/appkit/blob/34d8cf7aff829b2cb6104e2564d2024b31d51424/docs/docs/api/appkit-ui/data/DataTable.mdx);
  - a direct request to `/api/analytics/query/:key`, which no syntax check can see.
- **Not in scope.** `useMetricView` reads `config/metric-views/definitions.json`, not `.sql` files.
- **Traps.** The generated `shared/appkit-types/analytics.d.ts` lists every key whether used or not, so a scan must skip it. Test files (the first user's MSW mocks name keys) need a policy.

## Check 2: `*.obo.sql` requires `sql` in `user_api_scopes`

Verdict: holds, in a corrected form.

- Databricks' [user authorization page](https://docs.databricks.com/aws/en/dev-tools/databricks-apps/auth) says an app that acts for the user declares scopes. With none, it gets only `iam.access-control:read` and `iam.current-user:read`, which "don't permit access to data or compute resources". It names `sql` as the scope "for querying SQL warehouses".
- The same page lists the narrower `sql:read` and `sql:restricted-query`, and lists deprecated `sql.*` names (such as `sql.statement-execution`) as mapping to `sql`. It does not say whether the narrower scopes are enough for AppKit, so the script reports them as needing review.
- The bundle key is `resources.apps.<name>.user_api_scopes` ([bundle resources reference](https://docs.databricks.com/aws/en/dev-tools/bundles/resources), "Public Preview"). It can also sit under `targets.<name>.resources.apps`, or in a file named by `include:`.
- AppKit's own documentation never states the requirement. AppKit's template comment lists `sql` among the available scopes.
- A repository cannot show whether the workspace allows the scope (admins can restrict scopes, and "None" turns user authorization off), nor the scopes of an app configured in the UI or CLI instead of a bundle.

## The first user

[Kerrick/opinionated-databricks-appkit-template](https://github.com/Kerrick/opinionated-databricks-appkit-template) has no `config/queries/` and no `databricks.yml` of its own. It ships a Go template, [`databricks.yml.tmpl`](https://github.com/Kerrick/opinionated-databricks-appkit-template/blob/trunk/generic/databricks.yml.tmpl), which is not valid YAML. Both checks apply to a generated app.

- Check 2 exists already as [`generic/tools/triggers/obo-queries.ts`](https://github.com/Kerrick/opinionated-databricks-appkit-template/blob/trunk/generic/tools/triggers/obo-queries.ts), a line-based regex. It misses flow-style lists, target overrides and included files, and cannot tell which app a scope belongs to. A YAML parse reads all of these.
- Check 1 is on the template's plan. Hooks go through `client/src/acl/` and charts through `client/src/components/charts/` wrappers, and imports use the `@/` alias from `tsconfig.client.json`. A project's own wrapper prop is a use that syntax cannot see.

## What Ruby can do

Run with `ruby_tree_sitter` 2.1.1 (precompiled gems for Linux and macOS) and the TypeScript and TSX grammars from tree-sitter-typescript 0.23.2, compiled by `setup.sh` from a SHA-256-checked tarball.

Found by syntax, each covered in `fixture/`:

- string literals, and template literals without substitution;
- constants in the same file, imported constants, object members (`KEYS.sales`), constants re-exported through a barrel file, and constants imported through a tsconfig `paths` alias;
- aliased and namespace imports of `useAnalyticsQuery`, and calls with a type argument;
- both arms of a ternary;
- `useChartData({ queryKey })` and `queryKey` JSX props on any element;
- a key in a comment or in an unrelated string is not counted. A text search counts them: in the fixture, `unused` appears in a generated type file and `only_in_comment` in a comment.

Not found by syntax:

- a template literal with a substitution (`` `${prefix}_x` ``);
- a key passed through a parameter of a local helper;
- a key passed through a project component's own prop (`<SalesChart query="wrapper_prop">`).

A looser pass, which counts any non-comment string literal equal to a key, finds the second and third. It can also match a literal that is not a use. The script reports call sites it cannot read, because an unused key may be used there.

For `databricks.yml`, Ruby's YAML parser is enough: commented-out scopes are not counted, and flow lists, quoted values, target overrides and `include:` all resolve. It cannot resolve `${var.x}`.

The TypeScript grammar has no JSX nodes, so `.ts` and `.tsx` files need separate queries.

## Rerun

```sh
mise x -- ./setup.sh                 # installs the gem, compiles the grammars into build/
mise x -- bundle exec ruby check.rb --verify
```

Needs a C compiler, `curl`, and `shasum` or `sha256sum`. `--verify` compares the output with `fixture/expected.yml`. `--tests` counts test files as uses.
The fixture matched `expected.yml` on Linux (29 query files, 11 bundles). macOS and Windows were not run.
