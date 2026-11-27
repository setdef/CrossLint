# Warn about Vue components with unscoped styles

This recipe adds a check to a Vue app: a single-file component's `<style>` block should be `scoped`, so its rules apply only to that component's elements. A component with a `<style>` that isn't scoped gets a warning naming the file and the block's line.

It needs CrossLint and a configuration, as [Getting started](../getting-started.md) sets up, and nothing from Vue or Node: CrossLint reads the files as text.

## Declare the component

Each `.vue` file under `src/` is a component, and its unscoped `<style>` block is a **piece** of it that shouldn't exist. Create `.config/crosslint/vue/plugin.kdl`:

```kdl
// .config/crosslint/vue/plugin.kdl
artifact "vue-component" {
  primary "src/{path}.vue"
  piece "unscoped-style" "src/{path}.vue" regex=#"<style(?![^>]*\bscoped)[^>]*>"#
}

policy "scoped-styles" {
  applies-to "vue-component"
  rule "piece-absent" piece="unscoped-style" severity="warning"
}
```

- The piece `unscoped-style` is in the component's file, so its path is the same as the primary's. With `regex=`, the piece is a part of that file, and it exists when the file has a match.
- The regex matches a `<style` tag in which no `scoped` comes before its `>`, since `(?![^>]*\bscoped)` is a lookahead over the tag's attributes. So `<style>` and `<style lang="scss">` match, and `<style scoped>` and `<style lang="scss" scoped>` don't.
- `piece-absent` reports a piece that exists, here as a warning, so the check still passes while you fix the components.

The regex is a KDL raw string, `#"..."#`, so its quotes and backslashes reach CrossLint as written. [The plugin reference](../reference/plugin.md#regexes) has the whole of what a regex can hold.

Then list the plugin in `.config/crosslint/config.kdl`, beside the plugins already there:

```kdl
// .config/crosslint/config.kdl
plugin ".config/crosslint/vue"
```

## Run the check

Take an app with three components, one of whose styles isn't scoped:

```vue
<!-- src/components/CartButton.vue -->
<template>
  <button class="cart-button">Cart</button>
</template>

<style scoped>
.cart-button { font-weight: bold; }
</style>
```

```vue
<!-- src/components/CartBadge.vue -->
<template>
  <span class="badge"><slot /></span>
</template>

<style lang="scss">
.badge { border-radius: 50%; }
</style>
```

```vue
<!-- src/components/ProductCard.vue -->
<template>
  <article :class="$style.card"><slot /></article>
</template>

<style module>
.card { padding: 1rem; }
</style>
```

Run the check from the project's root:

```console
$ crosslint check
src/components/CartBadge.vue: warning: unscoped-style at src/components/CartBadge.vue:6 (vue/scoped-styles)
src/components/ProductCard.vue: warning: unscoped-style at src/components/ProductCard.vue:6 (vue/scoped-styles)
crosslint: checked 3 vue-component artifacts: 2 warnings
```

Each warning has the line of the component's first unscoped `<style>`. CrossLint exits with 0, since a warning fails the check only under `--warnings=error`, as [the command reference](../reference/cli.md) says.

## Count CSS modules as scoped

`ProductCard.vue` uses `<style module>`, a CSS module, whose class names Vue makes unique to the component, so its rules apply to no other component either. Add `module` beside `scoped` in the regex's lookahead:

```kdl
// .config/crosslint/vue/plugin.kdl
artifact "vue-component" {
  primary "src/{path}.vue"
  piece "unscoped-style" "src/{path}.vue" regex=#"<style(?![^>]*\b(?:scoped|module)\b)[^>]*>"#
}

policy "scoped-styles" {
  applies-to "vue-component"
  rule "piece-absent" piece="unscoped-style" severity="warning"
}
```

Only `CartBadge.vue` is left:

```console
$ crosslint check
src/components/CartBadge.vue: warning: unscoped-style at src/components/CartBadge.vue:6 (vue/scoped-styles)
crosslint: checked 3 vue-component artifacts: 1 warning
```

> [!NOTE]
> **A component can have global styles on purpose,** such as `App.vue` with a reset for the whole app. Accept such a warning as debt with the [debt plugin](../reference/configuration.md#debt), or narrow `primary` to the folders whose components should be scoped, such as `src/components/{path}.vue`.
