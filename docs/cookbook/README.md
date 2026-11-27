# Cookbook

Each recipe is one check to add to a project, with the plugin to write, an example project of three or four files, and what `crosslint check` prints for it. Each assumes CrossLint and a configuration, as you set them up in [Getting started](../getting-started.md), and links to [the plugin reference](../reference/plugin.md) for everything a line of the plugin can hold.

- [Check that every Rails route has its action](rails-routes.md): each route in `config/routes.rb` is an artifact, found by a regex, and its controller has to define the action in its `to:`.
- [Warn about Vue components with unscoped styles](scoped-vue-styles.md): a `<style>` block that isn't `scoped` is a piece of its component that shouldn't exist.
