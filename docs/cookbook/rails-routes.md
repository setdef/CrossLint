# Check that every Rails route has its action

This recipe adds a check to a Rails app: every route written in `config/routes.rb` as `get "/cart", to: "carts#show"` needs a `def show` in `app/controllers/carts_controller.rb`. A route whose action is missing fails the check, and CrossLint reports the route by its name and its line in `config/routes.rb`.

It needs CrossLint and a configuration, as [Getting started](../getting-started.md) sets up, and nothing from Rails: CrossLint reads the files as text.

## Declare the route

Each route is a line of `config/routes.rb`, so the **artifact** is a match in that file rather than the file. Create `.config/crosslint/routes/plugin.kdl`:

```kdl
// .config/crosslint/routes/plugin.kdl
artifact "route" {
  primary "config/routes.rb" regex=#"(?<verb>get|post|patch|put|delete) "(?<route>[^"]+)", to: "(?<controller>\w+)#(?<action>\w+)""#
  name "{verb} {route}"
  piece "action" "app/controllers/{controller}_controller.rb" regex=#"def {action}\b"#
  piece "request-spec" "spec/requests/{controller}_spec.rb"
}

policy "has-action" {
  applies-to "route"
  rule "piece-exists" piece="action"
}
```

- With `regex=` on `primary`, each match in `config/routes.rb` is a route, and each named capture, such as `(?<controller>\w+)`, is a placeholder the rest of the declaration can use.
- With `name "{verb} {route}"`, each route's name is like `get /cart`. CrossLint calls the route by this name in violations and debt entries, since every route has the same file.
- The piece `action` is a part of the controller: it exists when `app/controllers/{controller}_controller.rb` has a match of `def {action}\b`. CrossLint puts the action's name into that regex as literal text, and with `\b`, `def show` doesn't match `def show_all`.
- The piece `request-spec` is a whole file, as a piece without `regex=` always is. No policy runs a rule on it yet; [add one](#check-for-a-request-spec-too) when every controller should have a request spec.

The regex is a KDL raw string, `#"..."#`, so its quotes and backslashes reach CrossLint as written. [The plugin reference](../reference/plugin.md#regexes) has the whole of what a regex can hold.

Then list the plugin in `.config/crosslint/config.kdl`, beside the plugins already there:

```kdl
// .config/crosslint/config.kdl
plugin ".config/crosslint/routes"
```

## Run the check

Take an app with three routes, two controllers, and one action missing:

```rb
# config/routes.rb
Rails.application.routes.draw do
  get "/cart", to: "carts#show"
  post "/cart/items", to: "cart_items#create"
  delete "/cart/items/:id", to: "cart_items#destroy"
end
```

```rb
# app/controllers/carts_controller.rb
class CartsController < ApplicationController
  def show
    @cart = Current.cart
  end
end
```

```rb
# app/controllers/cart_items_controller.rb
class CartItemsController < ApplicationController
  def create
    Current.cart.items.create!(params.expect(item: [:product_id]))
    redirect_to cart_path
  end
end
```

Run the check from the project's root:

```console
$ crosslint check
config/routes.rb:5: delete /cart/items/:id: no action in app/controllers/cart_items_controller.rb (routes/has-action)
crosslint: checked 3 route artifacts: 1 error
```

The line starts with where the route is, `config/routes.rb:5`, then its name. CrossLint exits with 1. Add a `def destroy` to `CartItemsController` and the check passes.

CrossLint's message for a controller file that doesn't exist differs from its message for a file without the action, so a typo in a controller's name doesn't look like a missing method: a route to `checkouts#new` with no `checkouts_controller.rb` gives `no action in app/controllers/checkouts_controller.rb, which isn't a file`.

> [!WARNING]
> **CrossLint checks only the routes written out as the regex expects.** A route that `resources`, `resource`, or `draw` makes is no artifact, and neither is one written across several lines, with an option before `to:`, or with a controller in a module, such as `to: "admin/users#index"`, since `\w+` matches no `/`. Nothing reports such a route, and nothing fails for it. Inside `namespace` or `scope module:`, CrossLint finds the route but not its module, so it looks for the action in the wrong controller. When the app's routes come from `resources`, ask Rails instead, with a rule that [a helper runs](../reference/plugin.md#rules-a-program-runs) on the project's Ruby, where the app can load and `Rails.application.routes` has every route it draws.

## Check for a request spec too

The declaration already has the piece `request-spec`, so a second policy can warn about a controller with no spec at `spec/requests/`. Add the policy `has-request-spec` to `plugin.kdl`:

```kdl
// .config/crosslint/routes/plugin.kdl
artifact "route" {
  primary "config/routes.rb" regex=#"(?<verb>get|post|patch|put|delete) "(?<route>[^"]+)", to: "(?<controller>\w+)#(?<action>\w+)""#
  name "{verb} {route}"
  piece "action" "app/controllers/{controller}_controller.rb" regex=#"def {action}\b"#
  piece "request-spec" "spec/requests/{controller}_spec.rb"
}

policy "has-action" {
  applies-to "route"
  rule "piece-exists" piece="action"
}

policy "has-request-spec" {
  applies-to "route"
  rule "piece-exists" piece="request-spec" severity="warning"
}
```

With no `spec/` folder in the app, every route gets a warning, beside the error from `has-action`:

```console
$ crosslint check
config/routes.rb:3: get /cart: warning: no request-spec file at spec/requests/carts_spec.rb (routes/has-request-spec)
config/routes.rb:4: post /cart/items: warning: no request-spec file at spec/requests/cart_items_spec.rb (routes/has-request-spec)
config/routes.rb:5: delete /cart/items/:id: no action in app/controllers/cart_items_controller.rb (routes/has-action)
config/routes.rb:5: delete /cart/items/:id: warning: no request-spec file at spec/requests/cart_items_spec.rb (routes/has-request-spec)
crosslint: checked 3 route artifacts: 1 error, 3 warnings
```

A warning fails the check only under `--warnings=error`, as [the command reference](../reference/cli.md) says.
