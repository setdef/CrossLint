#!/bin/sh
# Shell plugin: every component has an HTML template. Needs jq.
while IFS= read -r line; do
  printf '%s' "$line" | jq -c '
    if .method == "handshake" then
      {id, result: {protocol: 1, name: "template-per-component"}}
    elif .method == "check" then
      {id, result: {violations: [
        .params.items[] | select(.companions.template.exists | not)
        | {rule: "component-has-template", path, message: ("no template at " + .companions.template.path)}
      ]}}
    else
      {id, error: {code: "unknown-method", message: .method}}
    end'
done
